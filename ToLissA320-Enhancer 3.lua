-----------------------------------------------------------------
--- ToLiss A320 Enhancers
-----------------------------------------------------------------

----------------------------
-- HELPER (nur intern aufgerufen -> duerfen local sein)
----------------------------

-- Int-Selektor auf festen Wert setzen
local function set_datai(name, v)
    if not (XPLMFindDataRef and XPLMSetDatai) then return end
    local dr = XPLMFindDataRef(name)
    if dr then XPLMSetDatai(dr, v) end
end

-- Nativen Command einmal ausloesen (mit Fallback auf command_once)
local function baro_cmd(name)
    if XPLMFindCommand then
        local c = XPLMFindCommand(name)
        if c and XPLMCommandOnce then
            XPLMCommandOnce(c)
            return
        end
    end
    if command_once then command_once(name) end
end

-- Int-DataRef zwischen 0 und 1 umschalten
local function toggle_datai01(name)
    if not (XPLMFindDataRef and XPLMGetDatai and XPLMSetDatai) then return end
    local dr = XPLMFindDataRef(name)
    if not dr then return end
    XPLMSetDatai(dr, (XPLMGetDatai(dr) == 0) and 1 or 0)
end

-- delta auf eine numerische DataRef addieren, unter Beruecksichtigung ihres
-- tatsaechlichen Typs (int/float/double). Wichtig, weil der falsche Accessor
-- (z.B. SetDataf auf einer int-Ref) still nichts tut.
-- lo/hi optional: begrenzt das Ergebnis (nil = keine Grenze in der Richtung).
local function dref_add(name, delta, lo, hi)
    if not XPLMFindDataRef then return end
    local dr = XPLMFindDataRef(name)
    if not dr then return end
    local function clamp(x)
        if lo and x < lo then x = lo end
        if hi and x > hi then x = hi end
        return x
    end
    local t = (XPLMGetDataRefTypes and XPLMGetDataRefTypes(dr)) or 0
    local is_int    = (t % 2) >= 1
    local is_float  = (math.floor(t / 2) % 2) >= 1
    local is_double = (math.floor(t / 4) % 2) >= 1
    if is_float and XPLMGetDataf and XPLMSetDataf then
        XPLMSetDataf(dr, clamp((XPLMGetDataf(dr) or 0) + delta))
    elseif is_double and XPLMGetDatad and XPLMSetDatad then
        XPLMSetDatad(dr, clamp((XPLMGetDatad(dr) or 0) + delta))
    elseif is_int and XPLMGetDatai and XPLMSetDatai then
        XPLMSetDatai(dr, clamp((XPLMGetDatai(dr) or 0) + delta))
    elseif XPLMGetDataf and XPLMSetDataf then
        -- Typ unbekannt (XPLMGetDataRefTypes fehlt): Gain/Tilt sind analog -> float
        XPLMSetDataf(dr, clamp((XPLMGetDataf(dr) or 0) + delta))
    end
end


----------------------------
-- CAPT WIPER DEC / INC (Encoder, 0..2)
----------------------------
-- AirbusFBW/LeftWiperSwitch: DEC -1 (min 0), INC +1 (max 2)

function capt_wiper_dec()
    dref_add("AirbusFBW/LeftWiperSwitch", -1, 0, 2)
end

function capt_wiper_inc()
    dref_add("AirbusFBW/LeftWiperSwitch", 1, 0, 2)
end

create_command(
    "FlyWithLua/ToLiss/CAPT_Wiper_dec",
    "CAPT WIPER DEC",
    "capt_wiper_dec()",
    "",
    ""
)

create_command(
    "FlyWithLua/ToLiss/CAPT_Wiper_inc",
    "CAPT WIPER INC",
    "capt_wiper_inc()",
    "",
    ""
)


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
-- BARO INC / DEC (enhanced) - 1 Raste = 1 hPa im hPa-Modus
----------------------------
-- Der native Command schrittet ~1/3 hPa. Steht der Kapitaens-Baro auf hPa
-- (AirbusFBW/BaroUnitCapt = 1), feuern wir 3x pro Raste (= ~1 hPa).
-- Steht er auf inHg (0), bleibt es beim nativen Einzelschritt.

