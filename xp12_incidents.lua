-- ============================================================
--  xp12_incidents.lua
--  Custom Failure & Incident System für X-Plane 12
--  Aircraft: C172, SR22 (G1000), SimCoders B58 REP
--  Requires: FlyWithLua NG+
--
--  Struktur:
--    [1] Framework  — Config, Profile, Helpers
--    [2] Failures   — Datentabelle, gegliedert wie Config
--    [3] Commands   — Generelle Commands + Per-Failure-Toggle
--    [4] Macro      — Draw-Callback + add_macro
--    [5] Init       — Bootstrap, Tick-Registrierung
-- ============================================================

math.randomseed(os.time())


-- ============================================================
--  [1] FRAMEWORK
-- ============================================================

-- ---- Condition DataRefs ------------------------------------
-- dataref() unterstützt keine [n]-Array-Syntax in FlyWithLua 2.8.x
-- → Arrays direkt über XPLMFindDataRef + XPLMGetDatavi/vf lesen
dataref("dr_on_ground", "sim/flightmodel/failures/onground_any")
dataref("dr_acf_icao",  "sim/aircraft/view/acf_ICAO")

local _ref_engn  = XPLMFindDataRef("sim/flightmodel/engine/ENGN_running")
local _ref_volts = XPLMFindDataRef("sim/cockpit2/electrical/bus_volts")

local function airborne()
    return dr_on_ground == 0
end

local function engine_on()
    if not _ref_engn then return false end
    local v = {}
    XPLMGetDatavi(_ref_engn, v, 0, 2)
    return v[1] == 1 or v[2] == 1
end

local function electrical_on()
    if not _ref_volts then return false end
    local v = {}
    XPLMGetDatavf(_ref_volts, v, 0, 1)
    return (v[1] or 0) > 1
end

-- ---- Config ------------------------------------------------
--
--  cfg.profiles  = { NAME = { icao={...}, failures={KEY={mtbf,fval}} } }
--  cfg.active_*  = nach build_active_profile() gesetzt

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
    elseif main == "ON"      then mtbf = "ON"
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

    -- Fix 5: Werte vor jedem Reload auf Defaults zurücksetzen
    cfg.mode         = "ON"
    cfg.default_mtbf = 10000
    cfg.profiles     = {}
    local section    = nil   -- aktiver Abschnittsname

    for line in file:lines() do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" and not line:match("^#") and not line:match("^%-%-") then

            -- Abschnitts-Header: [NAME]
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
                        -- globale Einstellungen vor erstem Abschnitt
                        if key == "MODE" then
                            local n = tonumber(val)
                            cfg.mode = n and n or val:upper()
                        elseif key == "DEFAULT_MTBF" then
                            local n = tonumber(val)
                            cfg.default_mtbf = (n and n > 0) and n or 10000
                        end
                    else
                        -- Fix 2: MODE/DEFAULT_MTBF nur im globalen Abschnitt gültig
                        if key == "ICAO" then
                            -- kommagetrennte ICAO-Liste
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

-- ---- Aktives Profil auflösen -------------------------------
--  Liest ICAO des geladenen Flugzeugs, sucht passendes Profil,
--  merged DEFAULT + Profil-Overrides in cfg.active_failures.

local function build_active_profile()
    -- Null-Bytes aus Byte-Array-DataRef abschneiden, dann trimmen
    local icao = ((dr_acf_icao or ""):match("^([^%z]*)") or ""):upper():match("^%s*(.-)%s*$")

    -- mit DEFAULT beginnen
    cfg.active_failures = {}
    cfg.active_name     = "DEFAULT"

    local default = cfg.profiles["DEFAULT"]
    if default then
        for k, v in pairs(default.failures) do
            cfg.active_failures[k] = v
        end
    end

    -- passendes Profil suchen (Fix 4: outer loop abbrechenn nach erstem Match)
    local matched = false
    for name, prof in pairs(cfg.profiles) do
        if name ~= "DEFAULT" and not matched then
            for _, pid in ipairs(prof.icao) do
                if pid == icao then
                    for k, v in pairs(prof.failures) do
                        cfg.active_failures[k] = v
                    end
                    cfg.active_name = name
                    matched = true
                    break
                end
            end
        end
    end
