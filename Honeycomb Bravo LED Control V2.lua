----------------------------------------------------------------------
-- BASIC PRESETS
----------------------------------------------------------------------

local bravo = nil
if type(hid_open) == "function" then
	bravo = hid_open(10571, 6401)
else
	logMsg(os.date('%H:%M:%S ') .. '[Honeycomb Bravo]: ' .. 'ERROR hid_open() not available. Script stopped.')
	return
end

function write_log(message)
	logMsg(os.date('%H:%M:%S ') .. '[Honeycomb Bravo]: ' .. message)
end

if bravo == nil then
	write_log('ERROR No Honeycomb Bravo Throttle Quadrant detected. Script stopped.')
	return
else
	write_log('INFO Honeycomb Bravo Throttle Quadrant detected.')
	write_log('INFO Detected aircraft ICAO: ' .. tostring(PLANE_ICAO))
	write_log('INFO Aircraft filename: ' .. tostring(AIRCRAFT_FILENAME))
end


local bitwise = require 'bit'

-- Helper functions
function int_to_bool(value)
	if value == 0 then
		return false
	else
		return true
	end
end

function get_ap_state(array)
	if array[0] >= 1 then
		return true
	else
		return false
	end
end

function array_has_true(array)
	for i = 0, 7 do
		if array[i] == 1 then
			return true
		end
	end

	return false
end


---------------------------------------------------------------------
-- GLOBAL STATE
---------------------------------------------------------------------

HB_AIRCRAFT_PROFILE = "DEFAULT"

-- LED behaviour toggles (set in AIRCRAFT SETTINGS)
HB_LED_NAV_INCLUDES_GPSS = false
HB_LED_HDG_GA_FILTER = false
HB_LED_USE_GEAR_LEDS = true
HB_LED_USE_HYD_LED = true


---------------------------------------------------------------------
-- AIRCRAFT LOAD HOOK
---------------------------------------------------------------------

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

---------------------------------------------------------------------
-- AIRCRAFT IDENTIFICATION
---------------------------------------------------------------------

function hb_identify_aircraft()
    if PLANE_ICAO == "C172" then
        HB_AIRCRAFT_PROFILE = "C172"
    elseif PLANE_ICAO == "SR22" then
        HB_AIRCRAFT_PROFILE = "SR22"
    elseif PLANE_ICAO == "A20N" then
        HB_AIRCRAFT_PROFILE = "A20N"
    else
        HB_AIRCRAFT_PROFILE = "DEFAULT"
    end

    write_log('INFO Honeycomb Bravo detected aircraft profile: ' .. tostring(HB_AIRCRAFT_PROFILE) .. ' (ICAO=' .. tostring(PLANE_ICAO) .. ')')
end

do_on_aircraft_load("hb_identify_aircraft()")

-- ===== PROBE (temporär): klaert, wie FlyWithLua bei Flugzeugwechsel reagiert =====
-- In X-Plane Log.txt lesen. Beim Wechsel OHNE manuelles Reload:
--   "PROBE body"  erscheint erneut  -> FlyWithLua laedt Skripte komplett neu
--   nur "PROBE hook"                -> do_on_aircraft_load funktioniert (kein Full-Reload)
--   weder noch                      -> kein Hook, manuelles Reload noetig
write_log('PROBE body  (script file executed)')
function hb_load_probe()
    write_log('PROBE hook  (do_on_aircraft_load fired)')
end
do_on_aircraft_load("hb_load_probe()")


---------------------------------------------------------------------
-- VARIABLES DEFINITIONS
---------------------------------------------------------------------

-- ************************* LED DATAREFS *************************

-- Bus voltage as a master LED switch
local bus_voltage = dataref_table('sim/cockpit2/electrical/bus_volts')

-- Autopilot
local hdg  = dataref_table('sim/cockpit2/autopilot/heading_mode')
local nav  = dataref_table('sim/cockpit2/autopilot/nav_status')
local apr  = dataref_table('sim/cockpit2/autopilot/approach_status')
local rev  = dataref_table('sim/cockpit2/autopilot/backcourse_status')
local alt  = dataref_table('sim/cockpit2/autopilot/altitude_hold_status')
local vs   = dataref_table('sim/cockpit2/autopilot/vvi_status')
local ias  = dataref_table('sim/cockpit2/autopilot/autothrottle_on')
local gpss = dataref_table('sim/cockpit2/autopilot/gpss_status')
local ap = dataref_table('sim/cockpit2/autopilot/servos_on')

