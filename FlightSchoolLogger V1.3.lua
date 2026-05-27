-- Flightschool Telemetry Logger
-- Output: X-Plane 12/Output/Flightschool_Log_YYYYMMDD_HHMMSS.txt

--------------------------------------------------
-- DATAREFS
--------------------------------------------------

dataref("FS_IAS", "sim/flightmodel/position/indicated_airspeed", "readonly")
dataref("FS_GS_MS", "sim/flightmodel/position/groundspeed", "readonly")
dataref("FS_VSI_FPM", "sim/cockpit2/gauges/indicators/vvi_fpm_pilot", "readonly")
dataref("FS_PITCH_DEG", "sim/flightmodel/position/theta", "readonly")
dataref("FS_BANK_DEG", "sim/flightmodel/position/phi", "readonly")
dataref("FS_HDG_TRUE", "sim/flightmodel/position/true_psi", "readonly")
dataref("FS_AGL_M", "sim/flightmodel/position/y_agl", "readonly")
dataref("FS_ALT_MSL_M", "sim/flightmodel/position/elevation", "readonly")
dataref("FS_LAT", "sim/flightmodel/position/latitude", "readonly")
dataref("FS_LON", "sim/flightmodel/position/longitude", "readonly")

dataref("FS_FLAPS_RATIO", "sim/flightmodel2/controls/flap_handle_deploy_ratio", "readonly")
dataref("FS_GEAR_HANDLE", "sim/cockpit2/controls/gear_handle_down", "readonly")

dataref("FS_SLIP_DEG", "sim/cockpit2/gauges/indicators/slip_deg", "readonly")
dataref("FS_RUDDER_IN", "sim/joystick/yoke_heading_ratio", "readonly")
dataref("FS_ELEV_IN", "sim/joystick/yoke_pitch_ratio", "readonly")
dataref("FS_AIL_IN", "sim/joystick/yoke_roll_ratio", "readonly")

dataref("FS_G_NORMAL", "sim/flightmodel/forces/g_nrml", "readonly")
dataref("FS_Q_DEGS", "sim/flightmodel/position/Q", "readonly")
dataref("FS_QDOT_DEGS2", "sim/flightmodel/position/Q_dot", "readonly")
dataref("FS_ONGROUND_ANY", "sim/flightmodel/failures/onground_any", "readonly")
dataref("FS_SIM_PAUSED", "sim/time/paused", "readonly")
dataref("FS_ZULU_TIME_SEC", "sim/time/zulu_time_sec", "readonly")

dataref("FS_WIND_SPEED_KT", "sim/weather/wind_speed_kt", "readonly")
dataref("FS_WIND_DIR_DEG", "sim/weather/wind_direction_degt", "readonly")

FS_RPM = dataref_table("sim/cockpit2/engine/indicators/prop_speed_rpm")
FS_MAP = dataref_table("sim/cockpit2/engine/indicators/MPR_in_hg")
FS_GEAR_DEPLOY = dataref_table("sim/flightmodel2/gear/deploy_ratio")
FS_GEAR_WOW = dataref_table("sim/flightmodel2/gear/on_ground")

--------------------------------------------------
-- STATE
--------------------------------------------------

FS_LOG_ACTIVE = false
FS_START_REQUEST = false
FS_STOP_REQUEST = false

FS_FILE = nil
FS_FILENAME = ""

FS_LAST_SAMPLE = 0
FS_SAMPLE_INTERVAL = 0.25

FS_LAST_FLUSH = 0
FS_FLUSH_INTERVAL = 5.0

FS_STATUS_TEXT = ""
FS_STATUS_UNTIL = 0

FS_WAS_AIRBORNE = true
FS_IN_LANDING_WINDOW = false
FS_TD_TIME = 0
FS_TD_VSI = 0
FS_TD_G = 0
FS_PEAK_G = 0
FS_BOUNCE = false

FS_LEFT_MAIN_TD = nil
FS_RIGHT_MAIN_TD = nil
FS_NOSE_TD = nil

--------------------------------------------------
-- HELPERS
--------------------------------------------------

function fs_time()
    return os.clock()
end

function fs_stamp()
    return os.date("%Y%m%d_%H%M%S")
end

function fs_n(v)
    if v == nil then return 0 end
    return v
end

function fs_set_status(txt)
    FS_STATUS_TEXT = txt
    FS_STATUS_UNTIL = fs_time() + 4.0
    logMsg("[Flightschool Logger] " .. txt)
end

--------------------------------------------------
-- COMMAND CALLBACKS
-- Nur Flags. Keine Dateioperationen im Command.
--------------------------------------------------

function fs_start_command()
    FS_START_REQUEST = true
    FS_STOP_REQUEST = false
    FS_STATUS_TEXT = "Flightschool Logger START requested"
    FS_STATUS_UNTIL = fs_time() + 2.0
    logMsg("[Flightschool Logger] START command received")
end

function fs_stop_command()
    FS_STOP_REQUEST = true
    FS_START_REQUEST = false
    FS_STATUS_TEXT = "Flightschool Logger STOP requested"
    FS_STATUS_UNTIL = fs_time() + 2.0
    logMsg("[Flightschool Logger] STOP command received")
