/**
 * SourceCraft NEO gravity gun compatibility layer.
 *
 * Preserves the public ztf2grab API used by SourceCraft while replacing the
 * legacy global entity caches and per-entity timer arrays. Engineer buildings
 * are tracked exclusively through entity references and per-client state.
 */

#pragma semicolon 1

#include <sourcemod>
#include <sdktools>

#define _ztf2grab_plugin
#include <lib/ztf2grab>

#define PLUGIN_VERSION "0.1.0-neo"

enum GrabKind
{
    Grab_None = 0,
    Grab_Building,
    Grab_Prop
};

new g_ObjectRef[MAXPLAYERS + 1];
new GrabKind:g_ObjectKind[MAXPLAYERS + 1];
new g_Permissions[MAXPLAYERS + 1];
new MoveType:g_OldMoveType[MAXPLAYERS + 1];
new Float:g_OldGravity[MAXPLAYERS + 1];
new bool:g_WasDisabled[MAXPLAYERS + 1];
new bool:g_DisabledByUs[MAXPLAYERS + 1];
new g_PickupHealth[MAXPLAYERS + 1];
new Float:g_GrabTime[MAXPLAYERS + 1];
new Float:g_MaxDuration[MAXPLAYERS + 1];
new Float:g_ThrowSpeed[MAXPLAYERS + 1];
new Float:g_ThrowGravity[MAXPLAYERS + 1];
new Float:g_ThrowStarted[MAXPLAYERS + 1];
new Float:g_Rotation[MAXPLAYERS + 1];
new bool:g_JustGrabbed[MAXPLAYERS + 1];

new Handle:g_UpdateTimer = INVALID_HANDLE;
new Handle:g_Settling = INVALID_HANDLE;

new Handle:g_OnPickupObject = INVALID_HANDLE;
new Handle:g_OnCarryObject = INVALID_HANDLE;
new Handle:g_OnThrowObject = INVALID_HANDLE;
new Handle:g_OnDropObject = INVALID_HANDLE;
new Handle:g_OnObjectStop = INVALID_HANDLE;

new Handle:g_CvarDistance = INVALID_HANDLE;
new Handle:g_CvarReach = INVALID_HANDLE;
new Handle:g_CvarFollowSpeed = INVALID_HANDLE;
new Handle:g_CvarThrowCharge = INVALID_HANDLE;
new Handle:g_CvarMinCharge = INVALID_HANDLE;
new Handle:g_CvarDefaultThrowSpeed = INVALID_HANDLE;
new Handle:g_CvarDefaultThrowGravity = INVALID_HANDLE;
new Handle:g_CvarDefaultDuration = INVALID_HANDLE;
new Handle:g_CvarSettleTime = INVALID_HANDLE;

new const String:g_PickupSound[] = "weapons/physcannon/physcannon_pickup.wav";
new const String:g_DropSound[] = "weapons/physcannon/physcannon_drop.wav";
new const String:g_ThrowSound[] = "weapons/physcannon/superphys_launch1.wav";
new const String:g_MissSound[] = "weapons/physcannon/physcannon_dryfire.wav";
new const String:g_InvalidSound[] = "weapons/physcannon/physcannon_tooheavy.wav";

public Plugin:myinfo =
{
    name = "SourceCraft NEO Gravity Gun",
    author = "SourceCraft NEO contributors",
    description = "Safe ztf2grab-compatible Engineer building transport",
    version = PLUGIN_VERSION,
    url = "https://github.com/somefunnybunny/SourceCraft-NEO"
};

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], errMax)
{
    CreateNative("ControlZtf2grab", Native_ControlZtf2grab);
    CreateNative("GiveGravgun", Native_GiveGravgun);
    CreateNative("TakeGravgun", Native_TakeGravgun);
    CreateNative("PickupObject", Native_PickupObject);
    CreateNative("DropObject", Native_DropObject);
    CreateNative("StartThrowObject", Native_StartThrowObject);
    CreateNative("ThrowObject", Native_ThrowObject);
    CreateNative("RotateObject", Native_RotateObject);
    CreateNative("DropEntity", Native_DropEntity);
    CreateNative("HasObject", Native_HasObject);
    CreateNative("IsObjectGrabbed", Native_IsObjectGrabbed);

    g_OnPickupObject = CreateGlobalForward("OnPickupObject", ET_Hook,
                                           Param_Cell, Param_Cell, Param_Cell);
    g_OnCarryObject = CreateGlobalForward("OnCarryObject", ET_Hook,
                                          Param_Cell, Param_Cell, Param_Float);
    g_OnThrowObject = CreateGlobalForward("OnThrowObject", ET_Hook,
                                          Param_Cell, Param_Cell);
    g_OnDropObject = CreateGlobalForward("OnDropObject", ET_Ignore,
                                         Param_Cell, Param_Cell);
    g_OnObjectStop = CreateGlobalForward("OnObjectStop", ET_Ignore,
                                         Param_Cell);

    RegPluginLibrary("ztf2grab");
    return APLRes_Success;
}

