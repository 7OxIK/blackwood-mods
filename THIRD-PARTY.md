# Third-party software

## The plugins
`BlackwoodInfiniteCash.dll`, `BlackwoodGodMode.dll` and `BlackwoodInfiniteAmmo.dll` are original work. At runtime they
link against BepInEx, HarmonyX (`0Harmony`) and Il2CppInterop.Runtime, which come from **your own BepInEx install** and
are not redistributed here. BepInEx itself (LGPL-2.1) is not included in this project - you download it from
<https://builds.bepinex.dev/projects/bepinex_be> (see the README).

## What the full release zip bundles (`tools\`)
`Setup.ps1` needs three tools to build the game-specific interop assemblies on your machine. They are the compiled,
unmodified upstream projects, bundled so the setup works without installing anything:

| Folder | Software | Licence | Source (exact commit) |
|---|---|---|---|
| `tools\cpp2il_cli` | Cpp2IL 2022.1.0 | MIT (`licenses\Cpp2IL-LICENSE.txt`) | <https://github.com/SamboyCoding/Cpp2IL/tree/b5ad444b82267cb1e4b88b8b373c008105bdea52> |
| `tools\interop_cli` | Il2CppInterop (CLI + Generator) 1.5.3 | LGPL-3.0 (`licenses\Il2CppInterop-LICENSE.txt`) | <https://github.com/BepInEx/Il2CppInterop/tree/81a6f78c8b653e0da4a3420ac4cd00819e8b6292> |
| `tools\dotnet10` | .NET 10 runtime (Microsoft.NETCore.App 10.0.12) | MIT (`licenses\dotnet-runtime-LICENSE.txt`) | <https://github.com/dotnet/runtime> |

Both tools also ship libraries of their own (AsmResolver, AssetRipper.CIL, Capstone, CommandLineParser, Disarm, Iced,
MonoMod, ClangSharp/libclang, CppAst, System.CommandLine, Microsoft.Extensions.*, ...) under their own licences; see the
upstream repositories above.

**LGPL note (Il2CppInterop):** the LGPL-covered code lives in separate DLLs in `tools\interop_cli`. You may replace
them with your own build of the source linked above; `Setup.ps1` will use whatever is in that folder.

## Not redistributed
- **The generated interop assemblies** (`BepInEx\interop`) are derived from Blackwood's own code, so they are created
  on your machine by `Setup.ps1` from your copy of the game and never shipped.
- **Unity's base libraries** are downloaded by `Setup.ps1` from BepInEx's own host
  (`unity.bepinex.dev`) - the same download BepInEx would do itself.
