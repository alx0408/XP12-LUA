-- ============================================================
--  fuel_leak_test.lua  —  DIAGNOSTIC VERSION
--  Confirms per-tank drain via m_fuel array write.
-- ============================================================

local DRAIN_PER_SEC = 0.5    -- kg/s
local DRAIN_STOP_KG = 2.0    -- stop leak below this threshold

local _ref_fuel1 = XPLMFindDataRef("sim/flightmodel/weight/m_fuel1")  -- left tank, scalar
local _ref_fuel2 = XPLMFindDataRef("sim/flightmodel/weight/m_fuel2")  -- right tank, scalar

local leak_t1   = false
local leak_t2   = false
local start_t1  = nil    -- fuel at leak start
local start_t2  = nil
local leaked_t1 = 0      -- total leaked so far
local leaked_t2 = 0
local drain_last = 0
local write_ok   = 0

-- ---- Write --------------------------------------------------

local function write_t1(value)
    XPLMSetDataf(_ref_fuel1, value)
    write_ok = write_ok + 1
end

local function write_t2(value)
    XPLMSetDataf(_ref_fuel2, value)
    write_ok = write_ok + 1
end

-- ---- Read ---------------------------------------------------

local function read_t1()
    local ok, v = pcall(XPLMGetDataf, _ref_fuel1)
    if ok and type(v) == "number" then return v end
    return nil
end

local function read_t2()
    local ok, v = pcall(XPLMGetDataf, _ref_fuel2)
    if ok and type(v) == "number" then return v end
    return nil
end

-- ---- Commands -----------------------------------------------

function fuel_leak_toggle_t1()
    leak_t1 = not leak_t1
    if leak_t1 then
        start_t1 = read_t1(); leaked_t1 = 0; drain_last = os.clock()
    else
        start_t1 = nil
    end
end

function fuel_leak_toggle_t2()
    leak_t2 = not leak_t2
    if leak_t2 then
        start_t2 = read_t2(); leaked_t2 = 0; drain_last = os.clock()
    else
        start_t2 = nil
    end
end

function fuel_leak_toggle_both()
    local any = leak_t1 or leak_t2
    leak_t1 = not any; leak_t2 = not any
    if leak_t1 then start_t1 = read_t1(); leaked_t1 = 0; drain_last = os.clock() else start_t1 = nil end
    if leak_t2 then start_t2 = read_t2(); leaked_t2 = 0; drain_last = os.clock() else start_t2 = nil end
end

create_command("FlyWithLua/FuelLeakTest/tank1", "Fuel Leak Test: toggle drain tank 1",
    "fuel_leak_toggle_t1()", "", "")
create_command("FlyWithLua/FuelLeakTest/tank2", "Fuel Leak Test: toggle drain tank 2",
    "fuel_leak_toggle_t2()", "", "")
create_command("FlyWithLua/FuelLeakTest/both",  "Fuel Leak Test: toggle drain both tanks",
    "fuel_leak_toggle_both()", "", "")

-- ---- Drain tick ---------------------------------------------

function fuel_leak_tick()
    if not leak_t1 and not leak_t2 then return end
    local now = os.clock()
    local dt  = math.min(now - drain_last, 0.5)
    drain_last = now
    local drain = DRAIN_PER_SEC * dt
    if leak_t1 then
        local cur = read_t1()
        if cur then
            if cur <= DRAIN_STOP_KG then
                leak_t1 = false; start_t1 = nil
            else
                leaked_t1 = leaked_t1 + drain
                write_t1(cur - drain)
            end
        end
    end
    if leak_t2 then
        local cur = read_t2()
        if cur then
            if cur <= DRAIN_STOP_KG then
                leak_t2 = false; start_t2 = nil
            else
                leaked_t2 = leaked_t2 + drain
                write_t2(cur - drain)
            end
        end
    end
end

do_often("fuel_leak_tick()")

-- ---- Status display -----------------------------------------

fuel_leak_show_status = true

local function fmt(v) return v and string.format("%.1f", v) or "?" end

function fuel_leak_draw()
    if not fuel_leak_show_status then return end
    local _, v1 = pcall(XPLMGetDataf, _ref_fuel1)
    local _, v2 = pcall(XPLMGetDataf, _ref_fuel2)
    local x, y = 20, 200
    graphics.set_color(1, 1, 0, 1)
    draw_string_Helvetica_18(x, y + 80, "[Fuel Leak Test]")
    graphics.set_color(1, 1, 1, 1)
    draw_string_Helvetica_18(x, y + 60, "writes=" .. write_ok)
    -- T1
    local lv1  = type(v1)=="number" and v1 or nil
    local cons1 = (start_t1 and lv1) and (start_t1 - leaked_t1 - lv1) or nil
    draw_string_Helvetica_18(x, y + 40,
        (leak_t1 and "T1: LEAK" or "T1: ok") ..
        "  start=" .. fmt(start_t1) ..
        "  leak=" .. fmt(leaked_t1 > 0 and leaked_t1 or nil) ..
        "  cons=" .. fmt(cons1) ..
        "  live=" .. fmt(lv1))
    -- T2
    local lv2  = type(v2)=="number" and v2 or nil
    local cons2 = (start_t2 and lv2) and (start_t2 - leaked_t2 - lv2) or nil
    draw_string_Helvetica_18(x, y + 20,
        (leak_t2 and "T2: LEAK" or "T2: ok") ..
        "  start=" .. fmt(start_t2) ..
        "  leak=" .. fmt(leaked_t2 > 0 and leaked_t2 or nil) ..
        "  cons=" .. fmt(cons2) ..
        "  live=" .. fmt(lv2))
end

do_every_draw("fuel_leak_draw()")

create_command("FlyWithLua/FuelLeakTest/status", "Fuel Leak Test: toggle status display",
    "fuel_leak_show_status = not fuel_leak_show_status", "", "")

add_macro("Fuel Leak Test: Status",
    "fuel_leak_show_status = true",
    "fuel_leak_show_status = false",
    "activate")