public OnPluginStart()
{
    CreateConVar("sm_grab_version", PLUGIN_VERSION,
                 "SourceCraft NEO Gravity Gun", FCVAR_SPONLY|FCVAR_NOTIFY);
    g_CvarDistance = CreateConVar("sm_grab_distance", "100.0",
                                  "Distance at which the gravity gun holds objects");
    g_CvarReach = CreateConVar("sm_grab_reach", "512.0",
                               "Maximum distance from which an object can be grabbed");
    g_CvarFollowSpeed = CreateConVar("sm_grab_speed", "12.0",
                                     "How quickly a held object follows its target");
    g_CvarThrowCharge = CreateConVar("sm_grab_throwcharge", "2.0",
                                     "Seconds required for a full-strength throw");
    g_CvarMinCharge = CreateConVar("sm_grab_mincharge", "0.2",
                                   "Charge shorter than this drops instead of throwing");
    g_CvarDefaultThrowSpeed = CreateConVar("sm_grab_throwspeed", "1000.0",
                                           "Default full-strength throw speed");
    g_CvarDefaultThrowGravity = CreateConVar("sm_grab_throwgrav", "1.0",
                                             "Default gravity of thrown objects");
    g_CvarDefaultDuration = CreateConVar("sm_grab_fatiguetime", "0.0",
                                         "Default maximum hold time; zero is unlimited");
    g_CvarSettleTime = CreateConVar("sm_grab_settletime", "4.0",
                                    "Maximum seconds before a dropped object is restored");

    RegConsoleCmd("+grav", Command_Grab);
    RegConsoleCmd("-grav", Command_ReleaseGrabKey);
    RegConsoleCmd("+throw", Command_StartThrow);
    RegConsoleCmd("-throw", Command_FinishThrow);
    RegConsoleCmd("rotate", Command_Rotate);
    RegConsoleCmd("+rotate", Command_Rotate);
    RegConsoleCmd("-rotate", Command_ReleaseRotateKey);

    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
    HookEvent("teamplay_round_start", Event_RoundStart, EventHookMode_PostNoCopy);

    g_Settling = CreateTrie();
    g_UpdateTimer = CreateTimer(0.05, Timer_UpdateHeldObjects, INVALID_HANDLE,
                                TIMER_REPEAT);

    for (new client = 1; client <= MaxClients; client++)
        ResetClientState(client);
}

public OnMapStart()
{
    PrecacheSound(g_PickupSound, true);
    PrecacheSound(g_DropSound, true);
    PrecacheSound(g_ThrowSound, true);
    PrecacheSound(g_MissSound, true);
    PrecacheSound(g_InvalidSound, true);

    if (g_Settling != INVALID_HANDLE)
        ClearTrie(g_Settling);

    for (new client = 1; client <= MaxClients; client++)
        ResetClientState(client);
}

public OnPluginEnd()
{
    for (new client = 1; client <= MaxClients; client++)
    {
        if (HasHeldObject(client))
            ReleaseHeldObject(client, false, true);
    }

    if (g_UpdateTimer != INVALID_HANDLE)
    {
        CloseHandle(g_UpdateTimer);
        g_UpdateTimer = INVALID_HANDLE;
    }
}

