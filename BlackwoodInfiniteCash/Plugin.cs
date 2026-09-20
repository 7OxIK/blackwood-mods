using System;
using BepInEx;
using BepInEx.Configuration;
using BepInEx.Logging;
using BepInEx.Unity.IL2CPP;
using BlackwoodMods.Shared;
using HarmonyLib;

namespace BlackwoodInfiniteCash
{
    [BepInPlugin(PluginGuid, "Blackwood Infinite Cash", "1.0.0")]
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

        // Keep both balances topped up so the on-screen numbers read as "infinite" too.
        private static long _nextTopUp;

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
                var save = __instance._runtimeSave;
                if (save == null) return;

                var floor = Plugin.FloorCents.Value;
                var changed = false;
                if (save.currentCleanMoney < floor) { save.currentCleanMoney = floor; changed = true; }
                if (save.currentDirtyMoney < floor) { save.currentDirtyMoney = floor; changed = true; }
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
