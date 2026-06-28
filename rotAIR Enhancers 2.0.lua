---------------------------------------------------------------------
-- rotAIR Enhancers 2.0
-- HDG encoder acceleration via FlyWithLua create_command()
-- Commands appear as: FlyWithLua/rotAIR/[command]
--
-- Logik:
--  • SLOW: nutzt den originären X-Plane Command (1°), ohne Queue
--  • FAST: wird nur aktiv, wenn N "schnelle" Ticks erkannt wurden,
--          wobei zwischen erkannten schnellen Ticks bis zu G Glitches
--          (verlorene / nicht-schnelle dt) toleriert werden.
--          Dann: 3° über Queue (3×1° über Frames)
---------------------------------------------------------------------

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------
-- Timing: dt <= FAST_DT_SEC zählt als "schnell"
ROTAIR_FAST_DT_SEC = 0.08

-- FAST-Erkennung: N schnelle Ticks nötig, G Glitches toleriert
ROTAIR_FAST_N = 4
ROTAIR_FAST_G = 0

-- Schrittweiten
ROTAIR_HDG_STEP_SLOW = 1    -- direkt via X-Plane Command (1°)
ROTAIR_HDG_STEP_FAST = 20    -- Queue-Inkrement (wird über Frames abgearbeitet)

-- Debug (optional)
ROTAIR_DEBUG = false

---------------------------------------------------------------------
-- INTERNALS
---------------------------------------------------------------------
local cmd_hdg_up   = "sim/autopilot/heading_up"
local cmd_hdg_down = "sim/autopilot/heading_down"

local cmd_obs1_up   = "sim/radios/obs_HSI_up"
local cmd_obs1_down = "sim/radios/obs_HSI_down"

local cmd_obs2_up   = "sim/radios/obs2_up"
local cmd_obs2_down = "sim/radios/obs2_down"
local cmd_copilot_obs2_up   = "sim/radios/copilot_obs2_up"
local cmd_copilot_obs2_down = "sim/radios/copilot_obs2_down"

local cmd_adf1_card_up   = "sim/radios/adf1_card_up"
local cmd_adf1_card_down = "sim/radios/adf1_card_down"

-- Zeitquelle: Wall-Clock (robust, unabhängig von Sim-Time)
local function rotair_now_sec()
    return os.clock()
end

local last_tick_t = nil

-- FAST-Heuristik-State
local fast_hits   = 0
local fast_glitch = 0