public OnClientPutInServer(client)
{
    ResetClientState(client);
}

public OnClientDisconnect(client)
{
    if (HasHeldObject(client))
        ReleaseHeldObject(client, false, true);
    ResetClientState(client);
}

public Action:Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
    if (client > 0 && HasHeldObject(client))
        ReleaseHeldObject(client, false, false);
    return Plugin_Continue;
}

public Action:Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
    for (new client = 1; client <= MaxClients; client++)
    {
        if (HasHeldObject(client))
            ReleaseHeldObject(client, false, true);
    }
    return Plugin_Continue;
}

ResetClientState(client)
{
    g_ObjectRef[client] = INVALID_ENT_REFERENCE;
    g_ObjectKind[client] = Grab_None;
    g_Permissions[client] = 0;
    g_OldMoveType[client] = MOVETYPE_NONE;
    g_OldGravity[client] = 1.0;
    g_WasDisabled[client] = false;
    g_DisabledByUs[client] = false;
    g_PickupHealth[client] = 0;
    g_GrabTime[client] = 0.0;
    g_MaxDuration[client] = 0.0;
    g_ThrowSpeed[client] = 0.0;
    g_ThrowGravity[client] = 1.0;
    g_ThrowStarted[client] = 0.0;
    g_Rotation[client] = 0.0;
    g_JustGrabbed[client] = false;
}

bool:IsUsableClient(client, bool:alive=false)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client) &&
            (!alive || IsPlayerAlive(client)));
}

bool:HasHeldObject(client)
{
    return (client > 0 && client <= MaxClients &&
            g_ObjectRef[client] != INVALID_ENT_REFERENCE &&
            EntRefToEntIndex(g_ObjectRef[client]) > MaxClients);
}

BuildReferenceKey(ref, String:key[], maxlen)
{
    IntToString(ref, key, maxlen);
}

bool:IsSettling(entity)
{
    if (g_Settling == INVALID_HANDLE || entity <= MaxClients || !IsValidEntity(entity))
        return false;

    decl String:key[24];
    BuildReferenceKey(EntIndexToEntRef(entity), key, sizeof(key));
    new value;
    return GetTrieValue(g_Settling, key, value);
}

FindHolder(entity)
{
    for (new client = 1; client <= MaxClients; client++)
    {
        if (HasHeldObject(client) && EntRefToEntIndex(g_ObjectRef[client]) == entity)
            return client;
    }
    return 0;
}

GrabKind:GetGrabKind(entity)
{
    if (entity <= MaxClients || !IsValidEntity(entity))
        return Grab_None;

    decl String:classname[64];
    GetEntityClassname(entity, classname, sizeof(classname));

    if (StrEqual(classname, "obj_sentrygun") ||
        StrEqual(classname, "obj_dispenser") ||
        StrEqual(classname, "obj_teleporter"))
    {
        return Grab_Building;
    }

    if (StrContains(classname, "prop_physics") == 0)
        return Grab_Prop;

    return Grab_None;
}

public bool:TraceFilter_NoPlayers(entity, contentsMask, any:data)
{
    return (entity != data && (entity <= 0 || entity > MaxClients));
}

TraceTarget(client)
{
    decl Float:eye[3], Float:angles[3], Float:hit[3];
    GetClientEyePosition(client, eye);
    GetClientEyeAngles(client, angles);

    TR_TraceRayFilter(eye, angles, MASK_SOLID, RayType_Infinite,
                      TraceFilter_NoPlayers, client);
    if (!TR_DidHit())
        return -1;

    new entity = TR_GetEntityIndex();
    if (entity <= MaxClients || !IsValidEntity(entity))
        return -1;

    TR_GetEndPosition(hit);
    if (GetVectorDistance(eye, hit) > GetConVarFloat(g_CvarReach))
        return -1;

    return entity;
}

bool:IsNativeCarriedBuilding(entity)
{
    return ((HasEntProp(entity, Prop_Send, "m_bCarried") &&
             GetEntProp(entity, Prop_Send, "m_bCarried")) ||
            (HasEntProp(entity, Prop_Send, "m_bCarryDeploy") &&
             GetEntProp(entity, Prop_Send, "m_bCarryDeploy")));
}

