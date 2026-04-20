// HUD.cs — in-game overlay drawn every Tick.
// All drawing happens on the game thread. Never call PipeClient from here except to read.
// Coordinates are normalized (0.0–1.0 relative to screen).

using System;
using System.Collections.Generic;
using System.Text;
using static IVSDKDotNet.Native.Natives;

namespace LiveChaos {
    internal static class HUD {
        // Panel position (top-right corner) — normalized screen coordinates
        private const float PanelX = 0.985f; // right-align anchor
        private const float PanelY = 0.030f;
        private const float PanelW = 0.32f;
        private const float PanelH = 0.115f;

        // Timer bar
        private const float BarX = 0.985f;
        private const float BarY = 0.075f;
        private const float BarW = 0.28f;
        private const float BarH = 0.015f;

        /// <summary>
        /// Draw the LiveChaos HUD. Must be called from the game Tick handler.
        /// Does nothing when Phase is "cooldown" or when state is null.
        /// </summary>
        public static void Draw(LiveState state) {
            if (state == null) return;
            string phase = state.Phase ?? "";
            if (phase == "cooldown") return;

            // Semi-transparent background panel
            DrawRect(PanelX, PanelY, PanelW, PanelH, 0, 0, 0, 160);

            // Effect name (white)
            string effectLabel = string.IsNullOrEmpty(state.Effect) ? "---" : state.Effect.Replace("_", " ");
            DrawHUDText(0.830f, 0.033f, $"EFFECT: {effectLabel}", 255, 255, 255, 220);

            // Timer bar background (dark grey)
            DrawRect(BarX, BarY, BarW, BarH, 50, 50, 50, 200);

            // Timer bar fill — color lerps green→yellow→red based on remaining/max
            float ratio = state.TimerMaxMs > 0 ? (float)state.TimerMs / state.TimerMaxMs : 0f;
            ratio = Math.Max(0f, Math.Min(1f, ratio));

            int fr, fg;
            if (ratio >= 0.5f) {
                float t = (ratio - 0.5f) * 2f; // 1→0 as ratio 1→0.5 (green fades to yellow)
                fr = (int)(255 * (1f - t));
                fg = 255;
            }
            else {
                float t = ratio * 2f; // 1→0 as ratio 0.5→0 (yellow fades to red)
                fr = 255;
                fg = (int)(255 * t);
            }

            float fillW = BarW * ratio;
            float fillX = BarX - (BarW - fillW) * 0.5f; // right-align fill from anchor
            DrawRect(fillX, BarY, fillW, BarH, fr, fg, 0, 220);

            // Remaining seconds label
            int remainingSec = state.TimerMs / 1000;
            DrawHUDText(BarX - BarW + 0.02f, BarY - 0.006f, $"{remainingSec}s", 200, 200, 200, 200);

            // Vote counts (grey, smaller)
            string voteLine = BuildVoteLine(state.Votes);
            DrawHUDText(0.830f, 0.095f, voteLine, 180, 180, 180, 200);
        }

        private static string BuildVoteLine(Dictionary<string, int> votes) {
            if (votes == null || votes.Count == 0) return "Votes: —";
            var sb = new StringBuilder("Votes: ");
            foreach (var kv in votes) {
                // Abbreviate long IDs to first 4 chars to keep the line short
                string key = kv.Key.Length > 4 ? kv.Key.Substring(0, 4) : kv.Key;
                sb.Append($"{key} {kv.Value}  ");
            }
            return sb.ToString().TrimEnd();
        }

        // ── Native drawing wrappers ────────────────────────────────────────────

        /// <summary>Draws a rectangle. All coords normalized 0–1.</summary>
        private static void DrawRect(float x, float y, float w, float h, int r, int g, int b, int a) {
            // GTA IV DRAW_RECT: left, top, right, bottom, r, g, b, a
            DRAW_RECT(x - w * 0.5f, y - h * 0.5f, x + w * 0.5f, y + h * 0.5f, r, g, b, a);
        }

        /// <summary>Draws a single line of HUD text at the given normalized position.</summary>
        private static void DrawHUDText(float x, float y, string text, int r, int g, int b, int a) {
            SET_TEXT_SCALE(0.0f, 0.22f);
            SET_TEXT_COLOUR((uint)r, (uint)g, (uint)b, (uint)a);
            SET_TEXT_RIGHT_JUSTIFY(false);
            SET_TEXT_DROPSHADOW(true, (uint)0, (uint)0, (uint)0, (uint)180);
            DISPLAY_TEXT_WITH_LITERAL_STRING(x, y, "STRING", text);
        }
    }
}
