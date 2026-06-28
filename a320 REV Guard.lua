-----------------------------------------------------------------
--- ToLiss A320 Enhancers
-----------------------------------------------------------------

----------------------------
--- ENG Anti-Ice TOGGLE  --
----------------------------
function _eng_ai_toggle_press()
    if not (XPLMFindDataRef and XPLMGetDatai and XPLMSetDatai) then return end
    local d1 = XPLMFindDataRef("AirbusFBW/ENG1AISwitch")
    local d2 = XPLMFindDataRef("AirbusFBW/ENG2AISwitch")
    if not d1 or not d2 then return end
    local v1 = XPLMGetDatai(d1)
    local v2 = XPLMGetDatai(d2)
    local tgt = (v1 == 0 and v2 == 0) and 1 or 0
    XPLMSetDatai(d1, tgt)
    XPLMSetDatai(d2, tgt)
end

create_command(
    "FlyWithLua/ToLiss/ENG_Anti_ice_toggle",
    "Toggle ENG1+ENG2 Anti-Ice",
    "_eng_ai_toggle_press()",
    "",
    ""
)

----------------------------
--- WX / PWS ON/OFF  --
----------------------------
wx_enforce_frames = 0
wx_ref = nil

function wx_enforcer()
    if wx_enforce_frames and wx_enforce_frames > 0 and wx_ref then
        XPLMSetDatai(wx_ref, 1)   -- WX OFF halten
        wx_enforce_frames = wx_enforce_frames - 1
    end
end

function _wx_pws_off_press()
    if not (XPLMFindDataRef and XPLMSetDatai and XPLMGetDatai) then return end
    local p = XPLMFindDataRef("AirbusFBW/WXSwitchPWS")
    wx_ref = XPLMFindDataRef("AirbusFBW/WXPowerSwitch")
    if not p or not wx_ref then return end

    XPLMSetDatai(p, 0)   -- PWS OFF
    XPLMSetDatai(wx_ref, 1)   -- WX OFF

    if XPLMGetDatai(wx_ref) ~= 1 then
        wx_enforce_frames = 10
    else
        wx_enforce_frames = 0
    end
end

create_command(
    "FlyWithLua/ToLiss/WX_PWS_off",
    "WX and PWS OFF",
    "_wx_pws_off_press()",
    "",
    ""
)

function _wx_pws_on_press()
    if not (XPLMFindDataRef and XPLMSetDatai) then return end
    local p = XPLMFindDataRef("AirbusFBW/WXSwitchPWS")
    local w = XPLMFindDataRef("AirbusFBW/WXPowerSwitch")
    if not p or not w then return end

    XPLMSetDatai(p, 2)   -- PWS AUTO/ON
    XPLMSetDatai(w, 0)   -- WX ON
end

create_command(
    "FlyWithLua/ToLiss/WX_PWS_on",
    "WX and PWS ON",
    "_wx_pws_on_press()",
    "",
    ""
)

-- Enforcer registrieren
do_every_frame("wx_enforcer()")


----------------------------
--- Reverser Guard  --
----------------------------