end

-- ---- MTBF-Wahrscheinlichkeit -------------------------------
local function prob_from_mtbf(mtbf_hours, interval_sec)
    return interval_sec / (mtbf_hours * 3600)
end

-- ---- Fehlerspeicher ----------------------------------------
-- forward declarations: failures und Helfer werden in [2] definiert
local failures
local get_dr, set_dr, get_mtbf

local MEMORY_PATH    = SCRIPT_DIRECTORY .. "xp12_incidents_memory.txt"
local memory_enabled = false   -- wird nach Bootstrap aktiviert

-- ---- Startup-Popup -----------------------------------------
local inc_popup_from   = nil
local inc_popup_until  = nil
local inc_popup_label  = nil
local inc_popup_armed  = false   -- beim ersten Draw-Frame auf echte Zeit umrechnen

local function inc_trigger_popup(label)
    inc_popup_from  = os.clock()
    inc_popup_until = os.clock() + 5
    inc_popup_label = label
end

local function save_memory()
    if not memory_enabled then return end
    if cfg.active_name == "DEFAULT" then return end

    -- bestehende Datei lesen, andere Profile erhalten
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

    -- neu schreiben
    file = io.open(MEMORY_PATH, "w")
    if not file then return end
    file:write("# xp12_incidents_memory.txt\n# Fehlerspeicher — automatisch generiert\n\n")

    -- aktives Profil
    file:write("[" .. cfg.active_name .. "]\n")
    for _, f in ipairs(failures) do
        if not f.no_memory then
            local v = get_dr(f)
            if v > 0 then
                file:write(f.key .. " = " .. v .. "\n")
            end
        end
    end
    file:write("\n")

    -- übrige Profile
    for _, name in ipairs(order) do
        file:write("[" .. name .. "]\n")
        for _, ln in ipairs(sections[name]) do
            file:write(ln .. "\n")
        end
        file:write("\n")
    end
    file:close()
end

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
                local key, val = line:match("^([%w_]+)%s*=%s*(%d+)$")
                if key and val then
                    key = key:upper()
                    local value = tonumber(val)
                    for _, f in ipairs(failures) do
                        if f.key == key and not f.no_memory and value == 6 then
                            local _, flag = get_mtbf(f)
                            if flag ~= "OFF" then set_dr(f, value) end
                            break
                        end
                    end
                end
            end
        end
    end
    file:close()
end


-- ============================================================
--  [2] FAILURES
-- ============================================================
--
--  Felder pro Eintrag:
--    key       = Config-Key (string, uppercase)
--    dr        = DataRef-Pfad
--    label     = Anzeige-Label (Macro)
--    condition = nil / "airborne" / "engine" / "engine_or_elec"
--    interval  = Prüfintervall (Sekunden)
--    _last     = letzter Prüfzeitpunkt (os.clock)
--    _ref      = XPLMDataRef-Handle (gesetzt bei Init)

local TICK_INTERVAL = 10   -- Sekunden zwischen Failure-Checks
local tick_last     = 0

failures = {}

local function def(key, dr_path, label, condition, no_memory)
    table.insert(failures, {
        key       = key,
        dr        = dr_path,
        label     = label,
        condition = condition,
        no_memory = no_memory,
        _ref      = nil,
    })
end

-- ---- ENVIRONMENT -------------------------------------------
def("VASI",           "sim/operation/failures/rel_vasi",             "VASI",         nil,        true)
def("RWY_LIGHTS",     "sim/operation/failures/rel_rwy_lites",        "Rwy Lights",   nil,        true)
def("BIRD_ENG1",      "sim/operation/failures/rel_bird_strike_eng1", "Bird/Eng1",    "airborne", true)
def("BIRD_ENG2",      "sim/operation/failures/rel_bird_strike_eng2", "Bird/Eng2",    "airborne", true)
def("BIRD_RANDOM",    "sim/operation/failures/rel_bird_strike",      "Bird/Random",  "airborne", true)

