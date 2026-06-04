---@diagnostic disable: undefined-global, lowercase-global, deprecated, assign-type-mismatch, param-type-mismatch

------------------------------------------------------------
-- 1) GRUNDEINSTELLUNGEN (UI-Position, Schriftgröße, Anzeige-Dauer)
------------------------------------------------------------

-- This defines the font size. Available sizes = 10, 12 or 18.
lrl_FONTSIZE = 18
-- The number of seconds to display the on-screen popup, or -1 for no popup.
lrl_SECONDS_TO_DISPLAY = 20
-- Set lrl_SHOW_TIMER to "true" (show) or "false" (don't show) the float timer
lrl_SHOW_TIMER = true
-- Set lrl_POSTRATE to "true" (write the rate to a file) or "false" (don't write)
lrl_POSTRATE = true

------------------------------------------------------------
-- 2) DATENQUELLEN AUS X-PLANE (DATAREFS) und Zustandsdefinitionen (ARMED, LANDED, ...)
------------------------------------------------------------
require("graphics")

dataref("lrl_vertfpm", "sim/flightmodel/position/vh_ind_fpm", "readonly")
dataref("lrl_gforce", "sim/flightmodel2/misc/gforce_normal", "readonly")
dataref("lrl_boolOnGroundAny", "sim/flightmodel/failures/onground_any", "readonly")
dataref("lrl_boolOnGroundAll", "sim/flightmodel/failures/onground_all", "readonly")
dataref("lrl_agl", "sim/flightmodel/position/y_agl", "readonly")
dataref("lrl_Q", "sim/flightmodel/position/Q", "readonly") -- Pitch-Rate (deg/s)
dataref("lrl_localtime", "sim/time/local_time_sec", "readonly")
dataref("lrl_boolSimPaused", "sim/time/paused", "readonly")
dataref("lrl_boolInReplay", "sim/time/is_in_replay", "readonly")

dataref("lrl_parkingBrake", "sim/cockpit2/controls/parking_brake_ratio", "readonly")
dataref("lrl_windDir", "sim/cockpit2/gauges/indicators/wind_heading_deg_mag", "readonly")
dataref("lrl_windSpd", "sim/cockpit2/gauges/indicators/wind_speed_kts", "readonly")

-- Zustandsdefinitionen
lrl_ARMED = 0
lrl_LANDED = 1
lrl_STEERINGDN = 2
lrl_STANDBY = 3

-- Umwandlung X-Plane Bool-Datarefs in echte Lua-Bools
lrl_logAnyWheel   = lrl_boolOnGroundAny == 1 and true or false
lrl_logAllWheels  = lrl_boolOnGroundAll == 1 and true or false
lrl_SimPaused     = lrl_boolSimPaused == 1 and true or false
lrl_ParkingBrake  = (lrl_parkingBrake or 0) >= 0.99 and true or false
lrl_InReplay      = lrl_boolInReplay == 1 and true or false

------------------------------------------------------------
-- 3) MESS-SPEICHER (ROLLING BUFFER)
-- Zweck: Ein kleines Hilfsmodul, das gleitende Zeitfenster (Listen) für
--        Messreihen anlegt. So können wir Verläufe/Peaks betrachten.
------------------------------------------------------------

