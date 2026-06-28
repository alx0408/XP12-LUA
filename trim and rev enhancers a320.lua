---------------------------------------------------------------------
-- HONEYCOMB BRAVO - REVERSER & TRIM ENHANCER
---------------------------------------------------------------------

---------------------------------------------------------------------
-- GLOBAL STATE
---------------------------------------------------------------------

HB_AIRCRAFT_PROFILE = "DEFAULT"
HB_REV1_ACTIVE = false
HB_REV2_ACTIVE = false

----------------------------------------------------------------------
-- AIRCRAFT LOAD HOOK
----------------------------------------------------------------------

-- Some FlyWithLua versions do not provide do_on_aircraft_load().
-- This shim maps to the closest available hook.
if type(do_on_aircraft_load) ~= "function" then
    if type(do_on_aircraft_load_once) == "function" then
        do_on_aircraft_load = do_on_aircraft_load_once
    elseif type(do_on_new_aircraft) == "function" then
        do_on_aircraft_load = do_on_new_aircraft
    else
        -- Last resort: execute immediately (no aircraft-change hook available)
        function do_on_aircraft_load(code)
            if type(code) == "string" then
                if type(do_string) == "function" then
                    do_string(code)
                else
                    local f = loadstring(code)
                    if type(f) == "function" then f() end
                end
            end
        end
    end
end

----------------------------------------------------------------------
-- AIRCRAFT IDENTIFICATION
----------------------------------------------------------------------

function hb_identify_aircraft()
    local descr = get("sim/aircraft/view/acf_descrip")

    -- Prefer PLANE_ICAO (stable at startup); fallback to the dataref if needed.
    local icao = PLANE_ICAO
    if type(icao) ~= "string" or icao == "" then
        icao = get("sim/aircraft/view/acf_ICAO")
    end

    if type(descr) ~= "string" then descr = "" end
    if type(icao)  ~= "string" then icao  = "" end

    -- Identification only. Starts with DEFAULT, then checks.
    HB_AIRCRAFT_PROFILE = "DEFAULT"

    -- Map known ICAO types (acf_ICAO) to profiles
    if icao == "C172" then
        HB_AIRCRAFT_PROFILE = "C172"
    elseif icao == "BE58" then
        HB_AIRCRAFT_PROFILE = "BE58"
    elseif icao == "A20N" then
        HB_AIRCRAFT_PROFILE = "A20N"
    elseif icao == "SR22" then
        HB_AIRCRAFT_PROFILE = "SR22"
    end
end

do_on_aircraft_load("hb_identify_aircraft()")

----------------------------------------------------------------------
-- VARIABLES DEFINITIONS
----------------------------------------------------------------------

HB_TRIM_CMD_UP_PRIMARY = nil
HB_TRIM_CMD_DN_PRIMARY = nil
HB_TRIM_CMD_UP_SECONDARY = nil
HB_TRIM_CMD_DN_SECONDARY = nil

----------------------------------------------------------------------
-- AIRCRAFT SETTINGS
----------------------------------------------------------------------

function hb_apply_aircraft_settings()
    -- Defaults
    HB_TRIM_CMD_UP_PRIMARY = "sim/flight_controls/pitch_trim_up_mech"
    HB_TRIM_CMD_DN_PRIMARY = "sim/flight_controls/pitch_trim_down_mech"
    HB_TRIM_CMD_UP_SECONDARY = nil
    HB_TRIM_CMD_DN_SECONDARY = nil

    -- A20N (ToLiss)
    if HB_AIRCRAFT_PROFILE == "A20N" then
        HB_TRIM_CMD_UP_PRIMARY = "sim/flight_controls/pitch_trim_up"
        HB_TRIM_CMD_DN_PRIMARY = "sim/flight_controls/pitch_trim_down"
        HB_TRIM_CMD_UP_SECONDARY = nil
        HB_TRIM_CMD_DN_SECONDARY = nil
    end
end

