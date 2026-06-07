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
     (e.g., engine running, airborne, on ground with engine off). The native
     system has no such guards.

  3. Custom failures — FUEL_CAP, FUEL_LEAK, and door failures (DOOR_OPEN,
     DOOR_1, DOOR_2) are not simple DataRef toggles but simulate physical
     effects over time via their own drain or state routines. They cannot be
     replicated with the native failure manager.

  4. Fix conditions — certain failures clear automatically when the real-world
     corrective action is performed (e.g., switching all electrics off clears
     cockpit smoke). The native system requires manual reset.

  5. Memory — non-environmental failure states persist across sessions in a
     profile memory file. The aircraft resumes exactly where it left off.

  6. Aircraft profiles — the config file defines failure sets per aircraft ICAO
     code. On load the script reads the aircraft ICAO and applies the matching
     profile. All settings in a profile override only those entries listed;
     everything else falls back to [DEFAULT].


AIRCRAFT PROFILES AND OVERRIDE LOGIC
--------------------------------------
The config file (xp12_incidents_config.txt) contains one [DEFAULT] section
and one section per supported aircraft. Each profile entry can be:

  OFF        — failure disabled for this aircraft
  ON         — failure active immediately on load / profile reset
  DEFAULT    — use the DEFAULT_MTBF value from the global setting
  <hours>    — specific MTBF in hours for this failure

A dedicated model profile (e.g., [BE58], [C172]) only needs to list deviations
from [DEFAULT]. Failures not listed in a profile keep their DEFAULT value.

If the loaded aircraft ICAO matches no profile, [DEFAULT] applies in full.

IMPORTANT: For aircraft managed by a dedicated simulation add-on (e.g.,
SimCoders REP for the Baron 58), the add-on intercepts many X-Plane failure
DataRefs and manages them internally. Setting such a failure in the script will
have no effect or unpredictable results. These failures are set to OFF in the
respective profile. See the aircraft-specific sections at the end of this file.


TRIGGER MODES
-------------
Global MODE setting in the config:

  ON           — every enabled failure is active immediately on load or reset.
                 Used for testing individual failures.
  OFF          — all automatic triggering disabled; manual toggle only.
  <minutes>    — RANDOM mode: one randomly selected enabled failure triggers
                 within this time window. After it fires, a new window begins.

Per-failure MTBF (in hours): probability is calculated per tick. A failure
with MTBF = 100 has a 1% chance per hour, spread over the tick interval.

CONDITIONS (when enabled in the config as Conditions ON):
  airborne          — aircraft must be in the air
  engine            — at least one engine must be running
  engine_or_elec    — engine running or electrical bus powered
  ground_engine_off — on the ground, both engines off
  ground_roll       — on the ground, rolling (speed > 15 kn)
  (none)            — no restriction; can trigger at any time


==============================================================================
 ENVIRONMENT FAILURES
==============================================================================

VASI
----
Effect:    PAPI/VASI approach lights fail. No visual glidepath reference on
           approach.
Condition: None — can trigger at any time.
Fix:       None. Reset profile or toggle manually.

RWY_LIGHTS
----------
Effect:    Runway edge and threshold lighting fails. Affects night and
           low-visibility approaches.
Condition: None.
Fix:       None — the X-Plane command "runway lights high" does NOT restore
           them once this failure is active. Reset profile or toggle manually.

SMOKE
-----
Effect:    Cockpit smoke appears (X-Plane rel_smoke_cpit failure). One of three
           electrical components is randomly assigned as the culprit (20%
           battery, 20% generator, 60% avionics bus) and shown in the status
           display. Smoke from engine fire (ENG_FIRE_1/2 followup) has no fix.
Condition: Engine running OR electrical bus powered (engine_or_elec).
Fix:       Switch OFF all electrical sources until the bus voltage drops to
           zero: both batteries, avionics master, and both generators.
           The script monitors bus voltage; when it reaches ≤1 V the smoke
           clears automatically. This works regardless of aircraft type.
           Note: if smoke was triggered as a followup of an engine fire, no
           automatic fix is possible — reset the profile or toggle manually.

BIRD_RANDOM
-----------
Effect:    Random bird strike — X-Plane applies the effect to an unspecified
           location (rel_bird_strike).
Condition: Airborne only.
Fix:       None. Consequences depend on what X-Plane decides to damage.

BIRD_ENG1 / BIRD_ENG2
----------------------
Effect:    Bird strike specifically directed at engine 1 or engine 2 intake.
           On a single-engine aircraft BIRD_ENG2 is set to OFF — birds will
           pass nearby without striking.
