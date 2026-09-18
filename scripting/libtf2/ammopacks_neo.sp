/**
 * SourceCraft NEO Ammopacks compatibility helper.
 *
 * This intentionally replaces the 2009 helper at build time while retaining
 * its public library name and native API.  The archived original remains in
 * ammopacks.sp for reference.
 */

#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <tf2>
#include <tf2_stocks>

#define PLUGIN_VERSION "2.0-neo"

#define SMALL_MODEL  "models/items/ammopack_small.mdl"
#define MEDIUM_MODEL "models/items/ammopack_medium.mdl"
#define LARGE_MODEL  "models/items/ammopack_large.mdl"

#define SMALL_METAL  50
#define MEDIUM_METAL 100
#define LARGE_METAL  200
#define METAL_AMMO_INDEX 3

new bool:g_NativeControl = false;
new g_AmmopackMode[MAXPLAYERS + 1];

public Plugin:myinfo =
{
    name = "SourceCraft NEO Ammopacks",
    author = "SourceCraft NEO, based on Hunter and Naris",
    description = "Safe TF2 Ammopacks compatibility helper for SourceCraft",
    version = PLUGIN_VERSION,
    url = "https://github.com/somefunnybunny/SourceCraft-NEO"
};

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
    CreateNative("ControlAmmopacks", Native_ControlAmmopacks);
    CreateNative("SetAmmopack", Native_SetAmmopack);
    CreateNative("DropAmmopack", Native_DropAmmopack);
    RegPluginLibrary("ammopacks");
    return APLRes_Success;
}

public OnPluginStart()
{
    CreateConVar("sm_ammopacks_neo_version", PLUGIN_VERSION,
                 "SourceCraft NEO Ammopacks version",
                 FCVAR_DONTRECORD|FCVAR_NOTIFY);

    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
    RegConsoleCmd("sm_ammopack", Command_Ammopack);
}

public OnMapStart()
{
    PrecacheModel(SMALL_MODEL, true);
    PrecacheModel(MEDIUM_MODEL, true);
    PrecacheModel(LARGE_MODEL, true);
}

public OnClientPutInServer(client)
{
    g_AmmopackMode[client] = 0;
}

public OnClientDisconnect(client)
{
    g_AmmopackMode[client] = 0;
}

public Action:Command_Ammopack(client, args)
{
    if (client > 0 && IsClientInGame(client) && IsPlayerAlive(client) &&
        TF2_GetPlayerClass(client) == TFClass_Engineer &&
        (GetAmmopackMode(client) & 2))
    {
        DropClientAmmopack(client, -1, true);
    }

    return Plugin_Handled;
}

public Action:Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
    if (client > 0 && IsClientInGame(client) &&
        TF2_GetPlayerClass(client) == TFClass_Engineer &&
        (GetAmmopackMode(client) & 1))
    {
        new metal = GetClientMetal(client);
        DropClientAmmopack(client, metal, false);
    }

    return Plugin_Continue;
}

GetAmmopackMode(client)
{
    return g_NativeControl ? g_AmmopackMode[client] : 3;
}

GetClientMetal(client)
{
    return GetEntProp(client, Prop_Send, "m_iAmmo", 4, METAL_AMMO_INDEX);
}

SetClientMetal(client, amount)
{
    SetEntProp(client, Prop_Send, "m_iAmmo", amount, 4, METAL_AMMO_INDEX);
}

bool:DropClientAmmopack(client, suppliedMetal, bool:commandDrop)
{
    if (client <= 0 || client > MaxClients || !IsClientInGame(client))
        return false;

    new metal = suppliedMetal;
    if (metal < 0)
        metal = GetClientMetal(client);

    decl String:classname[32];
    new cost;
    if (metal >= LARGE_METAL)
    {
        strcopy(classname, sizeof(classname), "item_ammopack_full");
        cost = LARGE_METAL;
    }
    else if (metal >= MEDIUM_METAL)
    {
        strcopy(classname, sizeof(classname), "item_ammopack_medium");
        cost = MEDIUM_METAL;
    }
    else if (metal >= SMALL_METAL)
    {
        strcopy(classname, sizeof(classname), "item_ammopack_small");
        cost = SMALL_METAL;
    }
    else
        return false;

    if (GetEntityCount() >= GetMaxEntities() - 64)
        return false;

    new pack = CreateEntityByName(classname);
    if (pack <= MaxClients || !IsValidEntity(pack))
        return false;

    DispatchKeyValue(pack, "OnPlayerTouch", "!self,Kill,,0,-1");
    if (!DispatchSpawn(pack))
    {
        AcceptEntityInput(pack, "Kill");
        return false;
    }

    new Float:position[3];
    GetClientAbsOrigin(client, position);
    position[2] += 16.0;

    if (commandDrop && IsPlayerAlive(client))
    {
        new Float:eyeAngles[3], Float:forwardVector[3];
        GetClientEyeAngles(client, eyeAngles);
        eyeAngles[0] = 0.0;
        GetAngleVectors(eyeAngles, forwardVector, NULL_VECTOR, NULL_VECTOR);
        position[0] += forwardVector[0] * 64.0;
        position[1] += forwardVector[1] * 64.0;
    }

    SetEntProp(pack, Prop_Send, "m_iTeamNum",
               commandDrop ? GetClientTeam(client) : 0);
    TeleportEntity(pack, position, NULL_VECTOR, NULL_VECTOR);
    CreateTimer(60.0, Timer_RemoveAmmopack, EntIndexToEntRef(pack),
                TIMER_FLAG_NO_MAPCHANGE);

    if (commandDrop && suppliedMetal < 0)
        SetClientMetal(client, metal - cost);

    return true;
}

public Action:Timer_RemoveAmmopack(Handle:timer, any:reference)
{
    new pack = EntRefToEntIndex(reference);
    if (pack > MaxClients && IsValidEntity(pack))
        AcceptEntityInput(pack, "Kill");

    return Plugin_Stop;
}

public Native_ControlAmmopacks(Handle:plugin, numParams)
{
    g_NativeControl = bool:GetNativeCell(1);
}

public Native_SetAmmopack(Handle:plugin, numParams)
{
    new client = GetNativeCell(1);
    if (client > 0 && client <= MaxClients)
        g_AmmopackMode[client] = GetNativeCell(2);
}

public Native_DropAmmopack(Handle:plugin, numParams)
{
    new client = GetNativeCell(1);
    new metal = (numParams >= 2) ? GetNativeCell(2) : -1;
    return DropClientAmmopack(client, metal, true);
}
