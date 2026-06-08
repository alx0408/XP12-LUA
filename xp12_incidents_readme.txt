xp12_incidents_v3.lua — Reference Documentation
================================================

OVERVIEW
--------
xp12_incidents is a custom failure and incident system for X-Plane 12, running
as a FlyWithLua NG+ script. It extends and replaces X-Plane's built-in failure
manager with the following key differences:

  1. Scheduled randomness — failures trigger automatically over time based on a
     configurable mean time between failures (MTBF). X-Plane's native system
     requires manual setup per session; this script runs autonomously.

  2. Conditions — failures only trigger when realistic preconditions are met
     (e.g. on ground with engine off, engine running, airborne). The native
     system has no such guards.

  3. Custom failures — FUEL_CAP, FUEL_LEAK, and door failures (DOOR_OPEN) are not simple DataRef toggles but simulate physical
     effects over time via their own drain or state routines. They cannot be
     replicated with the native failure manager.

  4. Fix conditions — certain failures clear automatically when the real-world
     corrective action is performed (e.g., switching all electrics off clears
     cockpit smoke). The native system requires manual reset.

  5. Memory — states persist across sessions in a profile memory file (except environmental failure).
     The aircraft resumes exactly where it left off.

  6. Aircraft profiles — the config file defines failure sets per aircraft ICAO
     code. On load the script reads the aircraft ICAO and applies the matching
     profile. All settings in a profile override only those entries listed;
     everything else falls back to [DEFAULT]. 

SCRIPT MODES
-------------
SCRIPT-MODE setting in the config:

  ON           — failures are active immediately on load.
  OFF          — all automatic triggering disabled; manual toggle only.
  <minutes>    — RANDOM mode: one randomly selected failure triggers
                 within this time window. After it fires, a new window begins.

Per-failure MTBF (in hours): probability is calculated per tick. A failure
with MTBF = 100 has a 1% chance per hour, spread over the tick interval.

==============================================================================
POP-UP, STATUS DISPLAY AND COMMANDS
==============================================================================

Popups (shown for 5 seconds in the status overlay area):
  "-- ACTIVE --"       Script resumed or loaded in active state.
  "-- PAUSED --"       Script paused.
  "-- PROFILE RESET --"
  "-- ALL TRIGGERED --" / "-- ALL RESET --"
  "DOOR 1 LATCHED" / "DOOR 2 LATCHED"
  "TANK CAP CHECKED"   External view preflight check registered.