Condition: Airborne only.
Fix:       None. May cause engine damage, fire, or failure depending on the
           aircraft model.

DOOR_OPEN
---------
Effect:    Custom failure. Opens one physical aircraft door by writing to the
           X-Plane door DataRef. The failure system performs a dice roll among
           all available non-open doors. If the selected door has a latch guard
           set, it does not open and nothing is shown — the latch held.
           If an unlatched door is selected, it opens and the status display
           shows it as active.
Condition: None — can trigger at any time.
Prevention / Fix:
           Latch guard: After closing a door on the ground with both engines
           off, the door is automatically latched. A latched door cannot be
           opened by the failure system (manual toggle commands can always open
           it). To latch all available doors at once, use the command
           FlyWithLua/Incidents/latch_all_doors.
           A popup "DOOR 1 LATCHED" or "DOOR 2 LATCHED" confirms the guard.
           Opening a door from inside the sim clears the latch for that door.
           Latch state is saved per profile in the memory file.

DOOR_1 / DOOR_2
---------------
Effect:    Opens the specific door (pilot = Door 1, copilot = Door 2) via the
           physical sim DataRef. Shown individually in the status display.
Condition: None.
Prevention / Fix:
           Same latch guard as DOOR_OPEN above. A latched door cannot be
           opened by either the automatic or manual trigger path.
           Per profile: set DOOR_1 or DOOR_2 to OFF to exclude a door
           entirely from all failure paths (e.g., if the aircraft has only
           one door).

FUEL_CAP
--------
Effect:    Custom failure — simulates a missing or loose fuel cap on one
           randomly selected tank. Fuel drains at a high initial rate
           (≈1 kg/s) that decreases over time to ≈0.05 kg/s. Stops when
           the affected tank reaches 0.5 kg remaining.
Condition: Airborne only.
Prevention:
           Preflight walk-around check: switch to any external view while on
           the ground with both engines off. The script detects the external
           view and sets the check as complete, blocking all automatic
           FUEL_CAP triggers for that flight. A popup "TANK CAP CHECKED"
           confirms this. The check status is saved to memory immediately.
           The check is invalidated if fuel quantity rises by more than 1 kg
           compared to the last engine-off snapshot (refueling detected).
           Refueling is detected both at script load and continuously while
           parked with engine off.
Fix:       No in-flight fix. Reset profile or pause the script.
Note:      FUEL_CAP does not work on the B58 (SimCoders REP). See aircraft
           limitations.

FUEL_WATER
----------
Effect:    Water contamination in fuel. Engine may run for a few seconds after
           start but will not sustain operation and will not restart.
Condition: On the ground, engine off (ground_engine_off).
Fix:       None — sumping the tanks is not simulated. Reset profile.
Note:      Does not work on the B58 (SimCoders REP).

FUEL_TYPE
---------
Effect:    Wrong fuel type loaded. Engine flames out after a short period;
           propeller will no longer turn with the starter.
Condition: On the ground, engine off (ground_engine_off).
Fix:       None. Reset profile.


==============================================================================
 ENGINE FAILURES
==============================================================================

ENG_FAIL_1 / ENG_FAIL_2
------------------------
Effect:    Complete engine failure. Engine stops producing power.
Condition: Engine running.

ENG_FIRE_1 / ENG_FIRE_2
------------------------
Effect:    Engine fire. With 75% probability, cockpit smoke (SMOKE) is
           triggered as an automatic followup. Smoke from engine fire has no
           automatic fix.
Condition: Engine running.

STARTER_1 / STARTER_2
----------------------
Effect:    Starter motor fails. Engine cannot be cranked.
Condition: None.

MAG_L1 / MAG_L2 / MAG_R1 / MAG_R2
-----------------------------------
Effect:    Left or right magneto failure on engine 1 or 2. RPM drop on the
           affected magneto during mag check; rough running at low power.
Condition: None.

FUEL_PUMP_LO_1 / FUEL_PUMP_LO_2
---------------------------------
Effect:    Fuel pump low pressure — pump runs but produces insufficient
           pressure. May cause engine roughness or lean-out at altitude.
Condition: None.

FUEL_PUMP_1 / FUEL_PUMP_2
--------------------------
Effect:    Mechanical (engine-driven) fuel pump failure.
Condition: None.

