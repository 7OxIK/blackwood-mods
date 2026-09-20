using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

namespace BlackwoodMods.Shared
{
    /// <summary>
    /// Toggle-key polling via Win32, on a plain background thread.
    /// Deliberately touches no Unity / IL2CPP objects, so it is safe from any thread and does not
    /// depend on Il2CppInterop class injection. Only fires while the game window has focus.
    /// </summary>
    internal static class Hotkey
    {
        [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int vKey);
        [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

        private static readonly Dictionary<string, int> Named = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase)
        {
            { "Insert", 0x2D }, { "Delete", 0x2E }, { "Home", 0x24 }, { "End", 0x23 },
            { "PageUp", 0x21 }, { "PageDown", 0x22 }, { "Pause", 0x13 }, { "ScrollLock", 0x91 },
            { "Numpad0", 0x60 }, { "Numpad1", 0x61 }, { "Numpad2", 0x62 }, { "Numpad3", 0x63 },
            { "Numpad4", 0x64 }, { "Numpad5", 0x65 }, { "Numpad6", 0x66 }, { "Numpad7", 0x67 },
            { "Numpad8", 0x68 }, { "Numpad9", 0x69 },
        };

        /// <summary>Parses "F6", "Insert", "K", "7", ... into a Win32 virtual-key code (0 if unknown).</summary>
        public static int ParseKey(string name)
        {
            if (string.IsNullOrWhiteSpace(name)) return 0;
            name = name.Trim();
            if (Named.TryGetValue(name, out var named)) return named;
            if ((name[0] == 'F' || name[0] == 'f') && int.TryParse(name.Substring(1), out var n) && n >= 1 && n <= 24)
                return 0x6F + n;                                   // F1 = 0x70
            if (name.Length == 1)
            {
                var c = char.ToUpperInvariant(name[0]);
                if ((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) return c;
            }
            return 0;
        }

        /// <summary>Starts a background thread that calls <paramref name="onPressed"/> on each key press.</summary>
        public static bool Start(string keyName, Action onPressed, Action<string> warn)
        {
            var vk = ParseKey(keyName);
            if (vk == 0) { warn?.Invoke("Unrecognised hotkey '" + keyName + "' - toggle key disabled."); return false; }

            var pid = (uint)Process.GetCurrentProcess().Id;
            var t = new Thread(() =>
            {
                var wasDown = false;
                while (true)
                {
                    Thread.Sleep(40);
                    try
                    {
                        GetWindowThreadProcessId(GetForegroundWindow(), out var fg);
                        var down = fg == pid && (GetAsyncKeyState(vk) & 0x8000) != 0;
                        if (down && !wasDown) onPressed();
                        wasDown = down;
                    }
                    catch (Exception e) { warn?.Invoke("Hotkey thread error: " + e.Message); Thread.Sleep(1000); }
                }
            })
            { IsBackground = true, Name = "BlackwoodMods.Hotkey" };
            t.Start();
            return true;
        }
    }
}