-- ---- GENERAL -----------------------------------------------
def("DOOR_OPEN",      "sim/operation/failures/rel_door_open",        "Door Open",    nil)

-- ---- ENGINES -----------------------------------------------
def("ENG_FAIL_1",     "sim/operation/failures/rel_engfai0",          "Eng Fail 1",   "engine")
def("ENG_FAIL_2",     "sim/operation/failures/rel_engfai1",          "Eng Fail 2",   "engine")
def("ENG_FIRE_1",     "sim/operation/failures/rel_engfir0",          "Eng Fire 1",   "engine")
def("ENG_FIRE_2",     "sim/operation/failures/rel_engfir1",          "Eng Fire 2",   "engine")
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
def("OIL_PRESS_LO_1", "sim/operation/failures/rel_eng_lo0",          "OilPressLo 1", nil)
def("OIL_PRESS_LO_2", "sim/operation/failures/rel_eng_lo1",          "OilPressLo 2", nil)
def("ELE_FUEL_PMP_1", "sim/operation/failures/rel_ele_fuepmp0",      "EleFuelPmp 1", nil)
def("ELE_FUEL_PMP_2", "sim/operation/failures/rel_ele_fuepmp1",      "EleFuelPmp 2", nil)
def("FUEL_FLOW_1",    "sim/operation/failures/rel_fuelfl0",          "Fuel Flow 1",  nil)
def("FUEL_FLOW_2",    "sim/operation/failures/rel_fuelfl1",          "Fuel Flow 2",  nil)
def("OIL_PUMP_1",     "sim/operation/failures/rel_oilpmp0",          "Oil Pump 1",   nil)
def("OIL_PUMP_2",     "sim/operation/failures/rel_oilpmp1",          "Oil Pump 2",   nil)
def("AIRFLOW_ENG1",   "sim/operation/failures/rel_airres0",          "Airflow Eng1", nil)
def("AIRFLOW_ENG2",   "sim/operation/failures/rel_airres1",          "Airflow Eng2", nil)

-- ---- PROPELLERS --------------------------------------------
def("PROP_FINE_1",    "sim/operation/failures/rel_prpfin0",          "Prop Fine 1",  nil)
def("PROP_FINE_2",    "sim/operation/failures/rel_prpfin1",          "Prop Fine 2",  nil)
def("PROP_COARSE_1",  "sim/operation/failures/rel_prpcrs0",          "PropCoarse 1", nil)
def("PROP_COARSE_2",  "sim/operation/failures/rel_prpcrs1",          "PropCoarse 2", nil)
def("PROP_SYNC",      "sim/operation/failures/rel_prop_sync",        "Prop Sync",    nil)

-- ---- FUEL --------------------------------------------------
def("FUEL_CAP",       "sim/operation/failures/rel_fuelcap",          "Fuel Cap",     nil)
def("FUEL_LEAK",      "sim/operation/failures/rel_fuel_leak",        "Fuel Leak",    nil)
def("FUEL_WATER",     "sim/operation/failures/rel_fuel_water",       "Fuel Water",   nil)
def("FUEL_TYPE",      "sim/operation/failures/rel_fuel_type",        "Fuel Type",    nil)
def("FUEL_BLOCK_1",   "sim/operation/failures/rel_fuel_block0",      "Fuel Blk 1",   nil)
def("FUEL_BLOCK_2",   "sim/operation/failures/rel_fuel_block1",      "Fuel Blk 2",   nil)

-- ---- ELECTRICAL --------------------------------------------
def("SMOKE",          "sim/operation/failures/rel_smoke_cpit",       "Smoke",        "engine_or_elec")
def("ELEC_BUS1",      "sim/operation/failures/rel_esys",             "Elec Bus 1",   nil)
def("ELEC_BUS2",      "sim/operation/failures/rel_esys2",            "Elec Bus 2",   nil)
def("INVERTER_1",     "sim/operation/failures/rel_invert0",          "Inverter 1",   nil)
def("INVERTER_2",     "sim/operation/failures/rel_invert1",          "Inverter 2",   nil)
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
def("AVIONICS_FAN",   "sim/operation/failures/rel_avionics_fan",     "Avionics Fan", nil)
def("MAGNETOMETER",   "sim/operation/failures/rel_g_magmtr",         "Magnetomtr",   nil)

