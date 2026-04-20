--[[
  LiveChaos-IV — OBS Lua overlay script
  ======================================
  Load via OBS → Tools → Scripts → "+" → select this file.

  Polls http://localhost:9001/state every 250 ms and updates the following
  OBS sources (create them manually or via obs_setup_sources() below):

    LC_Effect      — Text (GDI+) showing the current effect ID
    LC_Phase       — Text (GDI+) showing the current phase
    LC_Votes       — Text (GDI+) showing vote counts
    LC_Timer_BG    — Color Source used as the timer bar background
    LC_Timer_Fill  — Color Source whose X scale drives the fill ratio

  OBS source names can be customised in CONFIG below.

  Requirements:
    • OBS 28+ (LuaSocket is bundled; dkjson is bundled as obs-scripting)
    • Go server running: cd server && go run . (see README)

  IMPORTANT: Always release OBS resources after use.
--]]

local obs  = obslua
local http = require("socket.http")

-- Try to load dkjson (bundled with OBS since 28.x).
-- Fall back to a minimal JSON decoder if not available.
local json_ok, json = pcall(require, "dkjson")
if not json_ok then
    -- Minimal JSON decoder — handles the flat State struct only.
    json = {}
    function json.decode(s)
        local t = {}
        -- numbers
        for k, v in s:gmatch('"([^"]+)"%s*:%s*(-?%d+%.?%d*)') do
            t[k] = tonumber(v)
        end
        -- strings
        for k, v in s:gmatch('"([^"]+)"%s*:%s*"([^"]*)"') do
            t[k] = v
        end
        -- votes object (key:number pairs inside nested {})
        local votes_block = s:match('"votes"%s*:%s*(%b{})')
        if votes_block then
            local votes = {}
            for k, v in votes_block:gmatch('"([^"]+)"%s*:%s*(%d+)') do
                votes[k] = tonumber(v)
            end
            t.votes = votes
        end
        return t, 1, nil
    end
end

-- ── Configuration ─────────────────────────────────────────────────────────────
local CONFIG = {
    poll_url      = "http://localhost:9001/state",
    poll_ms       = 250,

    -- OBS source names (must match what you created in OBS)
    src_effect    = "LC_Effect",
    src_phase     = "LC_Phase",
    src_votes     = "LC_Votes",
    src_timer_fill= "LC_Timer_Fill",

    -- Reference pixel width of LC_Timer_Fill at 100% — match the source width in OBS
    timer_max_px  = 400,
}
-- ── End Configuration ─────────────────────────────────────────────────────────

local last_state = {}

-- ── Script metadata ───────────────────────────────────────────────────────────

function script_description()
    return "LiveChaos-IV — polls the Go server and updates OBS sources every 250 ms."
end

function script_properties()
    local props = obs.obs_properties_create()
    obs.obs_properties_add_text(props, "poll_url", "Server URL", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_int(props, "poll_ms", "Poll interval (ms)", 100, 2000, 50)
    obs.obs_properties_add_int(props, "timer_max_px", "Timer bar max width (px)", 50, 2000, 10)
    return props
end

function script_defaults(settings)
    obs.obs_data_set_default_string(settings, "poll_url",     CONFIG.poll_url)
    obs.obs_data_set_default_int(settings,    "poll_ms",      CONFIG.poll_ms)
    obs.obs_data_set_default_int(settings,    "timer_max_px", CONFIG.timer_max_px)
end

function script_update(settings)
    CONFIG.poll_url     = obs.obs_data_get_string(settings, "poll_url")
    CONFIG.poll_ms      = obs.obs_data_get_int(settings, "poll_ms")
    CONFIG.timer_max_px = obs.obs_data_get_int(settings, "timer_max_px")
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

function script_load(settings)
    script_update(settings)
    obs.timer_add(poll_server, CONFIG.poll_ms)
    print("[LiveChaos] overlay script loaded")
end

function script_unload()
    obs.timer_remove(poll_server)
    print("[LiveChaos] overlay script unloaded")
end

-- ── Polling ───────────────────────────────────────────────────────────────────

function poll_server()
    local body, code = http.request(CONFIG.poll_url)
    if code ~= 200 or not body then return end

    local data, _, err = json.decode(body)
    if err or not data then
        print("[LiveChaos] JSON decode error: " .. tostring(err))
        return
    end
    update_sources(data)
    last_state = data
end

-- ── Source update ─────────────────────────────────────────────────────────────

function update_sources(data)
    -- Effect label
    set_text(CONFIG.src_effect, data.effect or "---")

    -- Phase label
    set_text(CONFIG.src_phase, data.phase or "---")

    -- Vote counts line
    local vote_line = build_vote_line(data.votes)
    set_text(CONFIG.src_votes, vote_line)

    -- Timer fill bar width
    local ratio = 0
    if data.timer_max_ms and data.timer_max_ms > 0 then
        ratio = (data.timer_ms or 0) / data.timer_max_ms
    end
    ratio = math.max(0, math.min(1, ratio))
    local fill_px = math.floor(CONFIG.timer_max_px * ratio)
    set_source_width(CONFIG.src_timer_fill, fill_px)
end

function build_vote_line(votes)
    if not votes then return "Votes: —" end
    local parts = {}
    for k, v in pairs(votes) do
        parts[#parts + 1] = k .. ": " .. tostring(v)
    end
    if #parts == 0 then return "Votes: —" end
    return "Votes: " .. table.concat(parts, "  ")
end

-- ── OBS helpers ───────────────────────────────────────────────────────────────

function set_text(source_name, text)
    local source = obs.obs_get_source_by_name(source_name)
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
    if CONFIG.timer_max_px > 0 then
        scale.x = width_px / CONFIG.timer_max_px
    end
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