do_on_aircraft_load("hb_apply_aircraft_settings()")

----------------------------------------------------------------------
-- TRIM ENHANCER
----------------------------------------------------------------------

HB_TRIM_HELPER_DEBUG = false

HB_TRIM_PULSE_SEC = 0.05
HB_TRIM_PULSES_PER_EVENT = 1

-- Resolve trim commands based on aircraft settings (backup: always defaults to mechanical).
local function hb_get_trim_cmd(direction)
    -- Direction: >0 up, <0 down
    local up_default = "sim/flight_controls/pitch_trim_up_mech"
    local dn_default = "sim/flight_controls/pitch_trim_down_mech"

    local up_cmd = HB_TRIM_CMD_UP_PRIMARY or up_default
    local dn_cmd = HB_TRIM_CMD_DN_PRIMARY or dn_default

    if direction < 0 then return dn_cmd end
    return up_cmd
end

HB_TRIM__ACTIVE = false
HB_TRIM__ACTIVE_CMD = nil
HB_TRIM__END_TIME = 0.0
HB_TRIM__PULSES_LEFT = 0
HB_TRIM__NEXT_CMD = nil

function hb_trim_start_pulse(cmd)
    HB_TRIM__ACTIVE = true
    HB_TRIM__ACTIVE_CMD = cmd
    HB_TRIM__END_TIME = os.clock() + HB_TRIM_PULSE_SEC
    command_begin(cmd)
end

function hb_trim_tick()
    if HB_TRIM__ACTIVE and os.clock() >= HB_TRIM__END_TIME then
        command_end(HB_TRIM__ACTIVE_CMD)
        HB_TRIM__ACTIVE = false
        HB_TRIM__ACTIVE_CMD = nil

        if HB_TRIM__PULSES_LEFT > 0 then
            HB_TRIM__PULSES_LEFT = HB_TRIM__PULSES_LEFT - 1
            hb_trim_start_pulse(HB_TRIM__NEXT_CMD)
        end
    end
end

do_often("hb_trim_tick()")

function trim(direction)
    local cmd = hb_get_trim_cmd(direction)

    HB_TRIM__NEXT_CMD = cmd
    HB_TRIM__PULSES_LEFT = math.max(0, HB_TRIM_PULSES_PER_EVENT - 1)

    if not HB_TRIM__ACTIVE then
        hb_trim_start_pulse(cmd)
    end
end

create_command(
    "FlyWithLua/HoneycombBravo/Pitch trim up (emulated)",
    "Pitch trim up (emulated)",
    "",
    "trim(1)",
    ""
)

create_command(
    "FlyWithLua/HoneycombBravo/Pitch trim down (emulated)",
    "Pitch trim down (emulated)",
    "",
    "trim(-1)",
    ""
)

---------------------------------------------------------------------
-- REVERSER ENGINE 1
---------------------------------------------------------------------

create_command(
    "FlyWithLua/HoneycombBravo/Reverser 1",
    "Reverser 1",
    [[
        if not HB_REV1_ACTIVE then
            command_once("sim/engines/thrust_reverse_toggle_1")
            HB_REV1_ACTIVE = true
        end
    ]],
    "",
    [[
        if HB_REV1_ACTIVE then
            command_once("sim/engines/thrust_reverse_toggle_1")
            HB_REV1_ACTIVE = false
        end
    ]]
)

----------------------------------------------------------------------
-- REVERSER ENGINE 2
----------------------------------------------------------------------

create_command(
    "FlyWithLua/HoneycombBravo/Reverser 2",
    "Reverser 2",
    [[
        if not HB_REV2_ACTIVE then
            command_once("sim/engines/thrust_reverse_toggle_2")
            HB_REV2_ACTIVE = true
        end
    ]],
    "",
    [[
        if HB_REV2_ACTIVE then
            command_once("sim/engines/thrust_reverse_toggle_2")
            HB_REV2_ACTIVE = false
        end
    ]]
)