function new_table(tn, samples)
	-- make samples an optional argument
	samples = samples or 10
	tn = tostring(tn)

	local code = ""
	code = code .. "values_axis_" .. tn .. " = {}\n"
	code = code .. "ts_axis_" .. tn .. " = {}\n"
	code = code .. "function init_" .. tn .. "()\n"
	code = code .. "    values_axis_" .. tn .. " = {}\n"
	code = code .. "    ts_axis_" .. tn .. " = {}\n"
	code = code .. "end\n"
	code = code .. "init_" .. tn .. "()\n"
	code = code .. "function calcAvg_" .. tn .. "()\n"
	code = code .. "    local avg = 0\n"
	code = code .. "    if #values_axis_" .. tn .. " > 0 then\n"
	code = code .. "        for i = " .. samples .. ", 1, -1 do\n"
	code = code .. "            avg = avg + (values_axis_" .. tn .. "[i] or 0)\n"
	code = code .. "        end\n"
	code = code .. "        avg = avg / #values_axis_" .. tn .. "\n"
	code = code .. "    end\n"
	code = code .. "    return avg\n"
	code = code .. "end\n"
	code = code .. "function calcDeviation_" .. tn .. "()\n"
	code = code .. "    local prev\n"
	code = code .. "    local d = 0\n"
	code = code .. "    if #values_axis_" .. tn .. " > 0 then\n"
	code = code .. "        for i = " .. samples .. ", 1, -1 do\n"
	code = code .. "            if values_axis_" .. tn .. "[i] then\n"
	code = code .. "                if prev then\n"
	code = code .. "                    local diff = values_axis_" .. tn .. "[i] - prev\n"
	code = code .. "                    d = d + diff\n"
	code = code .. "                end\n"
	code = code .. "                prev = values_axis_" .. tn .. "[i]\n"
	code = code .. "            end\n"
	code = code .. "        end\n"
	code = code .. "        d = d / (#values_axis_" .. tn .. " - 1)\n"
	code = code .. "    end\n"
	code = code .. "    return d\n"
	code = code .. "end\n"
	code = code .. "function calcTime_" .. tn .. "()\n"
	code = code .. "    local d = 0\n"
	code = code .. "    if #ts_axis_" .. tn .. " > 1 then\n"
	code = code .. "        d = ts_axis_" .. tn .. "[1] - ts_axis_" .. tn .. "[#ts_axis_" .. tn .. "]\n"
	code = code .. "    end\n"
	code = code .. "    return d\n"
	code = code .. "end\n"
	code = code .. "function pushValue_" .. tn .. "(value, ts)\n"
	code = code .. "    ts = ts or os.clock()\n"
	code = code .. "    for i = " .. samples .. ", 2, -1 do\n"
	code = code .. "        values_axis_" .. tn .. "[i] = values_axis_" .. tn .. "[i-1]\n"
	code = code .. "        ts_axis_" .. tn .. "[i] = ts_axis_" .. tn .. "[i-1]\n"
	code = code .. "    end\n"
	code = code .. "    values_axis_" .. tn .. "[1] = value\n"
	code = code .. "    ts_axis_" .. tn .. "[1] = ts\n"
	code = code .. "end\n"

	assert(loadstring(code))()
end

-- Recorder
new_table("lrl_agl", 30)         -- AGL für gVS
new_table("lrl_landingG", 30)    -- G um t0
new_table("lrl_gVS", 30)         -- gVS um t0
new_table("lrl_wdir", 180)       -- Windrichtung während Float
new_table("lrl_wspd", 180)       -- Windgeschwindigkeit während Float

------------------------------------------------------------
-- 4) BEGRÜßUNG & INITIALISIERUNG
------------------------------------------------------------

-- Anzeige
lrl_popupText     = { "", "Landing Rate v4.2 (ALx)", "Based on Dan Berry v1.83" }
lrl_showUntil     = 0
lrl_logDisplayOn  = false
lrl_popupState    = lrl_STEERINGDN
lrl_startup_armed = true

-- Landing-Rate 
lrl_landingRate   = nil
lrl_landingG      = nil

-- Flare
lrl_qAdj          = nil
lrl_noseRate      = nil
lrl_floatTimer    = 0
lrl_floatFinal    = 0
lrl_loggedThisLanding = false

-- Touchdown-Stabilitätsprüfung
lrl_tdCandidateStart = nil
lrl_tdOnCount, lrl_tdTotalCount = 0, 0

-- Bounce-Tracking & Peak-G
lrl_bounceAirborneStart = nil
lrl_bounced             = false
lrl_peakG_allTouches    = nil
lrl_prevAnyWheel        = lrl_logAnyWheel

-- Wind-Tracking für Float
lrl_wdirStart      = nil
lrl_wspdStart      = nil
lrl_windDirDelta   = 0
lrl_windSpdDelta   = 0
lrl_windFrozen = false
lrl_wdirStop   = nil
lrl_wspdStop   = nil


------------------------------------------------------------
-- 5) LOGGING
------------------------------------------------------------

