/**
 * vim: set ai et ts=4 sw=4 :
 * File: ZergDrone.sp
 * Description: The Zerg Drone race for SourceCraft.
 * Author(s): -=|JFH|=-Naris
 */
 
#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <dhooks>
#include <raytrace>
#include <range>

#undef REQUIRE_EXTENSIONS
#include <tf2>
#include <tf2_objects>
#include <tf2_player>
#define REQUIRE_EXTENSIONS

#undef REQUIRE_PLUGIN
#include <lib/ztf2grab>
#include <libtf2/remote>
#include <libtf2/amp_node>
#include <libtf2/tf2teleporter>
#define REQUIRE_PLUGIN

#include "sc/SourceCraft"
#include "sc/clienttimer"
#include "sc/SupplyDepot"
#include "sc/maxhealth"
#include "sc/plugins"
#include "sc/weapons"
#include "sc/burrow"
#include "sc/sounds"
#include "sc/armor"

#include "effect/Smoke"
#include "effect/RedGlow"
#include "effect/BlueGlow"
#include "effect/SendEffects"

new const String:spawnWav[]     = "sc/zdrrdy00.wav";
new const String:deathWav[]     = "sc/zdrdth00.wav";
new const String:burrowUpWav[]  = "sc/burrowup.wav";
new const String:burrowDownWav[] = "sc/burrowdn.wav";

new raceID = -1;

#include "sc/Mutate"

new const String:g_ArmorName[]  = "Carapace";
new Float:g_InitialArmor[]      = { 0.0, 0.10, 0.20, 0.30, 0.40 };
new Float:g_ArmorPercent[][2]   = { {0.00, 0.00},
                                    {0.00, 0.10},
                                    {0.00, 0.30},
                                    {0.10, 0.40},
                                    {0.20, 0.50} };

new Float:g_NydusCanalRate[]    = { 0.0, 8.0, 6.0, 3.0, 1.0 };

new carapaceID, regenerationID, creepID, nydusCanalID;
new evolutionID, burrowID, burrowStructID, hiveQueenID;
new mutateID = -1;

new g_hiveQueenRace = -1;

new cfgMaxObjects;
new cfgAllowSentries;

DynamicHook g_CanBeUpgradedHook;
DynamicHook g_InputWrenchHitHook;

new g_CreepBaseMaxHealth[MAXENTITIES+1];
new g_CreepHealthBonus[MAXENTITIES+1];
new Float:g_CreepSapperDamage[MAXENTITIES+1];

#define CREEP_SUPPLY_PER_LEVEL       3
#define CREEP_REGEN_PER_LEVEL        4
#define CREEP_HEALTH_PER_LEVEL       15
#define CREEP_SAPPER_DAMAGE_FRACTION 0.60

public Plugin:myinfo = 
{
    name = "SourceCraft Race - Zerg Drone",
    author = "-=|JFH|=-Naris",
    description = "The Zerg Drone race for SourceCraft.",
    version = SOURCECRAFT_VERSION,
    url = "http://jigglysfunhouse.net/"
};

public OnPluginStart()
{
    LoadTranslations("sc.objects.phrases.txt");
    LoadTranslations("sc.mutate.phrases.txt");
    LoadTranslations("sc.recall.phrases.txt");
    LoadTranslations("sc.common.phrases.txt");
    LoadTranslations("sc.supply.phrases.txt");
    LoadTranslations("sc.drone.phrases.txt");

    GetGameType();

    if (GameType == tf2)
        SetupCreepUpgradeHook();

    if (IsSourceCraftLoaded())
        OnSourceCraftReady();
}

SetupCreepUpgradeHook()
{
    GameData gameData = new GameData("sourcecraft.drone");
    if (gameData == null)
        SetFailState("Could not load gamedata/sourcecraft.drone.txt");

    g_CanBeUpgradedHook = DynamicHook.FromConf(gameData,
                                               "CBaseObject::CanBeUpgraded");
    g_InputWrenchHitHook = DynamicHook.FromConf(gameData,
                                               "CBaseObject::InputWrenchHit");
    delete gameData;

    if (g_CanBeUpgradedHook == null)
        SetFailState("Could not create CBaseObject::CanBeUpgraded hook");

    if (g_InputWrenchHitHook == null)
        SetFailState("Could not create CBaseObject::InputWrenchHit hook");

    decl String:classname[64];
    new maxentities = GetMaxEntities();
    for (new entity = MaxClients + 1; entity <= maxentities; entity++)
    {
        if (IsValidEntity(entity) &&
            GetEntityClassname(entity, classname, sizeof(classname)))
        {
            HookCreepObject(entity, classname);
        }
    }
}