--- ON: hold >= 0.5s (wenn Reverser aus)
--- OFF: sofort beim Tastendruck (wenn Hebel in Reverser-Position, gem. ckpt/* DataRefs)

local HOLD_REQUIRED = 0.5
local press_t = 0
local fired   = false

-- Cache für sim-Commands
local cmd_rev_toggle, cmd_tog_rev = nil, nil

local function fire_toggle()
    if XPLMFindCommand then
        if not cmd_rev_toggle then cmd_rev_toggle = XPLMFindCommand("sim/engines/thrust_reverse_toggle") end
        if not cmd_tog_rev    then cmd_tog_rev    = XPLMFindCommand("sim/engines/tog_thrust_rev") end
    end
    if cmd_rev_toggle and XPLMCommandOnce then
        XPLMCommandOnce(cmd_rev_toggle)
    elseif command_once then
        command_once("sim/engines/thrust_reverse_toggle")
    end

    if cmd_tog_rev and XPLMCommandOnce then
        XPLMCommandOnce(cmd_tog_rev)
    elseif command_once then
        command_once("sim/engines/tog_thrust_rev")
    end
end

-- Prüft primär deine Hebel-DataRefs, fallback auf Standard-Sim-Refs
local function reverser_is_on()
    if not XPLMFindDataRef then return false end

    -- 1) Deine ToLiss-Hebel (Animation) als primäres Kriterium
    local l = XPLMFindDataRef("ckpt/throttleLeft/anim")
    local r = XPLMFindDataRef("ckpt/throttleRight/anim")
    if l and XPLMGetDataf and (XPLMGetDataf(l) or 0) <= -0.1 then return true end
    if r and XPLMGetDataf and (XPLMGetDataf(r) or 0) <= -0.1 then return true end

    -- 2) Fallback: übliche sim-DataRefs
    for i = 0, 7 do
        local r_on = XPLMFindDataRef("sim/cockpit2/engine/indicators/thrust_reverser_on[" .. i .. "]")
        if r_on and XPLMGetDatai and XPLMGetDatai(r_on) ~= 0 then return true end

        local r_handle = XPLMFindDataRef("sim/cockpit2/engine/actuators/thrust_reverser_handle_position[" .. i .. "]")
        if r_handle and XPLMGetDataf and (XPLMGetDataf(r_handle) or 0) > 0.05 then return true end

        local r_deploy = XPLMFindDataRef("sim/cockpit2/engine/actuators/thrust_reverser_deploy_ratio[" .. i .. "]")
        if r_deploy and XPLMGetDataf and (XPLMGetDataf(r_deploy) or 0) > 0.05 then return true end
    end

    return false
end

-- Command-Handler
function rev_begin()
    press_t = os.clock()
    fired   = false

    -- Sofortiges OFF: wenn Hebel schon in Reverser-Position (<= -0.1), direkt toggeln
    if reverser_is_on() then
        fire_toggle()
        fired = true
    end
end

function rev_hold()
    -- Einschalten nur, wenn noch nichts ausgelöst wurde und Reverser AUS sind,
    -- und die Taste mindestens HOLD_REQUIRED gehalten wurde
    if fired then return end
    if (not reverser_is_on()) and (os.clock() - press_t >= HOLD_REQUIRED) then
        fire_toggle()
        fired = true
    end
end

function rev_end()
    -- Nichts weiter nötig – OFF wurde ggf. schon in rev_begin() sofort ausgelöst.
    press_t = 0
    fired   = false
end

-- Command immer anlegen (Name unverändert)
create_command(
    "FlyWithLua/ToLiss/Reverse_hold_toggle",
    "Thrust Reverser (ON hold 0.5s, OFF instant if lever in REV)",
    "rev_begin()",
    "rev_hold()",
    "rev_end()"
)


----------------------------
-- ALT 100/1000  --
----------------------------

local toliss_alt_ready = false
local dr_alt_100_1000 = nil

function setup_toliss_alt_100_1000()
    toliss_alt_ready = false
    dr_alt_100_1000 = nil

    if not (XPLMFindDataRef and XPLMGetDatai and XPLMSetDatai) then return end

    dr_alt_100_1000 = XPLMFindDataRef("AirbusFBW/ALT100_1000")
    if dr_alt_100_1000 then
        toliss_alt_ready = true
    end
end

-- Run once now and keep it refreshed.
-- Some FlyWithLua variants don't have `do_on_aircraft_load()`, 
-- so we fall back to periodically re-checking the DataRef.

setup_toliss_alt_100_1000()

if do_on_aircraft_load then
    do_on_aircraft_load("setup_toliss_alt_100_1000()")
elseif do_sometimes then
    do_sometimes("setup_toliss_alt_100_1000()")
elseif do_often then
    do_often("setup_toliss_alt_100_1000()")
elseif do_every_frame then
    do_every_frame("setup_toliss_alt_100_1000()")
end

-- toggle function (guarded)
function toggle_altitude100_1000()
    if not toliss_alt_ready or not dr_alt_100_1000 then return end

    local v = XPLMGetDatai(dr_alt_100_1000)
    if v == 0 then
        XPLMSetDatai(dr_alt_100_1000, 1)
    else
        XPLMSetDatai(dr_alt_100_1000, 0)
    end
end

-- command for key / button assignment
create_command(
    "FlyWithLua/ToLiss/altitude100-1000",
    "Toggle altitude increment between 100 ft and 1000 ft (ToLiss only)",
    "toggle_altitude100_1000()",
    "",
    ""
)

----------------------------
-- EFIS/ND KNOB  --
----------------------------

-- DataRef: AirbusFBW/NDmodeCapt
-- Values: 0=LS, 1=VOR, 2=NAV, 3=ARC, 4=PLAN

local toliss_nd_ready = false
local dr_nd_mode_capt = nil

function setup_toliss_nd_mode_capt()
    toliss_nd_ready = false
    dr_nd_mode_capt = nil

    if not (XPLMFindDataRef and XPLMSetDatai) then return end

    dr_nd_mode_capt = XPLMFindDataRef("AirbusFBW/NDmodeCapt")
    if dr_nd_mode_capt then
        toliss_nd_ready = true
    end
end

-- Initialize now and refresh on aircraft load / periodically
setup_toliss_nd_mode_capt()

if do_on_aircraft_load then
    do_on_aircraft_load("setup_toliss_nd_mode_capt()")
elseif do_sometimes then
    do_sometimes("setup_toliss_nd_mode_capt()")
elseif do_often then
    do_often("setup_toliss_nd_mode_capt()")
elseif do_every_frame then
    do_every_frame("setup_toliss_nd_mode_capt()")
end

function set_nd_mode_capt(v)
    if not toliss_nd_ready or not dr_nd_mode_capt then return end
    -- NDmodeCapt is an integer selector
    XPLMSetDatai(dr_nd_mode_capt, v)
end

create_command(
    "FlyWithLua/ToLiss/EFIS-ND-LS",
    "EFIS ND mode CAPT: LS (0)",
    "set_nd_mode_capt(0)",
    "",
    ""
)

create_command(
    "FlyWithLua/ToLiss/EFIS-ND-VOR",
    "EFIS ND mode CAPT: VOR (1)",
    "set_nd_mode_capt(1)",
    "",
    ""
)

create_command(
    "FlyWithLua/ToLiss/EFIS-ND-NAV",
    "EFIS ND mode CAPT: NAV (2)",
    "set_nd_mode_capt(2)",
    "",
    ""
)

create_command(
    "FlyWithLua/ToLiss/EFIS-ND-ARC",
    "EFIS ND mode CAPT: ARC (3)",
    "set_nd_mode_capt(3)",
    "",
    ""
)

create_command(
    "FlyWithLua/ToLiss/EFIS-ND-PLAN",
    "EFIS ND mode CAPT: PLAN (4)",
    "set_nd_mode_capt(4)",
    "",
    ""
)



----------------------------
-- PULL (short) PUSH (long)
----------------------------

-- Double assignment to one key/button
-- Short press (<0,5s): PULL (selected)
-- Long  press (>=0,5s): PUSH (managed)
-- ALT / VS / SPD / AP1-AP2

local ALT_PP_THRESHOLD = 0.5
local alt_pp_press_t = 0
local alt_pp_fired = false

local cmd_alt_pull = nil
local cmd_alt_push = nil

function alt_pp_init_cmds()
    if XPLMFindCommand then
        if not cmd_alt_pull then cmd_alt_pull = XPLMFindCommand("AirbusFBW/PullAltitude") end
        if not cmd_alt_push then cmd_alt_push = XPLMFindCommand("AirbusFBW/PushAltitude") end
    end
end

alt_pp_init_cmds()

if do_on_aircraft_load then
    do_on_aircraft_load("alt_pp_init_cmds()")
end

function alt_pp_begin()
    alt_pp_press_t = os.clock()
    alt_pp_fired = false
end

function alt_pp_hold()
    if alt_pp_fired then return end
    if (os.clock() - alt_pp_press_t) >= ALT_PP_THRESHOLD then
        if cmd_alt_push and XPLMCommandOnce then
            XPLMCommandOnce(cmd_alt_push)
        elseif command_once then
            command_once("AirbusFBW/PushAltitude")
        end
        alt_pp_fired = true
    end
end

function alt_pp_end()
    if not alt_pp_fired then
        if cmd_alt_pull and XPLMCommandOnce then
            XPLMCommandOnce(cmd_alt_pull)
        elseif command_once then
            command_once("AirbusFBW/PullAltitude")
        end
    end
    alt_pp_press_t = 0
    alt_pp_fired = false
end

-- 1) ALT pull/push

create_command(
    "FlyWithLua/ToLiss/ALT_pull_push",
    "ALT knob pull (<0.5s) / push (>=0.5s)",
    "alt_pp_begin()",
    "alt_pp_hold()",
    "alt_pp_end()"
)


-- Cache commands
local cmd_vs_pull, cmd_vs_push = nil, nil
local cmd_spd_pull, cmd_spd_push = nil, nil
local cmd_ap1_push, cmd_ap2_push = nil, nil

function pp_init_more_cmds()
    if not XPLMFindCommand then return end

    if not cmd_vs_pull  then cmd_vs_pull  = XPLMFindCommand("AirbusFBW/PullVSSel") end
    if not cmd_vs_push  then cmd_vs_push  = XPLMFindCommand("AirbusFBW/PushVSSel") end

    if not cmd_spd_pull then cmd_spd_pull = XPLMFindCommand("AirbusFBW/PullSPDSel") end
    if not cmd_spd_push then cmd_spd_push = XPLMFindCommand("AirbusFBW/PushSPDSel") end

    if not cmd_ap1_push then cmd_ap1_push = XPLMFindCommand("toliss_airbus/ap1_push") end
    if not cmd_ap2_push then cmd_ap2_push = XPLMFindCommand("toliss_airbus/ap2_push") end
end

pp_init_more_cmds()

if do_on_aircraft_load then
    do_on_aircraft_load("pp_init_more_cmds()")
end

-- Generic state machine for one pull/push command
local function make_pp(name, desc, short_cmd_ref, short_cmd_str, long_cmd_ref, long_cmd_str)
    local t0 = 0
    local fired = false

    _G[name .. "_begin"] = function()
        t0 = os.clock()
        fired = false
    end

    _G[name .. "_hold"] = function()
        if fired then return end
        if (os.clock() - t0) >= ALT_PP_THRESHOLD then
            if long_cmd_ref and XPLMCommandOnce then
                XPLMCommandOnce(long_cmd_ref)
            elseif command_once then
                command_once(long_cmd_str)
            end
            fired = true
        end
    end

    _G[name .. "_end"] = function()
        if not fired then
            if short_cmd_ref and XPLMCommandOnce then
                XPLMCommandOnce(short_cmd_ref)
            elseif command_once then
                command_once(short_cmd_str)
            end
        end
        t0 = 0
        fired = false
    end

    create_command(
        "FlyWithLua/ToLiss/" .. desc,
        desc .. " (<0.5s short / >=0.5s long)",
        name .. "_begin()",
        name .. "_hold()",
        name .. "_end()"
    )
end

-- 2) VS pull/push
make_pp(
    "pp_vs",
    "VS_pull_push",
    cmd_vs_pull,
    "AirbusFBW/PullVSSel",
    cmd_vs_push,
    "AirbusFBW/PushVSSel"
)

-- 3) Speed pull/push
make_pp(
    "pp_spd",
    "Speed_pull_push",
    cmd_spd_pull,
    "AirbusFBW/PullSPDSel",
    cmd_spd_push,
    "AirbusFBW/PushSPDSel"
)


-- 4) Autopilot 1 / Autopilot 2 (short=AP1, long=AP2)
make_pp(
    "pp_ap",
    "Autopilot_1_Autopilot_2",
    cmd_ap1_push,
    "toliss_airbus/ap1_push",
    cmd_ap2_push,
    "toliss_airbus/ap2_push"
)


----------------------------
-- QNH pull/push (SPECIAL HANDLING)
----------------------------

-- ToLiss baro pull/push behaves more reliably when sent as BEGIN/END pulse

local qnh_pending_end = false
local qnh_end_time = 0
local qnh_end_cmd_ref = nil
local qnh_end_cmd_str = ""

function qnh_pulse_begin_end(cmd_ref, cmd_str)
    -- Prefer XPLM begin/end if available, else FlyWithLua command_begin/end.
    if cmd_ref and XPLMCommandBegin and XPLMCommandEnd then
        XPLMCommandBegin(cmd_ref)
        qnh_pending_end = true
        qnh_end_time = os.clock() + 0.05
        qnh_end_cmd_ref = cmd_ref
        qnh_end_cmd_str = ""
        return
    end

    if command_begin and command_end and cmd_str and cmd_str ~= "" then
        command_begin(cmd_str)
        qnh_pending_end = true
        qnh_end_time = os.clock() + 0.05
        qnh_end_cmd_ref = nil
        qnh_end_cmd_str = cmd_str
        return
    end

    -- Fallback
    if cmd_ref and XPLMCommandOnce then
        XPLMCommandOnce(cmd_ref)
    elseif command_once and cmd_str and cmd_str ~= "" then
        command_once(cmd_str)
    end
end

function qnh_pulse_update()
    if not qnh_pending_end then return end
    if qnh_end_time <= 0 or os.clock() < qnh_end_time then return end

    if qnh_end_cmd_ref and XPLMCommandEnd then
        XPLMCommandEnd(qnh_end_cmd_ref)
    elseif qnh_end_cmd_str ~= "" and command_end then
        command_end(qnh_end_cmd_str)
    end

    qnh_pending_end = false
    qnh_end_cmd_ref = nil
    qnh_end_cmd_str = ""
    qnh_end_time = 0
end

do_every_frame("qnh_pulse_update()")

-- Dedicated state machine for QNH
local qnh_t0 = 0
local qnh_fired = false

function pp_qnh_begin()
    qnh_t0 = os.clock() or 0
    qnh_fired = false
end

function pp_qnh_hold()
    if qnh_fired then return end

    -- Defensive: ensure numeric values
    local t0 = qnh_t0
    if type(t0) ~= "number" then t0 = os.clock() or 0 end

    local thr = ALT_PP_THRESHOLD
    if type(thr) ~= "number" then thr = 0.5 end

    local dt = (os.clock() or 0) - t0
    if dt >= thr then
        -- long: PUSH
        qnh_pulse_begin_end(cmd_qnh_push, "toliss_airbus/capt_baro_push")
        qnh_fired = true
    end
end

function pp_qnh_end()
    if not qnh_fired then
        -- short: PULL
        qnh_pulse_begin_end(cmd_qnh_pull, "toliss_airbus/capt_baro_pull")
    end
    qnh_t0 = 0
    qnh_fired = false
end

create_command(
    "FlyWithLua/ToLiss/QNH_pull_push",
    "QNH_pull_push (<0.5s short / >=0.5s long)",
    "pp_qnh_begin()",
    "pp_qnh_hold()",
    "pp_qnh_end()"
)

----------------------------
-- TCAS ALT abv / blw
----------------------------

local dr_tcas_alt = nil

function tcas_alt_init()
    if not (XPLMFindDataRef and XPLMGetDatai and XPLMSetDatai) then return end
    dr_tcas_alt = XPLMFindDataRef("AirbusFBW/XPDRTCASAltSelect")
end

tcas_alt_init()
if do_on_aircraft_load then
    do_on_aircraft_load("tcas_alt_init()")
end


function set_tcas_alt(v)
    if not dr_tcas_alt then return end
    -- Values: 2 = BLW, 1 = NORM, 0 = ABV
    XPLMSetDatai(dr_tcas_alt, v)
end

create_command(
    "FlyWithLua/ToLiss/TCAS_Alt_blw",
    "TCAS ALT BLW",
    "set_tcas_alt(2)",
    "",
    ""
)

create_command(
    "FlyWithLua/ToLiss/TCAS_Alt_abv",
    "TCAS ALT ABV",
    "set_tcas_alt(0)",
    "",
    ""
)

----------------------------
-- PROBE HEAT TOGGLE
----------------------------

local dr_probe_heat = nil

function probe_heat_init()
    if not (XPLMFindDataRef and XPLMGetDatai and XPLMSetDatai) then return end
    dr_probe_heat = XPLMFindDataRef("AirbusFBW/ProbeHeatSwitch")
end

probe_heat_init()
if do_on_aircraft_load then
    do_on_aircraft_load("probe_heat_init()")
end

function toggle_probe_heat()
    if not dr_probe_heat then return end
    local v = XPLMGetDatai(dr_probe_heat)
    XPLMSetDatai(dr_probe_heat, (v == 0) and 1 or 0)
end

create_command(
    "FlyWithLua/ToLiss/Probe_Heat_toggle",
    "Toggle Probe Heat",
    "toggle_probe_heat()",
    "",
    ""
)