ELE_FUEL_PMP_1 / ELE_FUEL_PMP_2
---------------------------------
Effect:    Electric auxiliary fuel pump failure.
Condition: None.

FUEL_FLOW_1 / FUEL_FLOW_2
--------------------------
Effect:    Irregular fuel supply causing flow fluctuations.
Condition: None.

FUEL_BLOCK_1 / FUEL_BLOCK_2
----------------------------
Effect:    Fuel filter or line blockage (listed under World in X-Plane).
           Restricts or stops fuel flow to the engine.
Condition: None.

FUEL_LEAK
---------
Effect:    Custom failure — active fuel leak. Side determined randomly:
           40% left tank only, 40% right tank only, 20% both tanks.
           Drain rate starts low (≈0.1 kg/s) and increases over time up to
           1.0 kg/s. Stops at 0.5 kg remaining in the affected tank(s).
           State is memory-persistent — survives sessions.
Condition: Engine running.
Fix:       Delete the FUEL_LEAK entry from the memory file, reset profile,
           or pause the script.

OIL_PUMP_1 / OIL_PUMP_2
------------------------
Effect:    Oil pump failure. Oil pressure will drop; engine damage follows.
Condition: None.

OIL_PRESS_LO_1 / OIL_PRESS_LO_2
----------------------------------
Effect:    Low oil pressure warning / reduced lubrication.
Condition: None.

AIRFLOW_ENG1 / AIRFLOW_ENG2
----------------------------
Effect:    Airflow restriction to the engine (induction system).
Condition: None.


==============================================================================
 PROPELLER FAILURES  (constant-speed props only)
==============================================================================

PROP_FINE_1 / PROP_FINE_2
--------------------------
Effect:    Propeller governor fails toward fine pitch. Overspeed tendency;
           high RPM at reduced power settings.
Condition: None.

PROP_COARSE_1 / PROP_COARSE_2
------------------------------
Effect:    Propeller governor fails toward coarse pitch. Inability to achieve
           full RPM; reduced climb performance.
Condition: None.

Note: All prop failures are disabled for single-engine aircraft (no constant-
speed propeller on C172) and for the B58 (REP manages propeller system).


==============================================================================
 ELECTRICAL FAILURES
==============================================================================

ELEC_BUS1 / ELEC_BUS2
----------------------
Effect:    Main or secondary electrical bus failure. All equipment on that bus
           loses power.
Condition: None.

GENERATOR_1 / GENERATOR_2
--------------------------
Effect:    Generator/alternator failure. Battery becomes sole power source.
           Ammeter shows discharge; limited time to electrical shutdown.
Condition: None.

BATTERY_1 / BATTERY_2
----------------------
Effect:    Battery failure. If generator is also off or fails subsequently,
           complete electrical shutdown follows.
Condition: None.

GEN0_LO / GEN0_HI / GEN1_LO / GEN1_HI
---------------------------------------
Effect:    Generator voltage out of normal range (low or high). Low voltage
           may cause under-voltage on avionics; high voltage risks equipment
           damage.
Condition: None.

BAT0_LO / BAT0_HI / BAT1_LO / BAT1_HI
---------------------------------------
Effect:    Battery voltage out of range. BAT0_HI is meaningful mainly as a
           followup of alternator failure — avionics can still run briefly at
           elevated battery voltage (≈32V).
Condition: None.

Note: All electrical failures are disabled for the B58 (SimCoders REP manages
the entire electrical system). See aircraft limitations.


==============================================================================
 LIGHT FAILURES
==============================================================================

LITES_BEACON    Rotating beacon fails.
LITES_NAV       Navigation lights (wingtip and tail) fail.
LITES_TAXI      Taxi light fails.
LITES_STROBE    Strobe lights fail.
LITES_LANDING   Landing light(s) fail. On the B58, both lights switch off.
LITES_INST      Instrument panel lighting fails.
LITES_COCKPIT   Cockpit interior lighting fails.

Condition: None for all lights.
Fix:       None — toggle manually or reset profile.


==============================================================================
 AUTOPILOT FAILURES
==============================================================================

AP_COMPUTER
-----------
Effect:    Autopilot computer failure. AP disconnects and cannot be re-engaged.
           No aural chime, no annunciator — silent failure.
Condition: None.

AP_RUNAWAY
----------
Effect:    Autopilot runs away — commands uncontrolled pitch/roll inputs.
           Requires immediate manual disconnect.
Condition: None.
Fix:       Disconnect autopilot. The electric trim runaway (ELV_TRIM_RUN)
           may follow if configured.

