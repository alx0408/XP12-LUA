---------------------------------------------------------------------
-- AIRCRAFT COMMAND STANDARD MAPPING
---------------------------------------------------------------------

-- Create some lua-commands for similar joystick and keyboard-mapping
-- with different aircraft; XP-commands only no hardware enhancement
-- Key Mapping-Path is AircraftCommands

---------------------------------------------------------------------
-- GLOBAL STATE
---------------------------------------------------------------------

AIRCRAFT_PROFILE = "DEFAULT"

REV1_ACTIVE = false
REV2_ACTIVE = false

----------------------------------------------------------------------
-- AIRCRAFT LOAD HOOK
----------------------------------------------------------------------

if type(do_on_aircraft_load) ~= "function" then
    if type(do_on_aircraft_load_once) == "function" then
        do_on_aircraft_load = do_on_aircraft_load_once
    elseif type(do_on_new_aircraft) == "function" then
        do_on_aircraft_load = do_on_new_aircraft
    else
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

function identify_aircraft()
    local descr = get("sim/aircraft/view/acf_descrip")

    local icao = PLANE_ICAO
    if type(icao) ~= "string" or icao == "" then
        icao = get("sim/aircraft/view/acf_ICAO")
    end

    if type(descr) ~= "string" then descr = "" end
    if type(icao)  ~= "string" then icao  = "" end

    AIRCRAFT_PROFILE = "DEFAULT"

    if icao == "C172" then
        AIRCRAFT_PROFILE = "C172"
    elseif icao == "SR22" then
        AIRCRAFT_PROFILE = "SR22"
    elseif icao == "BE58" then
        AIRCRAFT_PROFILE = "BE58"
    elseif icao == "A20N" then
        AIRCRAFT_PROFILE = "A20N"
    end
end

identify_aircraft()
do_on_aircraft_load("identify_aircraft()")

---------------------------------------------------------------------
-- REVERSER ENGINE 1
---------------------------------------------------------------------

create_command(
    "FlyWithLua/AircraftCommands/Reverser 1",
    "Reverser 1",
    [[
        if not REV1_ACTIVE then
            command_once("sim/engines/thrust_reverse_toggle_1")
            REV1_ACTIVE = true
        end
    ]],
    "",
    [[
        if REV1_ACTIVE then
            command_once("sim/engines/thrust_reverse_toggle_1")
            REV1_ACTIVE = false
        end
    ]]
)

----------------------------------------------------------------------
-- REVERSER ENGINE 2
----------------------------------------------------------------------

create_command(
    "FlyWithLua/AircraftCommands/Reverser 2",
    "Reverser 2",
    [[
        if not REV2_ACTIVE then
            command_once("sim/engines/thrust_reverse_toggle_2")
            REV2_ACTIVE = true
        end
    ]],
    "",
    [[
        if REV2_ACTIVE then
            command_once("sim/engines/thrust_reverse_toggle_2")
            REV2_ACTIVE = false
        end
    ]]
)

---------------------------------------------------------------------
-- FEATHER ENGINE 1 -- BE58 ONLY
---------------------------------------------------------------------

ENGN_PROP = dataref_table("sim/flightmodel/engine/ENGN_prop")

create_command(
    "FlyWithLua/AircraftCommands/Feather 1",
    "Feather 1",
    [[
        if AIRCRAFT_PROFILE ~= "BE58" then return end
        ENGN_PROP[0] = 73.29
    ]],
    "",
    ""
)

----------------------------------------------------------------------
-- FEATHER ENGINE 2 -- BE58 ONLY
----------------------------------------------------------------------

create_command(
    "FlyWithLua/AircraftCommands/Feather 2",
    "Feather 2",
    [[
        if AIRCRAFT_PROFILE ~= "BE58" then return end
        ENGN_PROP[1] = 73.29
    ]],
    "",
    ""
)

---------------------------------------------------------------------
-- AP HDG+NAV ARMED COMBO -- COMBO C172 ONLY
---------------------------------------------------------------------

HDG_NAV_WINDOW = 0.5
HDG_NAV_COOLDOWN = 0.6

last_hdg = -1
last_nav = -1
last_combo_fire = -1

dataref("t", "sim/time/total_running_time_sec", "readonly")

function hdg_pressed()
    if AIRCRAFT_PROFILE ~= "C172" then return end
    last_hdg = t
    check_hdg_nav()
end

function nav_pressed()
    if AIRCRAFT_PROFILE ~= "C172" then return end
    last_nav = t
    check_hdg_nav()
end

function check_hdg_nav()
    if AIRCRAFT_PROFILE ~= "C172" then return end
    if last_hdg < 0 or last_nav < 0 then return end

    if last_combo_fire >= 0 and (t - last_combo_fire) < HDG_NAV_COOLDOWN then
        return
    end

    if math.abs(last_hdg - last_nav) <= HDG_NAV_WINDOW then
        command_once("sim/autopilot/hdg_nav")
        last_combo_fire = t
        last_hdg = -1
        last_nav = -1
    end
end

create_command(
    "FlyWithLua/AircraftCommands/NavMapper",
    "AP NAV Mode (for combo mapping)",
    [[
        command_once("sim/autopilot/NAV")
        nav_pressed()
    ]],
    "",
    ""
)

create_command(
    "FlyWithLua/AircraftCommands/HeadingMapper",
    "AP HDG Mode (for combo mapping)",
    [[
        command_once("sim/autopilot/heading")
        hdg_pressed()
    ]],
    "",
    ""
)