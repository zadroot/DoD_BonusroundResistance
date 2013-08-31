/**
* DoD:S Bonusround Resistance by Root
*
* Description:
*   Allows losers to resist humiliation (allow attacking) during bonus round.
*
* Version 1.1
* Changelog & more info at http://goo.gl/4nKhJ
*/

#pragma semicolon 1

// ====[ INCLUDES ]=======================================================
#include <sdktools>
#include <sdkhooks>
#include <dodhooks>

// ====[ CONSTANTS ]======================================================
#define PLUGIN_NAME    "DoD:S Bonusround Resistance"
#define PLUGIN_VERSION "1.1"
#define DOD_MAXPLAYERS 33

enum Teams
{
	DODTeam_Unassigned,
	DODTeam_Spectator,
	DODTeam_Allies,
	DODTeam_Axis
}

enum
{
	SLOT_INVALID = -1,
	SLOT_PRIMARY,
	SLOT_SECONDARY,
	SLOT_MELEE,
	SLOT_GRENADE,
	SLOT_EXPLOSIVE
}

// ====[ VARIABLES ]======================================================
new	Handle:BR_Enabled = INVALID_HANDLE, Handle:BR_MeleeOnly = INVALID_HANDLE,
	bool:StopChain, bool:AllowWeaponsUsage[DOD_MAXPLAYERS + 1] = {true, ...};

// ====[ PLUGIN ]=========================================================
public Plugin:myinfo  =
{
	name        = PLUGIN_NAME,
	author      = "Root",
	description = "Allows losers to resist humiliation (allow attacking) during bonus round",
	version     = PLUGIN_VERSION,
	url         = "http://dodsplugins.com/"
};


/* OnPluginStart()
 *
 * When the plugin starts up.
 * ----------------------------------------------------------------------- */
public OnPluginStart()
{
	// Create version ConVar
	CreateConVar("dod_bonusround_resistance", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_NOTIFY|FCVAR_DONTRECORD);

	// And other plugin ConVars
	BR_Enabled   = CreateConVar("dod_bres_enabled",    "1", "Whether or not enable Bonusround Resistance",                   FCVAR_PLUGIN, true, 0.0, true, 1.0);
	BR_MeleeOnly = CreateConVar("dod_bres_allowmelee", "1", "Whether or not dont allow losers to use all weapons but melee", FCVAR_PLUGIN, true, 0.0, true, 1.0);

	// Hook events
	HookEvent("dod_round_win",   OnRoundWin);
	HookEvent("dod_round_start", OnRoundStart);

	// Hook changes only for primary ConVar
	HookConVarChange(BR_Enabled, OnPluginToggle);

	// Support for late-loading
	OnPluginToggle(BR_Enabled, "0", "1");
}

/* OnPluginToggle()
 *
 * Called when plugin is enabled or disabled by ConVar.
 * ----------------------------------------------------------------------- */
public OnPluginToggle(Handle:convar, const String:oldValue[], const String:newValue[])
{
	// Loop through all valid clients
	for (new client = 1; client <= MaxClients; client++)
	{
		if (IsValidClient(client))
		{
			// Get the new (changed) value
			switch (StringToInt(newValue))
			{
				// Plugin has been disabled
				case false:
				{
					// Unhook everything
					SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
					SDKUnhook(client, SDKHook_WeaponCanUse, OnWeaponUsage);
					SDKUnhook(client, SDKHook_WeaponEquip,  OnWeaponUsage);
					SDKUnhook(client, SDKHook_WeaponSwitch, OnWeaponUsage);
				}
				case true: OnClientPutInServer(client);
			}
		}
	}
}

/* OnClientPutInServer()
 *
 * Called when a client is entering the game.
 * ----------------------------------------------------------------------- */
public OnClientPutInServer(client)
{
	// Allow weapons usage for every connected client
	AllowWeaponsUsage[client] = true;

	// And hook some useful stuff for a player
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	SDKHook(client, SDKHook_WeaponCanUse, OnWeaponUsage);
	SDKHook(client, SDKHook_WeaponEquip,  OnWeaponUsage);
	SDKHook(client, SDKHook_WeaponSwitch, OnWeaponUsage);
}

/* OnWeaponUsage()
 *
 * Called when the player uses specified weapon.
 * ----------------------------------------------------------------------- */
