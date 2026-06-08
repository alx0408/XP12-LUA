-- ============================================================
--  xp12_incidents_v3.lua
--  Custom Failure & Incident System for X-Plane 12  —  V 3.0
--  Aircraft: SimCoders B58 REP
--  Requires: FlyWithLua NG+
--
--  V3 additions over V2:
--    - FUEL_CAP:  virtual drain routine, one side, high→decreasing
--      rate (1 kg/s → ~0.05), airborne only, no memory.
--      Fix: reset profile or pause script.
--    - FUEL_CAP check prevention: switching to any external view
--      while on the ground registers a preflight walk-around check.
--      After the check, FUEL_CAP cannot trigger automatically.
--      Manual trigger always works regardless of check state.
--      Check resets when fuel quantity rises by >1 kg vs. last
--      engine-off snapshot (refueling detected). Snapshot is saved
--      at engine-off and on first script start.
--    - FUEL_LEAK: virtual drain routine, 40% L / 40% R / 20% both,
--      low→increasing rate (0.1 → 1.0 kg/s), memory-persistent.
--      Fix: delete FUEL_LEAK entry in memory file, reset profile,
--      or pause script.
--    - Both fuel routines stop at 0.5 kg remaining in affected tank(s).
--    - DOOR_OPEN: intercepts rel_door_open — no DataRef=6. Triggers a
--      dice roll: one available/unlatched door is opened via the
--      physical sim DataRef (cockpit2/switches/door_open[n]).
--    - DOOR_1 / DOOR_2: virtual failures (configurable per profile).
--      Latch guard: open+close each door on ground+engine-off sets
--      "latched" guard, saved per profile in memory. Guard clears
--      when door opens. Manual trigger always fires regardless.
--      Command: FlyWithLua/Incidents/latch_all_doors latches all
--      available doors in one step.
--    - Fuel and door status display in incidents status overlay.
--    - Startup/status popup enlarged by one line.
--
--  Structure:
--    [1] Framework   — Config, profiles, helpers, save/load
--    [2] Fuel Routines — Custom fuel cap/leak simulation
--    [2b] Door Routines — Custom door-open failure simulation
--    [3] Failures    — Failure table + trigger/reset logic
--    [4] Commands    — Global commands + per-failure toggles
--    [5] Macro       — Draw callback + add_macro
--    [6] Init        — Bootstrap, tick registration
-- ============================================================

math.randomseed(os.time())


-- ============================================================
--  [1] FRAMEWORK
-- ============================================================

-- ---- DataRef bindings --------------------------------------
dataref("dr_acf_icao",     "sim/aircraft/view/acf_ICAO",                 "readonly")
dataref("dr_elec_trim_on", "sim/cockpit2/autopilot/electric_trim_on",    "readonly")
dataref("dr_bat_on",       "sim/cockpit/electrical/battery_on",          "readonly")
dataref("dr_avion",        "sim/cockpit/electrical/avionics_on",         "readonly")

local _ref_on_ground = XPLMFindDataRef("sim/flightmodel/failures/onground_any")
local _ref_engn      = XPLMFindDataRef("sim/flightmodel/engine/ENGN_running")
local _ref_gen_on    = XPLMFindDataRef("sim/cockpit/electrical/generator_on")
local _ref_volts     = XPLMFindDataRef("sim/cockpit2/electrical/bus_volts")
local _ref_gspeed    = XPLMFindDataRef("sim/flightmodel/position/groundspeed")
local _ref_view_ext  = XPLMFindDataRef("sim/graphics/view/view_is_external")

-- ---- Fuel DataRefs (scalar, confirmed working per fuel_leak_test) ----
local _ref_fuel_l = XPLMFindDataRef("sim/flightmodel/weight/m_fuel1")   -- left  tank
local _ref_fuel_r = XPLMFindDataRef("sim/flightmodel/weight/m_fuel2")   -- right tank

-- ---- Door DataRef (int[20], writable, index 0=pilot door, 1=copilot) ----
local _ref_door_sw = XPLMFindDataRef("sim/cockpit2/switches/door_open")

local function read_door(n)   -- n=1 or 2 → door_open[n-1]; key returned by FlyWithLua is offset-based
    if not _ref_door_sw then return 0 end
    local ok, v = pcall(XPLMGetDatavi, _ref_door_sw, n - 1, 1)
    return (ok and v and v[n - 1]) or 0
end
local function write_door(n, val)
    if not _ref_door_sw then return end
    local t = {}; t[n - 1] = val   -- FlyWithLua reads table[StartFrom+i]; key must match offset
    pcall(XPLMSetDatavi, _ref_door_sw, t, n - 1, 1)
end

local function read_fuel_l()
    local ok, v = pcall(XPLMGetDataf, _ref_fuel_l)
    return (ok and type(v) == "number") and v or nil
end
local function read_fuel_r()
    local ok, v = pcall(XPLMGetDataf, _ref_fuel_r)
    return (ok and type(v) == "number") and v or nil
end
local function write_fuel_l(v) if _ref_fuel_l then XPLMSetDataf(_ref_fuel_l, v) end end
local function write_fuel_r(v) if _ref_fuel_r then XPLMSetDataf(_ref_fuel_r, v) end end

-- ---- Flight condition helpers ------------------------------
local function airborne()
    if not _ref_on_ground then return false end
    return XPLMGetDatai(_ref_on_ground) == 0
end

local function engine_on()
    if not _ref_engn then return false end
    local v = XPLMGetDatavi(_ref_engn, 0, 2)
    return v ~= nil and (v[0] == 1 or v[1] == 1)
end

local function electrical_on()
    if not _ref_volts then return false end
    local v = XPLMGetDatavf(_ref_volts, 0, 1)
    return v ~= nil and (v[0] or 0) > 1
end

local function read_gen_on()
    if not _ref_gen_on then return 0 end
    local v = XPLMGetDatavi(_ref_gen_on, 0, 1)
    return (v and v[0]) or 0
end

-- ---- Fix conditions ----------------------------------------
local function smoke_fixable()
    return not electrical_on()
end

local function trim_fixable()
    return dr_elec_trim_on == 0
end

-- ---- Smoke culprit state -----------------------------------
local smoke_culprit    = nil   -- "bat" | "avion" | "gen"
local smoke_prev_bat   = nil
local smoke_prev_avion = nil
local smoke_prev_gen   = nil

-- ---- Forward declarations ----------------------------------
-- save_memory is defined further below but called from callbacks
-- defined here (smoke_on_fix, start_fuel_leak, stop_fuel_leak).
local save_memory
local find_failure

local failures
local get_dr, set_dr, get_mtbf

-- Fuel routine state tables; assigned in [2], referenced in save/load_memory.
local fuelcap_routine
local fuelleak_routine
local fuel_drain_last = 0

-- Door routine state table; assigned in [2b], referenced in save/load_memory.
local door_routine

-- Fuel cap preflight check state
local fuel_cap_check_done   = false  -- true: external-view check done, FUEL_CAP blocked
local fuel_drain_check_done = false  -- true: drain command done in ext view, FUEL_WATER blocked
local fuel_type_pending     = false  -- true: refueling detected, FUEL_TYPE can trigger while on ground
local fuel_cap_mem_l        = nil    -- last engine-off T1 qty (kg) — loaded from memory
local fuel_cap_mem_r        = nil    -- last engine-off T2 qty (kg) — loaded from memory
local engine_prev_on        = false  -- for engine-off edge detection

-- ---- Smoke on-fix callback ---------------------------------
local function smoke_on_fix(f)
    f._fix_cond = nil
    if f._fire_induced then
        f._fire_induced = nil
        return
    end
    if smoke_culprit then return end
    local r = math.random()
    if     r < 0.20 then smoke_culprit = "bat"
    elseif r < 0.40 then smoke_culprit = "gen"
    else                  smoke_culprit = "avion"
    end
    smoke_prev_bat   = dr_bat_on
    smoke_prev_avion = dr_avion
    smoke_prev_gen   = read_gen_on()
    save_memory()
end

-- ---- Config ------------------------------------------------
local cfg = {
    mode            = "ON",
    default_mtbf    = 10000,
    profiles        = {},
    active_failures = {},
    active_name     = "DEFAULT",
}

local CONFIG_PATH = SCRIPT_DIRECTORY .. "xp12_incidents_config.txt"

local function parse_failure_entry(val_str)
    local main = val_str:match("^%s*([^;%s]+)")
    if not main then return "DEFAULT" end
    local mtbf
    if     main == "OFF"     then mtbf = "OFF"
    elseif main == "DEFAULT" then mtbf = "DEFAULT"
    else
        local n = tonumber(main)
        mtbf = (n and n > 0) and n or "DEFAULT"
    end
    return mtbf
end

local function load_config()
    local file = io.open(CONFIG_PATH, "r")
    if not file then return end

    cfg.mode         = "ON"
    cfg.default_mtbf = 10000
    cfg.profiles     = {}
    local section    = nil

    for line in file:lines() do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" and not line:match("^#") and not line:match("^%-%-") then
            local hdr = line:match("^%[([%w_]+)%]$")
            if hdr then
                section = hdr:upper()
                if not cfg.profiles[section] then
                    cfg.profiles[section] = { icao = {}, failures = {} }
                end
            else
                local key, val = line:match("^([%w_]+)%s*=%s*(.+)$")
                if key and val then
                    key = key:upper()
                    val = val:match("^%s*(.-)%s*$")
                    if not section then
                        if key == "MODE" then
                            local n = tonumber(val)
                            cfg.mode = n and n or val:upper()
                        elseif key == "DEFAULT_MTBF" then
                            local n = tonumber(val)
                            cfg.default_mtbf = (n and n > 0) and n or 10000
                        end
                    else
                        if key == "ICAO" then
                            for icao in val:gmatch("[^,%s]+") do
                                table.insert(cfg.profiles[section].icao, icao:upper())
                            end
                        else
                            local mtbf = parse_failure_entry(val)
                            cfg.profiles[section].failures[key] = { mtbf = mtbf }
                        end
                    end
                end
            end
        end
    end
    file:close()