public OnEntityCreated(entity, const String:classname[])
{
    if (GameType == tf2 && g_CanBeUpgradedHook != null &&
        g_InputWrenchHitHook != null)
        HookCreepObject(entity, classname);
}

public OnEntityDestroyed(entity)
{
    if (entity > 0 && entity <= MAXENTITIES)
    {
        g_CreepBaseMaxHealth[entity] = 0;
        g_CreepHealthBonus[entity] = 0;
        g_CreepSapperDamage[entity] = 0.0;
    }
}

HookCreepObject(entity, const String:classname[])
{
    if (StrEqual(classname, "obj_sentrygun") ||
        StrEqual(classname, "obj_dispenser") ||
        StrEqual(classname, "obj_teleporter"))
    {
        g_CanBeUpgradedHook.HookEntity(Hook_Pre, entity,
                                       CreepCanBeUpgraded);
        g_InputWrenchHitHook.HookEntity(Hook_Pre, entity,
                                       CreepInputWrenchHit);
        SDKHook(entity, SDKHook_OnTakeDamage, CreepObjectTakeDamage);
    }
}

bool:IsActiveCreepObject(entity, &builder, &creep_level)
{
    builder = 0;
    creep_level = 0;

    if (raceID < 0 || !IsValidEntity(entity))
        return false;

    builder = GetEntPropEnt(entity, Prop_Send, "m_hBuilder");
    if (!IsValidClient(builder) || GetRace(builder) != raceID)
        return false;

    creep_level = GetUpgradeLevel(builder, raceID, creepID);
    return creep_level > 0 &&
           (GetUpgradeLevel(builder, raceID, mutateID) > 0 ||
            TF2_GetPlayerClass(builder) == TFClass_Engineer);
}

public MRESReturn CreepCanBeUpgraded(entity, DHookReturn returnValue,
                                     DHookParam parameters)
{
    new builder, creep_level;
    if (!TF2_IsObjectCarried(entity) &&
        !GetEntProp(entity, Prop_Send, "m_bMiniBuilding") &&
        IsActiveCreepObject(entity, builder, creep_level))
    {
        returnValue.Value = false;
        return MRES_Supercede;
    }

    return MRES_Ignored;
}

public MRESReturn CreepInputWrenchHit(entity, DHookReturn returnValue,
                                     DHookParam parameters)
{
    new builder, creep_level;
    if (IsActiveCreepObject(entity, builder, creep_level))
    {
        // Creep structures are autonomous organisms. Blocking the complete
        // wrench input rejects construction boosts, repairs, resupply,
        // upgrades, and wrench-based sapper removal alike.
        returnValue.Value = false;
        return MRES_Supercede;
    }

    return MRES_Ignored;
}

GetSapperEntity(attacker, inflictor, victim)
{
    new sapper = IsSapperEntity(inflictor) ? inflictor :
                 (IsSapperEntity(attacker) ? attacker : -1);

    if (sapper > 0 &&
        GetEntPropEnt(sapper, Prop_Send, "m_hBuiltOnEntity") == victim)
        return sapper;

    return -1;
}

bool:IsSapperEntity(entity)
{
    if (entity <= MaxClients || entity > MAXENTITIES ||
        !IsValidEntity(entity))
        return false;

    decl String:classname[32];
    return GetEntityClassname(entity, classname, sizeof(classname)) &&
           StrEqual(classname, "obj_attachment_sapper");
}

public Action:CreepObjectTakeDamage(victim, &attacker, &inflictor,
                                    &Float:damage, &damagetype, &weapon,
                                    Float:damageForce[3],
                                    Float:damagePosition[3])
{
    new builder, creep_level;
    if (!IsActiveCreepObject(victim, builder, creep_level))
        return Plugin_Continue;

    new sapper = GetSapperEntity(attacker, inflictor, victim);
    if (sapper < 0)
        return Plugin_Continue;

    new max_health = GetEntProp(victim, Prop_Data, "m_iMaxHealth");
    new Float:max_damage = float(max_health) * CREEP_SAPPER_DAMAGE_FRACTION;
    new Float:remaining = max_damage - g_CreepSapperDamage[sapper];

    if (remaining <= 0.0)
    {
        damage = 0.0;
        CreateTimer(0.0, FizzleCreepSapper, EntIndexToEntRef(sapper),
                    TIMER_FLAG_NO_MAPCHANGE);
        return Plugin_Changed;
    }

    if (damage >= remaining)
    {
        damage = remaining;
        g_CreepSapperDamage[sapper] = max_damage;
        CreateTimer(0.0, FizzleCreepSapper, EntIndexToEntRef(sapper),
                    TIMER_FLAG_NO_MAPCHANGE);
        return Plugin_Changed;
    }

    g_CreepSapperDamage[sapper] += damage;
    return Plugin_Continue;
}