-- Landing gear LEDs
local gear = dataref_table('sim/flightmodel2/gear/deploy_ratio')

-- Annunciator panel - top row
local master_warn = dataref_table('sim/cockpit2/annunciators/master_warning')
local fire = dataref_table('sim/cockpit2/annunciators/engine_fires')
local oil_low_p = dataref_table('sim/cockpit2/annunciators/oil_pressure_low')
local fuel_low_p = dataref_table('sim/cockpit2/annunciators/fuel_pressure_low')
local anti_ice = dataref_table('sim/cockpit2/annunciators/pitot_heat')
local starter = dataref_table('sim/cockpit2/engine/actuators/starter_hit')
local apu = dataref_table('sim/cockpit2/electrical/APU_running')

-- Annunciator panel - bottom row
local master_caution = dataref_table('sim/cockpit2/annunciators/master_caution')
local vacuum = dataref_table('sim/cockpit2/annunciators/low_vacuum')
local hydro_low_p = dataref_table('sim/cockpit2/annunciators/hydraulic_pressure')
local aux_fuel_pump_l = dataref_table('sim/cockpit2/fuel/transfer_pump_left')
local aux_fuel_pump_r = dataref_table('sim/cockpit2/fuel/transfer_pump_right')
local parking_brake = dataref_table('sim/cockpit2/controls/parking_brake_ratio')
local volt_low = dataref_table('sim/cockpit2/annunciators/low_voltage')
local canopy = dataref_table('sim/flightmodel2/misc/canopy_open_ratio')
local doors = dataref_table('sim/flightmodel2/misc/door_open_ratio')
local cabin_door = dataref_table('sim/cockpit2/annunciators/cabin_door_open')


---------------------------------------------------------------------
-- AIRCRAFT SETTINGS
---------------------------------------------------------------------

function hb_apply_aircraft_settings()
    -- Defaults (generic)
    HB_LED_NAV_INCLUDES_GPSS = false
    HB_LED_HDG_GA_FILTER = false
    HB_LED_USE_GEAR_LEDS = true
    HB_LED_USE_HYD_LED = true

    -- GA overrides (C172 / SR22)
    if HB_AIRCRAFT_PROFILE == "C172" or HB_AIRCRAFT_PROFILE == "SR22" then
        HB_LED_NAV_INCLUDES_GPSS = true
        HB_LED_HDG_GA_FILTER = true
        HB_LED_USE_GEAR_LEDS = false
        HB_LED_USE_HYD_LED = false
    end
end

do_on_aircraft_load("hb_apply_aircraft_settings()")

---------------------------------------------------------------------
-- CORE LED/AP LOGIC
---------------------------------------------------------------------

-- ************************* LED DEFINITIONS *************************

local LED_FCU_HDG =                 {1, 1}
local LED_FCU_NAV =                 {1, 2}
local LED_FCU_APR =                 {1, 3}
local LED_FCU_REV =                 {1, 4}
local LED_FCU_ALT =                 {1, 5}
local LED_FCU_VS  =                 {1, 6}
local LED_FCU_IAS =                 {1, 7}
local LED_FCU_AP  =                 {1, 8}

local LED_LDG_L_GREEN =             {2, 1}
local LED_LDG_L_RED =               {2, 2}
local LED_LDG_N_GREEN =             {2, 3}
local LED_LDG_N_RED =               {2, 4}
local LED_LDG_R_GREEN =             {2, 5}
local LED_LDG_R_RED =               {2, 6}

local LED_ANC_MSTR_WARNG =           {2, 7}
local LED_ANC_ENG_FIRE =             {2, 8}

local LED_ANC_OIL =                  {3, 1}
local LED_ANC_FUEL =                 {3, 2}
local LED_ANC_ANTI_ICE =             {3, 3}
local LED_ANC_STARTER =              {3, 4}
local LED_ANC_APU =                  {3, 5}
local LED_ANC_MSTR_CTN =             {3, 6}
local LED_ANC_VACUUM =               {3, 7}
local LED_ANC_HYD =                  {3, 8}

local LED_ANC_AUX_FUEL =             {4, 1}
local LED_ANC_PRK_BRK =              {4, 2}
local LED_ANC_VOLTS =                {4, 3}
local LED_ANC_DOOR =                 {4, 4}


-- Support variables & functions for sending LED data via HID

local buffer = {}
local master_state = false
local buffer_modified = false