local function baro_unit_is_hpa()
    if not XPLMFindDataRef then return false end
    local dr = XPLMFindDataRef("AirbusFBW/BaroUnitCapt")
    if not dr then return false end
    local t = (XPLMGetDataRefTypes and XPLMGetDataRefTypes(dr)) or 0
    local is_float = (math.floor(t / 2) % 2) >= 1
    if is_float and XPLMGetDataf then
        return (XPLMGetDataf(dr) or 0) >= 0.5
    end
    if XPLMGetDatai then
        return XPLMGetDatai(dr) == 1
    end
    return false
end

-- Mehrere Auslösungen in EINEM Frame verrechnet X-Plane zu nur einem Schritt.
-- Daher sammeln wir die ausstehenden Schritte und feuern einen pro Frame ab.
-- baro_queue > 0 = up, < 0 = down.
baro_queue = 0

function baro_enh_tick()
    if baro_queue > 0 then
        baro_cmd("sim/instruments/barometer_up")
        baro_queue = baro_queue - 1
    elseif baro_queue < 0 then
        baro_cmd("sim/instruments/barometer_down")
        baro_queue = baro_queue + 1
    end
end
do_every_frame("baro_enh_tick()")

function baro_inc_enhanced()
    baro_queue = baro_queue + (baro_unit_is_hpa() and 3 or 1)
end

function baro_dec_enhanced()
    baro_queue = baro_queue - (baro_unit_is_hpa() and 3 or 1)
end

create_command(
    "FlyWithLua/ToLiss/BARO_inc_enhanced",
    "BARO INC (enhanced)",
    "baro_inc_enhanced()",
    "",
    ""
)

create_command(
    "FlyWithLua/ToLiss/BARO_dec_enhanced",
    "BARO DEC (enhanced)",
    "baro_dec_enhanced()",
    "",
    ""
)


----------------------------
-- ALT 100/1000 INC / DEC (fest gesetzt)
----------------------------
-- AirbusFBW/ALT100_1000: 0=100ft, 1=1000ft. INC -> 1000 (1), DEC -> 100 (0).

function alt_100_1000_inc()
    set_datai("AirbusFBW/ALT100_1000", 1)
end

function alt_100_1000_dec()
    set_datai("AirbusFBW/ALT100_1000", 0)
end

create_command(
    "FlyWithLua/ToLiss/ALT100_1000_INC",
    "ALT100/1000 INC (-> 1000)",
    "alt_100_1000_inc()",
    "",
    ""
)

