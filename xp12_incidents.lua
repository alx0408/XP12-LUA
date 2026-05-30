-- ============================================================
--  xp12_incidents.lua
--  Custom Failure & Incident System für X-Plane 12
--  Aircraft: SimCoders B58 REP
--  Requires: FlyWithLua NG+
--
--  Struktur:
--    [1] Framework  - Phasen-Tracking, Hilfsfunktionen
--    [2] Kategorie 1 - Umwelt-Events
--    [3] Kategorie 2 - Pech-Events
--    [4] Kategorie 3 - Latente Fehler
-- ============================================================

math.randomseed(os.time())


-- ============================================================
--  [1] FRAMEWORK
-- ============================================================

-- ---- Flugphasen --------------------------------------------
local PHASE_GROUND   = "ground"
local PHASE_TAKEOFF  = "takeoff"
local PHASE_CLIMB    = "climb"
local PHASE_CRUISE   = "cruise"
local PHASE_DESCENT  = "descent"
local PHASE_APPROACH = "approach"
local PHASE_LANDING  = "landing"

-- DataRefs Flugzustand
dataref("dr_on_ground",  "sim/flightmodel/failures/onground_any")
dataref("dr_airspeed",   "sim/flightmodel/position/indicated_airspeed")
dataref("dr_agl",        "sim/flightmodel/position/y_agl")
dataref("dr_vs",         "sim/flightmodel/position/vh_ind_fpm")
dataref("dr_gs",         "sim/flightmodel/position/groundspeed")

local current_phase = PHASE_GROUND
local was_airborne = false   -- war das Flugzeug zuletzt in der Luft?

local function update_phase()
    local gs_kts = dr_gs * 1.94384   -- Umrechnung m/s → Knoten

    if dr_on_ground == 1 then
        if gs_kts > 5 then
            -- Rollend am Boden: Herkunft entscheidet
            if was_airborne then
                current_phase = PHASE_LANDING   -- kam aus der Luft → Ausrollen
            else
                current_phase = PHASE_TAKEOFF   -- war am Boden → Startlauf
            end
        else
            current_phase = PHASE_GROUND        -- steht oder rollt sehr langsam
            was_airborne = false                -- Reset: sauber für nächsten Start
        end
    else
        -- In der Luft
        was_airborne = true
        if dr_agl < 1000 and dr_vs > 200 then
            current_phase = PHASE_TAKEOFF
        elseif dr_vs > 200 then
            current_phase = PHASE_CLIMB
        elseif dr_agl < 2000 and dr_vs < -100 then
            current_phase = PHASE_APPROACH
        elseif dr_vs < -100 then
            current_phase = PHASE_DESCENT
        else
            current_phase = PHASE_CRUISE
        end
    end
end

-- ---- MTBE-Hilfsfunktion ------------------------------------
local function prob_from_mtbe(mtbe_hours, interval_sec)
    local mtbe_sec = mtbe_hours * 3600
    return interval_sec / mtbe_sec
end

-- ---- Reset bei neuem Flug ----------------------------------
local reset_callbacks = {}

local function register_reset(fn)
    table.insert(reset_callbacks, fn)
end

local function run_resets()
    for _, fn in ipairs(reset_callbacks) do fn() end
end

do_on_airport_load("run_resets()")


-- ============================================================
--  [2] KATEGORIE 1 - UMWELT-EVENTS
-- ============================================================

-- [noch keine DataRefs fuer Bird Strike ermittelt]
-- Module folgen sobald DataRefs bekannt


-- ============================================================
--  [3] KATEGORIE 2 - PECH-EVENTS
-- ============================================================

-- ------------------------------------------------------------
--  Modul: Pitot verstopft (Insekt / Debris)
-- ------------------------------------------------------------   
--  Hinweis:        stumm
--  Manuell:        Command "FWL/incidents/pitot_fail"
--  Gegenmassnahme: toggle
-- ------------------------------------------------------------

dataref("dr_pitot_fail", "sim/operation/failures/rel_pitot", "writable")

local pitot = {
    triggered      = false,
    drifting       = false,
    drift_elapsed  = 0,
    last_check     = 0,
    interval       = 120,   -- Prüfintervall in Sekunden
    mtbe_hours     = 11,    -- mittlere Zeit bis zum Ereignis in Stunden
    drift_duration = 60,    -- sofort ODER schleichend (~60 Sek.) - zufaellig
}
pitot.probability = prob_from_mtbe(pitot.mtbe_hours, pitot.interval)

local function pitot_trigger_immediate()
    dr_pitot_fail   = 6
    pitot.triggered = true
    pitot.drifting  = false
end

local function pitot_reset()
    if dr_pitot_fail == 6 then dr_pitot_fail = 0 end
    pitot.triggered     = false
    pitot.drifting      = false
    pitot.drift_elapsed = 0
    pitot.last_check    = os.clock()
end
register_reset(pitot_reset)

