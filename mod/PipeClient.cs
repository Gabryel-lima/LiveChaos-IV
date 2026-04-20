// PipeClient — reads newline-delimited JSON from the Go server's named pipe
// and maintains LiveState.Current.
//
// Background thread only; never touch GTA IV natives here.
// All GTA IV native calls happen in the game thread (LiveChaos.cs / EffectRunner.cs).

using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Pipes;
using System.Threading;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace LiveChaos {
    /// <summary>Mirror of the Go server's state.State struct.</summary>
    public class LiveState {
        [JsonProperty("timer_ms")]    public int    TimerMs    { get; set; }
        [JsonProperty("timer_max_ms")]public int    TimerMaxMs { get; set; }
        [JsonProperty("effect")]      public string Effect     { get; set; }
        [JsonProperty("phase")]       public string Phase      { get; set; }
        [JsonProperty("votes")]       public Dictionary<string, int> Votes { get; set; }
    }

    /// <summary>
    /// Typed pipe messages sent by the Go server.
    /// </summary>
    internal class PipeMsg {
        [JsonProperty("type")]        public string Type       { get; set; }
        [JsonProperty("id")]          public string Id         { get; set; }
        [JsonProperty("duration_ms")] public int    DurationMs { get; set; }
        [JsonProperty("remaining_ms")]public int    RemainingMs{ get; set; }
    }

    /// <summary>
    /// Named-pipe client. Reads pipe messages in a background thread and
    /// updates <see cref="Current"/> with a lock.
    /// </summary>
    public static class PipeClient {
        private const string PipeName = "LiveChaosIV";

        private static readonly object      _lock    = new object();
        private static          LiveState   _state   = new LiveState();
        private static readonly Queue<string> _pendingEffects = new Queue<string>();

        /// <summary>Thread-safe snapshot of the latest state.</summary>
        public static LiveState Current {
            get { lock (_lock) { return _state; } }
        }

        /// <summary>
        /// Dequeues and returns the next pending effect ID, or null if none.
        /// Called from the game thread each tick.
        /// </summary>
        public static string DequeueEffect() {
            lock (_lock) {
                return _pendingEffects.Count > 0 ? _pendingEffects.Dequeue() : null;
            }
        }

        /// <summary>Starts the background receiver thread.</summary>
        public static void Start() {
            var t = new Thread(ReceiveLoop) { IsBackground = true, Name = "PipeClient" };
            t.Start();
        }

        private static void ReceiveLoop() {
            while (true) {
                try {
                    ConnectAndRead();
                }
                catch (Exception ex) {
                    IVSDKDotNet.IVGame.Console.Print($"[PipeClient] error: {ex.Message} — reconnecting");
                    BackoffSleep();
                }
            }
        }

        private static void ConnectAndRead() {
            int backoffMs = 1000;
            while (true) {
                try {
                    using (var pipe = new NamedPipeClientStream(".", PipeName, 
                               PipeDirection.In, PipeOptions.None)) {
                        pipe.Connect(5000); // wait up to 5 s
                        IVSDKDotNet.IVGame.Console.Print("[PipeClient] connected to Go server");
                        backoffMs = 1000;
                        using (var reader = new StreamReader(pipe)) {
                            string line;
                            while ((line = reader.ReadLine()) != null) {
                                ProcessLine(line.Trim());
                            }
                        }
                    }
                }
                catch (TimeoutException) {
                    Thread.Sleep(Math.Min(backoffMs, 5000));
                    backoffMs = Math.Min(backoffMs * 2, 5000);
                }
            }
        }

        private static void ProcessLine(string json) {
            if (string.IsNullOrEmpty(json)) return;

            try {
                var msg = JsonConvert.DeserializeObject<PipeMsg>(json);
                if (msg == null) return;

                lock (_lock) {
                    switch (msg.Type) {
                        case "effect":
                            _state.Effect     = msg.Id;
                            _state.TimerMaxMs = msg.DurationMs;
                            _state.Phase      = "active";
                            _pendingEffects.Enqueue(msg.Id); // queue, not overwrite
                            break;

                        case "timer":
                            _state.TimerMs = msg.RemainingMs;
                            break;

                        case "reset":
                            _state.Effect = null;
                            _state.Phase  = "cooldown";
                            _state.TimerMs = 0;
                            break;
                    }
                }
            }
            catch (Exception ex) {
                IVSDKDotNet.IVGame.Console.Print($"[PipeClient] parse error: {ex.Message}");
            }
        }

        private static void BackoffSleep() {
            Thread.Sleep(2000);
        }
    }
}
