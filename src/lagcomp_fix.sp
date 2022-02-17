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
ConVar mp_teammates_are_enemies;
ConVar mp_friendlyfire;
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
	g_WantsLagCompensationOnEntity.AddParam(HookParamType_CBaseEntity);
	
	if (g_Engine == Engine_CSGO)
		mp_teammates_are_enemies = FindConVar("mp_teammates_are_enemies");
		
	mp_friendlyfire = FindConVar("mp_friendlyfire");
	
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

public MRESReturn WantsLagCompensationOnEntity(int client, DHookReturn hReturn, DHookParam hParams)
{
	int entity = hParams.Get(1);

	if (IsValidClient(client) && IsPlayerAlive(client) && IsValidClient(entity) && IsPlayerAlive(entity))
	{
		if ((g_Engine != Engine_CSGO) || !mp_teammates_are_enemies.BoolValue)
		{
			if (!mp_friendlyfire.BoolValue)
			{
				if (GetClientTeam(client) == GetClientTeam(entity))
					return MRES_Ignored;
			}
		}
		
		if (IsAbleToSee(entity, client))
		{
			hReturn.Value = true;
			return MRES_Supercede;
		}
	}
	return MRES_Ignored;
}

stock bool IsValidClient(int client)
{
	return ((0 < client <= MaxClients) && IsClientConnected(client) && !IsFakeClient(client) && IsClientInGame(client) && !IsClientSourceTV(client));
}

// Everything below taken from SMAC

bool IsAbleToSee(int entity, int client)
{
    // Skip all traces if the player isn't within the field of view.
    // - Temporarily disabled until eye angle prediction is added.
    // if (IsInFieldOfView(g_vEyePos[client], g_vEyeAngles[client], g_vAbsCentre[entity]))
    
    float vecOrigin[3], vecEyePos[3];
    GetClientAbsOrigin(entity, vecOrigin);
    GetClientEyePosition(client, vecEyePos);
    
    // Check if centre is visible.
    if (IsPointVisible(vecEyePos, vecOrigin))
    {
        return true;
    }
    
    float vecEyePos_ent[3], vecEyeAng[3];
    GetClientEyeAngles(entity, vecEyeAng);
    GetClientEyePosition(entity, vecEyePos_ent);
    // Check if weapon tip is visible.
    if (IsFwdVecVisible(vecEyePos, vecEyeAng, vecEyePos_ent))
    {
        return true;
    }
    
    float mins[3], maxs[3];
    GetClientMins(client, mins);
    GetClientMaxs(client, maxs);
    // Check outer 4 corners of player.
    if (IsRectangleVisible(vecEyePos, vecOrigin, mins, maxs, 1.30))
    {
        return true;
    }

    // Check inner 4 corners of player.
    if (IsRectangleVisible(vecEyePos, vecOrigin, mins, maxs, 0.65))
    {
        return true;
    }
    
    return false;
}

stock bool IsInFieldOfView(int client, const float start[3], const float angles[3], float fov = 90.0)
{
    float normal[3], plane[3];
    
    float end[3];
    GetClientAbsOrigin(client, end);
    
    GetAngleVectors(angles, normal, NULL_VECTOR, NULL_VECTOR);
    SubtractVectors(end, start, plane);
    NormalizeVector(plane, plane);
    
    return GetVectorDotProduct(plane, normal) > Cosine(DegToRad(fov/2.0));
}