AP_SERVOS
---------
Effect:    All AP servos fail. Disconnect chime sounds and AP indicators
           remain illuminated, but the autopilot has no authority.
Condition: None.

AP_SERVO_ELEV
-------------
Effect:    Elevator servo restricted. Altitude deviations under AP control.
Condition: None.

AP_SERVO_AILN
-------------
Effect:    Aileron servo restricted. AP reacts slowly or rarely to heading
           deviations.
Condition: None.

AP_SERVO_RUDD
-------------
Effect:    Yaw damper/rudder servo restricted.
Condition: None.


==============================================================================
 SYSTEMS FAILURES
==============================================================================

PITOT_HEAT_1 / PITOT_HEAT_2
----------------------------
Effect:    Pitot heat element failure. In icing conditions, pitot tube blocks;
           IAS freezes or drops to zero.
Condition: None.

AOA_HEAT
--------
Effect:    Angle-of-attack probe heat failure. AOA indicator unreliable in
           icing conditions.
Condition: None.

WINDOW_HEAT
-----------
Effect:    Windshield heat failure. Icing risk on windshield.
Condition: None.

PROP_HEAT_1 / PROP_HEAT_2
--------------------------
Effect:    Propeller de-ice heat failure. On the B58, effect shows only as an
           ammeter drop — the dedicated prop ampmeter is not affected.
Condition: None.

TKS_PUMP
--------
Effect:    TKS de-icing fluid pump failure. No fluid distributed to wings and
           tail. Relevant only on aircraft with TKS system.
Condition: None.

HVAC
----
Effect:    Cabin heating/cooling system failure.
Condition: None.

VACUUM_1 / VACUUM_2
--------------------
Effect:    Vacuum pump failure. Gyroscopic instruments (AHI, DI) driven by
           that pump spin down and become unreliable.
Condition: None.


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

--- Garmin G430 ---

G430_GPS1       GPS unit 1 fails completely — no moving map, no navigation.
G430_GPS2       GPS unit 2 fails completely.
G430_NAV1       NAV1 radio tuning fails — COM and NAV frequencies cannot be
                changed. Note: in installations where a GPS device replaces
                the NAV radio, this may have no effect.
G430_NAV2       NAV2 radio tuning fails.

--- G1000 (Garmin integrated glass cockpit) ---

G_ASI / G_ALT / G_VVI    Individual G1000 display instruments fail.
G_PFD                     Primary flight display fails completely.
G_MFD                     Multi-function display fails completely.
G_GIA1 / G_GIA2           GIA integrated avionics units fail.
G_GEA                     GEA engine and airframe unit fails.
MAGNETOMETER              G1000 magnetometer fails; heading reference lost.

Note: G1000 failures are only active on aircraft equipped with G1000 (e.g.,
SR22). They are disabled for all other profiles.

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
PROP_SYNC       Propeller sync instrument fails. Note: this fails the indicator
                only — the actual sync system is not affected.
FUEL_QTY        Fuel quantity sensor/indicator fails. Gauges show incorrect
                or zero fuel.


==============================================================================
 SENSORS AND ANTENNAS
==============================================================================

PITOT / PITOT_2
---------------
Effect:    Pitot tube blocked (no heat failure, physical blockage). IAS drops
           to zero or freezes.
Condition: None.

PITOT_STBY
----------
Effect:    Standby pitot system failure.
Condition: None.

STATIC / STATIC_2
-----------------
Effect:    Static port blocked. Altimeter, VSI, and ASI all affected.
           On the B58 (two static systems): Static 1 = pilot side,
           Static 2 = copilot side.
Condition: None.

STATIC_ERR_1 / STATIC_ERR_2
-----------------------------
Effect:    Static system reads low (approx. 1,200 ft error). Alternate air
           will restore function but with varying and unreliable readings.
Condition: None.

STATIC_STBY
-----------
Effect:    Standby static system failure.
Condition: None.

OAT
---
Effect:    Outside air temperature probe fails.
Condition: None.

ICE_DETECT
----------
Effect:    Ice detection system failure. Relevant only on TKS-equipped aircraft.
Condition: None.

LOC
---
Effect:    Localizer receiver fails. LOC needle red-flags.
Condition: None.

GLS
---
Effect:    Glide slope receiver fails. GS needle red-flags.
Condition: None.

GPS
---
Effect:    GPS position receiver fails. Position freezes while GPS device is
           powered on.
Condition: None.


==============================================================================
 GEAR FAILURES