end

local function build_active_profile()
    local icao = ((dr_acf_icao or ""):match("^([^%z]*)") or ""):upper():match("^%s*(.-)%s*$")
    cfg.active_failures = {}
    cfg.active_name     = "DEFAULT"
    local default = cfg.profiles["DEFAULT"]
    if default then
        for k, v in pairs(default.failures) do cfg.active_failures[k] = v end
    end
    local matched = false
    for name, prof in pairs(cfg.profiles) do
        if name ~= "DEFAULT" and not matched then
            for _, pid in ipairs(prof.icao) do
                if pid == icao then
                    for k, v in pairs(prof.failures) do cfg.active_failures[k] = v end
                    cfg.active_name = name
                    matched = true
                    break
                end
            end
        end
    end
end

local function prob_from_mtbf(mtbf_hours, interval_sec)
    return interval_sec / (mtbf_hours * 3600)
end

-- ---- Memory ------------------------------------------------
local MEMORY_PATH    = SCRIPT_DIRECTORY .. "xp12_incidents_v3_memory.txt"
local memory_enabled = false

-- ---- Startup popup -----------------------------------------
local inc_popup_from  = nil
local inc_popup_until = nil
local inc_popup_label = nil
local inc_popup_armed = false

local function inc_trigger_popup(label)
    inc_popup_from  = os.clock()
    inc_popup_until = os.clock() + 5
    inc_popup_label = label
end

-- ---- save_memory -------------------------------------------
save_memory = function()
    if not memory_enabled then return end
    if cfg.active_name == "DEFAULT" then return end

    local sections = {}
    local order    = {}
    local cur      = nil
    local file     = io.open(MEMORY_PATH, "r")
    if file then
        for line in file:lines() do
            local hdr = line:match("^%[([%w_]+)%]$")
            if hdr then
                cur = hdr:upper()
                if cur ~= cfg.active_name then
                    if not sections[cur] then
                        sections[cur] = {}
                        table.insert(order, cur)
                    end
                end
            elseif cur and cur ~= cfg.active_name then
                table.insert(sections[cur], line)
            end
        end
        file:close()
    end

    file = io.open(MEMORY_PATH, "w")
    if not file then return end
    file:write("# xp12_incidents_v3_memory.txt\n# Failure state — auto-generated\n\n")

    file:write("[" .. cfg.active_name .. "]\n")

    -- normal failures
    for _, f in ipairs(failures) do
        if not f.no_memory then
            local v = get_dr(f)
            if v > 0 then
                file:write(f.key .. " = " .. v .. "\n")
            end
        end
    end

    -- smoke culprit
    if smoke_culprit then
        file:write("SMOKE_CULPRIT = " .. smoke_culprit .. "\n")
    end

    -- fuel cap preflight check quantities (engine-off snapshot)
    if fuel_cap_mem_l then
        file:write(string.format("FUEL_CAP_T1 = %.2f\n", fuel_cap_mem_l))
    end
    if fuel_cap_mem_r then
        file:write(string.format("FUEL_CAP_T2 = %.2f\n", fuel_cap_mem_r))
    end
    if fuel_drain_check_done then file:write("FUEL_DRAIN_CHECK = done\n") end
    if fuel_type_pending     then file:write("FUEL_TYPE_PENDING = pending\n") end

    -- fuel leak routine state: 1=left, 2=right, 3=both
    if fuelleak_routine then
        local lv = 0
        if     fuelleak_routine.active_l and fuelleak_routine.active_r then lv = 3
        elseif fuelleak_routine.active_l                               then lv = 1
        elseif fuelleak_routine.active_r                               then lv = 2
        end
        if lv > 0 then
            file:write("FUEL_LEAK = " .. lv .. "\n")
        end
    end

    -- door latch guards (per door, memory-persistent)
    if door_routine then
        if door_routine.latched_1 then file:write("DOOR_1_LATCH = latched\n") end
        if door_routine.latched_2 then file:write("DOOR_2_LATCH = latched\n") end
    end

    file:write("\n")

    for _, name in ipairs(order) do
        file:write("[" .. name .. "]\n")
        for _, ln in ipairs(sections[name]) do file:write(ln .. "\n") end
        file:write("\n")
    end
    file:close()
end

-- ---- load_memory -------------------------------------------
local function load_memory()
    if cfg.active_name == "DEFAULT" then return end
    local file = io.open(MEMORY_PATH, "r")
    if not file then return end
    local in_section = false
    for line in file:lines() do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" and not line:match("^#") then
            local hdr = line:match("^%[([%w_]+)%]$")
            if hdr then
                in_section = (hdr:upper() == cfg.active_name)
            elseif in_section then
                local key, val = line:match("^([%w_]+)%s*=%s*(.+)$")
                if key and val then
                    key = key:upper()
                    val = val:match("^%s*(.-)%s*$")
                    if key == "SMOKE_CULPRIT" then
                        smoke_culprit    = val
                        smoke_prev_bat   = dr_bat_on
                        smoke_prev_avion = dr_avion
                        smoke_prev_gen   = read_gen_on()
                    elseif key == "FUEL_CAP_T1" then
                        fuel_cap_mem_l = tonumber(val)
                    elseif key == "FUEL_CAP_T2" then
                        fuel_cap_mem_r = tonumber(val)
                    elseif key == "FUEL_DRAIN_CHECK" and val == "done" then
                        fuel_drain_check_done = true
                    elseif key == "FUEL_TYPE_PENDING" and val == "pending" then
                        fuel_type_pending = true
                    elseif key == "FUEL_LEAK" and fuelleak_routine then
                        -- restore fuel leak routine (1=L, 2=R, 3=both)
                        local lv = tonumber(val)
                        if lv and lv >= 1 and lv <= 3 then
                            fuelleak_routine.active_l = (lv == 1 or lv == 3)
                            fuelleak_routine.active_r = (lv == 2 or lv == 3)
                            fuelleak_routine.elapsed  = 0
                            fuel_drain_last           = os.clock()
                        end
                    elseif key == "DOOR_1_LATCH" and val == "latched" and door_routine then
                        door_routine.latched_1 = true
                    elseif key == "DOOR_2_LATCH" and val == "latched" and door_routine then
                        door_routine.latched_2 = true
                    else
                        local value = tonumber(val)
                        if value == 6 then
                            for _, f in ipairs(failures) do
                                if f.key == key and not f.no_memory then
                                    local _, flag = get_mtbf(f)
                                    if flag ~= "OFF" then set_dr(f, value) end
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    file:close()
end


-- ---- Fuel cap check evaluation ----------------------------
-- Called after load_memory() and after aircraft change.
-- Compares live fuel with the last engine-off snapshot:
--   live > snapshot + 1 kg  →  refueling detected → check invalid
--   snapshot present, no refueling  →  check still valid
--   no snapshot (first start)  →  save baseline, check invalid
local function fuel_cap_evaluate_check()
    local live_l = read_fuel_l()
    local live_r = read_fuel_r()
    if fuel_cap_mem_l == nil or fuel_cap_mem_r == nil then
        -- first start: no snapshot yet — save current as baseline
        fuel_cap_check_done = false
        fuel_cap_mem_l = live_l
        fuel_cap_mem_r = live_r
        save_memory()
    elseif (live_l and live_l > fuel_cap_mem_l + 1.0)
        or (live_r and live_r > fuel_cap_mem_r + 1.0) then
        -- refueling detected: invalidate check, update snapshot
        fuel_cap_check_done = false
        fuel_cap_mem_l = live_l
        fuel_cap_mem_r = live_r
        save_memory()
    else
        -- no refueling since last engine-off: check remains valid
        fuel_cap_check_done = true
    end
end


-- ============================================================
--  [2] FUEL ROUTINES
--  Custom drain simulation for FUEL_CAP and FUEL_LEAK.
--  Neither routine sets the failure DataRef to 6.
--  FUEL_CAP: no memory, airborne only, one side, high→low rate.
--  FUEL_LEAK: memory-persistent, random side(s), low→high rate.
-- ============================================================

local FUEL_STOP_KG = 0.5   -- both routines stop draining at this level

-- State tables (forward-declared in [1])
fuelcap_routine = {
    active  = false,
    side    = nil,    -- "L" or "R"
    elapsed = 0,      -- seconds since activation
}

fuelleak_routine = {
    active_l = false,
    active_r = false,
    elapsed  = 0,
}

-- ---- Rate functions ----------------------------------------
-- Cap: starts at 1.0 kg/s, asymptotically decreases
-- t=0: 1.0  t=60s: 0.50  t=120s: 0.33  t=300s: 0.17  t=600s: 0.09
local function fuelcap_rate(elapsed)
    return math.max(0.05, 1.0 / (1 + elapsed / 60))
end

-- Leak: starts at 0.1 kg/s, increases linearly, capped at 1.0
-- t=0: 0.10  t=120s: 0.20  t=300s: 0.35  t=600s: 0.60  t=1080s: 1.00
local function fuelleak_rate(elapsed)
    return math.min(1.0, 0.1 * (1 + elapsed / 120))
