using System;
using BepInEx;
using BepInEx.Configuration;
using BepInEx.Logging;
using BepInEx.Unity.IL2CPP;
using BlackwoodMods.Shared;
using HarmonyLib;

namespace BlackwoodGodMode
{
    [BepInPlugin(PluginGuid, "Blackwood God Mode", "1.0.0")]
    public class Plugin : BasePlugin
    {
        public const string PluginGuid = "local.blackwood.godmode";

        internal static ManualLogSource Logger;
        internal static volatile bool Active;

        public override void Load()
        {
            Logger = Log;

            var enabledAtStart = Config.Bind("General", "EnabledAtStart", true, "Start with unlimited health switched on.");
            var toggleKey = Config.Bind("General", "ToggleKey", "F7", "Key that toggles the mod in game (F1-F12, Insert, Home, a letter, ...).");

            Active = enabledAtStart.Value;
            Hotkey.Start(toggleKey.Value, () =>
            {
                Active = !Active;
                Logger.LogMessage("God mode: " + (Active ? "ON" : "OFF"));
            }, Logger.LogWarning);

            new Harmony(PluginGuid).PatchAll(typeof(Patches));
            Logger.LogInfo($"Loaded. God mode is {(Active ? "ON" : "OFF")}; toggle with {toggleKey.Value}.");
        }
    }

    internal static class Patches
    {
        // The player's own health component, found via JW_Player_script (the player controller).
        private static JW_HealthComponent _playerHealth;
        private static bool _appliedInvincible;
        private static float _maxSeen;
        private static long _nextLookup;
        private static bool _loggedFound;

        private static bool IsPlayerHealth(JW_HealthComponent hc)
            => hc != null && _playerHealth != null && hc.Pointer == _playerHealth.Pointer;

        [HarmonyPatch(typeof(JW_Player_script), nameof(JW_Player_script.Update))]
        [HarmonyPostfix]
        private static void PlayerUpdate(JW_Player_script __instance)
        {
            Trace.Once(Plugin.Logger, "JW_Player_script.Update");
            try
            {
                // (Re)locate the health component now and then; the reference dies on scene change.
                // `== null` uses UnityEngine.Object semantics, so a destroyed component counts as null.
                if (_playerHealth == null)
                {
                    var now = Environment.TickCount64;
                    if (now < _nextLookup) return;
                    _nextLookup = now + 1000;

                    _playerHealth = __instance.GetComponent<JW_HealthComponent>();
                    if (_playerHealth == null) _playerHealth = __instance.GetComponentInParent<JW_HealthComponent>();
                    if (_playerHealth == null) _playerHealth = __instance.GetComponentInChildren<JW_HealthComponent>(true);
                    if (_playerHealth == null) return;

                    _maxSeen = _playerHealth._entityhealth;
                    _appliedInvincible = false;
                    if (!_loggedFound)
                    {
                        _loggedFound = true;
                        Plugin.Logger.LogInfo($"Found player health component (health {_playerHealth._entityhealth}).");
                    }
                }

                if (Plugin.Active)
                {
                    if (!_playerHealth._invincibleCheat) _playerHealth._invincibleCheat = true;
                    _appliedInvincible = true;

                    // Belt and braces: never let health sit below the highest value seen while enabled.
                    var hp = _playerHealth._entityhealth;
                    if (hp > _maxSeen) _maxSeen = hp;
                    else if (hp < _maxSeen && hp > 0f) _playerHealth._entityhealth = _maxSeen;
                }
                else if (_appliedInvincible)
                {
                    _playerHealth._invincibleCheat = false;
                    _appliedInvincible = false;
                }
            }
            catch (Exception e)
            {
                Plugin.Logger.LogWarning("Player update failed: " + e.Message);
                _playerHealth = null;
                _nextLookup = Environment.TickCount64 + 5000;
            }
        }

        // Stop the player dying even if some damage path bypasses the invincibility flag.
        [HarmonyPatch(typeof(JW_HealthComponent), nameof(JW_HealthComponent.onEntityDeath))]
        [HarmonyPrefix]
        private static bool PreventDeath(JW_HealthComponent __instance)
        {
            Trace.Once(Plugin.Logger, "JW_HealthComponent.onEntityDeath");
            return !(Plugin.Active && IsPlayerHealth(__instance));
        }

        [HarmonyPatch(typeof(JW_Player_script), nameof(JW_Player_script.OnDeath_Function))]
        [HarmonyPrefix]
        private static bool PreventDeathFunction()
        {
            Trace.Once(Plugin.Logger, "JW_Player_script.OnDeath_Function");
            return !Plugin.Active;
        }
    }
}
