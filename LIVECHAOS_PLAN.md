# LiveChaos-IV — Architecture & Implementation Plan
> Instruction document for GitHub Copilot (VSCode).
> Read this file entirely before generating any code.
> Follow each phase in order. Do not skip phases or merge steps.

---

## Project Overview

LiveChaos-IV is a chaos mod system for GTA IV composed of three independent components
that communicate over local IPC and WebSocket:

1. **Go Server** — central brain: Twitch IRC bot, vote aggregator, timer engine, IPC hub
2. **C# GTA IV Mod** — in-game HUD overlay using engine-native drawing calls
3. **OBS Lua Script** — spectator overlay injected into OBS via its built-in Lua runtime

The three components are **always decoupled**. They communicate through defined contracts
(TCP socket + WebSocket). No component imports another.

---

## Repository Structure

```
LiveChaos-IV/
├── server/                  # Go: central server
│   ├── main.go
│   ├── bot/
│   │   └── twitch.go        # IRC connection, message parsing
│   ├── vote/
│   │   └── aggregator.go    # vote counting, timer, winner selection
│   ├── ipc/
│   │   └── pipe.go          # named pipe server → GTA IV mod
│   ├── overlay/
│   │   └── ws.go            # WebSocket server → OBS Lua client
│   └── state/
│       └── state.go         # shared state struct, broadcast bus
│
├── mod/                     # C#: GTA IV ScriptHookDotNet mod
│   ├── LiveChaos.cs         # entry point, tick loop
│   ├── HUD.cs               # in-game overlay drawing
│   ├── PipeClient.cs        # named pipe client (reads from Go server)
│   └── EffectRunner.cs      # applies received effects to game
│
├── obs/                     # Lua: OBS spectator overlay
│   ├── livechaos_overlay.lua  # OBS script (Tools > Scripts)
│   └── sources.json           # OBS source names config
│
└── LIVECHAOS_PLAN.md        # this file
```

---

## Communication Contracts

### Contract A — Go Server → GTA IV Mod (Named Pipe)

**Pipe name:** `\\.\pipe\LiveChaosIV`

Message format (newline-delimited JSON):
```json
{ "type": "effect",  "id": "SPAWN_TANKS",  "duration_ms": 30000 }
{ "type": "timer",   "remaining_ms": 12400 }
{ "type": "reset" }
```

Rules:
- Go is the **server** (creates and listens on the pipe).
- C# mod is the **client** (connects on startup, reconnects on disconnect).
- Go writes only; C# reads only. No bidirectional state for now.

### Contract B — Go Server → OBS Lua (WebSocket)

**Address:** `ws://localhost:9001`

Message format (JSON text frames):
```json
{
  "timer_ms":      18500,
  "timer_max_ms":  30000,
  "effect":        "SPAWN_TANKS",
  "votes": {
    "SPAWN_TANKS":  14,
    "BLOW_ALL":      9,
    "RANDOM_PED":    6
  },
  "phase": "voting"
}
```

`phase` values: `"voting"` | `"active"` | `"cooldown"`

Rules:
- Go broadcasts this payload every **250ms** to all connected WebSocket clients.
- OBS Lua polls via WebSocket frame listener; updates OBS sources on each frame.
- State is always a **full snapshot**, never a delta. Lua should not track deltas.

---

## Component Specifications

---

### Component 1 — Go Server (`server/`)

#### Language & dependencies
- Go 1.22+
- `github.com/gorilla/websocket` — WebSocket server
- `github.com/gempir/go-twitch-irc/v4` — Twitch IRC client
- No CGo, no external C libraries.

#### Internal data flow
```
[Twitch IRC goroutine] ──votes──► [vote.Aggregator]
                                        │
                          ┌─────────────┼──────────────┐
                          ▼             ▼              ▼
                   [ipc.PipeServer] [overlay.WS]  [state.Bus]
                   (→ GTA IV mod)  (→ OBS Lua)
```

#### `state.State` struct (shared, define first)
```go
type Phase string
const (
    PhaseVoting   Phase = "voting"
    PhaseActive   Phase = "active"
    PhaseCooldown Phase = "cooldown"
)

type State struct {
    TimerMs    int64            `json:"timer_ms"`
    TimerMaxMs int64            `json:"timer_max_ms"`
    Effect     string           `json:"effect"`
    Votes      map[string]int   `json:"votes"`
    Phase      Phase            `json:"phase"`
}
```

#### `vote.Aggregator` behavior
- Holds a `map[string]int` of votes per cycle.
- A Twitch message counts as one vote per user per cycle (deduplicate by username).
- Cycle duration: configurable via `config.toml`, default 30s.
- On cycle end: select winner (highest votes, random tiebreak), publish effect to `state.Bus`,
  reset vote map, start cooldown (default 5s), then start next voting cycle.
- Exposes `func (a *Aggregator) CastVote(user, effectID string)`.

#### `ipc.PipeServer` behavior
- Creates `\\.\pipe\LiveChaosIV` on Windows using `golang.org/x/sys/windows`.
- On Linux/macOS (dev): use Unix domain socket at `/tmp/livechaos.sock`.
- Writes newline-delimited JSON on every state change from `state.Bus`.
- Reconnects automatically if client disconnects.

