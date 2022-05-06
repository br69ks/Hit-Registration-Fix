#include <sourcemod>
#include <dhooks>
#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = 
{
	name 	= "Lag Compensation Fix",
	author 	= "brooks, D34DSpy, xutaxkamay",
	version = "6.9"
};

#define DEBUG

DynamicHook g_WantsLagCompensationOnEntity;
Address distance_sqr;
ConVar mp_teammates_are_enemies;
ConVar mp_friendlyfire;
ConVar sv_lagcompensation_teleport_dist;
int distance_sqr_old;

public void OnPluginStart()
{
	GameData data = new GameData("LagComp.games");
	
	if (!data)
		SetFailState("Failed to load LagComp.games.txt!");
	
	int offset = data.GetOffset("WantsLagComp");
	distance_sqr = data.GetAddress("DistanceSqr");
	delete data;
	
	sv_lagcompensation_teleport_dist = FindConVar("sv_lagcompensation_teleport_dist");
	if (sv_lagcompensation_teleport_dist != null)
		sv_lagcompensation_teleport_dist.SetInt(0x7F7FFFFF);

	if (distance_sqr != Address_Null)
	{
		if ((distance_sqr_old = LoadFromAddress(distance_sqr, NumberType_Int32)))
		{
			StoreToAddress(distance_sqr, 0x7F7FFFFF, NumberType_Int32);
#if defined DEBUG
			LogMessage("[Lag Compensation Fix] Patched LAG_COMPENSATION_TELEPORTED_DISTANCE_SQR");
#endif
		}
		else
			LogError("Signature for LAG_COMPENSATION_TELEPORTED_DISTANCE_SQR needs to be updated.");
	}

	if (offset != -1)
	{
		g_WantsLagCompensationOnEntity = new DynamicHook(offset, HookType_Entity, ReturnType_Bool, ThisPointer_CBaseEntity);
		g_WantsLagCompensationOnEntity.AddParam(HookParamType_CBaseEntity);
#if defined DEBUG
		LogMessage("[Lag Compensation Fix] Patched WantsLagCompensationOnEntity");
#endif
	}
	mp_teammates_are_enemies = FindConVar("mp_teammates_are_enemies");
	mp_friendlyfire = FindConVar("mp_friendlyfire");

#if defined DEBUG
	RegServerCmd("sm_checkpatches", Command_CheckPatches);
#endif
	
	for (int i = 1; i <= MaxClients; i++)
		OnClientPutInServer(i);
}

public void OnPluginEnd()
{
	if (distance_sqr != Address_Null)
		StoreToAddress(distance_sqr, distance_sqr_old, NumberType_Int32);
}

public void OnClientPutInServer(int client) 
{
	if (IsValidClient(client) && (g_WantsLagCompensationOnEntity != null))
		g_WantsLagCompensationOnEntity.HookEntity(Hook_Post, client, WantsLagCompensationOnEntity);
}

public MRESReturn WantsLagCompensationOnEntity(int client, DHookReturn hReturn, DHookParam hParams)
{
	int entity = hParams.Get(1);

	if (IsValidClient(client) && IsPlayerAlive(client) && IsValidClient(entity) && IsPlayerAlive(entity))
	{
		if (mp_teammates_are_enemies == null || !mp_teammates_are_enemies.BoolValue)
		{
			if (!mp_friendlyfire.BoolValue)
			{
				if (GetClientTeam(client) == GetClientTeam(entity))
					return MRES_Ignored;
			}
		}
		
		hReturn.Value = true;
		return MRES_Override;
	}
	return MRES_Ignored;
}

public Action Command_CheckPatches(int args)
{
	PrintToServer("LAG_COMPENSATION_TELEPORTED_DISTANCE_SQR: %s", (LoadFromAddress(distance_sqr, NumberType_Int32) == 0x7F7FFFFF) ? "Patched" : "Not Patched");
	PrintToServer("WantsLagCompensationOnEntity: %s", (g_WantsLagCompensationOnEntity != null) ? "Patched" : "Not Patched");
}

stock bool IsValidClient(int client)
{
	return ((0 < client <= MaxClients) && IsClientConnected(client) && !IsFakeClient(client) && IsClientInGame(client) && !IsClientSourceTV(client));
}