function get_led(led)
	local bank = led[1]
	local bit  = led[2]

	if buffer[bank] == nil then return false end
	if buffer[bank][bit] == nil then return false end
	return buffer[bank][bit]
end

function set_led(led, state)
	local bank = led[1]
	local bit  = led[2]

	if buffer[bank] == nil then buffer[bank] = {} end
	if buffer[bank][bit] == nil then buffer[bank][bit] = false end

	if state ~= buffer[bank][bit] then
		buffer[bank][bit] = state
		buffer_modified = true
	end
end

function all_leds_off()
    for bank = 1, 4 do
        buffer[bank] = {}
        for bit = 1, 8 do
            buffer[bank][bit] = false
        end
    end

    buffer_modified = true
end

function send_hid_data()
    local data = {}

    for bank = 1, 4 do
        data[bank] = 0

        for bit = 1, 8 do
            if buffer[bank][bit] == true then
                data[bank] = bitwise.bor(data[bank], bitwise.lshift(1, bit - 1))
            end
        end
    end

    if type(hid_send_filled_feature_report) ~= "function" then
        logMsg('[Honeycomb Bravo]: ERROR hid_send_filled_feature_report() not available')
        buffer_modified = false
        return
    end

    local bytes_written = hid_send_filled_feature_report(bravo, 0, 65, data[1], data[2], data[3], data[4]) -- 65 = 1 byte (report ID) + 64 bytes (data)

    if bytes_written == -1 then
        logMsg('[Honeycomb Bravo]: ERROR Feature report write failed, an error occurred')
    elseif bytes_written < 65 then
        logMsg('[Honeycomb Bravo]: ERROR Feature report write failed, only '..bytes_written..' bytes written')
    else
        buffer_modified = false
    end
end

-- Initialize our default state
all_leds_off()
send_hid_data()
hid_open(10571, 6401) -- safeguard feature for .joy axes to operate: HID must be reopened 