function lrl_postLandingRate()
	local d = os.date("%Y-%m-%d %H:%M:%S")
	-- Guard: avoid logging empty/default rows
	if (lrl_landingRate or 0) == 0 and (lrl_landingG or 0) == 0 then return end
	local s = string.format(
		'%s,%s,"%s",%.2f,%.2f,%.2f,"%s",%.2f,%.2f,%.2f,%.2f,%s,%.0f,%.1f',
		d,                            -- 1 Timestamp
		tostring(PLANE_ICAO or ""),   -- 2 Aircraft
		tostring(lrl_computeLandingRating(lrl_landingRate) or ""), -- 3 LandingRateCode (LR_...)
		tonumber(lrl_landingRate or 0),       -- 4 VerticalSpeed_FPM
		tonumber(lrl_landingG or 0),          -- 5 LandingG (t0-Fenster)
		tonumber(lrl_peakG_allTouches or 0),  -- 6 PeakG_AllTouches (globales Max)
		tostring(lrl_popupText[3] or ""),     -- 7 FlareText (Popup-Zeile 3)
		tonumber(lrl_qAdj or lrl_Q or 0),     -- 8 Q @ t0 (deg/s)
		0.0,                                   -- 9 reserved (was Q-Dot); fixed 0.0
		tonumber(lrl_noseRate or 0),          -- 10 NoseRate
		tonumber(lrl_floatFinal or 0),        -- 11 FloatTime_s
		(lrl_bounced and "BOUNCE" or ""),   -- 12 BounceFlag
		tonumber(lrl_windDirDelta or 0),      -- 13 Delta Windrichtung (deg, signed)
		tonumber(lrl_windSpdDelta or 0)       -- 14 Delta Windgeschw. (kt, signed)
	)

	logMsg(string.format("%s Landing Rate: %s", d, s))
	if lrl_POSTRATE then
		io.output(io.open("LandingRate.log", "a"))
		io.write(s, "\n")
		io.close()
	end
end

------------------------------------------------------------
-- 6) ANZEIGEBOX
------------------------------------------------------------