#### `overlay.WS` behavior
- Listens on `:9001`.
- On new connection: immediately send current state.
- On `state.Bus` tick (every 250ms): broadcast full `State` snapshot to all clients.
- Handle client disconnects gracefully (do not crash on write to closed conn).

#### `config.toml` (root of `server/`)
```toml
[twitch]
channel      = "your_channel"
oauth_token  = ""             # loaded from env: TWITCH_OAUTH

[timer]
vote_duration_s    = 30
cooldown_duration_s = 5

[effects]
pool = ["SPAWN_TANKS", "BLOW_ALL", "RANDOM_PED", "WANTED_MAX", "FLIP_CARS"]

[server]
ws_port  = 9001
pipe_name = "\\\\.\\pipe\\LiveChaosIV"
```

Load `TWITCH_OAUTH` from environment, never hardcode in source.

---

### Component 2 — C# GTA IV Mod (`mod/`)

#### Framework
- ScriptHookDotNet (SHDN) for GTA IV.
- Target: .NET Framework 4.0 (SHDN requirement for GTA IV).
- Entry point: class inheriting `GTA.Script`, override `Tick`.

#### `PipeClient.cs`
- Connects to `\\.\pipe\LiveChaosIV` on script load.
- Reads in a background thread (avoid blocking the game tick).
- Deserializes newline-delimited JSON into a `LiveState` struct.
- Exposes `static LiveState Current` — thread-safe with a lock.
- On disconnect: retry with exponential backoff (max 5s interval).

#### `LiveState` struct (C# side mirror of Go's State)
```csharp
public class LiveState {
    public int    TimerMs    { get; set; }
    public int    TimerMaxMs { get; set; }
    public string Effect     { get; set; }
    public string Phase      { get; set; }
    public Dictionary<string, int> Votes { get; set; }
}
```

#### `HUD.cs` — in-game overlay
Drawn every `Tick` using SHDN native drawing. Do not use external libraries.

Elements to draw:
```
┌──────────────────────────────────────┐  ← top-right corner
│  EFFECT: Spawn Tanks                 │  drawText, white, small font
│  [████████████░░░░░░░░] 18s          │  drawRect x2 (bg + fill), progress ratio
│  Votes: TANKS 14  BLOW 9  PED 6      │  drawText, grey, smaller font
└──────────────────────────────────────┘
```

Drawing rules:
- All coordinates normalized (0.0–1.0 relative to screen).
- Background rect: semi-transparent black (alpha ~160).
- Timer fill: lerp color from green → yellow → red based on `remaining / max`.
- Only draw when `Phase == "active"` or `Phase == "voting"`. Hide during cooldown.

#### `EffectRunner.cs`
- Listens to `PipeClient.Current.Effect` changes (compare with previous tick value).
- On new effect: dispatch to `switch` statement mapping effect IDs to game calls.
- Keep effect logic in separate partial methods: `RunSpawnTanks()`, `RunBlowAll()`, etc.
- Each effect method is self-contained. Do not share state between effects.

---

### Component 3 — OBS Lua Script (`obs/`)

#### OBS Lua runtime constraints
- OBS embeds Lua 5.1 with `obslua` bindings and `LuaSocket` (available via `require("socket")`).
- No coroutines for WebSocket. Use a **polling timer** via `obs_timer_add`.
- WebSocket client: use `socket.tcp()` from LuaSocket with HTTP Upgrade handshake,
  or use HTTP polling to `http://localhost:9001/state` as fallback if WS handshake fails.
- Recommended approach: **HTTP polling every 250ms** via `socket.http` (simpler, no WS framing).
  Go server must expose `GET /state` returning current `State` as JSON.

#### OBS sources to control (configure names in `sources.json`)
| Source Name             | Type          | Content            |
|-------------------------|---------------|--------------------|
| `LC_Effect`             | Text (GDI+)   | current effect ID  |
| `LC_Timer_BG`           | Color Source  | background bar     |
| `LC_Timer_Fill`         | Color Source  | fill bar (width %) |
| `LC_Votes`              | Text (GDI+)   | vote counts line   |
| `LC_Phase`              | Text (GDI+)   | phase label        |