public Action:Command_Grab(client, args)
{
    if (!IsUsableClient(client, true))
        return Plugin_Handled;

    if (HasHeldObject(client))
    {
        ReleaseHeldObject(client, false, false);
        return Plugin_Handled;
    }

    if (!(g_Permissions[client] & HAS_GRABBER))
        return Plugin_Handled;

    new entity = TraceTarget(client);
    if (entity < 1)
    {
        EmitSoundToClient(client, g_MissSound);
        return Plugin_Handled;
    }

    new GrabKind:kind = GetGrabKind(entity);
    if (kind == Grab_None ||
        (kind == Grab_Building && !(g_Permissions[client] & CAN_GRAB_BUILDINGS)) ||
        (kind == Grab_Prop && !(g_Permissions[client] & CAN_GRAB_PROPS)) ||
        IsSettling(entity))
    {
        EmitSoundToClient(client, g_InvalidSound);
        return Plugin_Handled;
    }

    new otherHolder = FindHolder(entity);
    if (otherHolder > 0)
    {
        if (!(g_Permissions[client] & CAN_STEAL))
        {
            EmitSoundToClient(client, g_InvalidSound);
            return Plugin_Handled;
        }
        ReleaseHeldObject(otherHolder, false, true);
    }

    new builder = 0;
    if (kind == Grab_Building)
    {
        if (IsNativeCarriedBuilding(entity) ||
            (HasEntProp(entity, Prop_Send, "m_flPercentageConstructed") &&
             GetEntPropFloat(entity, Prop_Send, "m_flPercentageConstructed") < 1.0))
        {
            EmitSoundToClient(client, g_InvalidSound);
            return Plugin_Handled;
        }

        builder = GetEntPropEnt(entity, Prop_Send, "m_hBuilder");
        if (builder <= 0 ||
            (builder != client && !(g_Permissions[client] & CAN_GRAB_OTHER_BUILDINGS)) ||
            (!(g_Permissions[client] & CAN_HOLD_WHILE_SAPPED) &&
             GetEntProp(entity, Prop_Send, "m_bHasSapper")))
        {
            EmitSoundToClient(client, g_InvalidSound);
            return Plugin_Handled;
        }
    }

    new Action:result = Plugin_Continue;
    Call_StartForward(g_OnPickupObject);
    Call_PushCell(client);
    Call_PushCell(builder);
    Call_PushCell(entity);
    Call_Finish(result);
    if (result != Plugin_Continue)
    {
        EmitSoundToClient(client, g_InvalidSound);
        return Plugin_Handled;
    }

    g_ObjectRef[client] = EntIndexToEntRef(entity);
    g_ObjectKind[client] = kind;
    g_OldMoveType[client] = GetEntityMoveType(entity);
    g_OldGravity[client] = GetEntityGravity(entity);
    g_GrabTime[client] = GetEngineTime();
    g_ThrowStarted[client] = 0.0;
    g_Rotation[client] = 0.0;
    g_JustGrabbed[client] = true;
    g_DisabledByUs[client] = false;

    if (kind == Grab_Building)
    {
        g_PickupHealth[client] = GetEntProp(entity, Prop_Send, "m_iHealth");
        g_WasDisabled[client] = bool:GetEntProp(entity, Prop_Send, "m_bDisabled");

        if (!(g_Permissions[client] & CAN_HOLD_ENABLED_BUILDINGS) &&
            !g_WasDisabled[client])
        {
            SetEntProp(entity, Prop_Send, "m_bDisabled", 1);
            g_DisabledByUs[client] = true;
        }
    }

    SetEntityGravity(entity, 0.0);
    SetEntityMoveType(entity, MOVETYPE_FLY);
    EmitSoundToAll(g_PickupSound, entity);
    return Plugin_Handled;
}

public Action:Command_ReleaseGrabKey(client, args)
{
    if (client > 0 && client <= MaxClients)
        g_JustGrabbed[client] = false;
    return Plugin_Handled;
}

