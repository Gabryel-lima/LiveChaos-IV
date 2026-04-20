// LiveChaos.cs — entry point for the GTA IV mod.
// Inherits GTA.Script (IV-SDK .NET), overrides lifecycle events.
// All GTA IV native calls happen here or in HUD/EffectRunner, never in PipeClient.

using IVSDKDotNet;
using System;
using System.Numerics;
using static IVSDKDotNet.Native.Natives;

namespace LiveChaos {
    public class LiveChaos : Script {
        private readonly EffectRunner _runner = new EffectRunner();

        public LiveChaos() {
            Initialized  += OnInitialized;
            Uninitialize += OnUninitialize;
            Tick         += OnTick;
        }

        private void OnInitialized(object sender, EventArgs e) {
            PipeClient.Start();
            IVGame.Console.Print("[LiveChaos] mod initialised — connecting to Go server pipe");
        }

        private void OnUninitialize(object sender, EventArgs e) {
            IVGame.Console.Print("[LiveChaos] mod unloaded");
        }

        private void OnTick(object sender, EventArgs e) {
            int playerIdx    = CONVERT_INT_TO_PLAYERINDEX(GET_PLAYER_ID());
            GET_PLAYER_CHAR(playerIdx, out int playerHandle);
            GET_CHAR_COORDINATES(playerHandle, out Vector3 playerPos);

            // Draw HUD overlay (no-op during cooldown)
            HUD.Draw(PipeClient.Current);

            // Dispatch at most one queued effect per tick
            _runner.Tick(playerHandle, playerIdx, playerPos);
        }
    }
}