function lrl_loopCallback()

	-- startup popup: defer timing to first draw frame
	if lrl_startup_armed then
		lrl_showUntil    = os.clock() + 5
		lrl_logDisplayOn = true
		lrl_startup_armed = false
	end

	-- 1) Werte aktualisieren
	lrl_updateLandingResult()
	XPLMSetGraphicsState(0, 0, 0, 1, 1, 0, 0)

	-- 2) Anzeige nur bei aktivem Zeitfenster und nicht im Replay
	if (os.clock() < lrl_showUntil and lrl_logDisplayOn) then
		if (not lrl_InReplay or lrl_forceShowInReplay) then
			-- Box-Geometrie
			local boxWidth  = lrl_FONTSIZE * 21
			local boxHeight = lrl_FONTSIZE * 6.3
			local yspacing  = lrl_FONTSIZE * 1.23
			local yoffset   = yspacing * 4
			local ypos      = SCREEN_HIGHT - boxHeight - 400
			local xpos      = SCREEN_WIDTH - boxWidth - 40

			-- Hintergrund
			graphics.set_color(0.0, 0.0, 0.0, 0.3)
			graphics.draw_rectangle(xpos, ypos, xpos + boxWidth, ypos + boxHeight)

	-- 3) Anzeige-Zeilen:
	--    Zeile 1 (blinkend, farbig): Landing-Rating (Mapping aus Abschnitt 7)
	--    Zeile 2 (weiß): Vertical Speed & G (popupText[2])
	--    Zeile 3 (weiß): Flare-Text (popupText[3])
	local lr_code = lrl_computeLandingRating(lrl_landingRate)
	local m = LR_MAP[lr_code] or LR_MAP[LR_CODE.NONE]
	local line1 = m.label
	local line2 = lrl_popupText[2]
	local line3 = lrl_popupText[3]
	local display = { line1, line2, line3 }

	for x = 0, 2 do
		local text = display[x + 1]
		if text and text ~= "" then
			local xoffset = (boxWidth - measure_string(text, "Helvetica_" .. lrl_FONTSIZE)) * 0.5
			local tx = xpos + xoffset
			local ty = ypos + yoffset - (x * yspacing)

			if x == 0 then
				-- Zeile 1: farbig + blinkend + Kontur
				graphics.set_color(m.r, m.g, m.b, m.a)
				if os.clock() % 0.5 >= 0.25 then
					local code = string.format("draw_string_Helvetica_%d(%f, %f, '%s');\n", lrl_FONTSIZE, tx, ty, text)
					code = code .. string.format("draw_string_Helvetica_%d(%f, %f, '%s');\n", lrl_FONTSIZE, tx + 1, ty, text)
					assert(loadstring(code))()
				end
			else
				-- Zeile 2–3: weiß, ohne Blinken
				graphics.set_color(1.0, 1.0, 1.0, 1.0)
				local code = string.format("draw_string_Helvetica_%d(%f, %f, '%s');\n", lrl_FONTSIZE, tx, ty, text)
				assert(loadstring(code))()
			end
		end
	end

	local line4 = lrl_popupText[4]
	if line4 and line4 ~= "" then
		local xoffset = (boxWidth - measure_string(line4, "Helvetica_" .. lrl_FONTSIZE)) * 0.5
		local tx = xpos + xoffset
		local ty = ypos + yoffset - (3 * yspacing)
		graphics.set_color(1.0, 1.0, 1.0, 1.0)
		local code = string.format("draw_string_Helvetica_%d(%f, %f, '%s');\n", lrl_FONTSIZE, tx, ty, line4)
		assert(loadstring(code))()
	end

		end
	end

	-- 4) Anzeige nach Timeout ausblenden und ggf. Zustand auf STANDBY
	if lrl_popupState ~= lrl_ARMED and os.clock() > lrl_showUntil then
		lrl_logDisplayOn = false
		if lrl_landingRate == 1 then lrl_landingRate = nil end
		if lrl_popupState == lrl_STEERINGDN then lrl_popupState = lrl_STANDBY end
	end

	-- 5) Darstellung in Pause (Parking Brake aus)
	if (lrl_SimPaused and not lrl_ParkingBrake) then
		-- kurze Verlängerung nach Unpause
		lrl_showUntil = os.clock() + 0.1
		lrl_logDisplayOn = true

		-- Wenn noch keine Messwerte existieren, zeige eine neutrale Begrüßung
		if (lrl_landingRate == nil and (lrl_popupText == nil or #lrl_popupText == 0)) then
			lrl_popupText = { "", "Landing Rate v2.0 (ALx)", "Based on Dan Berry v1.83" }
		elseif (lrl_landingRate ~= nil and lrl_landingRate <= 0) then
			lrl_populatePopupStats()
		end
		return
	end

	-- 6) Darstellung im Replay (Parking Brake gesetzt)
	if lrl_InReplay then
		if lrl_ParkingBrake then
			lrl_forceShowInReplay = true            -- erlaubt das Zeichnen trotz Replay
			lrl_showUntil = os.clock() + 0.1       -- kurz "lebendig" halten
			lrl_logDisplayOn = true                -- Anzeige aktivieren
		else
			lrl_forceShowInReplay = false
			lrl_logDisplayOn = false
			lrl_showUntil = os.clock()             -- sofort ausblenden
		end
	else
		lrl_forceShowInReplay = false
	end
end

------------------------------------------------------------
-- 7) LANDING-RATING
------------------------------------------------------------

LR_CODE = {
	BUTTER     = "LR_BUTTER",
	GREAT      = "LR_GREAT",
	REGULAR    = "LR_REGULAR",
	ACCEPTABLE = "LR_ACCEPTABLE",
	HARD       = "LR_HARD",
	WASTED     = "LR_WASTED",
	NONE       = "LR_NONE",
}

LR_MAP = {
	[LR_CODE.BUTTER]     = { label = "BUTTER!",         r=1.00, g=1.00, b=0.00, a=1.00 },
	[LR_CODE.GREAT]      = { label = "GREAT LANDING!",  r=0.25, g=1.00, b=0.25, a=1.00 },
	[LR_CODE.REGULAR]    = { label = "REGULAR",         r=0.00, g=1.00, b=0.00, a=1.00 },
	[LR_CODE.ACCEPTABLE] = { label = "ACCEPTABLE",      r=0.00, g=1.00, b=0.00, a=1.00 },
	[LR_CODE.HARD]       = { label = "HARD LANDING!",   r=1.00, g=0.50, b=0.00, a=1.00 },
	[LR_CODE.WASTED]     = { label = "* WASTED! *",     r=1.00, g=0.00, b=0.00, a=1.00 },
	[LR_CODE.NONE]       = { label = "",                r=1.00, g=1.00, b=1.00, a=1.00 },
}

