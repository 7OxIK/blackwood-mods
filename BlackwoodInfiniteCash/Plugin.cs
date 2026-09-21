using System;
using BepInEx;
using BepInEx.Configuration;
using BepInEx.Logging;
using BepInEx.Unity.IL2CPP;
using BlackwoodMods.Shared;
using HarmonyLib;

namespace BlackwoodInfiniteCash
{
    [BepInPlugin(PluginGuid, "Blackwood Infinite Cash", "1.0.1")]
    public class Plugin : BasePlugin
    {
        public const string PluginGuid = "local.blackwood.infinitecash";

        internal static ManualLogSource Logger;
        internal static volatile bool Active;
        internal static ConfigEntry<int> FloorCents;

        public override void Load()
        {
            Logger = Log;

            var enabledAtStart = Config.Bind("General", "EnabledAtStart", true, "Start with infinite cash switched on.");
            var toggleKey = Config.Bind("General", "ToggleKey", "F6", "Key that toggles the mod in game (F1-F12, Insert, Home, a letter, ...).");
            FloorCents = Config.Bind("General", "BalanceFloorCents", 999_999_900,
                "Clean and dirty balances are topped up to at least this many CENTS (999999900 = $9,999,999). Game stores cents in an int32, so keep below 2147483647.");

            Active = enabledAtStart.Value;
            Hotkey.Start(toggleKey.Value, () =>
            {
                Active = !Active;
                Logger.LogMessage("Infinite cash: " + (Active ? "ON" : "OFF"));
            }, Logger.LogWarning);

            new Harmony(PluginGuid).PatchAll(typeof(Patches));
            Logger.LogInfo($"Loaded. Infinite cash is {(Active ? "ON" : "OFF")}; toggle with {toggleKey.Value}.");
        }
    }

    internal static class Patches
    {
        // Spending always succeeds and costs nothing (clean + dirty).
        [HarmonyPatch(typeof(BW_HubDayManager), nameof(BW_HubDayManager.TrySpendCleanMoney))]
        [HarmonyPrefix]
        private static bool SpendClean(ref bool __result)
        {
            Trace.Once(Plugin.Logger, "BW_HubDayManager.TrySpendCleanMoney");
            if (!Plugin.Active) return true;
            __result = true;
            return false;
        }

        [HarmonyPatch(typeof(BW_HubDayManager), nameof(BW_HubDayManager.TrySpendDirtyMoney))]
        [HarmonyPrefix]
        private static bool SpendDirty(ref bool __result)
        {
            Trace.Once(Plugin.Logger, "BW_HubDayManager.TrySpendDirtyMoney");
            if (!Plugin.Active) return true;
            __result = true;
            return false;
        }

        // Keep both balances topped up so the on-screen numbers read as "infinite" too. The game keeps the balance in
        // two places - the hub's runtime save and the shared player settings (which the shop, computer and bank screens
        // read, and which SyncFromPlayerSettingsToRuntime copies back over the hub save) - so both are topped up.
        private static long _nextTopUp;
        private static bool _loggedSave, _loggedSettings, _loggedNoSettings;

        [HarmonyPatch(typeof(BW_HubDayManager), nameof(BW_HubDayManager.Update))]
        [HarmonyPostfix]
        private static void HubUpdate(BW_HubDayManager __instance)
        {
            Trace.Once(Plugin.Logger, "BW_HubDayManager.Update");
            if (!Plugin.Active) return;
            var now = Environment.TickCount64;
            if (now < _nextTopUp) return;
            _nextTopUp = now + 500;

            try
            {
                var floor = Plugin.FloorCents.Value;
                var changed = false;

                var save = __instance._runtimeSave;
                if (save != null)
                {
                    int clean = save.currentCleanMoney, dirty = save.currentDirtyMoney;
                    if (clean < floor) { save.currentCleanMoney = floor; changed = true; }
                    if (dirty < floor) { save.currentDirtyMoney = floor; changed = true; }
                    if ((clean < floor || dirty < floor) && !_loggedSave)
                    {
                        _loggedSave = true;
                        Plugin.Logger.LogInfo($"Topped up the hub save balances (cents): clean {clean} -> {floor}, dirty {dirty} -> {floor}.");
                    }
                }

                var settings = __instance.playerSettings;
                if (settings != null)
                {
                    int white = settings._totalWhiteMoney, black = settings._totalBlackMoney;
                    if (white < floor) { settings._totalWhiteMoney = floor; changed = true; }
                    if (black < floor) { settings._totalBlackMoney = floor; changed = true; }
                    if ((white < floor || black < floor) && !_loggedSettings)
                    {
                        _loggedSettings = true;
                        Plugin.Logger.LogInfo($"Topped up the player-settings balances (cents): clean {white} -> {floor}, dirty {black} -> {floor}.");
                    }
                }
                else if (!_loggedNoSettings)
                {
                    _loggedNoSettings = true;
                    Plugin.Logger.LogWarning("BW_HubDayManager.playerSettings is null - only the hub save balance can be topped up.");
                }

                if (changed) __instance.UpdateMoneyUI();
            }
            catch (Exception e)
            {
                Plugin.Logger.LogWarning("Top-up failed: " + e.Message);
                _nextTopUp = now + 5000;
            }
        }
    }
}
