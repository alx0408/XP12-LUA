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
    "Toggle altitude increment between 100 ft and 1000 ft",
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
-- AP1 / AP2 (short=AP1, long=AP2)
----------------------------

-- Double assignment to one key/button
-- Short press (<0,5s): AP1
-- Long  press (>=0,5s): AP2

local AP_PP_THRESHOLD = 0.5
local ap_pp_press_t = 0
local ap_pp_fired = false

local cmd_ap1_push = nil
local cmd_ap2_push = nil

function ap_pp_init_cmds()
    if not XPLMFindCommand then return end
    -- Unconditional re-resolve on every aircraft load (ToLiss plugin
    -- unloads/reloads with the aircraft, cached refs would go stale).
    cmd_ap1_push = XPLMFindCommand("toliss_airbus/ap1_push")
    cmd_ap2_push = XPLMFindCommand("toliss_airbus/ap2_push")
end

ap_pp_init_cmds()

if do_on_aircraft_load then
    do_on_aircraft_load("ap_pp_init_cmds()")
end

function ap_pp_begin()
    ap_pp_press_t = os.clock()
    ap_pp_fired = false
end

function ap_pp_hold()
    if ap_pp_fired then return end
    if (os.clock() - ap_pp_press_t) >= AP_PP_THRESHOLD then
        if cmd_ap2_push and XPLMCommandOnce then
            XPLMCommandOnce(cmd_ap2_push)
        elseif command_once then
            command_once("toliss_airbus/ap2_push")
        end
        ap_pp_fired = true
    end
end

function ap_pp_end()
    if not ap_pp_fired then
        if cmd_ap1_push and XPLMCommandOnce then
            XPLMCommandOnce(cmd_ap1_push)
        elseif command_once then
            command_once("toliss_airbus/ap1_push")
        end
    end
    ap_pp_press_t = 0
    ap_pp_fired = false
end