-- Matrix-basierte Profile
local LRL_PROFILES = {
	DEFAULT = {
		class = "GA",
		thresholds = {
			BUTTER_MAX     = -125,
			GREAT_MAX      = -250,
			ACCEPTABLE_MAX = -350,
			HARD_MAX       = -600,
		},
	},

	GA = {},  -- General Aviation nutzt DEFAULT (keine abweichenden Schwellen)

	Airliner = {  -- Klassen-Defaults (Airliner)
		thresholds = {
			BUTTER_MAX     = -125,
			GREAT_MAX      = -250,
			REGULAR_MAX    = -400,
			ACCEPTABLE_MAX = -600,
			HARD_MAX       = -750,
		},
	},

	-- Spezifisches Muster: Beechcraft Baron 58
	BE58 = {
		class = "GA",
		thresholds = {
			BUTTER_MAX     = -100,
			GREAT_MAX      = -150,
			ACCEPTABLE_MAX = -250,
			HARD_MAX       = -350,
		},
	},
}

-- Ermittelt das aktive Profil (ICAO → Klassenprofil → DEFAULT) und merged flach
local function lrl_getProfile()
	local icao = tostring(PLANE_ICAO or ""):upper()
	-- Klassenbestimmung wie bisher: A320/A20N als Airliner, sonst GA
	local class = (icao == "A320" or icao == "A20N") and "Airliner" or "GA"

	local base    = LRL_PROFILES.DEFAULT or {}
	local byClass = LRL_PROFILES[class] or {}
	local byIcao  = LRL_PROFILES[icao] or {}

	local merged = { class = byIcao.class or byClass.class or base.class or class }
	merged.thresholds = {}
	-- DEFAULT → Klasse → ICAO (spätere überschreiben frühere)
	for k,v in pairs(base.thresholds or {})    do merged.thresholds[k] = v end
	for k,v in pairs(byClass.thresholds or {}) do merged.thresholds[k] = v end
	for k,v in pairs(byIcao.thresholds or {})  do merged.thresholds[k] = v end
	return merged
end

function lrl_computeLandingRating(rate)
	if rate == nil then return LR_CODE.NONE end
	local profile = lrl_getProfile()
	local T = profile.thresholds or {}

	if (rate >= (T.BUTTER_MAX or -125)) and (rate <= 0) then
		return LR_CODE.BUTTER
	end
	if (rate >= (T.GREAT_MAX or -250)) and (rate < (T.BUTTER_MAX or -125)) then
		return LR_CODE.GREAT
	end
	-- Optionaler REGULAR-Range (nur wenn im Profil vorhanden)
	if T.REGULAR_MAX and (rate >= T.REGULAR_MAX) and (rate < (T.GREAT_MAX or -250)) then
		return LR_CODE.REGULAR
	end
	if (rate >= (T.ACCEPTABLE_MAX or -350)) and (rate < (T.GREAT_MAX or -250)) then
		return LR_CODE.ACCEPTABLE
	end
	if (rate >= (T.HARD_MAX or -600)) and (rate < (T.ACCEPTABLE_MAX or -350)) then
		return LR_CODE.HARD
	end
	if (rate < (T.HARD_MAX or -600)) then
		return LR_CODE.WASTED
	end
	return LR_CODE.NONE
end

------------------------------------------------------------
-- 8) WERTE FÜR ANZEIGE UND LOG EINLESEN
------------------------------------------------------------

function lrl_populatePopupStats()
	-- Zeile 2: VS/G
	lrl_popupText[2] = string.format("%.2fFPM / %.2fG", lrl_landingRate or 0, lrl_landingG or 0)

	-- Zeile 3: Flare-Bewertung (nur mit Pitch-Rate, deg/s) + ggf. BOUNCE-Hinweis
	local qAdj  = lrl_qAdj or 0
	local qRate = math.abs(qAdj)
	local base
	if qRate < 1.0 then
		base = "Very good flare."
	elseif qRate <= 2.5 then
		base = "Good flare."
	else
		base = "" -- >2.5: keine Flare-Kommentierung
	end
	if lrl_bounced then
		local peakAll = lrl_peakG_allTouches or lrl_landingG or 0
		local appendix = string.format(" BOUNCE (%.1f G)", peakAll)
		base = (base ~= "" and (base .. appendix)) or (string.format("BOUNCE (%.1f G)", peakAll))
	end
	lrl_popupText[3] = base

	-- Zeile 4: Wind-Änderungen (Delta Richtung/Speed) als Popup-Text 4
	-- Berechnung hier in §8; Werte werden zusätzlich in Variablen für das Log abgelegt
	local wdir_start = lrl_wdirStart
	local wspd_start = lrl_wspdStart
	local wdir_now   = (lrl_windFrozen and lrl_wdirStop) or lrl_windDir
	local wspd_now   = (lrl_windFrozen and lrl_wspdStop) or lrl_windSpd

	local ddir, dspd = 0, 0
	if wdir_start ~= nil and wdir_now ~= nil then
		ddir = (wdir_now - wdir_start)
		while ddir > 180 do ddir = ddir - 360 end
		while ddir < -180 do ddir = ddir + 360 end
	end
	if wspd_start ~= nil and wspd_now ~= nil then
		dspd = (wspd_now - wspd_start)
	end
	lrl_windDirDelta = ddir
	lrl_windSpdDelta = dspd
	lrl_popupText[4] = string.format("\226\136\134WindDir %+.0f\194\176  |  \226\136\134Wind %+.1f kt", ddir, dspd)