-- ---- LIGHTS ------------------------------------------------
def("LITES_NAV",      "sim/operation/failures/rel_lites_nav",        "Nav Lights",   nil)
def("LITES_STROBE",   "sim/operation/failures/rel_lites_strobe",     "Strobes",      nil)
def("LITES_BEACON",   "sim/operation/failures/rel_lites_beac",       "Beacon",       nil)
def("LITES_TAXI",     "sim/operation/failures/rel_lites_taxi",       "Taxi Light",   nil)
def("LITES_LANDING",  "sim/operation/failures/rel_lites_land",       "Ldg Lights",   nil)
def("LITES_INST",     "sim/operation/failures/rel_lites_ins",        "Inst Lights",  nil)
def("LITES_COCKPIT",  "sim/operation/failures/rel_clights",          "Cpit Lights",  nil)

-- ---- AUTOPILOT ---------------------------------------------
def("AP_COMPUTER",    "sim/operation/failures/rel_otto",             "AP Computer",  nil)
def("AP_RUNAWAY",     "sim/operation/failures/rel_auto_runaway",     "AP Runaway",   nil)
def("AP_SERVOS",      "sim/operation/failures/rel_auto_servos",      "AP Servos",    nil)
def("AP_SERVO_RUDD",  "sim/operation/failures/rel_servo_rudd",       "AP Srv Rudd",  nil)
def("AP_SERVO_AILN",  "sim/operation/failures/rel_servo_ailn",       "AP Srv Ailn",  nil)
def("AP_SERVO_ELEV",  "sim/operation/failures/rel_servo_elev",       "AP Srv Elev",  nil)

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
def("AHZ_COPILOT",    "sim/operation/failures/rel_cop_ahz",          "AHZ Copilot",  nil)
def("ALT_COPILOT",    "sim/operation/failures/rel_cop_alt",          "ALT Copilot",  nil)
def("G_ASI",          "sim/operation/failures/rel_g_asi",            "G-ASI",        nil)
def("G_ALT",          "sim/operation/failures/rel_g_alt",            "G-ALT",        nil)
def("G_VVI",          "sim/operation/failures/rel_g_vvi",            "G-VVI",        nil)
def("G430_GPS1",      "sim/operation/failures/rel_g430_gps1",        "G430 GPS 1",   nil)
def("G430_GPS2",      "sim/operation/failures/rel_g430_gps2",        "G430 GPS 2",   nil)
def("G430_NAV1",      "sim/operation/failures/rel_g430_rad1_tune",   "G430 Nav 1",   nil)
def("G430_NAV2",      "sim/operation/failures/rel_g430_rad2_tune",   "G430 Nav 2",   nil)
def("G_PFD",          "sim/operation/failures/rel_g_pfd",            "PFD",          nil)
def("G_MFD",          "sim/operation/failures/rel_g_mfd",            "MFD",          nil)
def("WXR_RADAR",      "sim/operation/failures/rel_wxr_radar",        "WX Radar",     nil)
def("G_GIA1",         "sim/operation/failures/rel_g_gia1",           "GIA 1",        nil)
def("G_GIA2",         "sim/operation/failures/rel_g_gia2",           "GIA 2",        nil)
def("G_GEA",          "sim/operation/failures/rel_g_gea",            "GEA",          nil)
def("NAVCOM1",        "sim/operation/failures/rel_navcom1",           "NavCom 1",     nil)
def("NAVCOM2",        "sim/operation/failures/rel_navcom2",           "NavCom 2",     nil)
def("NAV1",           "sim/operation/failures/rel_nav1",             "NAV 1",        nil)
def("NAV2",           "sim/operation/failures/rel_nav2",             "NAV 2",        nil)
def("COM1",           "sim/operation/failures/rel_com1",             "COM 1",        nil)
def("COM2",           "sim/operation/failures/rel_com2",             "COM 2",        nil)
def("ADF1",           "sim/operation/failures/rel_adf1",             "ADF 1",        nil)
def("GPS",            "sim/operation/failures/rel_gps",              "GPS",          nil)
def("DME",            "sim/operation/failures/rel_dme",              "DME",          nil)
def("LOC",            "sim/operation/failures/rel_loc",              "LOC",          nil)
def("GLS",            "sim/operation/failures/rel_gls",              "Glide Slope",  nil)
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