function handle_led_changes()
    if HB_AIRCRAFT_PROFILE == "A20N" then
        -- A20N: keine LEDs gewuenscht. Guenstiger Check, kein DataRef-Zugriff.
        if master_state == true then
            master_state = false
            all_leds_off()
        end
        if buffer_modified == true then
            send_hid_data()
        end
        return
    end

    if bus_voltage[0] > 0 then
        master_state = true

	  -- reset
	  if HB_FORCE_LED_REFRESH then
    		HB_LAST_LED_STATE = {}
    		HB_FORCE_LED_REFRESH = false
	  end

        -- HDG
        if HB_LED_HDG_GA_FILTER == true and (hdg[0] == 15 or hdg[0] == 13 or hdg[0] == 2) then
            local hdg1 = {}
            hdg1[0] = 0
            set_led(LED_FCU_HDG, get_ap_state(hdg1))
        else
            set_led(LED_FCU_HDG, get_ap_state(hdg))
        end

        -- NAV
        if HB_LED_NAV_INCLUDES_GPSS == true then
            local nav1 = {}
            nav1[0] = nav[0] + gpss[0]
            set_led(LED_FCU_NAV, get_ap_state(nav1))
        else
            set_led(LED_FCU_NAV, get_ap_state(nav))
        end

        -- APR
        set_led(LED_FCU_APR, get_ap_state(apr))

        -- REV
        set_led(LED_FCU_REV, get_ap_state(rev))

        -- ALT
        local alt_bool
        if alt[0] > 1 then
            alt_bool = true
        else
            alt_bool = false
        end
        set_led(LED_FCU_ALT, alt_bool)

        -- VS
        set_led(LED_FCU_VS, get_ap_state(vs))

        -- IAS
        set_led(LED_FCU_IAS, get_ap_state(ias))

        -- AUTOPILOT
        set_led(LED_FCU_AP, int_to_bool(ap[0]))

        -- Landing gear LEDs
        if HB_LED_USE_GEAR_LEDS == true then
            local gear_leds = {}

            for i = 1, 3 do
                gear_leds[i] = {nil, nil} -- green, red

                if gear[i - 1] == 0 then
                    -- Gear stowed
                    gear_leds[i][1] = false
                    gear_leds[i][2] = false
                elseif gear[i - 1] == 1 then
                    -- Gear deployed
                    gear_leds[i][1] = true
                    gear_leds[i][2] = false
                else
                    -- Gear moving
                    gear_leds[i][1] = false
                    gear_leds[i][2] = true
                end
            end

            set_led(LED_LDG_N_GREEN, gear_leds[1][1])
            set_led(LED_LDG_N_RED, gear_leds[1][2])
            set_led(LED_LDG_L_GREEN, gear_leds[2][1])
            set_led(LED_LDG_L_RED, gear_leds[2][2])
            set_led(LED_LDG_R_GREEN, gear_leds[3][1])
            set_led(LED_LDG_R_RED, gear_leds[3][2])
        end

        -- MASTER WARNING
        set_led(LED_ANC_MSTR_WARNG, int_to_bool(master_warn[0]))

        -- ENGINE FIRE
        set_led(LED_ANC_ENG_FIRE, array_has_true(fire))

        -- LOW OIL PRESSURE
        set_led(LED_ANC_OIL, array_has_true(oil_low_p))

        -- LOW FUEL PRESSURE
        set_led(LED_ANC_FUEL, array_has_true(fuel_low_p))

        -- ANTI ICE
        set_led(LED_ANC_ANTI_ICE, not int_to_bool(anti_ice[0]))

        -- STARTER ENGAGED
        set_led(LED_ANC_STARTER, array_has_true(starter))

        -- APU
        set_led(LED_ANC_APU, int_to_bool(apu[0]))

        -- MASTER CAUTION
        set_led(LED_ANC_MSTR_CTN, int_to_bool(master_caution[0]))

        -- VACUUM
        set_led(LED_ANC_VACUUM, int_to_bool(vacuum[0]))

        -- LOW HYD PRESSURE
        if HB_LED_USE_HYD_LED == true then
            set_led(LED_ANC_HYD, int_to_bool(hydro_low_p[0]))
        else
            set_led(LED_ANC_HYD, false)
        end

        -- AUX FUEL PUMP
        local aux_fuel_pump_bool
        if aux_fuel_pump_l[0] == 2 or aux_fuel_pump_r[0] == 2 then
            aux_fuel_pump_bool = true
        else
            aux_fuel_pump_bool = false
        end
        set_led(LED_ANC_AUX_FUEL, aux_fuel_pump_bool)

        -- PARKING BRAKE
        local parking_brake_bool
        if parking_brake[0] > 0 then
            parking_brake_bool = true
        else
            parking_brake_bool = false
        end
        set_led(LED_ANC_PRK_BRK, parking_brake_bool)

        -- LOW VOLTS
        set_led(LED_ANC_VOLTS, int_to_bool(volt_low[0]))

        -- DOOR
        local door_bool = false

        if canopy[0] > 0.01 then
            door_bool = true
        end

        if door_bool == false then
            for i = 0, 9 do
                if doors[i] > 0.01 then
                    door_bool = true
                    break
                end
            end
        end

        if door_bool == false then
            door_bool = int_to_bool(cabin_door[0])
        end

        set_led(LED_ANC_DOOR, door_bool)

    elseif master_state == true then
        -- No bus voltage, disable all LEDs
        master_state = false
        all_leds_off()
    end

    -- If we have any LED changes, send them to the device
    if buffer_modified == true then
        send_hid_data()
    end
end

-- ===== FORCE LED REFRESH COMMAND =====

HB_FORCE_LED_REFRESH = false

function hb_force_led_refresh()
    HB_FORCE_LED_REFRESH = true
end

create_command(
    "FlyWithLua/Honeycomb_Bravo_LED/Force_Update",
    "Force resend of all Bravo LED states",
    "hb_force_led_refresh()",
    "",
    ""
)



HB_LED_TICK_REGISTERED = false

function hb_update_led_tick_registration()
    if HB_AIRCRAFT_PROFILE == "A20N" then
        -- A20N: keine LEDs benoetigt. Einmalig ausschalten.
        -- Tick bleibt unregistriert, falls er noch nie gebraucht wurde;
        -- war er schon aktiv (vorheriges Flugzeug), greift der Guard
        -- oben in handle_led_changes() und haelt die Kosten minimal.
        all_leds_off()
        send_hid_data()
        write_log('INFO A20N detected - Bravo LEDs disabled.')
        return
    end

    if not HB_LED_TICK_REGISTERED then
        do_often("handle_led_changes()")
        HB_LED_TICK_REGISTERED = true
    end
end

do_on_aircraft_load("hb_update_led_tick_registration()")

function exit_handler()
    all_leds_off()
    send_hid_data()
end

do_on_exit('exit_handler()')