Status display can be (toggeled via FLW-macro or assigned key:
  Shows current mode, conditions enforcement state, 
  all currently active guards and failures.

Global commands:
  FlyWithLua/Incidents/pause               Pause / resume all automatic triggering.
  FlyWithLua/Incidents/reset_profile       Reset all failures and reload memory.
  FlyWithLua/Incidents/reset_all           Reset all profile-failures.
  FlyWithLua/Incidents/trigger_all         Trigger / reset all enabled failures at once.
   FlyWithLua/Incidents/toggle_conditions   Toggle condition enforcement ON/OFF.
                                           When ON: manual triggers respect the
                                           same conditions as auto triggers.
  FlyWithLua/Incidents/latch_all_doors     Latch all available doors. Toggle:
                                           if all already latched, unlatches all.

Per-failure commands (one per failure):
  FlyWithLua/Incidents/<failure_key_lowercase>
  Example: FlyWithLua/Incidents/eng_fail_1
  Toggles the failure: triggers if inactive, resets if active.

  Per-failure commands will only trigger if conditions are met (default).
  Use toggle conditions to set conditions to OFF.
  Per-failure will then trigger unconditional.


AIRCRAFT PROFILES AND OVERRIDE LOGIC
--------------------------------------
The config file (xp12_incidents_config.txt) contains one [DEFAULT] section
and one section per supported aircraft. Each profile entry can be:

  OFF        — failure disabled for this aircraft
  DEFAULT    — use the DEFAULT_MTBF value from the global setting
  <hours>    — specific MTBF in hours for this failure for this aircraft

A dedicated model profile (e.g., [BE58], [C172]) only needs to list deviations
from [DEFAULT]. Failures not listed in a profile keep their DEFAULT value.

If the loaded aircraft ICAO matches no profile, [DEFAULT] applies in full.

IMPORTANT: For aircraft managed by a dedicated simulation add-on (e.g.,
SimCoders Baron 58 REP), the add-on intercepts many X-Plane failure
DataRefs and manages them internally. Setting such a failure in the script will
have no effect or unpredictable results. These failures can be set to OFF in the
respective profile. See the aircraft-specific sections at the end of this file.

Failures without effect on the profile aircraft will not trigger anything.
But if you are in SCRIPT MODE RANDOM an uneffective failure may triggered.
If it is your intension to really have one failure at least triggeres effectively,
set aircraft profile appropriate.

CONDITIONS:

  (none)            — no restriction; can trigger at any time
  ground_engine_off — on the ground, engines off
  engine            — at least one engine must be running
  engine_or_elec    — one engine running or electrical bus powered
  ground_roll       — on the ground, rolling (speed > 15 kn)
  airborne          — aircraft must be in the air

==============================================================================
 ENVIRONMENT FAILURES
==============================================================================

VASI
----
Effect:    PAPI/VASI approach lights fail. No visual glidepath reference on
           approach.
Condition: None — can trigger at any time. (if a failure description shows no condtion, it is "none")
Fix:       None. Reset profile or toggle manually. (if a failure description shows no fix, there is no fix)

RWY_LIGHTS
----------
Effect:    Runway lighting fails.

SMOKE
-----
Effect:    Cockpit smoke appears (X-Plane rel_smoke_cpit failure). 
Condition: Engine running OR electrical bus powered (engine_or_elec).
Fix:       Switch OFF all electrical (batteries, avionics master, generators).
           One of these is randomly assigned as the culprit and shown in the status
           display (20% battery, 20% generator, 60% avionics bus).
           Turning on the culprit will trigger smoke again.

           Smoke from engine fire (ENG_FIRE_1/2 followup) has no fix
           — reset the profile or toggle manually.

BIRD_ENG1 / BIRD_ENG2
----------------------
Effect:    Bird strike specifically directed at engine 1 or engine 2 intake.
           May cause engine damage, fire, or failure.
           On a single-engine aircraft BIRD_ENG2 is set to OFF — birds will
           pass nearby without striking.
Condition: Airborne only.

DOOR_OPEN
---------
Effect:    Custom failure. Opens one physical aircraft door by writing to the
           X-Plane door DataRef. The failure system performs a dice roll among
           all available non-open doors. If the selected door has a latch guard
           set, it does not open and nothing is shown — the latch held.
           If an unlatched door is selected, it opens and the status display
           shows it as active.
Condition: no latch guard: A latched door cannot be opened by the failure system. 
Prevention: 
           Latch guard: After closing a door it is automatically latched. 
           For preflight check open and close each door.
           A popup "DOOR 1 LATCHED" or "DOOR 2 LATCHED" confirms the guard.
           To latch all available doors at once, use the command latch_all_doors.
           Opening a door clears the latch for that door.
           Latch state is saved per profile in the memory file.
           To begin a new flight with door unlatches, previous flight must
           be left with door(s) open.
Fix:       Close the door. X-Plane allows closing any door via command regardless
           of seat position. In a real aircraft a passenger door out of reach
           cannot be closed from the cockpit — the pilot's decision whether to
           use the command or leave the door open until landing.

FUEL_CAP
--------
Effect:    Custom failure — simulates a missing or loose fuel cap on one
           randomly selected tank. Fuel drains at a high initial rate
           (≈1 kg/s) that decreases over time to ≈0.05 kg/s. Stops when
           the affected tank reaches 0.5 kg remaining.
Condition: Airborne only. tank cap guard missing.
Prevention:
           Preflight walk-around check: switch to any external view while on
           the ground with both engines off. The script detects the external
           view and sets the tank cap check, blocking all automatic
           FUEL_CAP triggers for that flight. A popup "TANK CAP CHECKED"
           confirms this. The check status is saved to memory immediately.
           The check is invalidated if fuel quantity rises by more than 1 kg
           compared to the last engine-off snapshot (refueling detected).
           Refueling is detected continuously while parked with engine off.

FUEL_WATER
----------
Effect:    Water contamination in fuel. Engine may run for a few seconds after
           start but will not sustain operation and will not restart.
Condition: On the ground, engine off (ground_engine_off). 
Prevention:[fuel drain check = outside view + command / to be done]
Note:      Does not work on the B58 (SimCoders REP).

FUEL_TYPE
---------
Effect:    Wrong fuel type loaded. Engine flames out after a short period;
           propeller will no longer turn with the starter.
Condition: On the ground, engine off (ground_engine_off) [+ refueling detected / to be done]
Note:      Does not work on the B58 (SimCoders REP).


==============================================================================
 ENGINE FAILURES
==============================================================================

Note:      Engine failures do not work on the B58 (SimCoders REP).

ENG_FAIL_1 / ENG_FAIL_2
------------------------
Effect:    Complete engine failure.
Condition: Engine running.

ENG_FIRE_1 / ENG_FIRE_2
------------------------
Effect:    Engine fire. 
           With 75% probability, cockpit smoke (SMOKE) is triggered as an automatic followup. 
           Smoke from engine fire has no fix.
Condition: Engine running.

STARTER_1 / STARTER_2
----------------------
Effect:    Starter motor fails. Engine cannot be cranked.

MAG_L1 / MAG_L2 / MAG_R1 / MAG_R2
-----------------------------------
Effect:    Left or right magneto failure on engine 1 or 2. RPM drop on the
           affected magneto during mag check; rough running at low power.

FUEL_PUMP_LO_1 / FUEL_PUMP_LO_2
---------------------------------
Effect:    Fuel pump low pressure — pump runs but produces insufficient
           pressure. May cause engine roughness or lean-out at altitude.

FUEL_PUMP_1 / FUEL_PUMP_2
--------------------------
Effect:    Mechanical (engine-driven) fuel pump failure.

ELE_FUEL_PMP_1 / ELE_FUEL_PMP_2
---------------------------------
Effect:    Electric fuel (boost) pump failure.

FUEL_FLOW_1 / FUEL_FLOW_2
--------------------------
Effect:    Irregular fuel supply causing flow fluctuations.

FUEL_BLOCK_1 / FUEL_BLOCK_2
----------------------------
Effect:    Fuel filter or line blockage.
           Restricts or stops fuel flow to the engine.

FUEL_LEAK
---------
Effect:    Custom failure — active fuel leak. Side determined randomly:
           40% left tank only, 40% right tank only, 20% both tanks.
           Drain rate starts low (≈0.1 kg/s) and increases over time up to
           1.0 kg/s. Stops at 0.5 kg remaining in the affected tank(s).
           State is memory-persistent — survives sessions.
Condition: Engine running.

OIL_PUMP_1 / OIL_PUMP_2
------------------------
Effect:    Oil pump failure. Oil pressure will drop; engine damage may follow.

OIL_PRESS_LO_1 / OIL_PRESS_LO_2
----------------------------------
Effect:    Low oil pressure warning / reduced lubrication.

AIRFLOW_ENG1 / AIRFLOW_ENG2
----------------------------
Effect:    Airflow restriction to the engine (induction system).

==============================================================================
 PROPELLER FAILURES  (constant-speed props only)
==============================================================================

Note:      Prop failures do not work on the B58 (SimCoders REP).
Note:      All prop failures not working on fixed blade propellers.

PROP_FINE_1 / PROP_FINE_2
--------------------------
Effect:    Propeller governor fails toward fine pitch. Overspeed tendency;
           high RPM at reduced power settings.

PROP_COARSE_1 / PROP_COARSE_2
------------------------------
Effect:    Propeller governor fails toward coarse pitch. Inability to achieve
           full RPM; reduced climb performance.

==============================================================================
 ELECTRICAL FAILURES
==============================================================================

Note:      Engine failures do not work on the B58 (SimCoders REP).

ELEC_BUS1 / ELEC_BUS2
----------------------
Effect:    Main or secondary electrical bus failure. All equipment on that bus
           loses power.

GENERATOR_1 / GENERATOR_2
--------------------------
Effect:    Generator/alternator failure. Battery becomes sole power source.
           Ammeter shows discharge; limited time to electrical shutdown.

BATTERY_1 / BATTERY_2
----------------------
Effect:    Battery failure. If generator is also off or fails subsequently,
           complete electrical shutdown follows.

GEN0_LO / GEN0_HI / GEN1_LO / GEN1_HI
---------------------------------------
Effect:    Generator voltage out of normal range (low or high). Low voltage
           may cause under-voltage on avionics; high voltage risks equipment
           damage.

BAT0_LO / BAT0_HI / BAT1_LO / BAT1_HI
---------------------------------------
Effect:    Battery voltage out of range. BAT0_HI is meaningful mainly as a
           followup of alternator failure — avionics can still run briefly at
           elevated battery voltage (≈32V).

Note: All electrical failures are disabled for the B58 (SimCoders REP manages
the entire electrical system). See aircraft limitations.

==============================================================================
 LIGHT FAILURES
==============================================================================

LITES_BEACON    Rotating beacon fails. On the B58 REP, only fuselage light off.
LITES_NAV       Navigation lights (wingtip and tail) fail.
LITES_TAXI      Taxi light fails.
LITES_STROBE    Strobe lights fail.
LITES_LANDING   Landing light(s) fail. On the B58 REP, both lights switch off.
LITES_INST      Instrument panel lighting fails.
LITES_COCKPIT   Cockpit interior lighting fails.

==============================================================================
 AUTOPILOT FAILURES
==============================================================================

AP_COMPUTER
-----------
Effect:    Autopilot computer failure. AP disconnects and cannot be re-engaged.
           No aural chime, no annunciator — silent failure.

AP_RUNAWAY
----------
Effect:    Autopilot runs away — commands uncontrolled pitch/roll inputs.
Fix:       Disconnect autopilot immediately.

AP_SERVOS
---------
Effect:    All AP servos fail. Disconnect chime sounds. AP indicators
           remain illuminated, but the autopilot has no authority.

AP_SERVO_ELEV
-------------
Effect:    Elevator servo restricted. Altitude deviations under AP control.

AP_SERVO_AILN
-------------
Effect:    Aileron servo restricted. AP reacts slowly or rarely to heading
           deviations.

AP_SERVO_RUDD
-------------
Effect:    Yaw damper/rudder servo restricted.

==============================================================================
 SYSTEMS FAILURES
==============================================================================

PITOT_HEAT_1 / PITOT_HEAT_2
----------------------------
Effect:    Pitot heat element failure. In icing conditions, pitot tube may block.

AOA_HEAT
--------
Effect:    Angle-of-attack probe heat failure. AOA indicator unreliable in icing conditions.

WINDOW_HEAT
-----------
Effect:    Windshield heat failure.

PROP_HEAT_1 / PROP_HEAT_2
--------------------------
Effect:    Propeller de-ice heat failure. 
Note:      On the B58, effect shows only as an ammeter drop — the dedicated prop ampmeter is not affected.

TKS_PUMP
--------
Effect:    TKS de-icing fluid pump failure. No fluid distributed to wings and
           tail. Relevant only on aircraft with TKS system.

HVAC
----
Effect:    Cabin heating/cooling system failure.

VACUUM_1 / VACUUM_2
--------------------
Effect:    Vacuum pump failure. Gyroscopic instruments driven by
           that pump spin down and become unreliable.
Note:      does not work on the B58 (SimCoders REP).

==============================================================================
 INSTRUMENT FAILURES
==============================================================================

--- Steam gauge instruments ---

ASI_PILOT       Airspeed indicator (pilot side) fails. Needle freezes or drops.
AHZ_PILOT       Artificial horizon (pilot) tumbles.
ALT_PILOT       Altimeter (pilot) freezes.
TSI_PILOT       Turn coordinator / turn and slip indicator fails.
DGY_PILOT       Directional gyro fails; drifts or freezes.
VVI_PILOT       Vertical speed indicator (pilot) fails.
ALT_COPILOT     Copilot altimeter fails.
AHZ_COPILOT     Copilot artificial horizon fails.

--- Garmin G430 (or G530)---

G430_GPS1       GPS unit 1 fails completely — no moving map, no navigation.
G430_GPS2       GPS unit 2 fails completely.
G430_NAV1       NAV1 radio tuning fails — COM and NAV frequencies cannot be
                changed. Note: in installations where a GPS device replaces
                the NAV radio, this may have no effect.
G430_NAV2       NAV2 radio tuning fails.

--- G1000 (Garmin integrated glass cockpit) ---

G_ASI / G_ALT / G_VVI     Individual G1000 display instruments fail.
G_PFD                     Primary flight display fails completely.
G_MFD                     Multi-function display fails completely.
G_GIA1 / G_GIA2           GIA integrated avionics units fail.
G_GEA                     GEA engine and airframe unit fails.
MAGNETOMETER              G1000 magnetometer fails; heading reference lost.

Note: G1000 failures are only active on aircraft equipped with G1000.

--- Engine instruments ---

RPM_IND_1 / RPM_IND_2    Tachometer (RPM indicator) for engine 1 or 2 fails.
MP_IND_1 / MP_IND_2      Manifold pressure indicator fails.
CHT_IND_1 / CHT_IND_2    Cylinder head temperature indicator fails.
EGT_IND_1 / EGT_IND_2    Exhaust gas temperature indicator fails.
FF_IND_1 / FF_IND_2      Fuel flow indicator fails.
FUEL_P_IND_1 / FUEL_P_IND_2   Fuel pressure indicator fails.
OIL_P_IND_1 / OIL_P_IND_2    Oil pressure indicator fails.
OIL_T_IND_1 / OIL_T_IND_2    Oil temperature indicator fails.

--- Other instruments ---

WXR_RADAR       Weather radar fails.
NAVCOM1         NAV/COM 1 radio (antenna/receiver) fails.
NAVCOM2         NAV/COM 2 radio fails.
ADF1            ADF receiver fails. Needle spins or parks.
DME             DME unit fails. Distance readout lost.
XPNDR           Transponder fails. No ATC replies.
MARKER          Marker beacon receiver fails.
STALL_WARN      Stall warning system (horn or stick shaker) fails silently.
GEAR_WARN       Gear warning horn muted.
PROP_SYNC       Propeller sync instrument fails. 
                Note: may fail the indicator only — the actual sync system is not affected.
FUEL_QTY        Fuel quantity sensor/indicator fails. Gauges show incorrect or zero fuel.

==============================================================================
 SENSORS AND ANTENNAS
==============================================================================

PITOT / PITOT_2 / PITOT_STBY
---------------
Effect:    Pitot tube blocked (no heat failure, physical blockage).

STATIC / STATIC_2 / STATIC_STBY
-----------------
Effect:    Static port blocked. Altimeter, VSI, and ASI all affected.
Note:      On the B58 (two static systems): Static 1 = pilot side, Static 2 = copilot side.

STATIC_ERR_1 / STATIC_ERR_2
-----------------------------
Effect:    Static system reads low (approx. 1,200 ft error). Alternate air
           will restore function but with varying and unreliable readings.

OAT
---
Effect:    Outside air temperature probe fails.

ICE_DETECT
----------
Effect:    Ice detection system failure. Relevant only on TKS-equipped aircraft.

LOC
---
Effect:    Localizer receiver fails. LOC needle red-flags.

GLS
---
Effect:    Glide slope receiver fails. GS needle red-flags.

GPS
---
Effect:    GPS position receiver fails. Position freezes while GPS device is
           powered on.

==============================================================================
 GEAR FAILURES
==============================================================================

GEAR_IND
--------
Effect:    Gear position indicator fails. Unsafe / transit indications unreliable.

GEAR_ACT
--------
Effect:    Gear actuator failure. Gear cannot be extended or retracted at all.

GEAR_RET_1 / GEAR_RET_2 / GEAR_RET_3
--------------------------------------
Effect:    Individual gear leg (1=nose/front, 2=left, 3=right on tricycle) freezes in its current position. 

GEAR_COL_1 / GEAR_COL_2 / GEAR_COL_3
--------------------------------------
Effect:    Gear leg collapse on the ground.
Condition: On ground.
Note:      On the B58: gear collapse cannot be repaired in maintenance — only a new flight resets it.

TIRE_1 / TIRE_2 / TIRE_3 / TIRE_4 / TIRE_5
--------------------------------------------
Effect:    Tire blowout. Aircraft veers on rollout.
Note:      Usually 3 tires. TIRE_4 and TIRE_5 apply to aircraft with double tires.

BRAKES_L / BRAKES_R
--------------------
Effect:    Left or right braking system fails completely. Strong directional pull on braking.

==============================================================================
 CONTROL FAILURES
==============================================================================

FLAP_ACT
--------
Effect:    Both flap actuators fail. Flaps lock in current position.
Note:      Overspeed with flaps extended may cause loss of flap (without
           animation, effect still applied).

FLAP_ACT_L / FLAP_ACT_R
-------------------------
Effect:    Left or right flap actuator fails independently. Asymmetric flap
           situation — strong roll tendency.

ELV_TRIM_RUN
------------
Effect:    Electric elevator trim runs away continuously and uncontrollably.
           Aircraft pitches. Affects electric trim only — manual trim wheel
           remains functional.

Fix:       Engage and hold the autopilot & trim disconnect switch. The script monitors the cutoff.
           This may take some secaonds ; once it detects the switch held off, the runaway
           clears and the trim system is locked dead (TRIM_ELV, TRIM_AIL, TRIM_RUD triggered as followup).
           Manually trim only.
Note:      Failures has effect, even if trims are not electrical.
           Make sure to disable this failure on AC without electrical trims.
           (i.a. C172 or B58 will have electrical elevator trim; disengage aileron and rudder failure)

AIL_TRIM_RUN
------------
Effect:    Aileron electric trim runaway. Aircraft rolls.
Fix:       Same electric trim cutoff as ELV_TRIM_RUN.

RUD_TRIM_RUN
------------
Effect:    Rudder electric trim runaway. Yaw develops continuously.
Fix:       Same electric trim cutoff as ELV_TRIM_RUN.

TRIM_ELV / TRIM_AIL / TRIM_RUD
--------------------------------
Effect:    Trim system locked dead after trim runaway fix — the cutoff has
           disconnected the trim motor. Manual trim input still has effect.
Note:      Failures has may appear on their own, or as a follow-up after trim runs.

==============================================================================
 AIRCRAFT-SPECIFIC LIMITATIONS
==============================================================================

The following describes known limitations and behavioral differences for each
aircraft profile in the order they appear in the config file.

--- DEFAULT (all aircraft without a dedicated profile) ----------------------

No specific limitations. All failures enabled at DEFAULT_MTBF unless the
failure itself is documented as OFF. Profiles for unlisted
aircraft should be created by copying DEFAULT and adjusting for the specific
airframe (single vs. twin engine, fixed vs. retractable gear, etc.).

--- C172 — Cessna 172 (Laminar, SEP, fixed gear) --------------

Single-engine aircraft. All _2 engine, pump, oil, magneto, and electrical
failures are disabled (no second engine or second generator/battery in this
configuration).

Constant-speed propeller failures (PROP_FINE, PROP_COARSE) are disabled —
the C172 has a fixed-pitch propeller.

No copilot instruments: ALT_COPILOT and AHZ_COPILOT disabled.

No retractable gear: GEAR_IND, GEAR_RET and GEAR_ACT failures disabled. 
TIRE_4 / TIRE_5 disabled.

Laminar C172 is available with G1000.
Make sure correct settings for equipment you prefer.

No TKS, no HVAC, no window heat, no prop heat, no AOA heat: disabled.

No weather radar: WXR_RADAR disabled.

Either G530/G430 or G1000: NAVCOM1, NAVCOM2 disabled (irrelevant).

PITOT_2, PITOT_STBY, STATIC_2, STATIC_ERR_2, ICE_DETECT disabled.

C172 electric trim is elevator only. aileron and rudder trim runaways (AIL_TRIM_RUN,
RUD_TRIM_RUN) and their followups (TRIM_AIL, TRIM_RUD) are disabled.


--- SR22 — Cirrus SR22 (Laminar, G1000, SEP, fixed gear) -------------------

Single-engine aircraft: all _2 engine and oil failures disabled. 
No second electrical bus (ELEC_BUS2), no second generator (GENERATOR_2). [needs to be checked]

G1000 aircraft: steam gauge instruments (ASI_PILOT, AHZ_PILOT, ALT_PILOT,
TSI_PILOT, DGY_PILOT, VVI_PILOT) and G430 units all disabled — the SR22 uses
only the G1000 suite. G1000-specific failures (G_PFD, G_MFD, etc.) are active.

No retractable gear: GEAR_IND, GEAR_ACT, and all GEAR_RET failures disabled.

No NAVCOM radios as standalone units (integrated in G1000): NAVCOM1, NAVCOM2
disabled. G430_GPS1, G430_GPS2, G430_NAV1, G430_NAV2 disabled.

No prop heat, no AOA heat: those failures disabled.

No second pitot or static: PITOT_2, PITOT_STBY, STATIC_2, STATIC_ERR_2
disabled.

No rotating beacon on this model: LITES_BEACON disabled.

Only elevator trim runaway active (AIL_TRIM_RUN, RUD_TRIM_RUN disabled —
same single-engine config as C172).


--- BE58 — SimCoders Baron 58 REP (twin, retractable gear) ------------------

The SimCoders Reality Expansion Pack (REP) intercepts and manages some
aircraft systems internally. Setting many X-Plane failure DataRefs while REP
is active has no effect or produces unpredictable results.

ENGINES AND PROPELLERS — all disabled:
  REP manages the entire engine and propeller simulation including failures,
  wear, and maintenance. All ENG_FAIL, ENG_FIRE, STARTER, MAG, FUEL_PUMP,
  ELE_FUEL_PMP, FUEL_FLOW, OIL_PUMP, OIL_PRESS_LO, AIRFLOW, and all PROP
  failures are set to OFF. Engine fires and their followup smoke remain
  available as manual triggers if needed.

ELECTRICAL SYSTEM — all disabled:
  REP manages the B58 electrical system (dual bus, dual battery, dual
  generator) internally. All ELEC_BUS, GENERATOR, BATTERY, GEN0/GEN1/BAT0/BAT1
  voltage failures are set to OFF.

FUEL_WATER / FUEL_TYPE — no effect:
  X-Plane contamination DataRefs have no effect while REP manages engine
  combustion. Disabled.

ENGINE INSTRUMENTS — no effect:
  REP renders all engine instruments (RPM, MP, CHT, EGT, FF, fuel pressure,
  oil pressure, oil temperature) from its own model. X-Plane failure DataRefs
  for these instruments (RPM_IND, MP_IND, CHT_IND, EGT_IND, FF_IND, Fuel QTY,
  FUEL_P_IND, OIL_P_IND, OIL_T_IND) have no effect. All disabled.

PITOT — REP controlled: the primary pitot (PITOT) is managed by REP; no effect.
PITOT_2 — no effect. PITOT_STBY — n/a. Disabled.

STATIC_STBY — no effect: disabled.

OAT — no effect: disabled.

AHZ_COPILOT — no effect: disabled.

G430_NAV1 — no effect (redundant with GPS device): disabled.
G430_GPS2, G430_NAV2, NAVCOM1, NAVCOM2 — n/a or redundant: disabled.

All G1000 failures — n/a (B58 is not a G1000 aircraft): disabled.

WXR_RADAR — no effect: disabled.

GEAR_IND — no effect: disabled. TIRE_4, TIRE_5 — n/a: disabled.

STALL_WARN — n/a: can be tested in flight, behavior uncertain.

AIL_TRIM_RUN / RUD_TRIM_RUN — n/a:
  Aileron and rudder trim on the B58 are not electrically driven; these
  failures have no effect. Disabled. Only ELV_TRIM_RUN is active.

TKS_PUMP, HVAC — n/a on B58 configuration: disabled.

ADF and XPNDR will fail but do not appear in REP maintenance logs.
LOC, GLS, and GPS failures work as described above — they freeze or flag
without REP interference.
Static port failures (STATIC, STATIC_2, STATIC_ERR_1/2) work and affect
pilot and copilot instruments respectively.
Gear collapse (GEAR_COL) cannot be repaired in REP maintenance — a new
flight is required.
Light failures all work. LITES_BEACON affects the fuselage beacon only.
Autopilot failures all work as described.