end

--------------------------------------------------
-- FILE HANDLING
--------------------------------------------------

function fs_open_file()
    if FS_FILE ~= nil then return true end

    FS_FILENAME = SYSTEM_DIRECTORY .. "Output/Flightschool_Log_" .. fs_stamp() .. ".txt"

    local ok, file_or_err = pcall(function()
        return io.open(FS_FILENAME, "w")
    end)

    if not ok or file_or_err == nil then
        FS_FILE = nil
        fs_set_status("Flightschool Logger FILE ERROR")
        return false
    end

    FS_FILE = file_or_err

    pcall(function()
        FS_FILE:write("utc_sec;time_s;phase;lat;lon;alt_msl_ft;agl_ft;ias_kt;gs_kt;vsi_fpm;pitch_deg;bank_deg;hdg_true;wind_kt;wind_dir;flaps;gear_handle;gear0;gear1;gear2;rpm1;rpm2;map1;map2;slip_deg;rudder;elevator;aileron;g;q_deg_s;qdot_deg_s2;wow_any;wow0;wow1;wow2\n")
        FS_FILE:flush()
    end)

    return true
end

function fs_close_file()
    if FS_FILE ~= nil then
        pcall(function()
            FS_FILE:flush()
            FS_FILE:close()
        end)
        FS_FILE = nil
    end
end

function fs_start_logger_deferred()
    if FS_LOG_ACTIVE then
        fs_set_status("Flightschool Logger already running")
        return
    end

    if fs_open_file() then
        FS_LOG_ACTIVE = true
        FS_LAST_SAMPLE = fs_time()
        FS_LAST_FLUSH = fs_time()
        fs_set_status("Flightschool Logger START")
    end
end

function fs_stop_logger_deferred()
    if not FS_LOG_ACTIVE then
        fs_set_status("Flightschool Logger already stopped")
        return
    end

    FS_LOG_ACTIVE = false
    fs_close_file()
    fs_set_status("Flightschool Logger STOP")
end

function fs_process_requests()
    if FS_START_REQUEST then
        FS_START_REQUEST = false
        fs_start_logger_deferred()
    end

    if FS_STOP_REQUEST then
        FS_STOP_REQUEST = false
        fs_stop_logger_deferred()
    end
end

--------------------------------------------------
-- LANDING DETECTION
--------------------------------------------------

function fs_reset_landing_state()
    FS_IN_LANDING_WINDOW = false
    FS_TD_TIME = 0
    FS_TD_VSI = 0
    FS_TD_G = 0
    FS_PEAK_G = 0
    FS_BOUNCE = false
    FS_LEFT_MAIN_TD = nil
    FS_RIGHT_MAIN_TD = nil
    FS_NOSE_TD = nil
end

function fs_write_landing_summary()
    if FS_FILE == nil then return end

    local main_delta = -1
    if FS_LEFT_MAIN_TD ~= nil and FS_RIGHT_MAIN_TD ~= nil then
        main_delta = math.abs(FS_LEFT_MAIN_TD - FS_RIGHT_MAIN_TD)
    end

    local nose_delay = -1
    local first_main = nil

    if FS_LEFT_MAIN_TD ~= nil and FS_RIGHT_MAIN_TD ~= nil then
        first_main = math.min(FS_LEFT_MAIN_TD, FS_RIGHT_MAIN_TD)
    elseif FS_LEFT_MAIN_TD ~= nil then
        first_main = FS_LEFT_MAIN_TD
    elseif FS_RIGHT_MAIN_TD ~= nil then
        first_main = FS_RIGHT_MAIN_TD
    end

    if first_main ~= nil and FS_NOSE_TD ~= nil then
        nose_delay = FS_NOSE_TD - first_main
    end

    pcall(function()
        FS_FILE:write(string.format(
            "LANDING_SUMMARY;td_vsi_fpm=%.0f;td_g=%.2f;peak_g_10s=%.2f;main_gear_delta_s=%.2f;nose_delay_s=%.2f;bounce=%s\n",
            FS_TD_VSI,
            FS_TD_G,
            FS_PEAK_G,
            main_delta,
            nose_delay,
            tostring(FS_BOUNCE)
        ))
    end)
end