end

-- Hilfsfunktionen: Fenster um t0 aus Rolling-Buffer

local function lrl_minVS_around(t0, pre, post)
	pre = pre or 0.12 -- Sekunden vor t0
	post = post or 0.03 -- Sekunden nach t0
	local minvs
	if #values_axis_lrl_gVS > 0 then
		for i = 1, #values_axis_lrl_gVS do
			local ts = ts_axis_lrl_gVS[i]
			local v  = values_axis_lrl_gVS[i]
			if ts and v and ts >= (t0 - pre) and ts <= (t0 + post) then
				if (minvs == nil) or (v < minvs) then minvs = v end
			end
		end
	end
	return minvs or calcAvg_lrl_gVS()
end

local function lrl_peakG_around(t0, pre, post)
	pre = pre or 0.10 -- Sekunden vor t0
	post = post or 0.20 -- Sekunden nach t0
	local peak
	if #values_axis_lrl_landingG > 0 then
		for i = 1, #values_axis_lrl_landingG do
			local ts = ts_axis_lrl_landingG[i]
			local g  = values_axis_lrl_landingG[i]
			if ts and g and ts >= (t0 - pre) and ts <= (t0 + post) then
				local a = math.abs(g)
				if not peak or a > peak then peak = a end
			end
		end
	end
	return peak or calcAvg_lrl_landingG()
end

------------------------------------------------------------
-- 9) KERNLOGIK / ABLAUF
-- Zweck: Erkennt Aufsetzen, hält Messwerte fest, berechnet Texte,
--        steuert Zustandswechsel und Display-Fenster.
------------------------------------------------------------