public Action:FizzleCreepSapper(Handle:timer, any:reference)
{
    new sapper = EntRefToEntIndex(reference);
    if (IsSapperEntity(sapper))
        AcceptEntityInput(sapper, "Kill");

    return Plugin_Stop;
}

public OnSourceCraftReady()
{
    if (GameType == tf2)
    {
        cfgMaxObjects    = GetConfigNum("max_objects", 3);
        cfgAllowSentries = GetConfigNum("allow_sentries", 2);
    }
    else
    {
        cfgMaxObjects    = 0;
        cfgAllowSentries = 0;
    }

    raceID          = CreateRace("drone", 64, 0, 27, .faction=Zerg,
                                 .type=Biological);

    carapaceID      = AddUpgrade(raceID, "armor", .cost_crystals=5);
    regenerationID  = AddUpgrade(raceID, "regeneration", .cost_crystals=10);

    creepID         = AddUpgrade(raceID, "creep", .cost_crystals=30);

    nydusCanalID    = AddUpgrade(raceID, "teleporter", .cost_crystals=0);

    evolutionID     = AddUpgrade(raceID, "evolution", 0, 8, (cfgMaxObjects < 5) ? cfgMaxObjects-1 : 4,
                                 .cost_crystals=25, .cost_vespene=10);

    // Ultimate 1
    mutateID        = AddUpgrade(raceID, "mutate", true, 4, .energy=30.0, .vespene=2, .cost_crystals=75,
                                 .cooldown=5.0, .cooldown_type=Cooldown_SpecifiesBaseValue,
                                 .desc=(cfgAllowSentries >= 2) ? "%drone_mutate_desc"
                                       : "%drone_mutate_engyonly_desc");

    // Ultimate 2
    burrowID        = AddBurrowUpgrade(raceID, 2, 6, 1);

    // Ultimate 3
    burrowStructID  = AddUpgrade(raceID, "burrow_structure", 3, 8, 1,
                                 .energy=5.0, .cost_crystals=75);

    // Ultimate 4
    hiveQueenID     = AddUpgrade(raceID, "hive_queen", 4, 10, 1, .energy=300.0,
                                 .accumulated=true, .cooldown=30.0, .cost_crystals=50);

    // Disable inapplicable upgrades
    if (GameType != tf2 || cfgAllowSentries < 2)
    {
        SetUpgradeDisabled(raceID, creepID, true);
        LogMessage("Disabling Zerg Drone:Creep due to configuration: sc_allow_sentries=%d (or gametype != tf2)",
                   cfgAllowSentries);
    }

    if (!IsTeleporterAvailable())
    {
        SetUpgradeDisabled(raceID, nydusCanalID, true);
        LogMessage("Disabling Zerg Drone:Nydus Canal due to tf2teleporter is not available (or gametype != tf2)");
    }

    if (GameType != tf2 || cfgMaxObjects <= 1)
    {
        SetUpgradeDisabled(raceID, evolutionID, true);
        LogMessage("Disabling Zerg Drone:Evolution Chamber due to configuration: sc_maxobjects=%d (or gametype != tf2)",
                   cfgMaxObjects);
    }

    if (!IsBuildAvailable() || cfgAllowSentries < 1)
    {
        SetUpgradeDisabled(raceID, mutateID, true);
        LogMessage("Disabling Zerg Drone:Mutate due to configuration: sc_allow_sentries=%d or remote is not available or (gametype != tf2)",
                   cfgAllowSentries);
    }

    if (GameType != tf2)
    {
        SetUpgradeDisabled(raceID, mutateID, true);
        LogMessage("Disabling Zerg Drone:Burrow Structure due to gametype != tf2");
    }

    // Get Configuration Data
    GetConfigFloatArray("armor_amount", g_InitialArmor, sizeof(g_InitialArmor),
                        g_InitialArmor, raceID, carapaceID);

    for (new level=0; level < sizeof(g_ArmorPercent); level++)
    {
        decl String:key[32];
        Format(key, sizeof(key), "armor_percent_level_%d", level);
        GetConfigFloatArray(key, g_ArmorPercent[level], sizeof(g_ArmorPercent[]),
                            g_ArmorPercent[level], raceID, carapaceID);
    }

    if (GameType == tf2)
    {
        GetConfigFloatArray("rate", g_NydusCanalRate, sizeof(g_NydusCanalRate),
                            g_NydusCanalRate, raceID, nydusCanalID);

        m_MutateDisableLevel = GetConfigNum("disable_level", 5, raceID, mutateID);
        m_MutateMultiplyEnergy = bool:GetConfigNum("multiply_energy", true, raceID, mutateID);
        m_MutateMultiplyVespene = bool:GetConfigNum("multiply_vespene", true, raceID, mutateID);

        for (new level=0; level < sizeof(m_MutateAmpRange); level++)
        {
            decl String:key[32];
            Format(key, sizeof(key), "amp_range_level_%d", level);
            GetConfigFloatArray(key, m_MutateAmpRange[level], sizeof(m_MutateAmpRange[]),
                                m_MutateAmpRange[level], raceID, mutateID);
        }

        for (new level=0; level < sizeof(m_MutateNodeRange); level++)
        {
            decl String:key[32];
            Format(key, sizeof(key), "node_range_level_%d", level);
            GetConfigFloatArray(key, m_MutateNodeRange[level], sizeof(m_MutateNodeRange[]),
                                m_MutateNodeRange[level], raceID, mutateID);
        }

        for (new level=0; level < sizeof(m_MutateNodeRegen); level++)
        {
            decl String:key[32];
            Format(key, sizeof(key), "node_regen_level_%d", level);
            GetConfigArray(key, m_MutateNodeRegen[level], sizeof(m_MutateNodeRegen[]),
                           m_MutateNodeRegen[level], raceID, mutateID);
        }

        for (new level=0; level < sizeof(m_MutateNodeShells); level++)
        {
            decl String:key[32];
            Format(key, sizeof(key), "node_shells_level_%d", level);
            GetConfigArray(key, m_MutateNodeShells[level], sizeof(m_MutateNodeShells[]),
                           m_MutateNodeShells[level], raceID, mutateID);
        }

        GetConfigArray("node_rockets", m_MutateNodeRockets, sizeof(m_MutateNodeRockets),
                       m_MutateNodeRockets, raceID, mutateID);
    }
}