-- Per-control FAST state (so HDG/OBS don't interfere with each other)
local obs1_state = { last_t = nil, hits = 0, glitch = 0 }
local obs2_state = { last_t = nil, hits = 0, glitch = 0 }
local adf1_state = { last_t = nil, hits = 0, glitch = 0 }

-- Queues for OBS acceleration (1° per frame)
local obs1_queue = 0
local obs2_queue = 0
local adf1_queue = 0

local function rotair_queue_add(current, delta)
    local q = current + delta
    if q > 360 then q = 360 end
    if q < -360 then q = -360 end
    return q
end

local function rotair_is_fast_state(state, dt)
    if dt <= ROTAIR_FAST_DT_SEC then
        state.hits = state.hits + 1
        state.glitch = 0
    else
        if state.hits > 0 then
            state.glitch = state.glitch + 1
            if state.glitch > ROTAIR_FAST_G then
                state.hits = 0
                state.glitch = 0
            end
        end
    end

    if state.hits >= ROTAIR_FAST_N then
        state.hits = 0
        state.glitch = 0
        return true
    end

    return false
end

-- Queue: 1° pro Frame, um "collapsing" zu vermeiden
local hdg_queue = 0

local function hdg_queue_add(delta)
    hdg_queue = hdg_queue + delta
    if hdg_queue > 360 then hdg_queue = 360 end
    if hdg_queue < -360 then hdg_queue = -360 end
end

local function rotair_log(msg)
    if ROTAIR_DEBUG then logMsg(msg) end
end

-- Returns true exactly when FAST should trigger (then resets state).
local function rotair_is_fast(dt)
    if dt <= ROTAIR_FAST_DT_SEC then
        fast_hits   = fast_hits + 1
        fast_glitch = 0
        rotair_log(string.format("rotAIR: fast dt=%.3f hits=%d glitch=%d", dt, fast_hits, fast_glitch))
    else
        -- Not fast. If we were building a streak, count a glitch.
        if fast_hits > 0 then
            fast_glitch = fast_glitch + 1
            rotair_log(string.format("rotAIR: glitch dt=%.3f hits=%d glitch=%d", dt, fast_hits, fast_glitch))
            if fast_glitch > ROTAIR_FAST_G then
                -- Too many glitches -> reset streak
                fast_hits   = 0
                fast_glitch = 0
                rotair_log("rotAIR: reset (too many glitches)")
            end
        end
    end

    if fast_hits >= ROTAIR_FAST_N then
        -- FAST achieved -> reset and signal FAST
        fast_hits   = 0
        fast_glitch = 0
        rotair_log("rotAIR: FAST trigger")
        return true
    end

    return false
end

---------------------------------------------------------------------
-- COMMAND HANDLER
---------------------------------------------------------------------
function rotair_hdg_inc()
    local t  = rotair_now_sec()
    local dt = last_tick_t and (t - last_tick_t) or 999
    last_tick_t = t

    if rotair_is_fast(dt) then
        -- FAST: queue multi-degree
        hdg_queue_add(ROTAIR_HDG_STEP_FAST)
    else
        -- SLOW: original command directly (no queue)
        command_once(cmd_hdg_up)
    end
end

function rotair_hdg_dec()
    local t  = rotair_now_sec()
    local dt = last_tick_t and (t - last_tick_t) or 999
    last_tick_t = t

    if rotair_is_fast(dt) then
        -- FAST: queue multi-degree
        hdg_queue_add(-ROTAIR_HDG_STEP_FAST)
    else
        -- SLOW: original command directly (no queue)
        command_once(cmd_hdg_down)
    end
end

function rotair_obs1_inc()
    local t = rotair_now_sec()
    local dt = obs1_state.last_t and (t - obs1_state.last_t) or 999
    obs1_state.last_t = t

    if rotair_is_fast_state(obs1_state, dt) then
        obs1_queue = rotair_queue_add(obs1_queue, ROTAIR_HDG_STEP_FAST)
    else
        command_once(cmd_obs1_up)
    end
end

function rotair_obs1_dec()
    local t = rotair_now_sec()
    local dt = obs1_state.last_t and (t - obs1_state.last_t) or 999
    obs1_state.last_t = t

    if rotair_is_fast_state(obs1_state, dt) then
        obs1_queue = rotair_queue_add(obs1_queue, -ROTAIR_HDG_STEP_FAST)
    else
        command_once(cmd_obs1_down)
    end
end

function rotair_obs2_inc()
    local t = rotair_now_sec()
    local dt = obs2_state.last_t and (t - obs2_state.last_t) or 999
    obs2_state.last_t = t

    if rotair_is_fast_state(obs2_state, dt) then
        obs2_queue = rotair_queue_add(obs2_queue, ROTAIR_HDG_STEP_FAST)
    else
        command_once(cmd_obs2_up)
        command_once(cmd_copilot_obs2_up)
    end
end

function rotair_obs2_dec()
    local t = rotair_now_sec()
    local dt = obs2_state.last_t and (t - obs2_state.last_t) or 999
    obs2_state.last_t = t

    if rotair_is_fast_state(obs2_state, dt) then
        obs2_queue = rotair_queue_add(obs2_queue, -ROTAIR_HDG_STEP_FAST)
    else
        command_once(cmd_obs2_down)
        command_once(cmd_copilot_obs2_down)
    end
end


function rotair_adf1_card_inc()
    local t = rotair_now_sec()
    local dt = adf1_state.last_t and (t - adf1_state.last_t) or 999
    adf1_state.last_t = t

    if rotair_is_fast_state(adf1_state, dt) then
        adf1_queue = rotair_queue_add(adf1_queue, ROTAIR_HDG_STEP_FAST)
    else
        command_once(cmd_adf1_card_up)
    end
end

function rotair_adf1_card_dec()
    local t = rotair_now_sec()
    local dt = adf1_state.last_t and (t - adf1_state.last_t) or 999
    adf1_state.last_t = t

    if rotair_is_fast_state(adf1_state, dt) then
        adf1_queue = rotair_queue_add(adf1_queue, -ROTAIR_HDG_STEP_FAST)
    else
        command_once(cmd_adf1_card_down)
    end
end



---------------------------------------------------------------------
-- QUEUE PROCESSING (1° per frame)
---------------------------------------------------------------------
function rotair_hdg_process_queue()
    -- HDG queue
    if hdg_queue > 0 then
        command_once(cmd_hdg_up)
        hdg_queue = hdg_queue - 1
    elseif hdg_queue < 0 then
        command_once(cmd_hdg_down)
        hdg_queue = hdg_queue + 1
    end

    -- OBS1 queue
    if obs1_queue > 0 then
        command_once(cmd_obs1_up)
        obs1_queue = obs1_queue - 1
    elseif obs1_queue < 0 then
        command_once(cmd_obs1_down)
        obs1_queue = obs1_queue + 1
    end

    -- OBS2 queue
    if obs2_queue > 0 then
        command_once(cmd_obs2_up)
        command_once(cmd_copilot_obs2_up)
        obs2_queue = obs2_queue - 1
    elseif obs2_queue < 0 then
        command_once(cmd_obs2_down)
        command_once(cmd_copilot_obs2_down)
        obs2_queue = obs2_queue + 1
    end

    -- ADF1 CARD queue
    if adf1_queue > 0 then
        command_once(cmd_adf1_card_up)
        adf1_queue = adf1_queue - 1
    elseif adf1_queue < 0 then
        command_once(cmd_adf1_card_down)
        adf1_queue = adf1_queue + 1
    end
end

do_every_frame("rotair_hdg_process_queue()")

---------------------------------------------------------------------
-- COMMAND REGISTRATION
---------------------------------------------------------------------
create_command(
    "FlyWithLua/rotAIR/HDG_right",
    "rotAIR: HDG right",
    "rotair_hdg_inc()",
    "",
    ""
)

create_command(
    "FlyWithLua/rotAIR/HDG_left",
    "rotAIR: HDG left",
    "rotair_hdg_dec()",
    "",
    ""
)

create_command(
    "FlyWithLua/rotAIR/OBS1_up",
    "rotAIR: OBS1 up",
    "rotair_obs1_inc()",
    "",
    ""
)

create_command(
    "FlyWithLua/rotAIR/OBS1_down",
    "rotAIR: OBS1 down",
    "rotair_obs1_dec()",
    "",
    ""
)


create_command(
    "FlyWithLua/rotAIR/OBS2_up",
    "rotAIR: OBS2 up",
    "rotair_obs2_inc()",
    "",
    ""
)

create_command(
    "FlyWithLua/rotAIR/OBS2_down",
    "rotAIR: OBS2 down",
    "rotair_obs2_dec()",
    "",
    ""
)

create_command(
    "FlyWithLua/rotAIR/ADF1 Card_up",
    "rotAIR: ADF1 Card up",
    "rotair_adf1_card_inc()",
    "",
    ""
)

create_command(
    "FlyWithLua/rotAIR/ADF1 Card_down",
    "rotAIR: ADF1 Card down",
    "rotair_adf1_card_dec()",
    "",
    ""
)