public Action:Command_StartThrow(client, args)
{
    if (!IsUsableClient(client, true))
        return Plugin_Handled;

    if (!HasHeldObject(client))
        return Command_Grab(client, args);

    if (g_ObjectKind[client] == Grab_Building &&
        !(g_Permissions[client] & CAN_THROW_BUILDINGS))
    {
        ReleaseHeldObject(client, false, false);
        return Plugin_Handled;
    }

    g_ThrowStarted[client] = GetEngineTime();
    return Plugin_Handled;
}

public Action:Command_FinishThrow(client, args)
{
    if (client <= 0 || client > MaxClients)
        return Plugin_Handled;

    if (g_JustGrabbed[client])
    {
        g_JustGrabbed[client] = false;
        return Plugin_Handled;
    }

    if (!HasHeldObject(client) || g_ThrowStarted[client] <= 0.0)
        return Plugin_Handled;

    new Float:held = GetEngineTime() - g_ThrowStarted[client];
    if (held < GetConVarFloat(g_CvarMinCharge))
    {
        ReleaseHeldObject(client, false, false);
        return Plugin_Handled;
    }

    new entity = EntRefToEntIndex(g_ObjectRef[client]);
    new Action:result = Plugin_Continue;
    Call_StartForward(g_OnThrowObject);
    Call_PushCell(client);
    Call_PushCell(entity);
    Call_Finish(result);

    if (result == Plugin_Continue)
        ReleaseHeldObject(client, true, false);
    else
        ReleaseHeldObject(client, false, false);

    return Plugin_Handled;
}

public Action:Command_Rotate(client, args)
{
    if (client > 0 && client <= MaxClients && HasHeldObject(client))
    {
        g_Rotation[client] += 90.0;
        if (g_Rotation[client] > 180.0)
            g_Rotation[client] = -90.0;
    }
    return Plugin_Handled;
}

public Action:Command_ReleaseRotateKey(client, args)
{
    return Plugin_Handled;
}

public Action:Timer_UpdateHeldObjects(Handle:timer)
{
    for (new client = 1; client <= MaxClients; client++)
    {
        if (!HasHeldObject(client))
            continue;

        new entity = EntRefToEntIndex(g_ObjectRef[client]);
        if (!IsUsableClient(client, true) || entity <= MaxClients || !IsValidEntity(entity))
        {
            ClearHeldState(client);
            continue;
        }

        if (!(g_Permissions[client] & CAN_JUMP_WHILE_HOLDING) &&
            (GetClientButtons(client) & IN_JUMP))
        {
            ReleaseHeldObject(client, false, false);
            continue;
        }

        if (g_ObjectKind[client] == Grab_Building)
        {
            if (!(g_Permissions[client] & CAN_HOLD_WHILE_SAPPED) &&
                GetEntProp(entity, Prop_Send, "m_bHasSapper"))
            {
                ReleaseHeldObject(client, false, false);
                continue;
            }

            if (!(g_Permissions[client] & CAN_REPAIR_WHILE_HOLDING) &&
                GetEntProp(entity, Prop_Send, "m_iHealth") > g_PickupHealth[client])
            {
                SetEntProp(entity, Prop_Send, "m_iHealth", g_PickupHealth[client]);
            }

            if (!(g_Permissions[client] & CAN_HOLD_ENABLED_BUILDINGS))
            {
                if (!GetEntProp(entity, Prop_Send, "m_bDisabled"))
                    SetEntProp(entity, Prop_Send, "m_bDisabled", 1);
                if (!g_WasDisabled[client])
                    g_DisabledByUs[client] = true;
            }
        }

        new Action:result = Plugin_Continue;
        Call_StartForward(g_OnCarryObject);
        Call_PushCell(client);
        Call_PushCell(entity);
        Call_PushFloat(g_GrabTime[client]);
        Call_Finish(result);

        if (result == Plugin_Stop)
        {
            ReleaseHeldObject(client, false, false);
            continue;
        }
        else if (result == Plugin_Changed && g_ObjectKind[client] == Grab_Building &&
                 GetEntProp(entity, Prop_Send, "m_bDisabled") &&
                 !g_WasDisabled[client])
        {
            g_DisabledByUs[client] = true;
        }

        if (g_MaxDuration[client] > 0.0 &&
            GetEngineTime() - g_GrabTime[client] >= g_MaxDuration[client])
        {
            ReleaseHeldObject(client, false, false);
            continue;
        }

        decl Float:eye[3], Float:angles[3], Float:forwardVec[3];
        decl Float:position[3], Float:target[3], Float:velocity[3];
        GetClientEyePosition(client, eye);
        GetClientEyeAngles(client, angles);
        GetAngleVectors(angles, forwardVec, NULL_VECTOR, NULL_VECTOR);

        new Float:distance = GetConVarFloat(g_CvarDistance);
        target[0] = eye[0] + forwardVec[0] * distance;
        target[1] = eye[1] + forwardVec[1] * distance;
        target[2] = eye[2] + forwardVec[2] * distance;

        GetEntPropVector(entity, Prop_Send, "m_vecOrigin", position);
        SubtractVectors(target, position, velocity);
        ScaleVector(velocity, GetConVarFloat(g_CvarFollowSpeed));

        new Float:speed = GetVectorLength(velocity);
        if (speed > 1200.0)
            ScaleVector(velocity, 1200.0 / speed);

        angles[0] = 0.0;
        angles[1] += g_Rotation[client];
        angles[2] = 0.0;
        TeleportEntity(entity, NULL_VECTOR, angles, velocity);
    }

    return Plugin_Continue;
}