end

-- ---- Start / stop helpers ----------------------------------
local function start_fuel_cap(side)
    -- no airborne guard here: automatic path uses condition_ok(); manual always fires
    fuelcap_routine.active  = true
    fuelcap_routine.side    = side
    fuelcap_routine.elapsed = 0
    fuel_drain_last         = os.clock()
end

local function stop_fuel_cap()
    fuelcap_routine.active  = false
    fuelcap_routine.elapsed = 0
end

local function start_fuel_leak(active_l, active_r)
    fuelleak_routine.active_l = active_l
    fuelleak_routine.active_r = active_r
    fuelleak_routine.elapsed  = 0
    fuel_drain_last           = os.clock()
    save_memory()
end

local function stop_fuel_leak()
    fuelleak_routine.active_l = false
    fuelleak_routine.active_r = false
    fuelleak_routine.elapsed  = 0
    save_memory()
end

-- ---- Fuel drain tick ---------------------------------------
-- Runs do_often (~10×/s). Both routines share the same dt calculation.
function incidents_fuel_tick()
    local any = fuelcap_routine.active
                or fuelleak_routine.active_l or fuelleak_routine.active_r
    if not any then return end

    local now = os.clock()
    local dt  = math.min(now - fuel_drain_last, 0.5)
    fuel_drain_last = now

    -- Fuel Cap routine
    if fuelcap_routine.active then
        fuelcap_routine.elapsed = fuelcap_routine.elapsed + dt
        local drain = fuelcap_rate(fuelcap_routine.elapsed) * dt
        if fuelcap_routine.side == "L" then
            local cur = read_fuel_l()
            if cur then
                if cur <= FUEL_STOP_KG then
                    stop_fuel_cap()
                else
                    write_fuel_l(math.max(FUEL_STOP_KG, cur - drain))
                end
            end
        else
            local cur = read_fuel_r()
            if cur then
                if cur <= FUEL_STOP_KG then
                    stop_fuel_cap()
                else
                    write_fuel_r(math.max(FUEL_STOP_KG, cur - drain))
                end
            end
        end
    end

    -- Fuel Leak routine
    if fuelleak_routine.active_l or fuelleak_routine.active_r then
        fuelleak_routine.elapsed = fuelleak_routine.elapsed + dt
        local drain = fuelleak_rate(fuelleak_routine.elapsed) * dt

        if fuelleak_routine.active_l then
            local cur = read_fuel_l()
            if cur then
                if cur <= FUEL_STOP_KG then
                    fuelleak_routine.active_l = false
                else
                    write_fuel_l(math.max(FUEL_STOP_KG, cur - drain))
                end
            end
        end
        if fuelleak_routine.active_r then
            local cur = read_fuel_r()
            if cur then
                if cur <= FUEL_STOP_KG then
                    fuelleak_routine.active_r = false
                else
                    write_fuel_r(math.max(FUEL_STOP_KG, cur - drain))
                end
            end
        end

        -- both sides drained to stop → clear memory
        if not fuelleak_routine.active_l and not fuelleak_routine.active_r then
            save_memory()
        end
    end
end

do_often("incidents_fuel_tick()")


-- ============================================================
--  [2b] DOOR ROUTINES
--  DOOR_OPEN (rel_door_open) intercepts to a dice roll — no DataRef=6.
--  DOOR_1 / DOOR_2: virtual failures; open sim door DataRef index 0/1.
--  Latch guard per door: open+close on ground+engine-off → latched.
--  Guard clears automatically when door opens (any cause).
--  Memory: DOOR_1_LATCH / DOOR_2_LATCH (per profile).
-- ============================================================

door_routine = {
    open_1    = false,   -- door 1 (pilot)    physically open
    open_2    = false,   -- door 2 (copilot)  physically open
    fail_1    = false,   -- door 1 opened by failure system → shows in status
    fail_2    = false,   -- door 2 opened by failure system → shows in status
    latched_1 = false,   -- latch guard set for door 1
    latched_2 = false,   -- latch guard set for door 2
    prev_1    = 0,       -- last seen door_open[0] for transition detection
    prev_2    = 0,
}

-- Returns true when the given door number is not set to OFF in config.
local function door_available(num)
    local f = find_failure(num == 1 and "DOOR_1" or "DOOR_2")
    if not f then return false end
    local _, flag = get_mtbf(f)
    return flag ~= "OFF"
end

local function start_door_open(num)
    write_door(num, 1)
    if num == 1 then
        door_routine.open_1    = true
        door_routine.fail_1    = true
        door_routine.latched_1 = false
        door_routine.prev_1    = 1   -- keep tick in sync, avoid double save_memory
    else
        door_routine.open_2    = true
        door_routine.fail_2    = true
        door_routine.latched_2 = false
        door_routine.prev_2    = 1
    end
    set_dr(find_failure("DOOR_OPEN"), 6)
    save_memory()
end

local function stop_door_open(num)
    write_door(num, 0)
    if num == 1 then
        door_routine.open_1    = false
        door_routine.fail_1    = false
        door_routine.latched_1 = true
    else
        door_routine.open_2    = false
        door_routine.fail_2    = false
        door_routine.latched_2 = true
    end
    if not door_routine.fail_1 and not door_routine.fail_2 then
        set_dr(find_failure("DOOR_OPEN"), 0)
    end
    inc_trigger_popup("DOOR " .. num .. " LATCHED")
    save_memory()
end


