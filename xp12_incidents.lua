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

local function update_phase()
    local gs_kts = dr_gs * 1.94384   -- Umrechnung m/s → Knoten
    if dr_on_ground == 1 then
        if gs_kts > 5 and dr_airspeed < 50 then
            current_phase = PHASE_TAKEOFF
        elseif gs_kts > 5 then
            current_phase = PHASE_LANDING
        else
            current_phase = PHASE_GROUND
        end
    else
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
--  MTBE:           ~11 Stunden (0.3% alle 120 Sek.)
--  Onset:          sofort ODER schleichend (~60 Sek.) - zufaellig
--  Gegenmassnahme: keine (permanent bis Reload/Airport load)
--  Hinweis:        stumm
--  Manuell:        Command "FWL/incidents/pitot_fail"
-- ------------------------------------------------------------

dataref("dr_pitot_fail", "sim/operation/failures/rel_pitot", "writable")

local pitot = {
    triggered      = false,
    drifting       = false,
    drift_elapsed  = 0,
    last_check     = 0,
    interval       = 120,
    probability    = prob_from_mtbe(11, 120),
    drift_duration = 60,
}

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

create_command(
    "FWL/incidents/pitot_fail",
    "Pitot blockiert (manuell)",
    "pitot_trigger_immediate()",
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

    pitot.triggered = true
    if math.random(2) == 1 then
        pitot_trigger_immediate()
    else
        pitot.drifting      = true
        pitot.drift_elapsed = 0
    end
end

do_sometimes("pitot_tick()")


-- ============================================================
--  [4] KATEGORIE 3 - LATENTE FEHLER
-- ============================================================

-- [Module folgen]


-- ============================================================
--  FRAMEWORK-TICK (Phasen-Update)
-- ============================================================

do_often("update_phase()")