function lrl_updateLandingResult()
	local osts = os.clock()

	-- gVS berechnen (aus AGL-Buffer)
	local aglAvg      = calcAvg_lrl_agl()
	local aglTimeslice = calcTime_lrl_agl()
	local aglMidpoint = lrl_agl - aglAvg
	local gVS         = (aglMidpoint / (aglTimeslice / 2)) * 196.85
	butterball_gVS    = gVS

	-- Debug
	if lrl_DEBUG then
		if gVS > 0 then graphics.set_color(0.0, 1.0, 0.0, 1.0) else graphics.set_color(1.0, 0.0, 0.0, 1.0) end
		draw_string_Helvetica_18(100, 120, string.format("lrl_landingRate: %s | lrl_noseRate: %s | lrl_floatFinal: %s",
			tostring(lrl_landingRate), tostring(lrl_noseRate), tostring(lrl_floatFinal)))
		draw_string_Helvetica_18(100, 100, string.format("agl: %.2f  VSI: %d | DisplayOn: %s   lrl_popupState: %d",
			lrl_agl, lrl_vertfpm, tostring(lrl_logDisplayOn), lrl_popupState))
		if #values_axis_lrl_agl > 0 then
			draw_string_Helvetica_18(100, 80, string.format("aglAvg: %.2f (%+.3fm in %.2fs = %+.2f FPM)",
				aglAvg, aglMidpoint, aglTimeslice, gVS))
		else
			draw_string_Helvetica_18(100, 80, "Recorder drained")
		end
		draw_string_Helvetica_18(100, 60, string.format("Q: %.2f", lrl_Q))
		if lrl_floatTimer ~= 0 then
			draw_string_Helvetica_18(100, 40, string.format("CAT IIIB timer: %.2f secs", osts - lrl_floatTimer))
		end
	end

	-- Reset/Arming > 15 m AGL (außer Replay)
	if lrl_popupState ~= lrl_ARMED and lrl_agl > 15 and not lrl_InReplay then
		if #values_axis_lrl_agl ~= 0 then
			init_lrl_agl()
			init_lrl_landingG()
		end
		lrl_landingRate = nil
		lrl_landingG = nil
		lrl_noseRate = nil
		lrl_qAdj = nil
		lrl_floatTimer = 0
		lrl_floatFinal = 0
		lrl_logDisplayOn = false
		lrl_popupState = lrl_ARMED
		lrl_popupText = {}
		lrl_bounceAirborneStart = nil
		lrl_bounced = false
		lrl_peakG_allTouches = nil
		lrl_prevAnyWheel = nil
		lrl_wdirStart = nil
		lrl_wspdStart = nil
		lrl_windDirDelta = 0
		lrl_windSpdDelta = 0
		lrl_wdirStop = nil
		lrl_wspdStop = nil
		lrl_loggedThisLanding = false
	end

	-- Recorder befüllen (keine Pause)
	if not lrl_SimPaused then
		pushValue_lrl_agl(lrl_agl, lrl_localtime)
		pushValue_lrl_landingG(lrl_gforce, lrl_localtime)
		pushValue_lrl_gVS(butterball_gVS or 0, lrl_localtime)
		if lrl_floatTimer > 0 and lrl_popupState == lrl_ARMED then
	-- Stoppe Windmessung 0.3s vor t0 (Start des TD-Kandidatenfensters)
	local cutoffReached = false
	if lrl_tdCandidateStart ~= nil then
		local cutoff = lrl_tdCandidateStart - 0.30
		if lrl_localtime > cutoff then cutoffReached = true end
	end
	if cutoffReached then
		if not lrl_windFrozen then
			lrl_wdirStop   = lrl_windDir or lrl_wdirStart
			lrl_wspdStop   = lrl_windSpd or lrl_wspdStart
			lrl_windFrozen = true
		end
		-- ab hier keine neuen Wind-Samples mehr pushen
	else
		pushValue_lrl_wdir(lrl_windDir or 0, lrl_localtime)
		pushValue_lrl_wspd(lrl_windSpd or 0, lrl_localtime)
	end
