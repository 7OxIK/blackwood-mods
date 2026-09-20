using System;
using System.Collections.Concurrent;
using BepInEx.Logging;

namespace BlackwoodMods.Shared
{
    /// <summary>Logs the first call of each patched game method, once, at Debug level (hidden by default; set
    /// LogLevels = All under [Logging.Disk] in BepInEx.cfg to see it). Cheap, thread-safe, and it makes a freeze
    /// or a dead hook diagnosable: the last "[trace]" line in LogOutput.log is the last hook the game reached.</summary>
    internal static class Trace
    {
        private static readonly ConcurrentDictionary<string, byte> Seen = new ConcurrentDictionary<string, byte>();

        public static void Once(ManualLogSource log, string hook)
        {
            if (Seen.TryAdd(hook, 0))
                log.LogDebug("[trace] first call: " + hook + " (thread " + Environment.CurrentManagedThreadId + ")");
        }
    }
}