-- ---- SENSORS -----------------------------------------------
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

-- ---- GEAR --------------------------------------------------
def("GEAR_ACT",       "sim/operation/failures/rel_gear_act",         "Gear Act",     nil)
def("GEAR_IND",       "sim/operation/failures/rel_gear_ind",         "Gear Ind",     nil)
def("GEAR_RET_1",     "sim/operation/failures/rel_lagear1",          "Gear Ret 1",   nil)
def("GEAR_RET_2",     "sim/operation/failures/rel_lagear2",          "Gear Ret 2",   nil)
def("GEAR_RET_3",     "sim/operation/failures/rel_lagear3",          "Gear Ret 3",   nil)
def("GEAR_COL_1",     "sim/operation/failures/rel_collapse1",        "Gear Col 1",   nil)
def("GEAR_COL_2",     "sim/operation/failures/rel_collapse2",        "Gear Col 2",   nil)
def("GEAR_COL_3",     "sim/operation/failures/rel_collapse3",        "Gear Col 3",   nil)
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
def("RUD_TRIM_RUN",   "sim/operation/failures/rel_rud_trim_run",      "Rud Trim Run", nil)
def("AIL_TRIM_RUN",   "sim/operation/failures/rel_ail_trim_run",      "Ail Trim Run", nil)
def("ELV_TRIM_RUN",   "sim/operation/failures/rel_elv_trim_run",      "Elv Trim Run", nil)

-- ---- DataRef-Handles ---------------------------------------
local function init_refs()
    for _, f in ipairs(failures) do
        f._ref = XPLMFindDataRef(f.dr)
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

-- ---- Bedingung prüfen --------------------------------------
local function condition_ok(f)
    if     f.condition == "airborne"       then return airborne()
    elseif f.condition == "engine"         then return engine_on()
    elseif f.condition == "engine_or_elec" then return engine_on() or electrical_on()
    end
    return true
end

-- ---- Config-Zugriff für Failure ----------------------------
get_mtbf = function(f)
    local fc = cfg.active_failures[f.key]
    if not fc then return cfg.default_mtbf, nil end
    if fc.mtbf == "OFF"     then return nil, "OFF" end
    if fc.mtbf == "ON"      then return nil, "ON"  end
    if fc.mtbf == "DEFAULT" then return cfg.default_mtbf, nil end
    return fc.mtbf, nil
end

-- ---- Failure auslösen / zurücksetzen -----------------------
local function trigger_failure(f)
    set_dr(f, 6)
    save_memory()
end

local function reset_failure(f)
    if get_dr(f) > 0 then
        set_dr(f, 0)
        save_memory()
    end
end

-- ---- Laufzeit-Toggle (unabhängig von cfg.mode) -------------
local system_paused = false   -- true = manuell pausiert, Memory bleibt erhalten

-- ---- RANDOM-Modus ------------------------------------------
local rnd_scheduled = false
local rnd_fired     = false
local rnd_target    = nil
local rnd_fire_at   = 0
local rnd_pause_at  = nil   -- os.clock() beim Toggle-OFF, für Zeitkorrektur