ClearHeldState(client)
{
    g_ObjectRef[client] = INVALID_ENT_REFERENCE;
    g_ObjectKind[client] = Grab_None;
    g_ThrowStarted[client] = 0.0;
    g_GrabTime[client] = 0.0;
    g_JustGrabbed[client] = false;
    g_DisabledByUs[client] = false;
    g_PickupHealth[client] = 0;
}

RestoreBuildingDisabledState(entity, bool:wasDisabled, bool:disabledByUs)
{
    if (!disabledByUs || entity <= MaxClients || !IsValidEntity(entity))
        return;

    if (wasDisabled || GetEntProp(entity, Prop_Send, "m_bHasSapper"))
        SetEntProp(entity, Prop_Send, "m_bDisabled", 1);
    else
        SetEntProp(entity, Prop_Send, "m_bDisabled", 0);
}

ReleaseHeldObject(client, bool:throwIt, bool:immediate)
{
    new ref = g_ObjectRef[client];
    new entity = EntRefToEntIndex(ref);
    if (entity <= MaxClients || !IsValidEntity(entity))
    {
        ClearHeldState(client);
        return;
    }

    new GrabKind:kind = g_ObjectKind[client];
    new MoveType:oldMoveType = g_OldMoveType[client];
    new Float:oldGravity = g_OldGravity[client];
    new bool:wasDisabled = g_WasDisabled[client];
    new bool:disabledByUs = g_DisabledByUs[client];

    if (kind == Grab_Building && throwIt &&
        !(g_Permissions[client] & CAN_THROW_ENABLED_BUILDINGS) &&
        !GetEntProp(entity, Prop_Send, "m_bDisabled"))
    {
        SetEntProp(entity, Prop_Send, "m_bDisabled", 1);
        if (!wasDisabled)
            disabledByUs = true;
    }

    if (immediate)
    {
        static const Float:stopped[3] = { 0.0, 0.0, 0.0 };
        TeleportEntity(entity, NULL_VECTOR, NULL_VECTOR, stopped);
        SetEntityMoveType(entity, oldMoveType);
        SetEntityGravity(entity, oldGravity);
        if (kind == Grab_Building)
            RestoreBuildingDisabledState(entity, wasDisabled, disabledByUs);
    }
    else
    {
        decl Float:velocity[3];
        if (throwIt)
        {
            decl Float:angles[3];
            GetClientEyeAngles(client, angles);
            GetAngleVectors(angles, velocity, NULL_VECTOR, NULL_VECTOR);

            new Float:charge = GetEngineTime() - g_ThrowStarted[client];
            new Float:maxCharge = GetConVarFloat(g_CvarThrowCharge);
            new Float:percent = (maxCharge > 0.0) ? charge / maxCharge : 1.0;
            if (percent > 1.0)
                percent = 1.0;
            ScaleVector(velocity, g_ThrowSpeed[client] * percent);
            EmitSoundToAll(g_ThrowSound, entity);
        }
        else
        {
            velocity[0] = 0.0;
            velocity[1] = 0.0;
            velocity[2] = -50.0;
            EmitSoundToAll(g_DropSound, entity);
        }

        new Float:fallGravity = throwIt ? g_ThrowGravity[client] : 1.0;
        SetEntityGravity(entity, fallGravity);
        SetEntityMoveType(entity, fallGravity <= 0.0 ? MOVETYPE_FLY : MOVETYPE_FLYGRAVITY);
        TeleportEntity(entity, NULL_VECTOR, NULL_VECTOR, velocity);
        StartSettlement(entity, oldMoveType, oldGravity, wasDisabled,
                        disabledByUs, kind == Grab_Building);
    }

    if (!throwIt)
    {
        Call_StartForward(g_OnDropObject);
        Call_PushCell(client);
        Call_PushCell(entity);
        Call_Finish();
    }

    ClearHeldState(client);
}