public OnLibraryAdded(const String:name[])
{
    if (StrEqual(name, "tf2teleporter"))
        IsTeleporterAvailable(true);
    else if (StrEqual(name, "ztf2grab"))
        IsGravgunAvailable(true);
    else if (StrEqual(name, "remote"))
    {
        new bool:available = IsBuildAvailable(true);
        if (raceID >= 0 && mutateID >= 0)
            SetUpgradeDisabled(raceID, mutateID,
                               !available || GameType != tf2 || cfgAllowSentries < 1);
    }
    else if (StrEqual(name, "amp_node"))
        IsAmpNodeAvailable(true);
}

public OnLibraryRemoved(const String:name[])
{
    if (StrEqual(name, "tf2teleporter"))
        m_TeleporterAvailable = false;
    else if (StrEqual(name, "ztf2grab"))
        m_GravgunAvailable = false;
    else if (StrEqual(name, "remote"))
    {
        m_BuildAvailable = false;
        if (raceID >= 0 && mutateID >= 0)
            SetUpgradeDisabled(raceID, mutateID, true);
    }
    else if (StrEqual(name, "amp_node"))
        m_AmpNodeAvailable = false;
}

public OnMapStart()
{
    for (new entity = 0; entity <= MAXENTITIES; entity++)
    {
        g_CreepBaseMaxHealth[entity] = 0;
        g_CreepHealthBonus[entity] = 0;
        g_CreepSapperDamage[entity] = 0.0;
    }

    SetupRedGlow();
    SetupBlueGlow();
    SetupSmokeSprite();

    SetupDeniedSound();

    SetupMutate();

    SetupSound(spawnWav);
    SetupSound(deathWav);
    SetupSound(mutateWav);
    SetupSound(mutateErr);
    SetupSound(burrowUpWav);
    SetupSound(burrowDownWav);
}

