#include <sourcemod>
#include <dhooks>
#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = 
{
	name = "Lag Compensation Fix",
	author = "brooks, D34DSpy, xutaxkamay",
	version = "6.9",
};

DynamicHook g_WantsLagCompensationOnEntity;
int distance_sqr_old;
Address distance_sqr;
int max_ms_old;
Address max_ms;
ConVar sv_lagcompensation_teleport_dist;
EngineVersion g_Engine;

public void OnPluginStart()
{
	GameData data = new GameData("LagComp.games");
	
	if (!data)
		SetFailState("Failed to load LagComp.games.txt!");
	
	g_Engine = GetEngineVersion();
	int offset = data.GetOffset("WantsLagComp");
		
	distance_sqr = data.GetAddress("DistanceSqr");
	max_ms = data.GetAddress("max_ms");
	delete data;
	
	sv_lagcompensation_teleport_dist = FindConVar("sv_lagcompensation_teleport_dist");
	if (sv_lagcompensation_teleport_dist != null)
		sv_lagcompensation_teleport_dist.SetInt(0x7F7FFFFF);

	if (g_Engine == Engine_CSGO)
	{	
		if (distance_sqr != Address_Null)
		{
			distance_sqr_old = LoadFromAddress(distance_sqr, NumberType_Int32);
			StoreToAddress(distance_sqr, 0x7F7FFFFF, NumberType_Int32);
		}
		else
			LogError("Could not find signature for \"LAG_COMPENSATION_TELEPORTED_DISTANCE_SQR\"");
	}
	
	if (max_ms != Address_Null)
	{
		max_ms_old = LoadFromAddress(max_ms, NumberType_Int32);
		StoreToAddress(max_ms, 0x7F7FFFFF, NumberType_Int32);
	}
	else
		LogError("Could not find signature for \"fabs( deltaTime ) > 0.2f\"");

	if (offset == -1)
	{
		LogError("Could not find offset for WantsLagCompensationOnEntity");
		return;
	}
	
	g_WantsLagCompensationOnEntity = new DynamicHook(offset, HookType_Entity, ReturnType_Bool, ThisPointer_CBaseEntity);
	
	for (int i = 1; i <= MaxClients; i++)
		OnClientPutInServer(i);
}

public void OnPluginEnd()
{
	if (g_Engine == Engine_CSGO && distance_sqr != Address_Null)
		StoreToAddress(distance_sqr, distance_sqr_old, NumberType_Int32);
	
	if (max_ms != Address_Null)
		StoreToAddress(max_ms, max_ms_old, NumberType_Int32);
}

public void OnClientPutInServer(int client) 
{
	if (IsValidClient(client) && (g_WantsLagCompensationOnEntity != null))
		g_WantsLagCompensationOnEntity.HookEntity(Hook_Post, client, WantsLagCompensationOnEntity);
}

public MRESReturn WantsLagCompensationOnEntity(int client, DHookReturn hReturn)
{
	hReturn.Value = true;
	return MRES_Supercede;
}

stock bool IsValidClient(int client)
{
	return ((0 < client <= MaxClients) && IsClientConnected(client) && !IsFakeClient(client) && IsClientInGame(client) && !IsClientSourceTV(client));
}