StartSettlement(entity, MoveType:oldMoveType, Float:oldGravity,
                bool:wasDisabled, bool:disabledByUs, bool:isBuilding)
{
    new ref = EntIndexToEntRef(entity);
    decl String:key[24];
    BuildReferenceKey(ref, key, sizeof(key));
    SetTrieValue(g_Settling, key, 1);

    new Handle:pack;
    CreateDataTimer(0.1, Timer_SettleObject, pack,
                    TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
    WritePackCell(pack, ref);
    WritePackCell(pack, _:oldMoveType);
    WritePackFloat(pack, oldGravity);
    WritePackCell(pack, wasDisabled);
    WritePackCell(pack, disabledByUs);
    WritePackCell(pack, isBuilding);
    WritePackFloat(pack, GetEngineTime());
}

public Action:Timer_SettleObject(Handle:timer, Handle:pack)
{
    ResetPack(pack);
    new ref = ReadPackCell(pack);
    new MoveType:oldMoveType = MoveType:ReadPackCell(pack);
    new Float:oldGravity = ReadPackFloat(pack);
    new bool:wasDisabled = bool:ReadPackCell(pack);
    new bool:disabledByUs = bool:ReadPackCell(pack);
    new bool:isBuilding = bool:ReadPackCell(pack);
    new Float:started = ReadPackFloat(pack);

    decl String:key[24];
    BuildReferenceKey(ref, key, sizeof(key));

    new entity = EntRefToEntIndex(ref);
    if (entity <= MaxClients || !IsValidEntity(entity))
    {
        RemoveFromTrie(g_Settling, key);
        return Plugin_Stop;
    }

    decl Float:velocity[3];
    GetEntPropVector(entity, Prop_Data, "m_vecAbsVelocity", velocity);
    new Float:elapsed = GetEngineTime() - started;
    new bool:grounded = ((GetEntityFlags(entity) & FL_ONGROUND) != 0);
    new bool:slow = (GetVectorLength(velocity) <= 15.0);

    if ((elapsed >= 0.35 && (grounded || slow)) ||
        elapsed >= GetConVarFloat(g_CvarSettleTime))
    {
        static const Float:stopped[3] = { 0.0, 0.0, 0.0 };
        TeleportEntity(entity, NULL_VECTOR, NULL_VECTOR, stopped);
        SetEntityMoveType(entity, oldMoveType);
        SetEntityGravity(entity, oldGravity);

        if (isBuilding)
            RestoreBuildingDisabledState(entity, wasDisabled, disabledByUs);

        RemoveFromTrie(g_Settling, key);
        Call_StartForward(g_OnObjectStop);
        Call_PushCell(entity);
        Call_Finish();
        return Plugin_Stop;
    }

    return Plugin_Continue;
}

public Native_ControlZtf2grab(Handle:plugin, numParams)
{
    return 0;
}

public Native_GiveGravgun(Handle:plugin, numParams)
{
    new client = GetNativeCell(1);
    if (client <= 0 || client > MaxClients)
        return 0;

    g_MaxDuration[client] = (numParams >= 2) ? (Float:GetNativeCell(2)) : -1.0;
    g_ThrowSpeed[client] = (numParams >= 3) ? (Float:GetNativeCell(3)) : -1.0;
    g_ThrowGravity[client] = (numParams >= 4) ? (Float:GetNativeCell(4)) : -1.0;
    g_Permissions[client] = (numParams >= 5) ? GetNativeCell(5) : HAS_GRABBER;

    if (g_MaxDuration[client] < 0.0)
        g_MaxDuration[client] = GetConVarFloat(g_CvarDefaultDuration);
    if (g_ThrowSpeed[client] < 0.0)
        g_ThrowSpeed[client] = GetConVarFloat(g_CvarDefaultThrowSpeed);
    if (g_ThrowGravity[client] < 0.0)
        g_ThrowGravity[client] = GetConVarFloat(g_CvarDefaultThrowGravity);

    return 0;
}

public Native_TakeGravgun(Handle:plugin, numParams)
{
    new client = GetNativeCell(1);
    if (client > 0 && client <= MaxClients)
    {
        if (HasHeldObject(client))
            ReleaseHeldObject(client, false, false);
        g_Permissions[client] = 0;
    }
    return 0;
}

public Native_PickupObject(Handle:plugin, numParams)
{
    Command_Grab(GetNativeCell(1), 0);
    return 0;
}

public Native_DropObject(Handle:plugin, numParams)
{
    new client = GetNativeCell(1);
    if (client > 0 && client <= MaxClients && HasHeldObject(client))
        ReleaseHeldObject(client, false, false);
    return 0;
}

public Native_StartThrowObject(Handle:plugin, numParams)
{
    Command_StartThrow(GetNativeCell(1), 0);
    return 0;
}

public Native_ThrowObject(Handle:plugin, numParams)
{
    Command_FinishThrow(GetNativeCell(1), 0);
    return 0;
}

public Native_RotateObject(Handle:plugin, numParams)
{
    Command_Rotate(GetNativeCell(1), 0);
    return 0;
}

public Native_DropEntity(Handle:plugin, numParams)
{
    new entity = GetNativeCell(1);
    if (entity <= MaxClients || !IsValidEntity(entity) || IsSettling(entity) ||
        FindHolder(entity) > 0)
    {
        return 0;
    }

    new Float:speed = (numParams >= 2) ? (Float:GetNativeCell(2)) : -1.0;
    new Float:gravity = (numParams >= 3) ? (Float:GetNativeCell(3)) : 1.0;
    new MoveType:oldMoveType = GetEntityMoveType(entity);
    new Float:oldGravity = GetEntityGravity(entity);
    new bool:isBuilding = (GetGrabKind(entity) == Grab_Building);
    new bool:wasDisabled = isBuilding ? (GetEntProp(entity, Prop_Send, "m_bDisabled") != 0) : false;

    decl Float:velocity[3];
    velocity[0] = 0.0;
    velocity[1] = 0.0;
    velocity[2] = speed;
    SetEntityGravity(entity, gravity);
    if (gravity <= 0.0)
        SetEntityMoveType(entity, MOVETYPE_FLY);
    else
        SetEntityMoveType(entity, MOVETYPE_FLYGRAVITY);
    TeleportEntity(entity, NULL_VECTOR, NULL_VECTOR, velocity);
    StartSettlement(entity, oldMoveType, oldGravity, wasDisabled, false, isBuilding);
    return 0;
}

public Native_HasObject(Handle:plugin, numParams)
{
    new client = GetNativeCell(1);
    if (client <= 0 || client > MaxClients)
        return (numParams >= 2 && GetNativeCell(2)) ? INVALID_ENT_REFERENCE : 0;

    if (numParams >= 2 && GetNativeCell(2))
        return HasHeldObject(client) ? g_ObjectRef[client] : INVALID_ENT_REFERENCE;
    return HasHeldObject(client);
}

public Native_IsObjectGrabbed(Handle:plugin, numParams)
{
    new entity = GetNativeCell(1);
    return (entity > MaxClients && IsValidEntity(entity) &&
            (FindHolder(entity) > 0 || IsSettling(entity)));
}