public bool Filter_NoPlayers(int entity, int mask)
{
    return (entity > MaxClients && !(0 < GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity") <= MaxClients));
}

bool IsPointVisible(const float start[3], const float end[3])
{
    TR_TraceRayFilter(start, end, MASK_VISIBLE, RayType_EndPoint, Filter_NoPlayers);

    return TR_GetFraction() == 1.0;
}

bool IsFwdVecVisible(const float start[3], const float angles[3], const float end[3])
{
    float fwd[3];
    
    GetAngleVectors(angles, fwd, NULL_VECTOR, NULL_VECTOR);
    ScaleVector(fwd, 50.0);
    AddVectors(end, fwd, fwd);

    return IsPointVisible(start, fwd);
}

bool IsRectangleVisible(const float start[3], const float end[3], const float mins[3], const float maxs[3], float scale = 1.0)
{
    float ZpozOffset = maxs[2];
    float ZnegOffset = mins[2];
    float WideOffset = ((maxs[0] - mins[0]) + (maxs[1] - mins[1])) / 4.0;

    // This rectangle is just a point!
    if (ZpozOffset == 0.0 && ZnegOffset == 0.0 && WideOffset == 0.0)
    {
        return IsPointVisible(start, end);
    }

    // Adjust to scale.
    ZpozOffset *= scale;
    ZnegOffset *= scale;
    WideOffset *= scale;
    
    // Prepare rotation matrix.
    float angles[3], fwd[3], right[3];

    SubtractVectors(start, end, fwd);
    NormalizeVector(fwd, fwd);

    GetVectorAngles(fwd, angles);
    GetAngleVectors(angles, fwd, right, NULL_VECTOR);

    float vRectangle[4][3], vTemp[3];

    // If the player is on the same level as us, we can optimize by only rotating on the z-axis.
    if (FloatAbs(fwd[2]) <= 0.7071)
    {
        ScaleVector(right, WideOffset);
        
        // Corner 1, 2
        vTemp = end;
        vTemp[2] += ZpozOffset;
        AddVectors(vTemp, right, vRectangle[0]);
        SubtractVectors(vTemp, right, vRectangle[1]);
        
        // Corner 3, 4
        vTemp = end;
        vTemp[2] += ZnegOffset;
        AddVectors(vTemp, right, vRectangle[2]);
        SubtractVectors(vTemp, right, vRectangle[3]);
        
    }
    else if (fwd[2] > 0.0) // Player is below us.
    {
        fwd[2] = 0.0;
        NormalizeVector(fwd, fwd);
        
        ScaleVector(fwd, scale);
        ScaleVector(fwd, WideOffset);
        ScaleVector(right, WideOffset);
        
        // Corner 1
        vTemp = end;
        vTemp[2] += ZpozOffset;
        AddVectors(vTemp, right, vTemp);
        SubtractVectors(vTemp, fwd, vRectangle[0]);
        
        // Corner 2
        vTemp = end;
        vTemp[2] += ZpozOffset;
        SubtractVectors(vTemp, right, vTemp);
        SubtractVectors(vTemp, fwd, vRectangle[1]);
        
        // Corner 3
        vTemp = end;
        vTemp[2] += ZnegOffset;
        AddVectors(vTemp, right, vTemp);
        AddVectors(vTemp, fwd, vRectangle[2]);
        
        // Corner 4
        vTemp = end;
        vTemp[2] += ZnegOffset;
        SubtractVectors(vTemp, right, vTemp);
        AddVectors(vTemp, fwd, vRectangle[3]);
    }
    else // Player is above us.
    {
        fwd[2] = 0.0;
        NormalizeVector(fwd, fwd);
        
        ScaleVector(fwd, scale);
        ScaleVector(fwd, WideOffset);
        ScaleVector(right, WideOffset);

        // Corner 1
        vTemp = end;
        vTemp[2] += ZpozOffset;
        AddVectors(vTemp, right, vTemp);
        AddVectors(vTemp, fwd, vRectangle[0]);
        
        // Corner 2
        vTemp = end;
        vTemp[2] += ZpozOffset;
        SubtractVectors(vTemp, right, vTemp);
        AddVectors(vTemp, fwd, vRectangle[1]);
        
        // Corner 3
        vTemp = end;
        vTemp[2] += ZnegOffset;
        AddVectors(vTemp, right, vTemp);
        SubtractVectors(vTemp, fwd, vRectangle[2]);
        
        // Corner 4
        vTemp = end;
        vTemp[2] += ZnegOffset;
        SubtractVectors(vTemp, right, vTemp);
        SubtractVectors(vTemp, fwd, vRectangle[3]);
    }

    // Run traces on all corners.
    for (int i = 0; i < 4; i++)
    {
        if (IsPointVisible(start, vRectangle[i]))
        {
            return true;
        }
    }

    return false;
}