#### Script structure
```lua
-- livechaos_overlay.lua
local obs    = obslua
local http   = require("socket.http")
local json   = require("dkjson")  -- bundled with OBS

local CONFIG = {
    poll_url     = "http://localhost:9001/state",
    poll_ms      = 250,
    timer_source = "LC_Timer_Fill",   -- source whose width we scale
    timer_max_px = 400,               -- pixel width at 100%
    -- add other source names here
}

local state = {}

function script_description()
    return "LiveChaos-IV overlay for OBS"
end

function script_load(settings)
    obs.timer_add(poll_server, CONFIG.poll_ms)
end

function script_unload()
    obs.timer_remove(poll_server)
end

function poll_server()
    local body, code = http.request(CONFIG.poll_url)
    if code == 200 then
        local data, _, err = json.decode(body)
        if data then
            update_sources(data)
        end
    end
end

function update_sources(data)
    -- update text sources
    set_text("LC_Effect", data.effect or "---")
    set_text("LC_Phase",  data.phase  or "---")

    -- format vote line
    local vote_line = ""
    if data.votes then
        for k, v in pairs(data.votes) do
            vote_line = vote_line .. k .. ": " .. v .. "  "
        end
    end
    set_text("LC_Votes", vote_line)

    -- scale timer bar width
    local ratio = 0
    if data.timer_max_ms and data.timer_max_ms > 0 then
        ratio = data.timer_ms / data.timer_max_ms
    end
    set_source_width("LC_Timer_Fill", math.floor(CONFIG.timer_max_px * ratio))
end

function set_text(source_name, text)
    local source   = obs.obs_get_source_by_name(source_name)
    if source == nil then return end
    local settings = obs.obs_data_create()
    obs.obs_data_set_string(settings, "text", text)
    obs.obs_source_update(source, settings)
    obs.obs_data_release(settings)
    obs.obs_source_release(source)
end

function set_source_width(source_name, width_px)
    local scene_item = find_scene_item(source_name)
    if scene_item == nil then return end
    local scale = obs.vec2()
    obs.obs_sceneitem_get_scale(scene_item, scale)
    scale.x = width_px / CONFIG.timer_max_px
    obs.obs_sceneitem_set_scale(scene_item, scale)
end

function find_scene_item(source_name)
    local scene_source = obs.obs_frontend_get_current_scene()
    if scene_source == nil then return nil end
    local scene = obs.obs_scene_from_source(scene_source)
    local item  = obs.obs_scene_find_source(scene, source_name)
    obs.obs_source_release(scene_source)
    return item
end
```

---

## Implementation Phases

Work through each phase completely before starting the next.

### Phase 0 — State contract and config (Go)
- [ ] Define `state.State` struct and `state.Bus` (channel-based broadcaster)
- [ ] Parse `config.toml` into a `Config` struct on startup
- [ ] Load `TWITCH_OAUTH` from environment; fail fast if missing

### Phase 1 — Vote aggregator (Go)
- [ ] Implement `vote.Aggregator` with deduplication and cycle timer
- [ ] Unit test: 3 users vote, correct winner selected, map resets after cycle
- [ ] Wire aggregator output to `state.Bus`

### Phase 2 — Twitch IRC bot (Go)
- [ ] Connect to Twitch IRC via `go-twitch-irc`, join channel from config
- [ ] Parse `!vote EFFECT_ID` messages, call `aggregator.CastVote`
- [ ] Ignore messages from users who already voted in current cycle

### Phase 3 — Named pipe IPC (Go + C#)
- [ ] Go: implement `ipc.PipeServer`, write JSON on state change
- [ ] C#: implement `PipeClient`, background reader thread, `Current` with lock
- [ ] Integration test: run Go server, connect C# client, verify message delivery

### Phase 4 — WebSocket + HTTP state endpoint (Go)
- [ ] Go: implement `overlay.WS` broadcasting at 250ms
- [ ] Go: expose `GET /state` returning current `State` as JSON
- [ ] Test with `wscat` or `curl http://localhost:9001/state`

### Phase 5 — In-game HUD (C#)
- [ ] Implement `HUD.cs` drawing timer bar, effect name, vote counts
- [ ] Test in-game with hardcoded mock state before wiring to `PipeClient`
- [ ] Wire `PipeClient.Current` to HUD rendering
- [ ] Implement `EffectRunner.cs` with at least 3 effects

### Phase 6 — OBS Lua overlay
- [ ] Create OBS Text (GDI+) and Color sources with names from `sources.json`
- [ ] Load `livechaos_overlay.lua` via Tools > Scripts in OBS
- [ ] Verify `poll_server` receives data from Go `/state` endpoint
- [ ] Test all source update functions with Go server running

### Phase 7 — Integration & polish
- [ ] Run all three components simultaneously, verify end-to-end flow
- [ ] Add `config.toml` hot-reload on SIGHUP (Go)
- [ ] Add effect blacklist support in config
- [ ] Write `README.md` with setup instructions

---

## Coding Constraints for Copilot

- **Go**: no global mutable state outside `state.Bus`. Use channels for all cross-goroutine
  communication. Every goroutine that can fail must recover and log, not crash the server.
- **C#**: all GTA IV native calls happen only on the game thread (inside `Tick`).
  PipeClient reads on a background thread; shared state protected by `lock`.
- **Lua**: keep the script procedural. No metatables, no OOP. Functions are top-level.
  Always release OBS sources after use (`obs_source_release`, `obs_data_release`).
- **JSON field names**: always snake_case. Go structs use `json:"field_name"` tags.
  C# uses `Newtonsoft.Json` with `[JsonProperty("field_name")]` attributes.
- **No hardcoded credentials** anywhere in source. Use environment variables or `config.toml`.
- **Effect IDs** are always SCREAMING_SNAKE_CASE strings. Define a constants file per component.