create_command(
    "FlyWithLua/ToLiss/Autopilot_1_Autopilot_2",
    "Autopilot_1_Autopilot_2 (<0.5s short / >=0.5s long)",
    "ap_pp_begin()",
    "ap_pp_hold()",
    "ap_pp_end()"
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

----------------------------
-- PITCH TRIM (Encoder: kurzer gehaltener nativer Trim-Puls pro Raste)
----------------------------

-- Hintergrund: Direktes Schreiben von elevator_trim wird vom ToLiss-FBW jeden
-- Frame ueberschrieben (Rad "zittert"); einzeln getriggerte Commands greifen
-- nicht. Zuverlaessig wirkt nur ein *gehaltener* nativer Command
-- (command_begin .. command_end), getaktet ueber do_often -- exakt die Bausteine,
-- die hier frueher schon funktioniert haben.
--
-- Jede Encoder-Raste haelt den nativen Trim-Command fuer eine feste Zeit gedrueckt.
-- Ein Deckel begrenzt den Rueckstau -> nach dem Loslassen laeuft nichts nach.
--
-- EINZIGE Stellschraube: Staerke (Trimm-Menge pro Raste). Zu langsam => groesser,
-- zu grob => kleiner.   1 ~ 0.1 Grad pro Raste, jede Stufe ~ +0.1 Grad.
TOLISS_TRIM_STRENGTH = 1

-- intern: Haltezeit je Staerkestufe in Sekunden (nicht anfassen)
local TOLISS_TRIM_BASE_SEC = 0.05

local toliss_trim_cmd_up = "sim/flight_controls/pitch_trim_up"
local toliss_trim_cmd_dn = "sim/flight_controls/pitch_trim_down"

local toliss_trim_active_cmd = nil
local toliss_trim_until = 0

-- direction: >0 = nose up, <0 = nose down. Eine Raste = ein Puls.
function toliss_trim_step(direction)
    local now = os.clock()
    local cmd = (direction < 0) and toliss_trim_cmd_dn or toliss_trim_cmd_up
    local pulse = TOLISS_TRIM_STRENGTH * TOLISS_TRIM_BASE_SEC

    -- Richtungswechsel: laufenden Puls sofort beenden
    if toliss_trim_active_cmd and toliss_trim_active_cmd ~= cmd then
        command_end(toliss_trim_active_cmd)
        toliss_trim_active_cmd = nil
        toliss_trim_until = 0
    end

    -- An laufenden Puls anhaengen, sonst ab jetzt; Deckel = max. 2 Rasten Rueckstau
    local base = (toliss_trim_active_cmd and toliss_trim_until > now) and toliss_trim_until or now
    toliss_trim_until = math.min(base + pulse, now + pulse * 2)

    if not toliss_trim_active_cmd then
        toliss_trim_active_cmd = cmd
        command_begin(cmd)
    end
end

-- Beendet den gehaltenen Command, sobald die Pulszeit abgelaufen ist.
function toliss_trim_tick()
    if toliss_trim_active_cmd and os.clock() >= toliss_trim_until then
        command_end(toliss_trim_active_cmd)
        toliss_trim_active_cmd = nil
        toliss_trim_until = 0
    end
end

-- Pro Frame fuer praezise, kurze Pulse; do_often als Sicherheits-Backstop,
-- falls do_every_frame in dieser FlyWithLua-Version nicht feuert.
do_every_frame("toliss_trim_tick()")
do_often("toliss_trim_tick()")

create_command(
    "FlyWithLua/ToLiss/Pitch_trim_up_multi",
    "Pitch trim up (step)",
    "toliss_trim_step(1)",
    "",
    ""
)

create_command(
    "FlyWithLua/ToLiss/Pitch_trim_down_multi",
    "Pitch trim down (step)",
    "toliss_trim_step(-1)",
    "",
    ""
)

----------------------------
-- A-SKID & NWS SWITCH ON/OFF
----------------------------

local dr_askid_nws = nil
local dr_askid_anim = nil

function askid_nws_init()
    if not (XPLMFindDataRef and XPLMSetDatai and XPLMSetDataf) then return end
    dr_askid_nws = XPLMFindDataRef("AirbusFBW/NWSnAntiSkid")
    dr_askid_anim = XPLMFindDataRef("ckpt/askidSwitch/anim")
end

askid_nws_init()
if do_on_aircraft_load then
    do_on_aircraft_load("askid_nws_init()")
end

function askid_nws_on()
    if dr_askid_nws and XPLMSetDatai then XPLMSetDatai(dr_askid_nws, 1) end
    if dr_askid_anim and XPLMSetDataf then XPLMSetDataf(dr_askid_anim, 1) end
end

function askid_nws_off()
    if dr_askid_nws and XPLMSetDatai then XPLMSetDatai(dr_askid_nws, 0) end
    if dr_askid_anim and XPLMSetDataf then XPLMSetDataf(dr_askid_anim, 0) end
end

create_command(
    "FlyWithLua/ToLiss/ASkidNWS_on",
    "A-Skid & NWS ON",
    "askid_nws_on()",
    "",
    ""
)

create_command(
    "FlyWithLua/ToLiss/ASkidNWS_off",
    "A-Skid & NWS OFF",
    "askid_nws_off()",
    "",
    ""
)

----------------------------
-- COCKPIT DOOR LOCK UP/DOWN
----------------------------

local dr_door_lock = nil

function door_lock_init()
    if not (XPLMFindDataRef and XPLMGetDatai and XPLMSetDatai) then return end
    dr_door_lock = XPLMFindDataRef("ckpt/doorLock")
end

door_lock_init()
if do_on_aircraft_load then
    do_on_aircraft_load("door_lock_init()")
end

function cockpit_door_up()
    if not dr_door_lock then return end
    local v = XPLMGetDatai(dr_door_lock)
    if v < 2 then
        XPLMSetDatai(dr_door_lock, v + 1)
    end
end

function cockpit_door_down()
    if not dr_door_lock then return end
    local v = XPLMGetDatai(dr_door_lock)
    if v > 0 then
        XPLMSetDatai(dr_door_lock, v - 1)
    end
end

create_command(
    "FlyWithLua/ToLiss/CockpitDoorUp",
    "Cockpit Door Lock +1 (max 2)",
    "cockpit_door_up()",
    "",
    ""
)

create_command(
    "FlyWithLua/ToLiss/CockpitDoorDown",
    "Cockpit Door Lock -1 (min 0)",
    "cockpit_door_down()",
    "",
    ""
)