end
	end

	-- CAT IIIB Timer starten (<= 15 m AGL)
	if lrl_popupState == lrl_ARMED and lrl_agl <= 15 and lrl_floatTimer == 0 then
		lrl_floatTimer = osts
		lrl_floatFinal = 0
		-- Wind-Startwerte für die Float-Phase erfassen
		lrl_wdirStart = lrl_windDir or lrl_wdirStart
		lrl_wspdStart = lrl_windSpd or lrl_wspdStart
		lrl_windDirDelta = 0
		lrl_windSpdDelta = 0
	end

	-- Float-Zeit fortschreiben (nach TD)
	if lrl_popupState >= lrl_LANDED and lrl_floatTimer > 0 and lrl_floatFinal == 0 then
		lrl_floatFinal = osts - lrl_floatTimer
	end

	-- Max-G über Landephase (ab bestätigt bis Steering-Down)
	if lrl_popupState >= lrl_LANDED and lrl_popupState < lrl_STEERINGDN then
		local gabs = math.abs(lrl_gforce or 0)
		if (lrl_peakG_allTouches == nil) or (gabs > lrl_peakG_allTouches) then
			lrl_peakG_allTouches = gabs
		end
	end

	-- Bounce-Erkennung
	local anyNow  = (lrl_boolOnGroundAny == 1)
	local prevAny = (lrl_prevAnyWheel == nil) and anyNow or lrl_prevAnyWheel
	if lrl_popupState >= lrl_LANDED and lrl_popupState < lrl_STEERINGDN then
		-- Start Airborne: 1 -> 0
		if (prevAny == true and anyNow == false) and (lrl_bounceAirborneStart == nil) then
			lrl_bounceAirborneStart = osts
		end
		-- Ende Airborne: 0 -> 1, Dauer prüfen
		if (prevAny == false and anyNow == true) and (lrl_bounceAirborneStart ~= nil) then
			if (osts - lrl_bounceAirborneStart) >= 1.0 then
				lrl_bounced = true
			end
			lrl_bounceAirborneStart = nil
		end
	else
		lrl_bounceAirborneStart = nil
	end
	lrl_prevAnyWheel = anyNow

	-- Touchdown-Stabilität & Messwert-Erfassung (t0 via lrl_localtime)
	local TD_WINDOW = 0.30
	if lrl_popupState == lrl_ARMED then
		-- Kandidat-Start: 0 -> 1
		if (lrl_tdCandidateStart == nil) and (not lrl_logAnyWheel and lrl_boolOnGroundAny == 1) then
			lrl_tdCandidateStart = lrl_localtime
			lrl_tdOnCount, lrl_tdTotalCount = 1, 1
			-- t0-Snapshot für Flare-Bewertung (nur Q)
			lrl_qAdj = lrl_Q
			-- Box leeren für frische Anzeige
			lrl_popupText = {}
		end

		-- Kandidat läuft
		if lrl_tdCandidateStart ~= nil then
			local now = lrl_localtime
			if (now - lrl_tdCandidateStart) < TD_WINDOW then
				lrl_tdTotalCount = lrl_tdTotalCount + 1
				if lrl_boolOnGroundAny == 1 then lrl_tdOnCount = lrl_tdOnCount + 1 end
			else
				-- Stabilität prüfen
				local ratio = (lrl_tdTotalCount > 0) and (lrl_tdOnCount / lrl_tdTotalCount) or 0
				if ratio >= 0.65 then
					-- bestätigter Touchdown @ t0
					if lrl_landingRate == nil then
						lrl_landingRate = lrl_minVS_around(lrl_tdCandidateStart, 0.12, 0.03)
						lrl_landingG    = lrl_peakG_around(lrl_tdCandidateStart, 0.10, 0.20)
						-- PeakG_AllTouches mindestens mit LandingG seed-en
						local lg_abs = math.abs(lrl_landingG or 0)
						if (lrl_peakG_allTouches == nil) or (lg_abs > lrl_peakG_allTouches) then
							lrl_peakG_allTouches = lg_abs
						end
					end
					-- Anzeigezeilen füllen (Zeile 2 & 3)
					lrl_populatePopupStats()
					lrl_popupState = lrl_LANDED
					if not lrl_InReplay then
						lrl_showUntil = os.clock() + lrl_SECONDS_TO_DISPLAY
						lrl_logDisplayOn = true
					end
				end
				-- Kandidat zurücksetzen
				lrl_tdCandidateStart = nil
				lrl_tdOnCount, lrl_tdTotalCount = 0, 0
			end
		end
	end

	if lrl_logAllWheels and not lrl_loggedThisLanding and (lrl_landingRate or 0) ~= 0 and (lrl_landingG or 0) ~= 0 and not lrl_InReplay then
		-- Finalisieren: NoseRate/FloatTime bestimmen
		if lrl_noseRate == nil then lrl_noseRate = lrl_Q end
		if lrl_floatTimer > 0 and lrl_floatFinal == 0 then
			lrl_floatFinal = osts - lrl_floatTimer
		end
		-- Anzeige-/Log-Zeilen jetzt aufbauen (setzt auch Wind-Deltas)
		lrl_populatePopupStats()
		-- Log schreiben
		lrl_postLandingRate()
		lrl_popupState = lrl_STEERINGDN
		lrl_loggedThisLanding = true
		-- Anzeige sofort verlängern
		lrl_showUntil    = osts + lrl_SECONDS_TO_DISPLAY
		lrl_logDisplayOn = true
	end

	-- Letzten Wheel-/Sim-Status refreshen (pro Frame)
	lrl_logAnyWheel   = (lrl_boolOnGroundAny == 1)
	lrl_logAllWheels  = (lrl_boolOnGroundAll == 1)
	lrl_SimPaused     = (lrl_boolSimPaused == 1)
	lrl_ParkingBrake  = ((lrl_parkingBrake or 0) >= 0.99)
	lrl_InReplay      = (lrl_boolInReplay == 1)
end

------------------------------------------------------------
-- 10) CALLBACKS & MAKROS
------------------------------------------------------------
do_every_draw('lrl_loopCallback()')
add_macro("Landing Rate: Show Debug Info", "lrl_DEBUG = true", "lrl_DEBUG = false", "deactivate")