-- Dice roll among ALL available (non-open) doors; latch check after selection.
-- If the selected door is latched: nothing opens, nothing shows in status.
local function door_trigger_unlatched()
    local avail = {}
    if door_available(1) and not door_routine.open_1 then table.insert(avail, 1) end
    if door_available(2) and not door_routine.open_2 then table.insert(avail, 2) end
    if #avail == 0 then return end
    local n = avail[math.random(#avail)]
    if (n == 1 and door_routine.latched_1) or (n == 2 and door_routine.latched_2) then return end
    start_door_open(n)
end

local function door_has_unlatched()
    if door_available(1) and not door_routine.latched_1 and not door_routine.open_1 then return true end
    if door_available(2) and not door_routine.latched_2 and not door_routine.open_2 then return true end
    return false
end

-- ---- Door state monitoring tick ----------------------------
-- Detects door opens/closes via sim DataRef transitions.
-- Close on ground + engine off → sets latch guard automatically.
function incidents_door_tick()
    local cur_1 = read_door(1)
    local cur_2 = read_door(2)

    if cur_1 ~= door_routine.prev_1 then
        if cur_1 == 1 then
            door_routine.latched_1 = false
            door_routine.open_1    = true
            save_memory()
        elseif door_routine.open_1 then
            door_routine.open_1    = false
            door_routine.fail_1    = false
            door_routine.latched_1 = true
            if not door_routine.fail_2 then set_dr(find_failure("DOOR_OPEN"), 0) end
            inc_trigger_popup("DOOR 1 LATCHED")
            save_memory()
        end
        door_routine.prev_1 = cur_1
    end

    if cur_2 ~= door_routine.prev_2 then
        if cur_2 == 1 then
            door_routine.latched_2 = false
            door_routine.open_2    = true
            save_memory()
        elseif door_routine.open_2 then
            door_routine.open_2    = false
            door_routine.fail_2    = false
            door_routine.latched_2 = true
            if not door_routine.fail_1 then set_dr(find_failure("DOOR_OPEN"), 0) end
            inc_trigger_popup("DOOR 2 LATCHED")
            save_memory()
        end
        door_routine.prev_2 = cur_2
    end
end

do_often("incidents_door_tick()")


-- ============================================================
--  [3] FAILURES
-- ============================================================

local TICK_INTERVAL = 10
local tick_last     = 0

failures = {}

local function def(key, dr_path, label, condition, no_memory, fix, on_trigger)
    table.insert(failures, {
        key           = key,
        dr            = dr_path,
        label         = label,
        condition     = condition,
        no_memory     = no_memory,
        fix           = fix,
        on_trigger    = on_trigger,
        _ref          = nil,
        _fix_cond     = nil,
        _fire_induced = nil,
    })
end

-- ---- ENVIRONMENT -------------------------------------------
def("VASI",        "sim/operation/failures/rel_vasi",             "VASI",        nil,        true)
def("RWY_LIGHTS",  "sim/operation/failures/rel_rwy_lites",        "Rwy Lights",  nil,        true)
def("SMOKE",       "sim/operation/failures/rel_smoke_cpit",       "Smoke",       "engine_or_elec", true,
    { cond = smoke_fixable, on_fix = smoke_on_fix })
def("BIRD_ENG1",   "sim/operation/failures/rel_bird_strike_eng1", "Bird/Eng1",   "airborne", true)
def("BIRD_ENG2",   "sim/operation/failures/rel_bird_strike_eng2", "Bird/Eng2",   "airborne", true)
def("DOOR_OPEN",   "sim/operation/failures/rel_door_open",  "Door",       nil,       true)
-- DOOR_1 / DOOR_2: virtual failures (dr=nil) — no XP failure DataRef.
-- Trigger opens the physical door DataRef; latch guard in door_routine.
-- no_memory=true: door-open state read from sim at startup; latch saved separately.
def("DOOR_1",      nil,                                     "Door 1",     nil,       true)
def("DOOR_2",      nil,                                     "Door 2",     nil,       true)
-- FUEL_CAP: no DataRef=6 — custom drain routine handles it.
-- no_memory=true; airborne condition + fuel_cap_check_done guard enforced when conditions_enforced=true.
def("FUEL_CAP",    "sim/operation/failures/rel_fuelcap",    "Fuel Cap",  "airborne",  true)
def("FUEL_WATER",  "sim/operation/failures/rel_fuel_water", "Fuel Water", "ground_engine_off", true)
def("FUEL_TYPE",   "sim/operation/failures/rel_fuel_type",  "Fuel Type",  "ground", true)

-- ---- ENGINES -----------------------------------------------
def("ENG_FAIL_1",     "sim/operation/failures/rel_engfai0",          "Eng Fail 1",   "engine")
def("ENG_FAIL_2",     "sim/operation/failures/rel_engfai1",          "Eng Fail 2",   "engine")
def("ENG_FIRE_1",     "sim/operation/failures/rel_engfir0",          "Eng Fire 1",   "engine", nil, nil,
    { followup = { { key="SMOKE", prob=0.75, fix_source="ENG_FIRE_1" } } })
def("ENG_FIRE_2",     "sim/operation/failures/rel_engfir1",          "Eng Fire 2",   "engine", nil, nil,
    { followup = { { key="SMOKE", prob=0.75, fix_source="ENG_FIRE_2" } } })
def("STARTER_1",      "sim/operation/failures/rel_startr0",          "Starter 1",    nil)
def("STARTER_2",      "sim/operation/failures/rel_startr1",          "Starter 2",    nil)
def("MAG_L1",         "sim/operation/failures/rel_magLFT0",          "Mag L Eng1",   nil)
def("MAG_L2",         "sim/operation/failures/rel_magLFT1",          "Mag L Eng2",   nil)
def("MAG_R1",         "sim/operation/failures/rel_magRGT0",          "Mag R Eng1",   nil)
def("MAG_R2",         "sim/operation/failures/rel_magRGT1",          "Mag R Eng2",   nil)
def("FUEL_PUMP_LO_1", "sim/operation/failures/rel_lo_press_fuepmp0", "FuelPmpLo 1",  nil)
def("FUEL_PUMP_LO_2", "sim/operation/failures/rel_lo_press_fuepmp1", "FuelPmpLo 2",  nil)
def("FUEL_PUMP_1",    "sim/operation/failures/rel_fuepmp0",          "Fuel Pump 1",  nil)
def("FUEL_PUMP_2",    "sim/operation/failures/rel_fuepmp1",          "Fuel Pump 2",  nil)
def("ELE_FUEL_PMP_1", "sim/operation/failures/rel_ele_fuepmp0",      "EleFuelPmp 1", nil)
def("ELE_FUEL_PMP_2", "sim/operation/failures/rel_ele_fuepmp1",      "EleFuelPmp 2", nil)
def("FUEL_FLOW_1",    "sim/operation/failures/rel_fuelfl0",          "Fuel Flow 1",  nil)
def("FUEL_FLOW_2",    "sim/operation/failures/rel_fuelfl1",          "Fuel Flow 2",  nil)
def("FUEL_BLOCK_1",   "sim/operation/failures/rel_fuel_block0",      "Fuel Blk 1",   nil)
def("FUEL_BLOCK_2",   "sim/operation/failures/rel_fuel_block1",      "Fuel Blk 2",   nil)
def("FUEL_LEAK",   "sim/operation/failures/rel_fuel_leak",  "Fuel Leak", "engine")
def("OIL_PUMP_1",     "sim/operation/failures/rel_oilpmp0",          "Oil Pump 1",   nil)
def("OIL_PUMP_2",     "sim/operation/failures/rel_oilpmp1",          "Oil Pump 2",   nil)
def("OIL_PRESS_LO_1", "sim/operation/failures/rel_eng_lo0",          "OilPressLo 1", nil)
def("OIL_PRESS_LO_2", "sim/operation/failures/rel_eng_lo1",          "OilPressLo 2", nil)
def("AIRFLOW_ENG1",   "sim/operation/failures/rel_airres0",          "Airflow Eng1", nil)
def("AIRFLOW_ENG2",   "sim/operation/failures/rel_airres1",          "Airflow Eng2", nil)

-- ---- PROPELLERS --------------------------------------------
def("PROP_FINE_1",    "sim/operation/failures/rel_prpfin0",          "Prop Fine 1",  nil)
def("PROP_FINE_2",    "sim/operation/failures/rel_prpfin1",          "Prop Fine 2",  nil)
def("PROP_COARSE_1",  "sim/operation/failures/rel_prpcrs0",          "PropCoarse 1", nil)
def("PROP_COARSE_2",  "sim/operation/failures/rel_prpcrs1",          "PropCoarse 2", nil)

-- ---- ELECTRICAL --------------------------------------------
def("ELEC_BUS1",      "sim/operation/failures/rel_esys",             "Elec Bus 1",   nil)
def("ELEC_BUS2",      "sim/operation/failures/rel_esys2",            "Elec Bus 2",   nil)
def("GENERATOR_1",    "sim/operation/failures/rel_genera0",          "Generator 1",  nil)
def("GENERATOR_2",    "sim/operation/failures/rel_genera1",          "Generator 2",  nil)
def("BATTERY_1",      "sim/operation/failures/rel_batter0",          "Battery 1",    nil)
def("BATTERY_2",      "sim/operation/failures/rel_batter1",          "Battery 2",    nil)
def("GEN0_LO",        "sim/operation/failures/rel_gen0_lo",          "Gen0 V Low",   nil)
def("GEN0_HI",        "sim/operation/failures/rel_gen0_hi",          "Gen0 V High",  nil)
def("GEN1_LO",        "sim/operation/failures/rel_gen1_lo",          "Gen1 V Low",   nil)
def("GEN1_HI",        "sim/operation/failures/rel_gen1_hi",          "Gen1 V High",  nil)
def("BAT0_LO",        "sim/operation/failures/rel_bat0_lo",          "Bat0 V Low",   nil)
def("BAT0_HI",        "sim/operation/failures/rel_bat0_hi",          "Bat0 V High",  nil)
def("BAT1_LO",        "sim/operation/failures/rel_bat1_lo",          "Bat1 V Low",   nil)
def("BAT1_HI",        "sim/operation/failures/rel_bat1_hi",          "Bat1 V High",  nil)

-- ---- LIGHTS ------------------------------------------------
def("LITES_BEACON",   "sim/operation/failures/rel_lites_beac",       "Beacon",       nil)
def("LITES_NAV",      "sim/operation/failures/rel_lites_nav",        "Nav Lights",   nil)
def("LITES_TAXI",     "sim/operation/failures/rel_lites_taxi",       "Taxi Light",   nil)
def("LITES_STROBE",   "sim/operation/failures/rel_lites_strobe",     "Strobes",      nil)
def("LITES_LANDING",  "sim/operation/failures/rel_lites_land",       "Ldg Lights",   nil)
def("LITES_INST",     "sim/operation/failures/rel_lites_ins",        "Inst Lights",  nil)
def("LITES_COCKPIT",  "sim/operation/failures/rel_clights",          "Cpit Lights",  nil)

-- ---- AUTOPILOT ---------------------------------------------
def("AP_COMPUTER",    "sim/operation/failures/rel_otto",             "AP Computer",  nil)
def("AP_RUNAWAY",     "sim/operation/failures/rel_auto_runaway",     "AP Runaway",   nil)
def("AP_SERVOS",      "sim/operation/failures/rel_auto_servos",      "AP Servos",    nil)
def("AP_SERVO_ELEV",  "sim/operation/failures/rel_servo_elev",       "AP Srv Elev",  nil)
def("AP_SERVO_AILN",  "sim/operation/failures/rel_servo_ailn",       "AP Srv Ailn",  nil)
def("AP_SERVO_RUDD",  "sim/operation/failures/rel_servo_rudd",       "AP Srv Rudd",  nil)

-- ---- SYSTEMS -----------------------------------------------
def("PITOT_HEAT_1",   "sim/operation/failures/rel_ice_pitot_heat1",  "Pitot Heat 1", nil)
def("PITOT_HEAT_2",   "sim/operation/failures/rel_ice_pitot_heat2",  "Pitot Heat 2", nil)
def("AOA_HEAT",       "sim/operation/failures/rel_ice_AOA_heat",     "AOA Heat",     nil)
def("WINDOW_HEAT",    "sim/operation/failures/rel_ice_window_heat",  "Window Heat",  nil)
def("PROP_HEAT_1",    "sim/operation/failures/rel_ice_prop_heat",    "Prop Heat 1",  nil)
def("PROP_HEAT_2",    "sim/operation/failures/rel_ice_prop_heat2",   "Prop Heat 2",  nil)
def("TKS_PUMP",       "sim/operation/failures/rel_dice_tks_pump_0",  "TKS Pump",     nil)
def("HVAC",           "sim/operation/failures/rel_HVAC",             "HVAC",         nil)
def("VACUUM_1",       "sim/operation/failures/rel_vacuum",           "Vacuum 1",     nil)
def("VACUUM_2",       "sim/operation/failures/rel_vacuum2",          "Vacuum 2",     nil)

-- ---- INSTRUMENTS -------------------------------------------
def("ASI_PILOT",      "sim/operation/failures/rel_ss_asi",           "ASI Pilot",    nil)
def("AHZ_PILOT",      "sim/operation/failures/rel_ss_ahz",           "AHZ Pilot",    nil)
def("ALT_PILOT",      "sim/operation/failures/rel_ss_alt",           "ALT Pilot",    nil)
def("TSI_PILOT",      "sim/operation/failures/rel_ss_tsi",           "Turn Ind",     nil)
def("DGY_PILOT",      "sim/operation/failures/rel_ss_dgy",           "Dir Gyro",     nil)
def("VVI_PILOT",      "sim/operation/failures/rel_ss_vvi",           "VVI Pilot",    nil)
def("ALT_COPILOT",    "sim/operation/failures/rel_cop_alt",          "ALT Copilot",  nil)
def("AHZ_COPILOT",    "sim/operation/failures/rel_cop_ahz",          "AHZ Copilot",  nil)
def("G430_GPS1",      "sim/operation/failures/rel_g430_gps1",        "G430 GPS 1",   nil)
def("G430_GPS2",      "sim/operation/failures/rel_g430_gps2",        "G430 GPS 2",   nil)
def("G430_NAV1",      "sim/operation/failures/rel_g430_rad1_tune",   "G430 Nav 1",   nil)
def("G430_NAV2",      "sim/operation/failures/rel_g430_rad2_tune",   "G430 Nav 2",   nil)
def("G_ASI",          "sim/operation/failures/rel_g_asi",            "G-ASI",        nil)
def("G_ALT",          "sim/operation/failures/rel_g_alt",            "G-ALT",        nil)
def("G_VVI",          "sim/operation/failures/rel_g_vvi",            "G-VVI",        nil)
def("G_PFD",          "sim/operation/failures/rel_g_pfd",            "PFD",          nil)
def("G_MFD",          "sim/operation/failures/rel_g_mfd",            "MFD",          nil)
def("G_GIA1",         "sim/operation/failures/rel_g_gia1",           "GIA 1",        nil)
def("G_GIA2",         "sim/operation/failures/rel_g_gia2",           "GIA 2",        nil)
def("G_GEA",          "sim/operation/failures/rel_g_gea",            "GEA",          nil)
def("MAGNETOMETER",   "sim/operation/failures/rel_g_magmtr",         "Magnetomtr",   nil)
def("WXR_RADAR",      "sim/operation/failures/rel_wxr_radar",        "WX Radar",     nil)
def("NAVCOM1",        "sim/operation/failures/rel_navcom1",           "NavCom 1",     nil)
def("NAVCOM2",        "sim/operation/failures/rel_navcom2",           "NavCom 2",     nil)
def("ADF1",           "sim/operation/failures/rel_adf1",             "ADF 1",        nil)
def("DME",            "sim/operation/failures/rel_dme",              "DME",          nil)
def("XPNDR",          "sim/operation/failures/rel_xpndr",            "Transponder",  nil)
def("MARKER",         "sim/operation/failures/rel_marker",           "Markers",      nil)
def("RPM_IND_1",      "sim/operation/failures/rel_RPM_ind_0",        "RPM Ind 1",    nil)
def("RPM_IND_2",      "sim/operation/failures/rel_RPM_ind_1",        "RPM Ind 2",    nil)
def("MP_IND_1",       "sim/operation/failures/rel_MP_ind_0",         "MP Ind 1",     nil)
def("MP_IND_2",       "sim/operation/failures/rel_MP_ind_1",         "MP Ind 2",     nil)
def("CHT_IND_1",      "sim/operation/failures/rel_CHT_ind_0",        "CHT Ind 1",    nil)
def("CHT_IND_2",      "sim/operation/failures/rel_CHT_ind_1",        "CHT Ind 2",    nil)
def("EGT_IND_1",      "sim/operation/failures/rel_EGT_ind_0",        "EGT Ind 1",    nil)
def("EGT_IND_2",      "sim/operation/failures/rel_EGT_ind_1",        "EGT Ind 2",    nil)
def("FF_IND_1",       "sim/operation/failures/rel_FF_ind0",          "FF Ind 1",     nil)
def("FF_IND_2",       "sim/operation/failures/rel_FF_ind1",          "FF Ind 2",     nil)
def("FUEL_P_IND_1",   "sim/operation/failures/rel_fp_ind_0",         "FuelP Ind 1",  nil)
def("FUEL_P_IND_2",   "sim/operation/failures/rel_fp_ind_1",         "FuelP Ind 2",  nil)
def("OIL_P_IND_1",    "sim/operation/failures/rel_oilp_ind_0",       "OilP Ind 1",   nil)
def("OIL_P_IND_2",    "sim/operation/failures/rel_oilp_ind_1",       "OilP Ind 2",   nil)
def("OIL_T_IND_1",    "sim/operation/failures/rel_oilt_ind_0",       "OilT Ind 1",   nil)
def("OIL_T_IND_2",    "sim/operation/failures/rel_oilt_ind_1",       "OilT Ind 2",   nil)
def("STALL_WARN",     "sim/operation/failures/rel_stall_warn",       "Stall Warn",   nil)
def("GEAR_WARN",      "sim/operation/failures/rel_gear_warning",     "Gear Warn",    nil)

-- ---- SENSORS / ANTENNAS  -----------------------------------------------
def("PITOT",          "sim/operation/failures/rel_pitot",            "Pitot",        nil)
def("PITOT_2",        "sim/operation/failures/rel_pitot2",           "Pitot 2",      nil)
def("PITOT_STBY",     "sim/operation/failures/rel_pitot_stby",       "Pitot Stby",   nil)
def("STATIC",         "sim/operation/failures/rel_static",           "Static",       nil)
def("STATIC_2",       "sim/operation/failures/rel_static2",          "Static 2",     nil)
def("STATIC_ERR_1",   "sim/operation/failures/rel_static1_err",      "Static Err 1", nil)
def("STATIC_ERR_2",   "sim/operation/failures/rel_static2_err",      "Static Err 2", nil)
def("STATIC_STBY",    "sim/operation/failures/rel_static_stby",      "Static Stby",  nil)
def("OAT",            "sim/operation/failures/rel_g_oat",            "OAT",          nil)
def("ICE_DETECT",     "sim/operation/failures/rel_ice_detect",       "Ice Detect",   nil)
def("FUEL_QTY",       "sim/operation/failures/rel_g_fuel",           "Fuel Qty",     nil)
def("LOC",            "sim/operation/failures/rel_loc",              "LOC",          nil)
def("GLS",            "sim/operation/failures/rel_gls",              "Glide Slope",  nil)
def("GPS",            "sim/operation/failures/rel_gps",              "GPS",          nil)

-- ---- GEAR --------------------------------------------------
def("GEAR_IND",       "sim/operation/failures/rel_gear_ind",         "Gear Ind",     nil)
def("GEAR_ACT",       "sim/operation/failures/rel_gear_act",         "Gear Act",     nil)
def("GEAR_RET_1",     "sim/operation/failures/rel_lagear1",          "Gear Ret 1",   nil)
def("GEAR_RET_2",     "sim/operation/failures/rel_lagear2",          "Gear Ret 2",   nil)
def("GEAR_RET_3",     "sim/operation/failures/rel_lagear3",          "Gear Ret 3",   nil)
def("GEAR_COL_1",     "sim/operation/failures/rel_collapse1",        "Gear Col 1",   "ground")
def("GEAR_COL_2",     "sim/operation/failures/rel_collapse2",        "Gear Col 2",   "ground")
def("GEAR_COL_3",     "sim/operation/failures/rel_collapse3",        "Gear Col 3",   "ground")
def("TIRE_1",         "sim/operation/failures/rel_tire1",            "Tire 1",       nil)
def("TIRE_2",         "sim/operation/failures/rel_tire2",            "Tire 2",       nil)
def("TIRE_3",         "sim/operation/failures/rel_tire3",            "Tire 3",       nil)
def("TIRE_4",         "sim/operation/failures/rel_tire4",            "Tire 4",       nil)
def("TIRE_5",         "sim/operation/failures/rel_tire5",            "Tire 5",       nil)
def("BRAKES_L",       "sim/operation/failures/rel_lbrakes",          "Brakes L",     nil)
def("BRAKES_R",       "sim/operation/failures/rel_rbrakes",          "Brakes R",     nil)

-- ---- CONTROLS ----------------------------------------------
def("FLAP_ACT",       "sim/operation/failures/rel_flap_act",         "Flap Act",     nil)
def("FLAP_ACT_L",     "sim/operation/failures/rel_fc_L_flp",         "Flap Act L",   nil)
def("FLAP_ACT_R",     "sim/operation/failures/rel_fc_R_flp",         "Flap Act R",   nil)
def("ELV_TRIM_RUN",   "sim/operation/failures/rel_elv_trim_run",     "Elv Trim Run", nil, nil,
    { cond = trim_fixable, followup = { "TRIM_ELV", "TRIM_AIL", "TRIM_RUD" } })
def("AIL_TRIM_RUN",   "sim/operation/failures/rel_ail_trim_run",     "Ail Trim Run", nil, nil,
    { cond = trim_fixable, followup = { "TRIM_ELV", "TRIM_AIL", "TRIM_RUD" } })
def("RUD_TRIM_RUN",   "sim/operation/failures/rel_rud_trim_run",     "Rud Trim Run", nil, nil,
    { cond = trim_fixable, followup = { "TRIM_ELV", "TRIM_AIL", "TRIM_RUD" } })
def("TRIM_ELV",       "sim/operation/failures/rel_trim_elv",         "Trim Elv",     nil)
def("TRIM_AIL",       "sim/operation/failures/rel_trim_ail",         "Trim Ail",     nil)
def("TRIM_RUD",       "sim/operation/failures/rel_trim_rud",         "Trim Rud",     nil)

-- ---- DataRef handles ---------------------------------------
local function init_refs()
    for _, f in ipairs(failures) do
        if f.dr then f._ref = XPLMFindDataRef(f.dr) end
    end
end

get_dr = function(f)
    if not f._ref then return 0 end
    return XPLMGetDatai(f._ref)
end

set_dr = function(f, value)
    if not f._ref then return end
    XPLMSetDatai(f._ref, value)
end

-- ---- Condition check ---------------------------------------
local function ground_roll()
    if not _ref_on_ground then return false end
    if not _ref_gspeed then return XPLMGetDatai(_ref_on_ground) ~= 0 end
    return XPLMGetDatai(_ref_on_ground) ~= 0 and XPLMGetDataf(_ref_gspeed) > 15.0
end

local function condition_ok(f)
    if     f.condition == "airborne"         then return airborne()
    elseif f.condition == "engine"           then return engine_on()
    elseif f.condition == "engine_or_elec"   then return engine_on() or electrical_on()
    elseif f.condition == "ground"           then return not airborne()
    elseif f.condition == "ground_roll"      then return ground_roll()
    elseif f.condition == "ground_engine_off" then return not airborne() and not engine_on()
    end
    return true
end

-- ---- Config lookup -----------------------------------------
get_mtbf = function(f)
    local fc = cfg.active_failures[f.key]
    if not fc then return cfg.default_mtbf, nil end
    if fc.mtbf == "OFF"     then return nil, "OFF" end
    if fc.mtbf == "ON"      then return nil, "ON"  end
    if fc.mtbf == "DEFAULT" then return cfg.default_mtbf, nil end
    return fc.mtbf, nil
end

-- ---- find_failure ------------------------------------------
find_failure = function(key)
    for _, f in ipairs(failures) do
        if f.key == key then return f end
    end
end

-- ---- Active state check (includes fuel and door routines) -
-- Use instead of get_dr(f) > 0 wherever custom routines need to be
-- excluded from re-triggering while already running.
local function failure_is_active(f)
    if f.key == "FUEL_CAP"  then return fuelcap_routine.active end
    if f.key == "FUEL_LEAK" then return fuelleak_routine.active_l or fuelleak_routine.active_r end
    if f.key == "DOOR_OPEN" then return door_routine.fail_1 or door_routine.fail_2 end
    if f.key == "DOOR_1"    then return door_routine.fail_1 end
    if f.key == "DOOR_2"    then return door_routine.fail_2 end
    return get_dr(f) > 0
end

-- ---- Trigger failure ---------------------------------------
local function trigger_failure(f)
    -- FUEL_CAP: start custom drain routine instead of setting DataRef=6
    if f.key == "FUEL_CAP" then
        start_fuel_cap(math.random() < 0.5 and "L" or "R")
        return
    end
    -- FUEL_LEAK: random side determination, then custom drain routine
    -- 40% left only / 40% right only / 20% both (engine position)
    if f.key == "FUEL_LEAK" then
        local r = math.random()
        local al, ar
        if     r < 0.4 then al, ar = true,  false
        elseif r < 0.8 then al, ar = false, true
        else                al, ar = true,  true
        end
        start_fuel_leak(al, ar)
        return
    end
    -- DOOR_OPEN: dice roll among all available doors; latch checked after selection
    if f.key == "DOOR_OPEN" then
        door_trigger_unlatched()
        return
    end
    -- DOOR_1 / DOOR_2: respects latch guard — latched door cannot be opened manually
    if f.key == "DOOR_1" then if door_routine.latched_1 then return end; start_door_open(1); return end
    if f.key == "DOOR_2" then if door_routine.latched_2 then return end; start_door_open(2); return end
    set_dr(f, 6)
    save_memory()
    -- cascade followup (e.g. engine fire → smoke)
    if f.on_trigger and f.on_trigger.followup then
        for _, entry in ipairs(f.on_trigger.followup) do
            local key2 = type(entry) == "table" and entry.key  or entry
            local prob  = type(entry) == "table" and (entry.prob or 1.0) or 1.0
            if math.random() < prob
               and not (key2 == "SMOKE" and dr_acf_icao == "BE58") then
                local f2 = find_failure(key2)
                if f2 and get_dr(f2) ~= 6 then
                    if type(entry) == "table" and entry.fix_source then
                        local src = find_failure(entry.fix_source)
                        if src then
                            f2._fix_cond     = function() return get_dr(src) ~= 6 end
                            f2._fire_induced = true
                        end
                    end
                    trigger_failure(f2)
                end
            end
        end
    end
end

-- ---- Reset failure -----------------------------------------
local function reset_failure(f)
    -- FUEL_CAP: stop custom routine (no memory involved)
    if f.key == "FUEL_CAP" then
        stop_fuel_cap()
        return
    end
    -- FUEL_LEAK: stop custom routine and clear memory
    if f.key == "FUEL_LEAK" then
        stop_fuel_leak()
        return
    end
    -- DOOR_OPEN: close open doors; always clear fail flags + DataRef (door may have closed externally)
    if f.key == "DOOR_OPEN" then
        if door_routine.open_1 then stop_door_open(1) end
        if door_routine.open_2 then stop_door_open(2) end
        door_routine.fail_1 = false
        door_routine.fail_2 = false
        set_dr(f, 0)
        return
    end
    if f.key == "DOOR_1" then
        if door_routine.open_1 then stop_door_open(1) end
        door_routine.fail_1 = false
        if not door_routine.fail_2 then set_dr(find_failure("DOOR_OPEN"), 0) end
        return
    end
    if f.key == "DOOR_2" then
        if door_routine.open_2 then stop_door_open(2) end
        door_routine.fail_2 = false
        if not door_routine.fail_1 then set_dr(find_failure("DOOR_OPEN"), 0) end
        return
    end
    if get_dr(f) > 0 then
        set_dr(f, 0)
        save_memory()
    end
end

-- ---- Runtime toggle ----------------------------------------
local system_paused = false

-- ---- RANDOM mode -------------------------------------------
local rnd_scheduled = false
local rnd_fired     = false
local rnd_target    = nil
local rnd_fire_at   = 0
local rnd_pause_at  = nil

local function schedule_random()
    if type(cfg.mode) ~= "number" then return end
    local eligible = {}
    for _, f in ipairs(failures) do
        local _, flag = get_mtbf(f)
        if flag ~= "OFF" and not failure_is_active(f)
           and not (f.key == "FUEL_CAP"   and fuel_cap_check_done)
           and not (f.key == "FUEL_WATER" and fuel_drain_check_done)
           and not (f.key == "FUEL_TYPE"  and not fuel_type_pending)
           and not (f.key == "DOOR_OPEN"  and not door_has_unlatched())
           and not (f.key == "DOOR_1"     and door_routine.latched_1)
           and not (f.key == "DOOR_2"     and door_routine.latched_2) then
            table.insert(eligible, f)
        end
    end
    if #eligible == 0 then return end
    rnd_target    = eligible[math.random(#eligible)]
    local window  = math.max(0, math.floor(cfg.mode * 60))
    rnd_fire_at   = os.clock() + (window > 0 and math.random(0, window) or 0)
    rnd_fired     = false
    rnd_scheduled = true
end


-- ============================================================
--  [4] COMMANDS
-- ============================================================

function incidents_toggle()
    if system_paused then
        -- resume: shift RANDOM window, reload memory (restores fuel leak if present)
        if rnd_pause_at and rnd_scheduled and not rnd_fired then
            rnd_fire_at = rnd_fire_at + (os.clock() - rnd_pause_at)
        end
        rnd_pause_at  = nil
        system_paused = false
        load_memory()
    else
        -- pause: stop all failures and fuel routines; memory file is NOT touched
        -- (fuel leak entry persists in memory, resume via load_memory restores it)
        rnd_pause_at = os.clock()
        local was = memory_enabled
        memory_enabled = false
        for _, f in ipairs(failures) do reset_failure(f) end
        -- fuel cap has no memory → permanently fixed by pause
        -- fuel leak stop already called by reset_failure above;
        -- save_memory was no-op (memory_enabled=false) so file entry is preserved
        memory_enabled = was
        system_paused = true
    end
    inc_trigger_popup(system_paused and "-- PAUSED --" or "-- ACTIVE --")
end

create_command(
    "FlyWithLua/Incidents/toggle_system",
    "Incidents: toggle system ON/OFF",
    "incidents_toggle()", "", ""
)

function incidents_reset_profile()
    local was_enabled = memory_enabled
    memory_enabled = false
    for _, f in ipairs(failures) do reset_failure(f) end
    smoke_culprit = nil
    door_routine.latched_1 = false
    door_routine.latched_2 = false
    memory_enabled = was_enabled
    save_memory()   -- writes empty profile section → clears all routine entries
    rnd_scheduled = false
    rnd_fired     = false
    rnd_target    = nil
    if type(cfg.mode) == "number" then schedule_random() end
    inc_trigger_popup("-- PROFILE RESET --")
end

create_command(
    "FlyWithLua/Incidents/reset_profile",
    "Incidents: reset profile",
    "incidents_reset_profile()", "", ""
)


function incidents_trigger_all()
    -- check fuel and door routine state in addition to DataRef values
    local any_active = fuelcap_routine.active
                       or fuelleak_routine.active_l or fuelleak_routine.active_r
                       or door_routine.open_1 or door_routine.open_2
    for _, f in ipairs(failures) do
        if get_dr(f) > 0 then any_active = true; break end
    end
    local was_enabled = memory_enabled
    memory_enabled = false
    for _, f in ipairs(failures) do
        local _, flag = get_mtbf(f)
        if flag ~= "OFF" then
            if any_active then reset_failure(f) else trigger_failure(f) end
        end
    end
    memory_enabled = was_enabled
    save_memory()
    inc_trigger_popup(any_active and "-- ALL RESET --" or "-- ALL TRIGGERED --")
end

create_command(
    "FlyWithLua/Incidents/trigger_all",
    "Incidents: toggle all failures on/off",
    "incidents_trigger_all()", "", ""
)

function incidents_toggle_status()
    incidents_show_status = not incidents_show_status
end

create_command(
    "FlyWithLua/Incidents/toggle_status",
    "Incidents: toggle status display",
    "incidents_toggle_status()", "", ""
)

function incidents_fuelcap_check()
    fuel_cap_check_done = not fuel_cap_check_done
end

create_command(
    "FlyWithLua/Incidents/fuelcap_check",
    "Incidents: toggle fuel cap preflight check on/off",
    "incidents_fuelcap_check()", "", ""
)

function incidents_latch_all_doors()
    local all_latched = true
    if door_available(1) and not door_routine.latched_1 then all_latched = false end
    if door_available(2) and not door_routine.latched_2 then all_latched = false end
    if all_latched then
        if door_available(1) then door_routine.latched_1 = false end
        if door_available(2) then door_routine.latched_2 = false end
        save_memory()
    else
        if door_available(1) then door_routine.latched_1 = true end
        if door_available(2) then door_routine.latched_2 = true end
        local msg = (door_available(1) and door_available(2)) and "DOORS LATCHED"
                 or door_available(1) and "DOOR 1 LATCHED"
                 or "DOOR 2 LATCHED"
        inc_trigger_popup(msg)
        save_memory()
    end
end

create_command(
    "FlyWithLua/Incidents/latch_all_doors",
    "Incidents: toggle latch all available doors",
    "incidents_latch_all_doors()", "", ""
)

-- ---- Fuel drain preflight check ---------------------------
function incidents_drain_fuel_tanks()
    if airborne() or engine_on() then return end
    if not (_ref_view_ext and XPLMGetDatai(_ref_view_ext) == 1) then return end
    fuel_drain_check_done = true
    inc_trigger_popup("FUEL TANKS DRAINED")
    save_memory()
end

create_command(
    "FlyWithLua/Incidents/drain_fuel_tanks",
    "Incidents: drain fuel tanks preflight check (outside view, engine off)",
    "incidents_drain_fuel_tanks()", "", ""
)

-- ---- Conditions enforcement toggle ------------------------
conditions_enforced = true

function incidents_toggle_conditions()
    conditions_enforced = not conditions_enforced
end

create_command(
    "FlyWithLua/Incidents/toggle_conditions",
    "Incidents: toggle condition enforcement for manual toggles",
    "incidents_toggle_conditions()", "", ""
)

-- ---- Per-failure toggle ------------------------------------
local function make_toggle(f)
    local fn = "incidents_toggle_" .. f.key:lower()
    _G[fn] = function()
        if failure_is_active(f) then
            reset_failure(f)
        else
            if conditions_enforced then
                if f.condition and not condition_ok(f) then return end
                if f.key == "FUEL_CAP"   and fuel_cap_check_done        then return end
                if f.key == "FUEL_WATER" and fuel_drain_check_done      then return end
                if f.key == "FUEL_TYPE"  and not fuel_type_pending       then return end
            end
            trigger_failure(f)
        end
    end
    create_command(
        "FlyWithLua/Incidents/" .. f.key:lower(),
        "Incidents: toggle " .. f.label,
        fn .. "()", "", ""
    )
end

for _, f in ipairs(failures) do make_toggle(f) end


-- ============================================================
--  [5] MACRO / STATUS
-- ============================================================

incidents_show_status = false

function incidents_draw_status()
    -- startup popup: defer timing to first draw frame
    if inc_popup_armed then
        inc_popup_from  = os.clock() + 5
        inc_popup_until = os.clock() + 13
        inc_popup_armed = false
    end

    local now = os.clock()
    if inc_popup_from and inc_popup_until and now >= inc_popup_from and now < inc_popup_until then
        local font   = 18
        local lines  = inc_popup_label and 3 or 2
        local bw     = font * 21
        local bh     = font * (lines + 1.5)   -- +1 line vs. v2
        local sw     = SCREEN_WIDTH  or 1920
        local sy     = SCREEN_HIGHT  or SCREEN_HEIGHT or 1080
        local xpos   = sw - bw - 40
        local ypos   = sy - (font * 6.3) - 400 - 10 - bh

        local mode_str
        if system_paused then
            mode_str = "OFF"
        elseif type(cfg.mode) == "number" then
            mode_str = "RANDOM (" .. cfg.mode .. " min)"
        else
            mode_str = tostring(cfg.mode)
        end

        XPLMSetGraphicsState(0, 0, 0, 1, 1, 0, 0)
        graphics.set_color(0, 0, 0, 0.3)
        graphics.draw_rectangle(xpos, ypos, xpos + bw, ypos + bh)
        local ty = ypos + bh - 20
        graphics.set_color(0.4, 0.8, 1, 1)
        draw_string_Helvetica_18(xpos + 8, ty, "Incident-Tool by ALx")
        ty = ty - 22
        graphics.set_color(1, 1, 1, 1)
        draw_string_Helvetica_18(xpos + 8, ty, "MODE: " .. mode_str .. "  |  " .. cfg.active_name)
        if inc_popup_label then
            ty = ty - 22
            graphics.set_color(1, 0.8, 0.2, 1)
            draw_string_Helvetica_18(xpos + 8, ty, inc_popup_label)
        end
    end

    if not incidents_show_status then return end

    local x   = 20
    local y   = 40

    local mode_str
    if system_paused then
        mode_str = "OFF"
    elseif type(cfg.mode) == "number" then
        mode_str = "RANDOM (" .. cfg.mode .. " min)"
    else
        mode_str = tostring(cfg.mode)
    end

    -- collect active normal failures
    local active = {}
    for _, f in ipairs(failures) do
        if get_dr(f) == 6 then
            table.insert(active, f.label)
        end
    end
    if smoke_culprit then
        table.insert(active, "Culprit: " .. smoke_culprit)
    end

    -- add fuel routine entries to active list
    local any_fuel = fuelcap_routine.active
                     or fuelleak_routine.active_l or fuelleak_routine.active_r
    if fuelcap_routine.active then
        local rate = fuelcap_rate(fuelcap_routine.elapsed)
        table.insert(active, string.format("Cap %s: %.2f kg/s↓", fuelcap_routine.side, rate))
    end
    if fuelleak_routine.active_l or fuelleak_routine.active_r then
        local sides
        if   fuelleak_routine.active_l and fuelleak_routine.active_r then sides = "L+R"
        elseif fuelleak_routine.active_l                             then sides = "L"
        else                                                              sides = "R"
        end
        local rate = fuelleak_rate(fuelleak_routine.elapsed)
        table.insert(active, string.format("Leak %s: %.2f kg/s↑", sides, rate))
    end


    -- green status entries (pre-computed for layout)
    local show_cap_checked   = fuel_cap_check_done
    local show_drain_checked = fuel_drain_check_done
    local show_type_pending  = fuel_type_pending
    local show_latch_1 = door_available(1) and door_routine.latched_1
    local show_latch_2 = door_available(2) and door_routine.latched_2

    -- layout: title + active failures + fuel quantities + green status lines
    local extra_lines = (any_fuel and 1 or 0)
                      + (show_cap_checked   and 1 or 0)
                      + (show_drain_checked and 1 or 0)
                      + (show_type_pending  and 1 or 0)
                      + (show_latch_1 and 1 or 0)
                      + (show_latch_2 and 1 or 0)
    local top = y + 20 + (#active + extra_lines) * 20
    local cy  = top

    graphics.set_color(1, 1, 1, 1)
    local cond_str = conditions_enforced and "COND: ON" or "COND: OFF"
    draw_string_Helvetica_18(x, cy, "[xp12 Incidents V3]  MODE: " .. mode_str .. "  PROFILE: " .. cfg.active_name .. "  " .. cond_str)
    cy = cy - 20

    for _, label in ipairs(active) do
        graphics.set_color(1, 0.2, 0.2, 1)
        draw_string_Helvetica_18(x, cy, label .. ":   FAIL")
        cy = cy - 20
    end

    -- fuel tank quantities (shown when any fuel routine is active)
    if any_fuel then
        local t1 = read_fuel_l()
        local t2 = read_fuel_r()
        local fmt = function(v) return v and string.format("%.1f", v) or "?" end
        graphics.set_color(1, 0.85, 0.2, 1)
        draw_string_Helvetica_18(x, cy,
            string.format("[Fuel]  T1: %s kg   T2: %s kg", fmt(t1), fmt(t2)))
        cy = cy - 20
    end

    -- orange warning: fuel type risk pending
    if show_type_pending then
        graphics.set_color(1.0, 0.6, 0.1, 1)
        draw_string_Helvetica_18(x, cy, "FUEL TYPE: PENDING")
        cy = cy - 20
    end

    -- green status lines
    if show_cap_checked or show_drain_checked or show_latch_1 or show_latch_2 then
        graphics.set_color(0.3, 1.0, 0.3, 1)
        if show_cap_checked then
            draw_string_Helvetica_18(x, cy, "FUEL CAPS: CHECKED")
            cy = cy - 20
        end
        if show_drain_checked then
            draw_string_Helvetica_18(x, cy, "FUEL TANKS: DRAINED")
            cy = cy - 20
        end
        if show_latch_1 then
            draw_string_Helvetica_18(x, cy, "DOOR 1: LATCHED")
            cy = cy - 20
        end
        if show_latch_2 then
            draw_string_Helvetica_18(x, cy, "DOOR 2: LATCHED")
            cy = cy - 20
        end
    end
end

do_every_draw("incidents_draw_status()")

add_macro(
    "xp12 Incidents V3: Status",
    "incidents_show_status = true",
    "incidents_show_status = false",
    "deactivate"
)


-- ============================================================
--  [6] INITIALIZATION
-- ============================================================

-- ---- Main failure tick -------------------------------------
function incidents_tick()
    local now = os.clock()
    if now - tick_last < TICK_INTERVAL then return end
    tick_last = now
    if system_paused then return end
    if cfg.mode == "OFF" then return end

    if type(cfg.mode) == "number" then
        if rnd_scheduled and not rnd_fired and os.clock() >= rnd_fire_at then
            local f = rnd_target
            -- guard checks: skip (reschedule) if blocked
            local skip = f and (
                (f.key == "FUEL_CAP"   and (fuel_cap_check_done or not airborne()))
             or (f.key == "FUEL_WATER" and fuel_drain_check_done)
             or (f.key == "FUEL_TYPE"  and not fuel_type_pending)
             or (f.key == "DOOR_OPEN"  and not door_has_unlatched())
             or (f.key == "DOOR_1"     and door_routine.latched_1)
             or (f.key == "DOOR_2"     and door_routine.latched_2)
            )
            if skip then
                rnd_scheduled = false
                schedule_random()
            elseif f and f.key == "DOOR_OPEN" then
                -- auto DOOR_OPEN: dice roll; latch checked after selection
                door_trigger_unlatched()
                rnd_fired = true
            elseif f and condition_ok(f) then
                trigger_failure(f)
                rnd_fired = true
            elseif f then
                rnd_fire_at = os.clock() + TICK_INTERVAL
            end
        end
        return
    end

    -- ON / MTBF mode
    for _, f in ipairs(failures) do
        if f.key == "DOOR_OPEN" then
            -- special path: only trigger if at least one unlatched door available
            if not failure_is_active(f) and door_has_unlatched() then
                local mtbf, flag = get_mtbf(f)
                if flag ~= "OFF" and mtbf then
                    if math.random() < prob_from_mtbf(mtbf, TICK_INTERVAL) then
                        door_trigger_unlatched()
                    end
                end
            end
        elseif not failure_is_active(f)
            and not (f.key == "FUEL_CAP"   and (fuel_cap_check_done or not airborne()))
            and not (f.key == "FUEL_WATER" and fuel_drain_check_done)
            and not (f.key == "FUEL_TYPE"  and not fuel_type_pending)
            and not (f.key == "DOOR_1"     and door_routine.latched_1)
            and not (f.key == "DOOR_2"     and door_routine.latched_2) then
            local mtbf, flag = get_mtbf(f)
            if flag ~= "OFF" and mtbf then
                if math.random() < prob_from_mtbf(mtbf, TICK_INTERVAL) then
                    if condition_ok(f) then trigger_failure(f) end
                end
            end
        end
    end
end

do_sometimes("incidents_tick()")

-- ---- Fix tick ----------------------------------------------
function incidents_fix_tick()
    if system_paused then return end
    if cfg.mode == "OFF" then return end
    for _, f in ipairs(failures) do
        local fix_cond = f._fix_cond or (f.fix and f.fix.cond)
        if fix_cond and get_dr(f) == 6 and fix_cond() then
            local was = memory_enabled
            memory_enabled = false
            reset_failure(f)
            f._fix_cond = nil
            if f.fix and f.fix.on_fix then f.fix.on_fix(f) end
            if f.fix and f.fix.followup then
                for _, entry in ipairs(f.fix.followup) do
                    local key2 = type(entry) == "table" and entry.key or entry
                    local f2   = find_failure(key2)
                    if f2 then
                        local _, flag = get_mtbf(f2)
                        if flag ~= "OFF" then trigger_failure(f2) end
                    end
                end
            end
            memory_enabled = was
            save_memory()
        end
    end
end

do_sometimes("incidents_fix_tick()")

-- ---- Smoke culprit monitor ---------------------------------
function incidents_culprit_tick()
    -- ---- Engine-off detection: save fuel snapshot for refuel detection ----
    local eng_now = engine_on()
    if engine_prev_on and not eng_now then
        fuel_cap_mem_l = read_fuel_l()
        fuel_cap_mem_r = read_fuel_r()
        save_memory()
    end
    engine_prev_on = eng_now

    -- ---- Refueling detection: continuous monitor while parked with engine off ----
    if not airborne() and not eng_now and fuel_cap_mem_l ~= nil and fuel_cap_mem_r ~= nil then
        local live_l = read_fuel_l()
        local live_r = read_fuel_r()
        if (live_l and live_l > fuel_cap_mem_l + 1.0)
        or (live_r and live_r > fuel_cap_mem_r + 1.0) then
            fuel_cap_check_done   = false
            fuel_drain_check_done = false
            fuel_type_pending     = true
            fuel_cap_mem_l = live_l
            fuel_cap_mem_r = live_r
            save_memory()
        end
    end

    -- ---- Airborne: clear fuel type pending ----
    if airborne() and fuel_type_pending then
        fuel_type_pending = false
        save_memory()
    end

    -- ---- External view + on ground + engines off → fuel cap preflight check ----
    if not system_paused and not fuel_cap_check_done and not airborne()
       and not eng_now
       and _ref_view_ext and XPLMGetDatai(_ref_view_ext) == 1 then
        fuel_cap_check_done = true
        inc_trigger_popup("TANK CAP CHECKED")
    end

    if system_paused then
        smoke_prev_bat   = dr_bat_on
        smoke_prev_avion = dr_avion
        smoke_prev_gen   = read_gen_on()
        return
    end
    if not smoke_culprit then
        smoke_prev_bat   = dr_bat_on
        smoke_prev_avion = dr_avion
        smoke_prev_gen   = read_gen_on()
        return
    end
    local smoke_f = find_failure("SMOKE")
    if not smoke_f or get_dr(smoke_f) == 6 then
        smoke_prev_bat   = dr_bat_on
        smoke_prev_avion = dr_avion
        smoke_prev_gen   = read_gen_on()
        return
    end

    local triggered = false
    if smoke_culprit == "bat"   and smoke_prev_bat   ~= nil and smoke_prev_bat   == 0 and dr_bat_on   == 1 then triggered = true end
    if smoke_culprit == "avion" and smoke_prev_avion ~= nil and smoke_prev_avion == 0 and dr_avion    == 1 then triggered = true end
    if smoke_culprit == "gen"   and smoke_prev_gen   ~= nil and smoke_prev_gen   == 0 and read_gen_on() == 1 then triggered = true end

    smoke_prev_bat   = dr_bat_on
    smoke_prev_avion = dr_avion
    smoke_prev_gen   = read_gen_on()

    if triggered then trigger_failure(smoke_f) end
end

do_sometimes("incidents_culprit_tick()")

-- ---- Aircraft change detection ----------------------------
local last_icao = ""

function incidents_aircraft_check()
    local current = ((dr_acf_icao or ""):match("^([^%z]*)") or ""):upper():match("^%s*(.-)%s*$")
    if current ~= "" and current ~= last_icao then
        last_icao = current
        build_active_profile()
        fuel_cap_mem_l        = nil
        fuel_cap_mem_r        = nil
        fuel_drain_check_done = false
        fuel_type_pending     = false
        -- reset door routine for new aircraft; do_often tick reads actual sim state within ~100ms
        door_routine.open_1    = false
        door_routine.open_2    = false
        door_routine.fail_1    = false
        door_routine.fail_2    = false
        door_routine.latched_1 = false
        door_routine.latched_2 = false
        door_routine.prev_1    = 0
        door_routine.prev_2    = 0
        load_memory()   -- restores latches from profile section
        fuel_cap_evaluate_check()
    end
end

do_sometimes("incidents_aircraft_check()")

-- ---- Bootstrap ---------------------------------------------
load_config()
init_refs()
build_active_profile()

for _, f in ipairs(failures) do
    local _, flag = get_mtbf(f)
    if flag == "OFF" then reset_failure(f) end
end

load_memory()

-- door_open DataRef not yet ready at load time; do_often tick picks up actual state within ~100ms
door_routine.prev_1 = 0
door_routine.prev_2 = 0
door_routine.open_1 = false
door_routine.open_2 = false
door_routine.fail_1 = false
door_routine.fail_2 = false

system_paused  = (cfg.mode == "OFF")
memory_enabled = true

-- defensive: open door must not carry a stale latch from memory
if door_routine.open_1 and door_routine.latched_1 then door_routine.latched_1 = false; save_memory() end
if door_routine.open_2 and door_routine.latched_2 then door_routine.latched_2 = false; save_memory() end

-- evaluate fuel cap check state now that memory is loaded and writable
fuel_cap_evaluate_check()

if type(cfg.mode) == "number" then schedule_random() end

inc_popup_armed = true

last_icao = ((dr_acf_icao or ""):match("^([^%z]*)") or ""):upper():match("^%s*(.-)%s*$")