public OnMapEnd()
{
    ResetAllClientTimers();
}

public OnPluginEnd()
{
    // Avoid stacking maximum-health bonuses if the race plugin is reloaded
    // while a map and its buildings are still live.
    for (new client = 1; client <= MaxClients; client++)
    {
        if (IsValidClient(client))
            RemoveCreepHealthBonuses(client);
    }
}

public OnClientDisconnect(client)
{
    KillClientTimer(client);
}

public Action:OnRaceDeselected(client,oldrace,newrace)
{
    if (oldrace == raceID)
    {
        KillClientTimer(client);
        RemoveCreepHealthBonuses(client);

        SetHealthRegen(client, 0.0);
        ResetArmor(client);

        if (m_BuildAvailable && GameType == tf2)
        {
            if (g_hiveQueenRace < 0)
                g_hiveQueenRace = FindRace("hive_queen");

            if (newrace != g_hiveQueenRace)
                DestroyBuildings(client, false);
        }

        if (m_TeleporterAvailable)
            SetTeleporter(client, 0.0);

        return Plugin_Handled;
    }
    else
    {
        if (g_hiveQueenRace < 0)
            g_hiveQueenRace = FindRace("hive_queen");

        if (oldrace == g_hiveQueenRace &&
            GetCooldownExpireTime(client, raceID, hiveQueenID) <= 0.0)
        {
            CreateCooldown(client, raceID, hiveQueenID,
                           .type=Cooldown_CreateNotify
                                |Cooldown_AlwaysNotify);
        }
        return Plugin_Continue;
    }
}

