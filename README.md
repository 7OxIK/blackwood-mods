# Blackwood mods

Three small, independent [BepInEx](https://github.com/BepInEx/BepInEx) plugins for the Steam game **Blackwood**
(Unity 6000.5.3, IL2CPP). Blackwood is a single-player game and these are meant for offline play only.

| Plugin | Key | What it does |
|---|---|---|
| **Infinite Cash** (`BlackwoodInfiniteCash.dll`) | **F6** | Spending clean or dirty money is free, and both balances are topped up to a floor (default $9,999,999). |
| **God Mode** (`BlackwoodGodMode.dll`) | **F7** | Turns on the game's own invincibility flag, keeps your health full and blocks death. |
| **Infinite Ammo** (`BlackwoodInfiniteAmmo.dll`) | **F8** | Reserve ammo never runs out and your gun's magazine is kept full, so you never need to reload (the reload key simply does nothing). Your weapon only, not enemies'. |

Press the key to toggle a mod (only while the game window is focused). All three start **on**. The start state, the
key and the cash floor can be changed in `BepInEx\config\local.blackwood.*.cfg`, which appears after the first launch.
Each plugin is a single DLL in `BepInEx\plugins` - delete one to drop just that mod.

Infinite Cash raises your real balance, so once the game saves, the money stays in your save even if you switch the
mod off later. Lower `BalanceFloorCents` in its config if you want less than $9,999,999.

Tested on Windows 10 with Blackwood's Steam build 25422644 (Unity 6000.5.3f1) and BepInEx 6.0.0-be.788.

## Install

The game needs a one-time setup step, because BepInEx can't yet read Blackwood's IL2CPP metadata by itself
([BepInEx#1395](https://github.com/BepInEx/BepInEx/issues/1395)). `Setup.bat` does that step for you.

1. **Install BepInEx.** Download
   [BepInEx-Unity.IL2CPP-win-x64-6.0.0-be.788+5b766a3.zip](https://builds.bepinex.dev/projects/bepinex_be/788/BepInEx-Unity.IL2CPP-win-x64-6.0.0-be.788%2B5b766a3.zip)
   (build #788 from [builds.bepinex.dev](https://builds.bepinex.dev/projects/bepinex_be)) and extract it into the game
   folder (Steam > right-click Blackwood > Manage > Browse local files), so `winhttp.dll` sits next to `Blackwood.exe`.
   Use exactly this build - newer or older ones are untested.
2. **Run the setup.** Download `BlackwoodMods-<version>.zip` from the
   [Releases](../../releases) page, extract it anywhere, close Blackwood, and double-click **`Setup.bat`**.
   It takes a couple of minutes (and briefly uses about 3 GB of RAM); it finds your game through Steam, builds the
   game-specific files BepInEx needs from *your* copy of the game, and installs the three plugins.
3. **Play.** Start Blackwood from Steam. The BepInEx log (`BepInEx\LogOutput.log`) should show each plugin loading.

You can run the setup before or after your first launch of the modded game, but the mods only work once it has run. It is safe to run again.

### After a Blackwood update
A game update makes the generated files stale, and the mods can then misbehave without any error. BepInEx warns
`Interop assemblies are possibly out of date` in that case - **run `Setup.bat` again** (game closed). Steam can update
the game silently; to avoid surprises set Steam > Blackwood > Properties > Updates > *Only update this game when I
launch it*. If an update renames the classes the mods hook, the log will show Harmony errors and the plugins themselves
need an update - please open an issue with `LogOutput.log`.

### Uninstall
Delete the plugin DLLs to remove just the mods. To remove BepInEx entirely, delete these from the game folder:
the `BepInEx` and `dotnet` folders, and `winhttp.dll`, `doorstop_config.ini`, `.doorstop_version`, `changelog.txt`.
To play vanilla for a while, just rename `winhttp.dll` - without it BepInEx never loads.

### Already have working BepInEx interop?
Use `BlackwoodMods-<version>-plugins-only.zip` instead: extract it into the game folder and you're done.

## Troubleshooting
- **Nothing happens / keys do nothing:** check `BepInEx\LogOutput.log` for `Loaded. ... toggle with F6/F7/F8`. Keys only
  work while the game window is focused. If the log is empty, BepInEx isn't loading - is `winhttp.dll` next to
  `Blackwood.exe`?
- **Weapons or reloading act oddly:** most likely stale generated files after a game update - run `Setup.bat` again.
- **Need more detail in a bug report:** in `BepInEx\config\BepInEx.cfg` set `LogLevels = All` under `[Logging.Disk]`;
  the log then also shows which game hooks each plugin reached (`[trace]` lines).

## Build from source
Needs the .NET SDK and a game folder that has BepInEx and the generated interop (run `Setup.bat` once). Then:
```
dotnet build BlackwoodInfiniteCash\BlackwoodInfiniteCash.csproj -c Release   # also copies the DLL into the game
```
(`-p:GameDir=...` if the game isn't in the default Steam location, `-p:InstallToGame=false` to skip the copy.)
`build-release.ps1` assembles the release zips and additionally needs the `tools\` folder from a release zip.

## Notes for modders
- Il2CppInterop can't inject managed classes on this Unity version, so the plugins avoid `MonoBehaviour`s and use only
  Harmony patches plus a Win32 key-polling thread. `UnityLogListening = false` is required for the same reason;
  `Setup.ps1` sets it.
- `JW_WeaponInfo_script._currentMag` is an index into `_MagazinePool` - never write a round count to it. `_AmmoLeft`
  is the loaded-rounds counter.

## Changelog
- **1.0.1** - Infinite Cash now really raises your balances. 1.0.0 only made spending free: the game keeps its money in
  two places (the hub save and the shared player settings that the shop, computer and bank screens read) and the plugin
  only wrote the first. God Mode and Infinite Ammo are unchanged (new version number only).
- **1.0.0** - First release.

## Credits and licence
Built on [BepInEx](https://github.com/BepInEx/BepInEx), [HarmonyX](https://github.com/BepInEx/HarmonyX),
[Il2CppInterop](https://github.com/BepInEx/Il2CppInterop) and [Cpp2IL](https://github.com/SamboyCoding/Cpp2IL) - see
[THIRD-PARTY.md](THIRD-PARTY.md) for exactly what the release zip bundles and under which licences.
These are unofficial mods, not affiliated with the developers of Blackwood; use them at your own risk.
The code was written with AI assistance (Claude, by Anthropic) and tested by hand in the game.
Licence: MIT, see [LICENSE](LICENSE).
