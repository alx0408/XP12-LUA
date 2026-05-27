-- LandingReplay.lua
-- X-Plane 12 + FlyWithLua
--
-- Command: FlyWithLua/LandingReplay
-- Behavior:
--   1) Enter replay mode
--   2) Switch to chase view
--   3) Fast reverse until TARGET_AGL_FT (AGL) is reached
--   4) Pause there
--
-- Requirements (your latest):
--   - The automatic stop at TARGET_AGL_FT must ONLY happen while *rewinding* (reverse playback).
--   - After the script has paused at TARGET_AGL_FT once, it must STOP running entirely
--     the first time you leave pause mode (i.e., as soon as the sim is unpaused again).
--   - When you later want another auto-stop during reverse, you trigger the command again.

local TARGET_AGL_FT = 50.0
local TARGET_AGL_M  = TARGET_AGL_FT * 0.3048
local HYST_M        = 1.0

-- AGL (meters)
dataref("y_agl_m", "sim/flightmodel/position/y_agl", "readonly")

-- Pause state: 1 paused, 0 running
dataref("sim_paused", "sim/time/paused", "readonly")

-- Replay state: 1 = in replay, 0 = normal sim
-- (Used to shut down the script cleanly when replay ends / replay mode is exited)
dataref("in_replay", "sim/time/is_in_replay", "readonly")

-- Replay commands (XP12 replay namespace)
local CMD_REPLAY_TOGGLE   = "sim/replay/replay_toggle"
local CMD_REPLAY_PAUSE    = "sim/replay/rep_pause"
local CMD_REPLAY_FAST_REV = "sim/replay/rep_play_fr"   -- fast reverse

-- View
local CMD_VIEW_CHASE      = "sim/view/chase"

local active = false
local state = 0
local rewinding = false

-- Once we paused at target, we arm shutdown as soon as the user unpauses again
local armed_shutdown_on_unpause = false

-- Becomes true once we have actually entered replay mode at least once.
-- Prevents premature shutdown during the initial transition into replay.
local replay_entered = false

local function log(s) logMsg("[LandingReplay] " .. s) end
local function once(c) if c and c ~= "" then command_once(c) end end
local function begin_cmd(c) if c and c ~= "" then command_begin(c) end end
local function end_cmd(c) if c and c ~= "" then command_end(c) end end

local function shutdown(reason)
  if rewinding then
    end_cmd(CMD_REPLAY_FAST_REV)
    rewinding = false
  end
  active = false
  state = 0
  armed_shutdown_on_unpause = false
  replay_entered = false
  log("Stopped: " .. (reason or ""))
end

-- IMPORTANT: global for create_command
function start_landing_replay()
  active = true
  state = 1
  rewinding = false
  armed_shutdown_on_unpause = false
  replay_entered = false
  log("Triggered")
end

create_command(
  "FlyWithLua/LandingReplay",
  "Landing Replay (Replay + Chase + fast reverse to 50ft AGL + pause; stop after first unpause)",
  "start_landing_replay()",
  "",
  ""
)

-- Replay OFF + Pause OFF

function replay_off_unpause()
    command_once("sim/replay/replay_off")
    command_once("sim/operation/pause_off")
end

create_command(
    "FlyWithLua/Replay_OFF_and_Unpause",
    "Replay OFF and unpause simulator",
    "replay_off_unpause()",
    "",
    ""
)

function landing_replay_tick()
  if not active then return end

  -- Track whether we have actually entered replay mode.
  if in_replay == 1 then
    replay_entered = true
  end

  -- If replay has ended / replay mode was exited, stop the script entirely so
  -- no further AGL checks or replay commands can run in normal flight.
  if replay_entered and in_replay == 0 then
    shutdown("Replay ended / replay mode exited")
    return
  end

  -- After we paused at the target point, the first time the user leaves pause mode,
  -- the script must stop entirely (no further AGL checks, no interference on takeoff).
  if armed_shutdown_on_unpause and sim_paused == 0 then
    shutdown("User unpaused after target stop")
    return
  end

  if state == 1 then
    once(CMD_REPLAY_TOGGLE)
    log("Replay toggle")
    state = 2
    return
  end

  if state == 2 then
    once(CMD_VIEW_CHASE)
    log("Chase view")
    state = 3
    return
  end

  if state == 3 then
    -- We ONLY do the AGL stop logic while we ourselves are rewinding.
    -- (Once the script stops, it can never stop you again unless you trigger it again.)
    if y_agl_m < (TARGET_AGL_M - HYST_M) then
      if not rewinding then
        begin_cmd(CMD_REPLAY_FAST_REV)
        rewinding = true
        log("Fast reverse begin")
      end
    else
      if rewinding then
        end_cmd(CMD_REPLAY_FAST_REV)
        rewinding = false
        log("Fast reverse end @ AGL=" .. string.format("%.1f m", y_agl_m))
      end
      state = 4
    end
    return
  end

  if state == 4 then
    -- Pause at target AGL, then arm shutdown for the moment the user unpauses again.
    once(CMD_REPLAY_PAUSE)
    log("Paused @ " .. tostring(TARGET_AGL_FT) .. "ft AGL; will stop on first unpause")
    armed_shutdown_on_unpause = true
    state = 5
    return
  end

  if state == 5 then
    -- Idle while paused; waiting for user to unpause -> then shutdown above.
    return
  end
end

do_every_frame("landing_replay_tick()")