public Action:OnRaceSelected(client,oldrace,newrace)
{
    if (newrace == raceID)
    {
        new regeneration_level=GetUpgradeLevel(client,raceID,regenerationID);
        SetHealthRegen(client, float(regeneration_level));

        new carapace_level = GetUpgradeLevel(client,raceID,carapaceID);
        SetupArmor(client, carapace_level, g_InitialArmor,
                   g_ArmorPercent, g_ArmorName);

        new teleporter_level = GetUpgradeLevel(client,raceID,nydusCanalID);
        if (teleporter_level > 0)
            SetupTeleporter(client, teleporter_level);

        if (IsValidClientAlive(client))
        {
            if (GameType == tf2 && GetUpgradeLevel(client,raceID,creepID) &&
                (GetUpgradeLevel(client,raceID,mutateID) ||
                 TF2_GetPlayerClass(client) == TFClass_Engineer))
            {
                CreateClientTimer(client, 1.0, CreepTimer,
                                  TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
            }
        }

        return Plugin_Handled;
    }
    else
        return Plugin_Continue;
}

public OnUpgradeLevelChanged(client,race,upgrade,new_level)
{
    if (race == raceID && GetRace(client) == raceID)
    {
        if (upgrade==nydusCanalID)
            SetupTeleporter(client, new_level);
        else if (upgrade==regenerationID)
            SetHealthRegen(client, float(new_level));
        else if (upgrade==carapaceID)
        {
            SetupArmor(client, new_level, g_InitialArmor,
                        g_ArmorPercent, g_ArmorName,
                        .upgrade=true);
        }
        else if (upgrade==burrowID)
        {
            if (new_level <= 0)
                ResetBurrow(client, true);
        }
        else if (upgrade==creepID)
        {
            if (GameType == tf2 && new_level &&
                (GetUpgradeLevel(client,race,mutateID) ||
                 TF2_GetPlayerClass(client) == TFClass_Engineer))
            {
                if (IsPlayerAlive(client))
                {
                    CreateClientTimer(client, 1.0, CreepTimer,
                                      TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
                }
            }
            else
            {
                KillClientTimer(client);
                RemoveCreepHealthBonuses(client);
            }
        }
    }
}

public OnUltimateCommand(client,race,bool:pressed,arg)
{
    if (race==raceID)
    {
        switch (arg)
        {
            case 4:
            {
                if (!pressed)
                {
                    if (GetUpgradeLevel(client,race,hiveQueenID))
                        EvolveHiveQueen(client);
                }
            }
            case 3:
            {
                if (GameType == tf2 && GetUpgradeLevel(client,race,burrowStructID))
                {
                    if (pressed)
                        BurrowStructure(client, GetUpgradeEnergy(raceID,burrowStructID));
                }
                else if (!pressed)
                {
                    if (GetUpgradeLevel(client,race,hiveQueenID))
                        EvolveHiveQueen(client);
                }
            }
            case 2:
            {
                new burrow_level=GetUpgradeLevel(client,race,burrowID);
                if (burrow_level > 0)
                {
                    if (pressed)
                        Burrow(client, burrow_level);
                }
                else if (GameType == tf2 && GetUpgradeLevel(client,race,burrowStructID))
                {
                    if (pressed)
                        BurrowStructure(client, GetUpgradeEnergy(raceID,burrowStructID));
                }
                else if (!pressed)
                {
                    if (GetUpgradeLevel(client,race,hiveQueenID))
                        EvolveHiveQueen(client);
                }
            }
            default:
            {
                new mutate_level = GetUpgradeLevel(client,race,mutateID);
                if (mutate_level && m_BuildAvailable && GameType == tf2 && cfgAllowSentries >= 1)
                {
                    if (pressed)
                    {
                        Mutate(client, mutate_level, race, mutateID, evolutionID,
                               cfgMaxObjects, (cfgAllowSentries < 2));
                    }
                }
                else if (GameType == tf2 && GetUpgradeLevel(client,race,burrowStructID))
                {
                    if (pressed)
                        BurrowStructure(client, GetUpgradeEnergy(raceID,burrowStructID));
                }
                else
                {
                    new burrow_level=GetUpgradeLevel(client,race,burrowID);
                    if (burrow_level > 0)
                    {
                        if (pressed)
                            Burrow(client, burrow_level);
                    }
                    else if (!pressed)
                    {
                        if (GetUpgradeLevel(client,race,hiveQueenID))
                            EvolveHiveQueen(client);
                    }
                }
            }
        }
    }
}

// Events
public OnPlayerSpawnEvent(Handle:event, client, race)
{
    if (race == raceID)
    {
        PrepareAndEmitSoundToAll(spawnWav,client);
        
        SetOverrideSpeed(client, -1.0);

        new regeneration_level=GetUpgradeLevel(client,raceID,regenerationID);
        SetHealthRegen(client, float(regeneration_level));

        new carapace_level = GetUpgradeLevel(client,raceID,carapaceID);
        SetupArmor(client, carapace_level, g_InitialArmor,
                   g_ArmorPercent, g_ArmorName);

        if (GameType == tf2 && GetUpgradeLevel(client,raceID,creepID) &&
            (GetUpgradeLevel(client,raceID,mutateID) ||
             TF2_GetPlayerClass(client) == TFClass_Engineer))
        {
            CreateClientTimer(client, 1.0, CreepTimer,
                              TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
        }
    }
}

public OnPlayerDeathEvent(Handle:event, victim_index, victim_race, attacker_index,
                          attacker_race, assister_index, assister_race, damage,
                          const String:weapon[], bool:is_equipment, customkill,
                          bool:headshot, bool:backstab, bool:melee)
{
    SetOverrideSpeed(victim_index, -1.0);

    if (victim_race == raceID)
    {
        PrepareAndEmitSoundToAll(deathWav,victim_index);
        KillClientTimer(victim_index);
    }
    else
    {
        if (g_hiveQueenRace < 0)
            g_hiveQueenRace = FindRace("hive_queen");

        if (victim_race == g_hiveQueenRace &&
            GetCooldownExpireTime(victim_index, raceID, hiveQueenID) <= 0.0)
        {
            CreateCooldown(victim_index, raceID, hiveQueenID,
                           .type=Cooldown_CreateNotify
                                |Cooldown_AlwaysNotify);
        }
    }
}

public Action:CreepTimer(Handle:timer, any:userid)
{
    new client = GetClientOfUserId(userid);
    if (IsValidClientNotSpec(client))
    {
        if (GetRace(client) == raceID &&
            !GetRestriction(client,Restriction_NoUpgrades) &&
            !GetRestriction(client,Restriction_Stunned))
        {
            new creep_level=GetUpgradeLevel(client,raceID,creepID);
            if (creep_level && (cfgAllowSentries >= 2) &&
                (GetUpgradeLevel(client,raceID,mutateID) ||
                 TF2_GetPlayerClass(client) == TFClass_Engineer))
            {
                new obj;
                new supply_amount = creep_level * CREEP_SUPPLY_PER_LEVEL;
                new regen_amount = creep_level * CREEP_REGEN_PER_LEVEL;
                while ((obj = FindEntityByClassname(obj, "obj_sentrygun")) != -1)
                {
                    ReplenishObject(client, obj, TFObject_Sentry,
                                    supply_amount, regen_amount, creep_level);
                }

                while ((obj = FindEntityByClassname(obj, "obj_teleporter")) != -1)
                {
                    ReplenishObject(client, obj, TFObject_Teleporter,
                                    supply_amount, regen_amount, creep_level);
                }

                while ((obj = FindEntityByClassname(obj, "obj_dispenser")) != -1)
                {
                    ReplenishObject(client, obj, TFObject_Dispenser,
                                    supply_amount, regen_amount, creep_level);
                }
            }
        }
    }
    return Plugin_Continue;
}

ReplenishObject(client, obj, TFObjectType:type, supply_amount,
                regen_amount, num_rockets)
{
    if (!TF2_IsObjectCarried(obj) &&
        GetEntPropEnt(obj, Prop_Send, "m_hBuilder") == client &&
        GetEntPropFloat(obj, Prop_Send, "m_flPercentageConstructed") >= 1.0)
    {
        ApplyCreepHealthBonus(obj, GetUpgradeLevel(client, raceID, creepID));

        new iLevel = GetEntProp(obj, Prop_Send, "m_bMiniBuilding") ? 0 : 
                     GetEntProp(obj, Prop_Send, "m_iUpgradeLevel");

        if (iLevel > 0 && iLevel < 3)
        {
            new iUpgrade = GetEntProp(obj, Prop_Send, "m_iUpgradeMetal");
            if (iUpgrade < TF2_MaxUpgradeMetal)
            {
                iUpgrade += supply_amount;
                if (iUpgrade >= TF2_MaxUpgradeMetal)
                {
                    // Raising the remembered highest level makes TF2's own
                    // object think call the correct virtual StartUpgrading()
                    // implementation. That preserves the real model,
                    // animation, health, sound and teleporter behavior.
                    SetEntProp(obj, Prop_Send, "m_iUpgradeMetal", 0);
                    SetEntProp(obj, Prop_Send, "m_iHighestUpgradeLevel",
                               iLevel + 1);
                    FireCreepUpgradeEvent(client, obj, type);
                }
                else
                    SetEntProp(obj, Prop_Send, "m_iUpgradeMetal", iUpgrade);
            }                                        
        }

        new max_health = GetEntProp(obj, Prop_Data, "m_iMaxHealth");
        new health = GetEntProp(obj, Prop_Send, "m_iHealth");
        if (health < max_health)
        {
            health += regen_amount;
            if (health > max_health)
                health = max_health;

            SetEntityHealth(obj, health);
        }

        switch (type)
        {
            case TFObject_Dispenser:
            {
                new iMetal = GetEntProp(obj, Prop_Send, "m_iAmmoMetal");
                if (iMetal < TF2_MaxDispenserMetal)
                {
                    iMetal += supply_amount;
                    if (iMetal > TF2_MaxDispenserMetal)
                        iMetal = TF2_MaxDispenserMetal;
                    SetEntProp(obj, Prop_Send, "m_iAmmoMetal", iMetal);
                }
            }
            case TFObject_Sentry:
            {
                new maxShells = TF2_MaxSentryShells[iLevel];
                new iShells = GetEntProp(obj, Prop_Send, "m_iAmmoShells");
                if (iShells < maxShells)
                {
                    iShells += supply_amount;
                    if (iShells > maxShells)
                        iShells = maxShells;
                    SetEntProp(obj, Prop_Send, "m_iAmmoShells", iShells);
                }

                if (iLevel > 2)
                {
                    new maxRockets = TF2_MaxSentryRockets[iLevel];
                    new iRockets = GetEntProp(obj, Prop_Send, "m_iAmmoRockets");
                    if (iRockets < maxRockets)
                    {
                        iRockets += num_rockets;
                        if (iRockets > maxRockets)
                            iRockets = maxRockets;
                        SetEntProp(obj, Prop_Send, "m_iAmmoRockets", iRockets);
                    }
                }
            }
        }
    }
}

ApplyCreepHealthBonus(obj, creep_level)
{
    if (obj <= 0 || obj > MAXENTITIES)
        return;

    new desired_bonus = creep_level * CREEP_HEALTH_PER_LEVEL;
    new current_max = GetEntProp(obj, Prop_Data, "m_iMaxHealth");
    new stored_bonus = g_CreepHealthBonus[obj];
    new base_max = g_CreepBaseMaxHealth[obj];

    if (stored_bonus <= 0 || base_max <= 0)
        base_max = current_max;
    else if (current_max != base_max + stored_bonus)
    {
        // TF2 recalculates an object's base health when it changes level.
        // Treat that new value as the base before restoring Creep's bonus.
        base_max = current_max;
    }

    new desired_max = base_max + desired_bonus;
    if (current_max != desired_max)
    {
        new health = GetEntProp(obj, Prop_Send, "m_iHealth");
        new difference = desired_max - current_max;

        SetEntProp(obj, Prop_Data, "m_iMaxHealth", desired_max);

        if (difference > 0)
            health += difference;
        if (health > desired_max)
            health = desired_max;

        SetEntityHealth(obj, health);
    }

    g_CreepBaseMaxHealth[obj] = base_max;
    g_CreepHealthBonus[obj] = desired_bonus;
}

RemoveCreepHealthBonuses(client)
{
    decl String:classname[32];
    new maxentities = GetMaxEntities();
    for (new obj = MaxClients + 1; obj <= maxentities; obj++)
    {
        if (g_CreepHealthBonus[obj] <= 0 || !IsValidEntity(obj) ||
            GetEntPropEnt(obj, Prop_Send, "m_hBuilder") != client ||
            !GetEntityClassname(obj, classname, sizeof(classname)) ||
            (!StrEqual(classname, "obj_sentrygun") &&
             !StrEqual(classname, "obj_dispenser") &&
             !StrEqual(classname, "obj_teleporter")))
            continue;

        new current_max = GetEntProp(obj, Prop_Data, "m_iMaxHealth");
        new base_max = g_CreepBaseMaxHealth[obj];
        if (base_max > 0 &&
            current_max == base_max + g_CreepHealthBonus[obj])
        {
            SetEntProp(obj, Prop_Data, "m_iMaxHealth", base_max);
            new health = GetEntProp(obj, Prop_Send, "m_iHealth");
            if (health > base_max)
                SetEntityHealth(obj, base_max);
        }

        g_CreepBaseMaxHealth[obj] = 0;
        g_CreepHealthBonus[obj] = 0;
    }
}

FireCreepUpgradeEvent(client, obj, TFObjectType:type)
{
    new Handle:event = CreateEvent("player_upgradedobject");
    if (event != INVALID_HANDLE)
    {
        SetEventInt(event, "userid", GetClientUserId(client));
        SetEventInt(event, "object", _:type);
        SetEventInt(event, "index", obj);
        SetEventBool(event, "isbuilder", true);
        FireEvent(event);
    }
}

SetupTeleporter(client, level)
{
    if (m_TeleporterAvailable)
        SetTeleporter(client, g_NydusCanalRate[level]);
}

EvolveHiveQueen(client)
{
    if (g_hiveQueenRace < 0)
        g_hiveQueenRace = FindRace("hive_queen");

    if (g_hiveQueenRace < 0)
    {
        decl String:upgradeName[64];
        GetUpgradeName(raceID, hiveQueenID, upgradeName, sizeof(upgradeName), client);
        DisplayMessage(client, Display_Ultimate, "%t", "IsNotAvailable", upgradeName);
        LogError("***The Zerg Hive Queen race is not Available!");
        PrepareAndEmitSoundToClient(client,deniedWav);
    }
    else if (GetRestriction(client,Restriction_NoUltimates) ||
             GetRestriction(client,Restriction_Stunned))
    {
        DisplayMessage(client, Display_Ultimate, "%t", "PreventedFromHiveQueen");
        PrepareAndEmitSoundToClient(client,deniedWav);
    }
    else if (HasCooldownExpired(client, raceID, hiveQueenID))
    {
        new Float:clientLoc[3];
        GetClientAbsOrigin(client, clientLoc);
        clientLoc[2] += 40.0; // Adjust position to the middle

        TE_SetupSmoke(clientLoc, SmokeSprite(), 8.0, 2);
        TE_SendEffectToAll();

        TE_SetupGlowSprite(clientLoc,(GetClientTeam(client) == 3) ? BlueGlow() : RedGlow(),
                           5.0, 40.0, 255);
        TE_SendEffectToAll();

        ChangeRace(client, g_hiveQueenRace, true, false, true);
    }
}