local function pitot_toggle()
    if pitot.triggered or pitot.drifting then
        pitot_reset()       -- bereits aktiv → zurücksetzen
    else
        pitot_trigger_immediate()   -- nicht aktiv → auslösen
    end
end

create_command(
    "FWL/incidents/pitot_fail",
    "Pitot blockiert (manuell, Toggle)",
    "pitot_toggle()",
    "",
    ""
)

local function pitot_tick()
    if pitot.triggered and not pitot.drifting then return end

    if pitot.drifting then
        pitot.drift_elapsed = pitot.drift_elapsed + DELTA_TIME
        if pitot.drift_elapsed >= pitot.drift_duration then
            dr_pitot_fail   = 6
            pitot.drifting  = false
            pitot.triggered = true
        end
        return
    end

    local now = os.clock()
    if (now - pitot.last_check) < pitot.interval then return end
    pitot.last_check = now

    if math.random() > pitot.probability then return end

    if math.random(2) == 1 then
        pitot_trigger_immediate()
    else
        pitot.drifting      = true
        pitot.drift_elapsed = 0
    end
end

do_sometimes("pitot_tick()")


-- ------------------------------------------------------------
--  Modul: Static Port verstopft (Insekt / Debris)
-- ------------------------------------------------------------
--  Hinweis:        stumm
--  Manuell:        Command "FWL/incidents/static_fail"
--  Gegenmassnahme: toggle
-- ------------------------------------------------------------

dataref("dr_static_fail", "sim/operation/failures/rel_static", "writable")

local static = {
    triggered      = false,
    drifting       = false,
    drift_elapsed  = 0,
    last_check     = 0,
    interval       = 120,
    mtbe_hours     = 11,
    drift_duration = 60,
}
static.probability = prob_from_mtbe(static.mtbe_hours, static.interval)

local function static_trigger_immediate()
    dr_static_fail   = 6
    static.triggered = true
    static.drifting  = false
end

local function static_reset()
    if dr_static_fail == 6 then dr_static_fail = 0 end
    static.triggered     = false
    static.drifting      = false
    static.drift_elapsed = 0
    static.last_check    = os.clock()
end
register_reset(static_reset)

local function static_toggle()
    if static.triggered or static.drifting then
        static_reset()
    else
        static_trigger_immediate()
    end
end

create_command(
    "FWL/incidents/static_fail",
    "Static Port verstopft (manuell, Toggle)",
    "static_toggle()",
    "",
    ""
)

local function static_tick()
    if static.triggered and not static.drifting then return end

    if static.drifting then
        static.drift_elapsed = static.drift_elapsed + DELTA_TIME
        if static.drift_elapsed >= static.drift_duration then
            dr_static_fail   = 6
            static.drifting  = false
            static.triggered = true
        end
        return
    end

    local now = os.clock()
    if (now - static.last_check) < static.interval then return end
    static.last_check = now

    if math.random() > static.probability then return end

    if math.random(2) == 1 then
        static_trigger_immediate()
    else
        static.drifting      = true
        static.drift_elapsed = 0
    end
end

do_sometimes("static_tick()")


-- ============================================================
--  [4] KATEGORIE 3 - LATENTE FEHLER
-- ============================================================

-- [Module folgen]


-- ============================================================
--  [5] STATUS-ANZEIGE (Prüfmodus)
-- ============================================================

incidents_show_status = false   -- wird per Makro ein/ausgeschaltet

local function incidents_draw_status()
    if not incidents_show_status then return end

    local x  = 20
    local sy = (SCREEN_HIGHT or SCREEN_HEIGHT or 1080)
    local y  = sy - 60

    -- Titel
    draw_string(x, y,      "[xp12 Incidents]")

    -- Flugphase
    draw_string(x, y - 20, "Phase:  " .. current_phase)

    -- Pitot
    local pitot_text
    if pitot.triggered then
        pitot_text = "AKTIV"
    elseif pitot.drifting then
        local pct = math.floor((pitot.drift_elapsed / pitot.drift_duration) * 100)
        pitot_text = "schleichend (" .. pct .. "%)"
    else
        pitot_text = "OK"
    end
    draw_string(x, y - 40, "Pitot:  " .. pitot_text)

    -- Static Port
    local static_text
    if static.triggered then
        static_text = "AKTIV"
    elseif static.drifting then
        local pct = math.floor((static.drift_elapsed / static.drift_duration) * 100)
        static_text = "schleichend (" .. pct .. "%)"
    else
        static_text = "OK"
    end
    draw_string(x, y - 60, "Static: " .. static_text)
end

do_every_draw("incidents_draw_status()")

add_macro(
    "xp12 Incidents: Status anzeigen",
    "incidents_show_status = true",
    "incidents_show_status = false",
    "deactivate"
)


-- ============================================================
--  FRAMEWORK-TICK (Phasen-Update)
-- ============================================================

do_often("update_phase()")