local function schedule_random()
    if type(cfg.mode) ~= "number" then return end
    local eligible = {}
    for _, f in ipairs(failures) do
        local _, flag = get_mtbf(f)
        if flag ~= "OFF" and get_dr(f) == 0 then table.insert(eligible, f) end
    end
    if #eligible == 0 then return end
    rnd_target    = eligible[math.random(#eligible)]
    -- Fix 1: negative oder 0-Werte für MODE absichern
    local window  = math.max(0, math.floor(cfg.mode * 60))
    rnd_fire_at   = os.clock() + (window > 0 and math.random(0, window) or 0)
    rnd_fired     = false
    rnd_scheduled = true
end


-- ============================================================
--  [3] COMMANDS
-- ============================================================

function incidents_toggle()
    if system_paused then
        -- Resume: RANDOM-Fenster um Pausendauer verschieben, dann Memory laden
        if rnd_pause_at and rnd_scheduled and not rnd_fired then
            rnd_fire_at = rnd_fire_at + (os.clock() - rnd_pause_at)
        end
        rnd_pause_at  = nil
        system_paused = false
        load_memory()
    else
        -- Pause: Zeitstempel merken, DataRefs zurücksetzen, Memory NICHT anfassen
        rnd_pause_at = os.clock()
        local was = memory_enabled
        memory_enabled = false
        for _, f in ipairs(failures) do reset_failure(f) end
        memory_enabled = was
        system_paused = true
    end
    inc_trigger_popup(system_paused and "-- PAUSED --" or "-- ACTIVE --")
end

create_command(
    "FlyWithLua/Incidents/toggle_system",
    "Incidents: System ON/OFF umschalten",
    "incidents_toggle()",
    "", ""
)

function incidents_reset_profile()
    local was_enabled = memory_enabled
    memory_enabled = false          -- Einzel-Saves während Loop unterdrücken
    for _, f in ipairs(failures) do
        reset_failure(f)
    end
    memory_enabled = was_enabled
    save_memory()                   -- bei DEFAULT: No-Op; bei benanntem Profil: geleert,
                                    -- andere Profile in der Datei bleiben erhalten
    rnd_scheduled = false
    rnd_fired     = false
    rnd_target    = nil
    if type(cfg.mode) == "number" then schedule_random() end
    inc_trigger_popup("-- PROFILE RESET --")
end

create_command(
    "FlyWithLua/Incidents/reset_profile",
    "Incidents: Profil zurücksetzen",
    "incidents_reset_profile()",
    "", ""
)

function incidents_reload_config()
    load_config()
    build_active_profile()
    -- Failures die jetzt OFF sind und noch aktiv sind, zurücksetzen
    local was_enabled = memory_enabled
    memory_enabled = false
    for _, f in ipairs(failures) do
        local _, flag = get_mtbf(f)
        if flag == "OFF" then reset_failure(f) end
    end
    memory_enabled = was_enabled
    save_memory()
    rnd_scheduled = false
    rnd_fired     = false
    rnd_target    = nil
    if type(cfg.mode) == "number" then schedule_random() end
    inc_trigger_popup("-- CONFIG RELOADED --")
end

create_command(
    "FlyWithLua/Incidents/reload_config",
    "Incidents: Config neu einlesen",
    "incidents_reload_config()",
    "", ""
)

-- ---- Alle Failures triggern / zurücksetzen -----------------
function incidents_trigger_all()
    local any_active = false
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
    "Incidents: Alle Failures ein/aus",
    "incidents_trigger_all()",
    "", ""
)

-- ---- Per-Failure Toggle ------------------------------------
local function make_toggle(f)
    local fn = "incidents_toggle_" .. f.key:lower()
    _G[fn] = function()
        if get_dr(f) > 0 then reset_failure(f) else trigger_failure(f) end
    end
    create_command(
        "FlyWithLua/Incidents/" .. f.key:lower(),
        "Incidents: Toggle " .. f.label,
        fn .. "()",
        "", ""
    )
end

for _, f in ipairs(failures) do
    make_toggle(f)
end


-- ============================================================
--  [4] MACRO / STATUS
-- ============================================================

incidents_show_status = false

function incidents_draw_status()
    -- Startup-Popup: Timing erst ab erstem Draw-Frame setzen (nicht ab Script-Load)
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
        local bh     = font * (lines + 0.5)
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
    local y   = 40   -- Titel unten links, Failures stapeln sich nach oben

    local mode_str
    if system_paused then
        mode_str = "OFF"
    elseif type(cfg.mode) == "number" then
        mode_str = "RANDOM (" .. cfg.mode .. " min)"
    else
        mode_str = tostring(cfg.mode)
    end

    -- aktive Failures sammeln und nach oben zeichnen
    local active = {}
    for _, f in ipairs(failures) do
        if get_dr(f) == 6 then
            table.insert(active, f.label)
        end
    end
    local top = y + 20 + #active * 20
    local cy  = top
    graphics.set_color(1, 1, 1, 1)
    draw_string_Helvetica_18(x, cy, "[xp12 Incidents]  MODE: " .. mode_str .. "  PROFILE: " .. cfg.active_name)
    cy = cy - 20
    for _, label in ipairs(active) do
        graphics.set_color(1, 0.2, 0.2, 1)
        draw_string_Helvetica_18(x, cy, label .. ":   FAIL")
        cy = cy - 20
    end
end

do_every_draw("incidents_draw_status()")

add_macro(
    "xp12 Incidents: Status",
    "incidents_show_status = true",
    "incidents_show_status = false",
    "deactivate"
)


-- ============================================================
--  [5] INITIALIZATION
-- ============================================================

function incidents_tick()
    local now = os.clock()
    if now - tick_last < TICK_INTERVAL then return end
    tick_last = now
    if system_paused then return end
    if cfg.mode == "OFF" then return end

    if type(cfg.mode) == "number" then
        if rnd_scheduled and not rnd_fired and os.clock() >= rnd_fire_at then
            local f = rnd_target
            if f and condition_ok(f) then
                trigger_failure(f)
                rnd_fired = true
            elseif f then
                -- Fix 3: Bedingung nicht erfüllt → in einem Tick erneut versuchen
                rnd_fire_at = os.clock() + TICK_INTERVAL
            end
        end
        return
    end

    for _, f in ipairs(failures) do
        if get_dr(f) == 0 then
            local mtbf, flag = get_mtbf(f)
            if flag == "ON" and condition_ok(f) then
                trigger_failure(f)
            elseif flag ~= "OFF" and mtbf then
                if math.random() < prob_from_mtbf(mtbf, TICK_INTERVAL) then
                    if condition_ok(f) then trigger_failure(f) end
                end
            end
        end
    end
end

do_sometimes("incidents_tick()")

-- ---- Flugzeugwechsel erkennen ------------------------------
local last_icao = ""

function incidents_aircraft_check()
    local current = ((dr_acf_icao or ""):match("^([^%z]*)") or ""):upper():match("^%s*(.-)%s*$")
    if current ~= "" and current ~= last_icao then
        last_icao = current
        build_active_profile()
        load_memory()
    end
end

do_sometimes("incidents_aircraft_check()")

-- ---- Bootstrap ---------------------------------------------
load_config()
init_refs()
build_active_profile()

-- ON/OFF aus Config anwenden
for _, f in ipairs(failures) do
    local _, flag = get_mtbf(f)
    if     flag == "ON"  then trigger_failure(f)
    elseif flag == "OFF" then reset_failure(f)
    end
end

-- Fehlerspeicher wiederherstellen (überschreibt Config-ON-Einträge)
load_memory()

-- Startmodus aus Config übernehmen
system_paused = (cfg.mode == "OFF")

-- ab jetzt Änderungen speichern
memory_enabled = true

if type(cfg.mode) == "number" then
    schedule_random()
end

-- Startup-Popup: Timing ab erstem Draw-Frame (nicht ab Script-Load)
inc_popup_armed = true

-- ICAO merken damit incidents_aircraft_check() nicht sofort neu aufbaut
last_icao = ((dr_acf_icao or ""):match("^([^%z]*)") or ""):upper():match("^%s*(.-)%s*$")
