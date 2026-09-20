using System;
using BepInEx;
using BepInEx.Configuration;
using BepInEx.Logging;
using BepInEx.Unity.IL2CPP;
using BlackwoodMods.Shared;
using HarmonyLib;

namespace BlackwoodInfiniteAmmo
{
    [BepInPlugin(PluginGuid, "Blackwood Infinite Ammo", "1.0.0")]
    public class Plugin : BasePlugin
    {
        public const string PluginGuid = "local.blackwood.infiniteammo";

        internal static ManualLogSource Logger;
        internal static volatile bool Active;

        public override void Load()
        {
            Logger = Log;

            var enabledAtStart = Config.Bind("General", "EnabledAtStart", true, "Start with unlimited ammo switched on.");
            var toggleKey = Config.Bind("General", "ToggleKey", "F8", "Key that toggles the mod in game (F1-F12, Insert, Home, a letter, ...).");

            Active = enabledAtStart.Value;
            Hotkey.Start(toggleKey.Value, () =>
            {
                Active = !Active;
                Logger.LogMessage("Infinite ammo: " + (Active ? "ON" : "OFF"));
            }, Logger.LogWarning);

            new Harmony(PluginGuid).PatchAll(typeof(Patches));
            Logger.LogInfo($"Loaded. Infinite ammo is {(Active ? "ON" : "OFF")}; toggle with {toggleKey.Value}.");
        }
    }

    internal static class Patches
    {
        // Reserve ammo: taking rounds out of the reserve always succeeds and costs nothing,
        // and the reserve always reports as non-empty so reloads are never refused.
        [HarmonyPatch(typeof(BW_WeaponBulletsInventory), nameof(BW_WeaponBulletsInventory.UseAmmo))]
        [HarmonyPrefix]
        private static bool UseAmmo(ref bool __result)
        {
            Trace.Once(Plugin.Logger, "BW_WeaponBulletsInventory.UseAmmo");
            if (!Plugin.Active) return true;
            __result = true;
            return false;
        }

        [HarmonyPatch(typeof(BW_WeaponBulletsInventory), nameof(BW_WeaponBulletsInventory.HasAmmoAvailable))]
        [HarmonyPrefix]
        private static bool HasAmmo(ref bool __result)
        {
            Trace.Once(Plugin.Logger, "BW_WeaponBulletsInventory.HasAmmoAvailable");
            if (!Plugin.Active) return true;
            __result = true;
            return false;
        }

        // Rounds loaded in the gun: keep the player's weapon topped up (never touches enemy weapons).
        // NB: `_AmmoLeft` is the round counter. `_currentMag` is an INDEX into `_MagazinePool` - never write to it.
        private static bool _loggedOnce;

        [HarmonyPatch(typeof(JW_WeaponInfo_script), nameof(JW_WeaponInfo_script.Update))]
        [HarmonyPostfix]
        private static void WeaponUpdate(JW_WeaponInfo_script __instance)
        {
            Trace.Once(Plugin.Logger, "JW_WeaponInfo_script.Update");
            if (!Plugin.Active) return;
            try
            {
                if (__instance._userAssigned == null) return;   // enemy / unheld weapon
                if (__instance.isMidReload) return;              // don't fight the reload animation
                if (!__instance.HasMagazineLoaded) return;       // mag is out: nothing to top up

                var cap = __instance.MaxLoadedCapacity;
                if (cap <= 0) return;

                var cur = __instance._AmmoLeft;
                if (!_loggedOnce)
                {
                    _loggedOnce = true;
                    Plugin.Logger.LogInfo($"Player weapon seen: _AmmoLeft={cur}, MaxLoadedCapacity={cap}, currentMagazineCapacity={__instance.currentMagazineCapacity}.");
                }
                if (cur < cap) __instance._AmmoLeft = cap;
            }
            catch (Exception e)
            {
                Plugin.Logger.LogWarning("Weapon update failed: " + e.Message);
            }
        }
    }
}