function fs_update_landing()
    local t = fs_time()
    local agl_ft = FS_AGL_M * 3.28084
    local airborne = (FS_ONGROUND_ANY == 0 and agl_ft > 5)

    if airborne and agl_ft > 300 then
        FS_WAS_AIRBORNE = true
        if not FS_IN_LANDING_WINDOW then
            fs_reset_landing_state()
        end
    end

    if FS_WAS_AIRBORNE and FS_ONGROUND_ANY == 1 and agl_ft < 15 then
        FS_WAS_AIRBORNE = false
        FS_IN_LANDING_WINDOW = true
        FS_TD_TIME = t
        FS_TD_VSI = FS_VSI_FPM
        FS_TD_G = FS_G_NORMAL
        FS_PEAK_G = FS_G_NORMAL
    end

    if FS_IN_LANDING_WINDOW then
        if FS_G_NORMAL > FS_PEAK_G then
            FS_PEAK_G = FS_G_NORMAL
        end

        if fs_n(FS_GEAR_WOW[0]) == 1 and FS_NOSE_TD == nil then FS_NOSE_TD = t end
        if fs_n(FS_GEAR_WOW[1]) == 1 and FS_LEFT_MAIN_TD == nil then FS_LEFT_MAIN_TD = t end
        if fs_n(FS_GEAR_WOW[2]) == 1 and FS_RIGHT_MAIN_TD == nil then FS_RIGHT_MAIN_TD = t end

        if t - FS_TD_TIME < 10 then
            if FS_ONGROUND_ANY == 0 and agl_ft > 3 then
                FS_BOUNCE = true
            end
        else
            fs_write_landing_summary()
            fs_reset_landing_state()
        end
    end
end

--------------------------------------------------
-- SAMPLE LOGGING
--------------------------------------------------

function fs_log_sample()
    if not FS_LOG_ACTIVE then return end
    if FS_FILE == nil then return end

    if FS_SIM_PAUSED == 1 then
    	return
    end

    local t = fs_time()

    if t - FS_LAST_SAMPLE < FS_SAMPLE_INTERVAL then
        return
    end

    FS_LAST_SAMPLE = t
    fs_update_landing()

	local agl_ft = FS_AGL_M * 3.28084
	local alt_msl_ft = FS_ALT_MSL_M * 3.28084
	local gs_kt = FS_GS_MS * 1.94384

    pcall(function()
        FS_FILE:write(string.format(
            "%.0f;%.2f;SAMPLE;%.7f;%.7f;%.1f;%.1f;%.1f;%.1f;%.0f;%.2f;%.2f;%.1f;%.1f;%.1f;%.2f;%d;%.2f;%.2f;%.2f;%.0f;%.0f;%.1f;%.1f;%.2f;%.3f;%.3f;%.3f;%.3f;%.2f;%.2f;%d;%d;%d;%d\n",
            FS_ZULU_TIME_SEC,
	    t,
	    FS_LAT,
	    FS_LON,
	    alt_msl_ft,
	    agl_ft,
	    FS_IAS,
            gs_kt,
            FS_VSI_FPM,
            FS_PITCH_DEG,
            FS_BANK_DEG,
            FS_HDG_TRUE,
	    FS_WIND_SPEED_KT,
	    FS_WIND_DIR_DEG,
            FS_FLAPS_RATIO,
            FS_GEAR_HANDLE,
            fs_n(FS_GEAR_DEPLOY[0]),
            fs_n(FS_GEAR_DEPLOY[1]),
            fs_n(FS_GEAR_DEPLOY[2]),
            fs_n(FS_RPM[0]),
            fs_n(FS_RPM[1]),
            fs_n(FS_MAP[0]),
            fs_n(FS_MAP[1]),
            FS_SLIP_DEG,
            FS_RUDDER_IN,
            FS_ELEV_IN,
            FS_AIL_IN,
            FS_G_NORMAL,
            FS_Q_DEGS,
            FS_QDOT_DEGS2,
            FS_ONGROUND_ANY,
            fs_n(FS_GEAR_WOW[0]),
            fs_n(FS_GEAR_WOW[1]),
            fs_n(FS_GEAR_WOW[2])
        ))
    end)

    if t - FS_LAST_FLUSH > FS_FLUSH_INTERVAL then
        FS_LAST_FLUSH = t
        pcall(function()
            FS_FILE:flush()
        end)
    end
end

--------------------------------------------------
-- DISPLAY
--------------------------------------------------

function fs_draw_status()
    if FS_STATUS_TEXT == "" then return end
    if fs_time() > FS_STATUS_UNTIL then return end

    local x = 1200
    local y = 900

    if SCREEN_WIDTH ~= nil then
        x = SCREEN_WIDTH - 380
    end

    if SCREEN_HEIGHT ~= nil then
        y = SCREEN_HEIGHT - 45
    elseif SCREEN_HIGHT ~= nil then
        y = SCREEN_HIGHT - 45
    end

    draw_string(x, y, FS_STATUS_TEXT)
end

--------------------------------------------------
-- COMMANDS
-- NICHT UMBENENNEN
--------------------------------------------------

create_command(
    "FlyWithLua/Flightschool/StartTelemetryLogger",
    "Starts logging Flightschool telemetry",
    "fs_start_command()",
    "",
    ""
)


create_command(
    "FlyWithLua/Flightschool/StopTelemetryLogger",
    "Stops logging Flightschool telemetry",
    "fs_stop_command()",
    "",
    ""
)

--------------------------------------------------
-- SCHEDULER
--------------------------------------------------

do_often("fs_process_requests()")
do_often("fs_log_sample()")
do_often("fs_draw_status()")
do_on_exit("fs_close_file()")

-- AUTO START LOGGER AFTER AIRCRAFT LOAD
fs_start_logger_deferred()

logMsg("[Flightschool Logger] Script loaded")