==============================================================================

GEAR_IND
--------
Effect:    Gear position indicator fails. Unsafe / transit indications
           unreliable.
Condition: None.

GEAR_ACT
--------
Effect:    Gear actuator failure. Gear cannot be extended or retracted at all.
Condition: None.

GEAR_RET_1 / GEAR_RET_2 / GEAR_RET_3
--------------------------------------
Effect:    Individual gear leg (1=nose/front, 2=left, 3=right on tricycle)
           freezes in its current position. Partial retraction or extension
           possible.
Condition: None.

GEAR_COL_1 / GEAR_COL_2 / GEAR_COL_3
--------------------------------------
Effect:    Gear leg collapse on the ground during rollout.
Condition: Ground roll (speed > 15 kn).
Note:      On the B58: gear collapse cannot be repaired in maintenance — only
           a new flight resets it.

TIRE_1 / TIRE_2 / TIRE_3 / TIRE_4 / TIRE_5
--------------------------------------------
Effect:    Tire blowout. Aircraft veers on rollout.
Condition: None.
Note:      TIRE_4 and TIRE_5 apply to aircraft with additional gear legs
           (e.g., dual main tires). Disabled on C172 and B58 (not applicable).

BRAKES_L / BRAKES_R
--------------------
Effect:    Left or right braking system fails completely. Strong directional
           pull on braking.
Condition: None.


==============================================================================
 CONTROL FAILURES
==============================================================================

FLAP_ACT
--------
Effect:    Both flap actuators fail. Flaps lock in current position.
Condition: None.

FLAP_ACT_L / FLAP_ACT_R
-------------------------
Effect:    Left or right flap actuator fails independently. Asymmetric flap
           situation — strong roll tendency.
Condition: None.
Note:      Overspeed with flaps extended may cause loss of flap (without
           animation, effect still applied).

ELV_TRIM_RUN
------------
Effect:    Electric elevator trim runs away continuously and uncontrollably.
           Aircraft pitches. Affects electric trim only — manual trim wheel
           remains functional.
Condition: None.
Fix:       Engage the electric trim cutoff switch. The script monitors the
           cutoff DataRef; once it detects the switch held off, the runaway
           clears and the trim system is locked dead (TRIM_ELV, TRIM_AIL,
           TRIM_RUD triggered as followup).
Note:      On the B58, aileron and rudder trim are not electrical — AIL_TRIM_RUN
           and RUD_TRIM_RUN are set to OFF.

AIL_TRIM_RUN
------------
Effect:    Aileron electric trim runaway. Aircraft rolls.
Fix:       Same electric trim cutoff as ELV_TRIM_RUN.

RUD_TRIM_RUN
------------
Effect:    Rudder electric trim runaway. Yaw develops continuously.
Fix:       Same electric trim cutoff.

TRIM_ELV / TRIM_AIL / TRIM_RUD
--------------------------------
Effect:    Trim system locked dead after trim runaway fix — the cutoff has
           disconnected the trim motor. Manual trim input has no effect.
Condition: None — these are followup failures triggered automatically after a
           trim runaway is fixed via the cutoff switch.


==============================================================================
 AIRCRAFT-SPECIFIC LIMITATIONS
==============================================================================

The following describes known limitations and behavioral differences for each
aircraft profile in the order they appear in the config file.


--- DEFAULT (all aircraft without a dedicated profile) ----------------------

No specific limitations. All failures enabled at DEFAULT_MTBF unless the
failure itself is documented as non-functional above. Profiles for unlisted
aircraft should be created by copying DEFAULT and adjusting for the specific
airframe (single vs. twin engine, fixed vs. retractable gear, etc.).


--- C172 — Cessna 172 (Laminar, steam gauges, SEP, fixed gear) --------------

Single-engine aircraft. All _2 engine, pump, oil, magneto, and electrical
failures are disabled (no second engine or second generator/battery in this
configuration).

Constant-speed propeller failures (PROP_FINE, PROP_COARSE) are disabled —
the C172 has a fixed-pitch propeller.

No copilot instruments: ALT_COPILOT and AHZ_COPILOT disabled.

No retractable gear: all GEAR_RET and GEAR_ACT failures disabled. GEAR_IND
disabled (no gear position indicator). TIRE_4 / TIRE_5 disabled.

No G1000: all G_ instrument failures disabled. MAGNETOMETER disabled.

No TKS, no HVAC, no window heat, no prop heat, no AOA heat: disabled.