create_command(
    "FlyWithLua/ToLiss/ALT100_1000_DEC",
    "ALT100/1000 DEC (-> 100)",
    "alt_100_1000_dec()",
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
-- CLOCK: ELAPSED TIME ON/OFF
----------------------------
-- AirbusFBW/ClockETSwitch: 0=on(laeuft), 1=stop, 2=reset
-- Toggle ON(0) <-> OFF/STOP(1). Reset(2) wird beim Umschalten zu ON(0).

function clock_et_toggle()
    toggle_datai01("AirbusFBW/ClockETSwitch")
end

create_command(
    "FlyWithLua/ToLiss/Clock_ET_toggle",
    "Elapsed Time ON/OFF",
    "clock_et_toggle()",
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
-- WX RADAR GAIN INC / DEC (Schritt +/-10, Grenze -150..+120)
----------------------------
-- AirbusFBW/WXRadarGain: 0=Auto, Schritte +/-10

function wx_gain_inc()
    dref_add("AirbusFBW/WXRadarGain", 10, -150, 120)
end

function wx_gain_dec()
    dref_add("AirbusFBW/WXRadarGain", -10, -150, 120)
end

create_command(
    "FlyWithLua/ToLiss/WxGAIN_INC",
    "WxGAIN INC (+10)",
    "wx_gain_inc()",
    "",
    ""
)

create_command(
    "FlyWithLua/ToLiss/WxGAIN_DEC",
    "WxGAIN DEC (-10)",
    "wx_gain_dec()",
    "",
    ""
)


----------------------------
-- WX RADAR TILT INC / DEC (Schritt +/-5, Grenze -120..+120)
----------------------------
-- AirbusFBW/WXRadarTilt: 0=neutral, Schritte +/-5

function wx_tilt_inc()
    dref_add("AirbusFBW/WXRadarTilt", 5, -120, 120)
end

function wx_tilt_dec()
    dref_add("AirbusFBW/WXRadarTilt", -5, -120, 120)
end

create_command(
    "FlyWithLua/ToLiss/WxTILT_INC",
    "WxTILT INC (+5)",
    "wx_tilt_inc()",
    "",
    ""
)

create_command(
    "FlyWithLua/ToLiss/WxTILT_DEC",
    "WxTILT DEC (-5)",
    "wx_tilt_dec()",
    "",
    ""
)


----------------------------
-- WX MULTISCAN TOGGLE
----------------------------
-- AirbusFBW/WXSwitchMultiscan: 0=Manual, 1=Auto

function wx_multiscan_toggle()
    toggle_datai01("AirbusFBW/WXSwitchMultiscan")
end

create_command(
    "FlyWithLua/ToLiss/WX_Multiscan_toggle",
    "WX Multiscan toggle",
    "wx_multiscan_toggle()",
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


----------------------------
-- COCKPIT DOOR OPEN / LOCK
----------------------------
-- ckpt/doorLock: 0=OPEN/UNLOCK, 1=NORM, 2=LOCK

function cockpit_door_norm()
    set_datai("ckpt/doorLock", 1)
end

function cockpit_door_unlock()
    set_datai("ckpt/doorLock", 0)
end

create_command(
    "FlyWithLua/ToLiss/CockpitDoorNorm",
    "COCKPIT DOOR NORM",
    "cockpit_door_norm()",
    "",
    ""
)

-- Command-ID bleibt "CockpitDoorLock" (Zuweisung stabil), setzt jetzt aber UNLOCK (0)
create_command(
    "FlyWithLua/ToLiss/CockpitDoorLock",
    "COCKPIT DOOR UNLOCK",
    "cockpit_door_unlock()",
    "",
    ""
)


----------------------------
-- TRANSPONDER POWER MODE (0..4)
----------------------------
-- AirbusFBW/XPDRPower: 0=STBY, 1=ALT RPTG OFF, 2=XPNDR(ON), 3=TA ONLY, 4=TA/RA

function xpdr_power_set(v)
    set_datai("AirbusFBW/XPDRPower", v)
end

create_command(
    "FlyWithLua/ToLiss/XPDR_STBY",
    "XPNDR STBY (0)",
    "xpdr_power_set(0)",
    "",
    ""
)

create_command(
    "FlyWithLua/ToLiss/XPDR_ALT_RPTG_OFF",
    "XPNDR ALT RPTG OFF (1)",
    "xpdr_power_set(1)",
    "",
    ""
)

create_command(
    "FlyWithLua/ToLiss/XPDR_ON",
    "XPNDR ON (2)",
    "xpdr_power_set(2)",
    "",
    ""
)

create_command(
    "FlyWithLua/ToLiss/XPDR_TA_ONLY",
    "XPNDR TA ONLY (3)",
    "xpdr_power_set(3)",
    "",
    ""
)

create_command(
    "FlyWithLua/ToLiss/XPDR_TA_RA",
    "XPNDR TA/RA (4)",
    "xpdr_power_set(4)",
    "",
    ""
)

----------------------------
-- TRANSPONDER POWER MODE DEC / INC (Encoder, 0..4)
----------------------------
-- DEC -1 (min 0), INC +1 (max 4)

function xpdr_power_dec()
    dref_add("AirbusFBW/XPDRPower", -1, 0, 4)
end

function xpdr_power_inc()
    dref_add("AirbusFBW/XPDRPower", 1, 0, 4)
end

create_command(
    "FlyWithLua/ToLiss/XPDR_Mode_dec",
    "XPNDR Mode DEC (0..4)",
    "xpdr_power_dec()",
    "",
    ""
)

create_command(
    "FlyWithLua/ToLiss/XPDR_Mode_inc",
    "XPNDR Mode INC (0..4)",
    "xpdr_power_inc()",
    "",
    ""
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

-- Schrittweise: DEC -1 (min 0 = ABV), INC +1 (max 2 = BLW)
function tcas_alt_dec()
    if not dr_tcas_alt then return end
    local v = XPLMGetDatai(dr_tcas_alt)
    if v > 0 then XPLMSetDatai(dr_tcas_alt, v - 1) end
end

function tcas_alt_inc()
    if not dr_tcas_alt then return end
    local v = XPLMGetDatai(dr_tcas_alt)
    if v < 2 then XPLMSetDatai(dr_tcas_alt, v + 1) end
end

create_command(
    "FlyWithLua/ToLiss/TCAS_Alt_dec",
    "TCAS ALT DEC",
    "tcas_alt_dec()",
    "",
    ""
)

create_command(
    "FlyWithLua/ToLiss/TCAS_Alt_inc",
    "TCAS ALT INC",
    "tcas_alt_inc()",
    "",
    ""
)


----------------------------
-- RUDDER TRIM DEC / INC (nativer Command + Knopf-Animation)
----------------------------
-- Der native XP-Command trimmt, aber die Knopfstellung ckpt/rudderTrim/anim
-- bewegt sich nicht mit. Daher setzen wir die Animation beim Halten selbst:
-- DEC = links (-29) + rudder_trim_left, INC = rechts (+29) + rudder_trim_right.
-- Beim Loslassen stoppt der Command und der Knopf federt zurueck auf 0 (neutral).

local dr_rudder_trim_anim = nil

function rudder_trim_init()
    if XPLMFindDataRef then
        dr_rudder_trim_anim = XPLMFindDataRef("ckpt/rudderTrim/anim")
    end
end

rudder_trim_init()
if do_on_aircraft_load then
    do_on_aircraft_load("rudder_trim_init()")
end

-- ToLiss setzt ckpt/rudderTrim/anim jeden Frame auf 0 zurueck (federzentriert),
-- ein einzelner Write "verpufft". Solange die Taste gehalten wird, erzwingen
-- wir die Knopfstellung jeden Frame ueber den Enforcer.
local rudder_trim_anim_hold = nil   -- nil = nicht erzwingen

-- Typ-sicher schreiben: anim koennte int ODER float sein. Falscher Accessor
-- tut still nichts -> bei unbekanntem Typ schreiben wir beide.
local function rudder_trim_write(v)
    if not dr_rudder_trim_anim then return end
    local t = (XPLMGetDataRefTypes and XPLMGetDataRefTypes(dr_rudder_trim_anim)) or 0
    local is_int    = (t % 2) >= 1
    local is_float  = (math.floor(t / 2) % 2) >= 1
    local is_double = (math.floor(t / 4) % 2) >= 1
    local vi = (v >= 0) and math.floor(v + 0.5) or math.ceil(v - 0.5)
    if is_float and XPLMSetDataf then
        XPLMSetDataf(dr_rudder_trim_anim, v)
    elseif is_double and XPLMSetDatad then
        XPLMSetDatad(dr_rudder_trim_anim, v)
    elseif is_int and XPLMSetDatai then
        XPLMSetDatai(dr_rudder_trim_anim, vi)
    else
        if XPLMSetDataf then XPLMSetDataf(dr_rudder_trim_anim, v) end
        if XPLMSetDatai then XPLMSetDatai(dr_rudder_trim_anim, vi) end
    end
end

function rudder_trim_enforcer()
    if rudder_trim_anim_hold then
        rudder_trim_write(rudder_trim_anim_hold)
    end
end
-- WICHTIG: Draw-Phase (nicht Flight-Loop), damit unser Write NACH ToLiss' Reset
-- kommt. do_every_frame lief vor ToLiss und wurde sofort ueberschrieben.
do_every_draw("rudder_trim_enforcer()")

local function rudder_trim_release_anim()
    rudder_trim_anim_hold = nil
    rudder_trim_write(0)
end

function rudder_trim_dec_begin()
    rudder_trim_anim_hold = -29
    if command_begin then command_begin("sim/flight_controls/rudder_trim_left") end
end

function rudder_trim_dec_end()
    if command_end then command_end("sim/flight_controls/rudder_trim_left") end
    rudder_trim_release_anim()
end

function rudder_trim_inc_begin()
    rudder_trim_anim_hold = 29
    if command_begin then command_begin("sim/flight_controls/rudder_trim_right") end
end

function rudder_trim_inc_end()
    if command_end then command_end("sim/flight_controls/rudder_trim_right") end
    rudder_trim_release_anim()
end

create_command(
    "FlyWithLua/ToLiss/RudderTrim_dec",
    "RUDDER TRIM DEC",
    "rudder_trim_dec_begin()",
    "",
    "rudder_trim_dec_end()"
)

create_command(
    "FlyWithLua/ToLiss/RudderTrim_inc",
    "RUDDER TRIM INC",
    "rudder_trim_inc_begin()",
    "",
    "rudder_trim_inc_end()"
)