public Action:OnTakeDamage(victim, &attacker, &inflictor, &Float:damage, &damagetype)
{
	// Block enabled friendly fire damage on bonus round (because RoundState was changed to RoundRunning)
	return (StopChain
	&& IsValidClient(attacker) && IsValidClient(victim)
	&& GetClientTeam(attacker) == GetClientTeam(victim))
	? Plugin_Handled
	: Plugin_Continue;
}

/* OnWeaponUsage()
 *
 * Called when the player uses specified weapon.
 * ----------------------------------------------------------------------- */
public Action:OnWeaponUsage(client, weapon)
{
	// Dont allow to player use any other weapon than active one
	return !AllowWeaponsUsage[client] ? Plugin_Handled : Plugin_Continue;
}

/* OnRoundWin()
 *
 * Called when a round ends.
 * ----------------------------------------------------------------------- */
public OnRoundWin(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Does plugin is enabled?
	if (GetConVarBool(BR_Enabled))
	{
		/**
		* This dirty way works like a charm
		* Since event is called *after* team has won - the original SetWinningTeam callback is already set
		* However, if we change round state during this callback, it will cause infinite loop during "m_flRestartRoundTime"
		* In other words this event will be fired at every frame until new round starts
		* A solution is when event is fired, stop the SetWinningTeam callback chain
		* The winners panel still will be shown, and round will start eventually (after bonus round time is expired)
		*/
		StopChain = true;

		/**
		* I call this Fake-RoundState
		* It _should_ set round state to normal, but its won't for unknown reason
		* Simply SDKTools dont set round state properly (as DoD Hooks does)
		* So if I'd use DoD Hook's 'SetRoundState' native, it would change round state immediately
		* Good thing that this one just allows players to shoot during bonus round, so it works, but different
		*/
		GameRules_SetProp("m_iRoundState", RoundState_RoundRunning);

		// Check whether or not allow losers to use melee weapons only
		if (GetConVarBool(BR_MeleeOnly))
		{
			// Find all the losers
			for (new i = 1; i <= MaxClients; i++)
			{
				// Compare winning team and team of other players to perform weapon changing
				if (IsValidClient(i) && GetClientTeam(i) != GetEventInt(event, "team"))
				{
					RestrictWeaponsUsage(i);
				}
			}
		}
	}
}

/* OnRoundStart()
 *
 * Called when a new round starts.
 * ----------------------------------------------------------------------- */
public OnRoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Make sure to allow callback chain to perform as usual when round starts
	// Otherwise DoD Hooks will block round ending at all
	StopChain = false;

	for (new client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client))
		{
			// Allow to use all weapons again when bonus round time is expired
			AllowWeaponsUsage[client] = true;
		}
	}
}

/* OnSetWinningTeam()
 *
 * Called when a team is about to win.
 * ----------------------------------------------------------------------- */
public Action:OnSetWinningTeam(index)
{
	// If plugin is enabled and round is ended, block winning; Plugin_Continue otherwise
	return GetConVarBool(BR_Enabled) && StopChain ? Plugin_Handled : Plugin_Continue;
}

/* RestrictWeaponsUsage()
 *
 * Removes all weapons from player's inventory.
 * ----------------------------------------------------------------------- */
RestrictWeaponsUsage(client)
{
	// Initialize slot to search for melee weapons
	new slot = SLOT_INVALID;

	// Make sure melee weapon is exists
	if ((slot = GetPlayerWeaponSlot(client, SLOT_MELEE)) != SLOT_INVALID)
	{
		// It may not be a melee weapon really (a smoke), so remove it
		RemovePlayerItem(client, slot);
		AcceptEntityInput(slot, "Kill");
	}

	switch (GetClientTeam(client))
	{
		case DODTeam_Allies:
		{
			// Get the player's team and give proper weapon depends on team
			GivePlayerItem(client, "weapon_amerknife");
			FakeClientCommand(client, "use weapon_amerknife");
		}
		case DODTeam_Axis:
		{
			GivePlayerItem(client, "weapon_spade");
			FakeClientCommand(client, "use weapon_spade");
		}
	}

	// In case if player is deployed MG or rocket (because weapons will not change via "use" command)
	SetEntPropEnt(client, Prop_Data, "m_hActiveWeapon", GetPlayerWeaponSlot(client, SLOT_MELEE));

	// Also dont allow player to change it to any other
	AllowWeaponsUsage[client] = false;
}

/* IsValidClient()
 *
 * Checks if a client is valid.
 * ------------------------------------------------------------------------- */
bool:IsValidClient(client)
{
	// ingame edict and not a server
	return (client > 0 && client <= MaxClients && IsClientInGame(client)) ? true : false;
}