No weather radar: WXR_RADAR disabled.

No second NAV/COM: NAVCOM1, NAVCOM2 disabled (irrelevant at this level).

No second pitot or static: PITOT_2, PITOT_STBY, STATIC_2, STATIC_ERR_2,
ICE_DETECT disabled.

Only elevator trim runaway active — aileron and rudder trim runaways (AIL_TRIM_RUN,
RUD_TRIM_RUN) and their followups (TRIM_AIL, TRIM_RUD) are disabled; C172
electric trim is elevator only.


--- SR22 — Cirrus SR22 (Laminar, G1000, SEP, fixed gear) -------------------

Single-engine aircraft: all _2 engine and oil failures disabled. No second
electrical bus (ELEC_BUS2), no second generator (GENERATOR_2).

G1000 aircraft: steam gauge instruments (ASI_PILOT, AHZ_PILOT, ALT_PILOT,
TSI_PILOT, DGY_PILOT, VVI_PILOT) and G430 units all disabled — the SR22 uses
only the G1000 suite. G1000-specific failures (G_PFD, G_MFD, etc.) are active.

No retractable gear: GEAR_IND, GEAR_ACT, and all GEAR_RET failures disabled.

No NAVCOM radios as standalone units (integrated in G1000): NAVCOM1, NAVCOM2
disabled. G430_GPS1, G430_GPS2, G430_NAV1, G430_NAV2 disabled.

No prop heat, no AOA heat, no TKS: those failures disabled.

No second pitot or static: PITOT_2, PITOT_STBY, STATIC_2, STATIC_ERR_2
disabled.

No rotating beacon on this model: LITES_BEACON disabled.

Only elevator trim runaway active (AIL_TRIM_RUN, RUD_TRIM_RUN disabled —
same single-engine config as C172).


--- BE58 — SimCoders Baron 58 REP (twin, retractable gear) ------------------

The SimCoders Reality Expansion Pack (REP) intercepts and manages most
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

FUEL_CAP — no effect:
  REP intercepts the fuel system. The custom drain routine cannot write fuel
  quantities reliably on the B58. Disabled.

FUEL_WATER / FUEL_TYPE — no effect:
  X-Plane contamination DataRefs have no effect while REP manages engine
  combustion. Disabled.

ENGINE INSTRUMENTS — no effect:
  REP renders all engine instruments (RPM, MP, CHT, EGT, FF, fuel pressure,
  oil pressure, oil temperature) from its own model. X-Plane failure DataRefs
  for these instruments (RPM_IND, MP_IND, CHT_IND, EGT_IND, FF_IND,
  FUEL_P_IND, OIL_P_IND, OIL_T_IND) have no effect. All disabled.

FUEL_QTY — no effect: disabled.

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

PROP_SYNC — n/a (instrument only; REP manages sync system): disabled.

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


==============================================================================
 STATUS DISPLAY AND COMMANDS
==============================================================================

Status overlay (toggle via macro or assigned key):
  Shows all currently active failures, fuel and door status, current mode,
  conditions enforcement state, and fuel cap check state.

Global commands:
  FlyWithLua/Incidents/toggle_conditions   Toggle condition enforcement ON/OFF.
                                           When ON: manual triggers respect the
                                           same conditions as auto triggers.
  FlyWithLua/Incidents/pause               Pause / resume all automatic triggering.
  FlyWithLua/Incidents/reset_profile       Reset all failures and reload memory.
  FlyWithLua/Incidents/reset_all           Reset all failures (no memory reload).
  FlyWithLua/Incidents/trigger_all         Trigger all enabled failures at once.
  FlyWithLua/Incidents/latch_all_doors     Latch all available doors. Toggle:
                                           if all already latched, unlatches all.

Per-failure commands (one per failure):
  FlyWithLua/Incidents/<failure_key_lowercase>
  Example: FlyWithLua/Incidents/eng_fail_1
  Toggles the failure: triggers if inactive, resets if active.

Popups (shown for 5 seconds in the status overlay area):
  "-- ACTIVE --"       Script resumed or loaded in active state.
  "-- PAUSED --"       Script paused.
  "-- PROFILE RESET --"
  "-- ALL RESET --" / "-- ALL TRIGGERED --"
  "DOOR 1 LATCHED" / "DOOR 2 LATCHED" / "DOORS LATCHED"
  "TANK CAP CHECKED"   External view preflight check registered.
  "FUEL CAP: CHECKED"  (legacy — replaced by TANK CAP CHECKED in V3)

