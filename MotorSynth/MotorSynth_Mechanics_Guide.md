# SBP MotorSynth Mechanics Guide (Detailed)

This guide documents concrete behavior thresholds and timing constants used by the engine logic.

## 1. Engine State Machine

States:
- Off
- Cranking
- Running

Cold start path:
- Cold Start parameter defines crank duration and startup flare character.

Ignition off path:
- Engine enters coast-down and shutdown transient behavior instead of hard mute.

## 2. Main Control Modes

### Direct mode
- Pedal maps RPM from idle to RPM Target.
- Fast deterministic behavior for sound design.

### Physics mode
- RPM depends on throttle, gear ratio, and load.
- Inertia and engine-brake curves are active.
- Automatic shift scheduler can run (except Manual transmission mode).

## 3. Transmission Modes

### D (Drive)
- Upshift speed gate offset: `-5 km/h`.
- Upshift RPM gate offset: `-60 RPM`.
- Downshift RPM offset: `-140 RPM`.
- Downshift throttle gate offset: `+0.06`.
- Overall: earlier and calmer shift strategy.

### S (Sport)
- Upshift speed gate offset: `+9 km/h`.
- Upshift RPM gate offset: `+80 RPM`.
- Downshift RPM offset: `+320 RPM`.
- Downshift throttle gate offset: `-0.08`.
- Overall: later/more aggressive shift strategy.

### M (Manual)
- Automatic upshift/downshift scheduling is disabled.
- Gear changes happen by user control.

## 4. Shift Intent Modes (slider6)

Mapping:
- `0` Auto (adaptive)
- `1` Cruise
- `2` Neutral
- `3` Downshift
- `4` Kickdown

Intent effects:
- Cruise: easier upshift, downshift-resistant behavior.
- Downshift: delays upshift and prepares lower gear strategy.
- Kickdown: strongest lower-gear pressure and transient style.

## 5. Exact Trigger Thresholds

### 5.1 Auto engage from Neutral
- Condition: `eff_throttle > 0.08`
- Additional required conditions:
	- current gear is `0`
	- Park/N lock (`n_hold_mode`) is off
	- transmission mode is not Manual
	- no active shift timer

### 5.2 Throttle drop transient trigger
- Condition: `throttle_delta < -0.15` and previous throttle `> 0.30`
- Actions:
	- BOV burst queue
	- crackle/ALS transient queue

### 5.3 Auto-intent kickdown detection
- Condition:
	- `throttle_delta > 0.12`
	- `target_throttle > 0.55`
	- `gear > 1`
	- `cur_rpm < min(target_rpm * 0.72, limiter_rpm * 0.62)`
- Action: kickdown timer starts (`0.85 s`).

### 5.4 Kickdown active window
- While timer > 0, kickdown intent remains active only if:
	- `target_throttle > 0.45`
	- `cur_rpm < min(target_rpm * 0.80, limiter_rpm * 0.70)`

## 6. Upshift Scheduler (Physics, non-Manual)

### 6.1 Base speed gate by current gear
- G1: `24 km/h`
- G2: `40 km/h`
- G3: `62 km/h`
- G4: `88 km/h`
- G5+: `112 km/h`

Speed gate intent offsets:
- Cruise: `-4`
- Downshift/Kickdown: `+6`

Mode offsets:
- D: `-5`
- S: `+9`

### 6.2 RPM gate
Base gate by intent:
- Auto: `target_rpm - 80`
- Cruise: `target_rpm - 420`
- Downshift/Kickdown: `target_rpm + 420`

Mode offsets:
- D: `-60`
- S: `+80`

Safety cap:
- `upshift_rpm_gate <= target_rpm + 120`

Force-upshift fallback:
- If `cur_rpm >= target_rpm + 160`, speed gate can be bypassed.

Throttle gate:
- Default: `0.30`
- Cruise: `0.18`
- Then adjusted by D/S logic.

Shift execution:
- Upshift timer: `0.25 s`
- Cooldown next: `0.70 + (1 - eff_throttle) * 2.10`

## 7. Downshift Scheduler (Physics, non-Manual)

### 7.1 Base downshift thresholds
- Base RPM: `1800` (or `1450` in 6th)
- Base throttle gate: `0.40` (or `0.72` in 6th)

### 7.2 Intent-specific thresholds

Soft-downshift:
- RPM: `max(base, min(target_rpm * 0.62, limiter_rpm * 0.72))`
- throttle gate: `0.02`

Kickdown:
- RPM: `max(base, min(target_rpm * 0.46, 2550))`
- throttle gate: `0.34` (or `0.58` in 6th)

Cruise:
- RPM: `1650` (or `1325` in 6th)
- throttle gate: `0.56` (or `0.86` in 6th)

### 7.3 Mode offsets for downshift
- D: RPM `-140`, throttle `+0.06`
- S: RPM `+320`, throttle `-0.08`

### 7.4 Speed gate by current gear
- G6: `84 km/h`
- G5: `66 km/h`
- G4: `48 km/h`
- G3: `32 km/h`
- G2: `18 km/h`

Mode speed offsets:
- D: `-4`
- S: `+8`

### 7.5 Predicted RPM guard
- Kickdown: `target + 900`
- Soft-downshift: `target + 180`
- Other intents: `target + 420`

Shift execution:
- Downshift timer: `0.30 s`
- Cooldown next:
	- in 6th: `0.95 + (1 - eff_throttle) * 1.40`
	- otherwise: `0.50 + (1 - eff_throttle) * 1.10`

## 8. Engine Braking and Coasting (Detailed)

### 8.1 Closed-throttle detection
- `closed_thr = clamp((0.14 - eff_throttle) / 0.14, 0..1)`
- Meaning: engine-brake map starts below ~14% throttle, grows fast near closed pedal.

### 8.2 Engine-brake map formula
- `closed_thr2 = closed_thr * closed_thr`
- `gear_idx_norm = clamp((gear - 1) / 5, 0..1)`
- `gear_brake_curve = (1 - gear_idx_norm)^1.25`
- `rpm_brake_norm = clamp((cur_rpm - base_idle_rpm) / (limiter_rpm - base_idle_rpm), 0..1)`
- `rpm_brake_curve = 0.20 + (rpm_brake_norm^0.80) * 0.80`
- Final map (only when gear > 0):
	- `engine_brake_map = closed_thr2 * (0.10 + gear_brake_curve * 0.90) * rpm_brake_curve`

Interpretation:
- Lower gears -> stronger engine braking.
- Higher RPM -> stronger engine braking.
- Nearly closed throttle -> strongly nonlinear rise (square law).

### 8.3 How it enters RPM dynamics
- Physics decel term:
	- `base_decel = 0.020 + engine_brake_map * 0.085`
- So engine braking is not a separate branch; it is injected into deceleration gain.

### 8.4 Chassis feedback from engine braking
- Additional body pulse on closed throttle:
	- `bus_chassis += ebrk_pulse * engine_brake_map * (0.045 + norm_speed*0.10) * (0.75 + target_size*0.55)`
- Result: audible/physical decel feel increases with speed and engine size.

### 8.5 Coasting and stop-hold interactions
- Wheel-speed coupling is reduced when braking and launch intent is low:
	- decouple when `brake_speed_ctl > 0.10 && launch_intent < 0.18`
- Speed fall time constants are tightened under braking.
- Stop-lock hard zero condition:
	- `brake > 0.12`
	- `speed_display_norm < 0.020`
	- `coast_speed_norm < 0.024`
	- `launch_intent < 0.04`

This prevents endless crawl and keeps stationary brake behavior stable.

## 9. Shift Style and Impact Differences

### Manual N -> 1
- Heavy short clunk profile.
- Delayed second hit around `0.165 s`.
- Minimal scrape tail.

### Manual gear-to-gear
- "ta-DA" profile.
- Softer first hit, stronger delayed second hit.
- Delayed second hit around `0.300 s`.
- Scrape intensity scales with gear delta.

### Auto shifts
- Jolt/scrape are throttle-scaled.
- Cooldown and transient envelope adapt to load.

## 10. Speed Override Domain

Speed Override behavior:
- `0`: speed estimated by drivetrain model (RPM and gear ratio compute vehicle speed).
- `>0`: forced speed domain in km/h (independent of drivetrain estimate).

Affected systems:
- road noise
- wind noise
- slip/drift logic
- tire slip textures and frequencies
- shift readiness branches that depend on vehicle speed

### Drift Simulation Use Case
Speed Override is ideal for drift and wheel-slip scenarios:
- Set Speed Override to match the vehicle's actual speed while wheels spin independently.
- Engine and transmission logic work normally (RPM-based), but tire noise and slip textures decouple from drivetrain.
- Road and wind behaviors use the forced speed value, not the computed estimate.
- This allows realistic multi-layer sounds: engine acceleration + tire slip + wind variation + road friction — all independently modulated.

Example workflow:
1. Vehicle traveling at 60 km/h (overhead estimation).
2. Set Speed Override = 60 km/h.
3. Play drift event: wheels spin, slip/crunch sounds layer independently from engine RPM.
4. Wind noise and road texture respond to the 60 km/h domain, not the transient slip speed.
5. Result: convincing multi-sensory drift feel without engine-to-wheel sync breaking the illusion.

### Drift and Brake Sound Unification
As of v1.2.0, drift (slip) sound character is now linked to brake parameters for unified sonic identity:
- **Drift Aggression** (slider32) combines with **Brake Squeal Level** (slider27) and **Brake Overtone Drive** (slider28)
- **Brake squeal influence**: `brake_squeal_link = max(0.0, target_brake_squeal - 0.20) * 1.25` (active when squeal >20%)
- **Brake overtone influence**: `brake_overtone_link = target_brake_overtone * 0.95` (scales 0..0.95)
- **Unified aggression formula**: `slip_aggr = 0.75 + (target_drift_aggr * 1.65 + brake_squeal_link * 0.60) * (0.85 + brake_overtone_link * 0.15)`
- **Unified loudness formula**: `slip_loud = (0.45 + target_drift_aggr * 0.90) * (0.92 + brake_squeal_influence * 0.45 + brake_overtone_influence * 0.35)`

This ensures that when you tune Brake Squeal and Overtone, the drift slip sound evolves together, creating a cohesive braking+slip character. Adjusting either Drift Aggression or Brake parameters now influences both systems with proper weighting, eliminating the timbral disconnect between drift and brake events.

## 11. Core Engine Parameters: Size and Character

### Engine Size (slider13, 0-100)
Engine Size scales the physical engine presence across multiple dimensions:

**Voice and startup:**
- Larger engines (>50): deeper startup flare, more revolutions during cold start
- Smaller engines (<30): tighter, quicker startup with less flare
- Formula: `startup_flare = 0.35 + target_size * 0.35` (0.35 to 0.70 envelope)

**Shift impact impression:**
- Larger engines produce longer, heavier jolt pulses
- Jolt envelope: `1.22 + target_size * 0.25` (1.22 to 1.47 baseline)
- Scrape intensity scales: `0.72 + target_size * 0.12` (0.72 to 0.84)
- Larger engines also produce more scrape bursts: `5 + (target_size * 3)` bursts (5 to 8)

**Mechanical friction and character:**
- Cold engines (larger) exhibit more mechanical rattle: `mech_grit = 0.70 + target_size * 0.55` (0.70 to 1.25)
- Mechanical click frequency decreases with size (deeper clicks): `2200 - target_size * 420` Hz
- Mechanical rattle raw amplitude: `(0.44 + target_size * 0.24)` scaling

**Core engine output:**
- Engine volume scales: `engine_out *= (0.5 + target_size * 1.0)` (0.5x to 1.5x)

**Flywheel inertia:**
- Larger engines have higher inertia (slower RPM decay on throttle release)
- `flywheel_speed_mult = 1.0 - (target_size * 0.75)` (1.0 to 0.25, lower = slower decel)

### Core Character (slider14, -100 to +100)
Character morphs the combustion sound from Thump (negative) to Rasp (positive):
- `-100 (Thump)`: deep, smooth, mechanical character
  - Emphasizes low-frequency harmonics
  - Smoother transients
  - More "muscular" feel
- `0 (Balanced)`: neutral mix of harmonics
- `+100 (Rasp)`: bright, edgy, high-frequency emphasis
  - Sharper harmonic skew
  - More "angry" or "aggressive" tone
  - Better for high-revving or tuned engines

Formula: `skew = target_character` is applied in core combustion waveform shaping to adjust spectral emphasis.



### Thermal State Model
The engine maintains a normalized thermal state (`thermal_norm`, 0.0 = cold, 1.0 = fully hot):
- **Warm-up while running**: `therm_up_tc = 1.0 - exp(-(dt / srate) / 45.0)` (~45 seconds to reach full warmth)
- **Cool-down while off**: `therm_dn_tc = 1.0 - exp(-(dt / srate) / 90.0)` (~90 seconds to reach full cold)
- **Cold factor**: `cold_fact = 1.0 - thermal_norm` (inverse, used to scale cold-engine effects)

### Cold Start Effects
The Cold Start parameter (1-100) controls startup character:
- **Starter duration**: `starter_timer = cold_start * 2.0` (0.02 to 2.0 seconds based on slider)
- **Post-start idle stabilization**: extends by `cold_start * 0.9` additional cycles
- **Starter motor roughness**: `starter_den = cold_start * 2.0 + 0.1` (RPM jitter amount)
- During startup (if `starter_timer < cold_start`), RPM is randomized: `cur_rpm += rand(150)`

### Temperature Effects on Performance

**Idle RPM adjustment** (while engine running):
- Cold idle: `base_idle_rpm = 800 + cold_fact * 280` (up to 1080 RPM when cold)
- Hot idle: `base_idle_rpm = 800` RPM (stable after ~45s warm-up)

**Mechanical friction layer**:
- Cold engines have added friction: `bus_mech += cold_fact^2 * 0.28` (quadratic falloff as engine warms)
- Creates audible mechanical clatter and higher frequency content when cold

**Combustion character adjustment**:
- Rough factor scales with cold: `rough_fact = (target_roughness + cold_fact * 0.20) * ...`
- Cold combustion adds exhaust rasp: `exh_rasp *= 1.0 + cold_fact * 0.45` (40% additional rasp when fully cold)

**Backfire/crackle behavior**:
- Microbackfire probability influenced by temperature: `temp_fire = 0.65 + thermal_norm * 0.70`
- Hot engines crackle more actively (70% increase from cold baseline)
- Cold engines produce fewer backfires (65% of hot engine level)

### Temperature Indicator Display
Live thermometer color transitions based on `thermal_norm`:
- **R (Red)**: `0.30 + thermal_norm * 0.65` (0.30 cold, 0.95 hot)
- **G (Green)**: 
  - If `thermal_norm < 0.5`: `0.52 + thermal_norm * 0.36` (0.52 to 0.88)
  - If `thermal_norm >= 0.5`: `max(0.0, 0.70 - (thermal_norm - 0.5) * 1.10)` (0.70 to 0.0)
- **B (Blue)**: consistently 0.0
- **Color progression**: Deep blue (cold 0%) → Cyan (20%) → Amber (50%) → Red-orange (80%) → Bright red (100%)

### Integration with Other Systems
- Thermal state is **not** affected by throttle/RPM directly, only by engine on/off state
- Warm-up and cool-down occur regardless of load or speed
- Temperature persists across gear changes and mode switches
- Cold Start slider value is read once at ignition-on and uses that value for the startup sequence


## 12. Output Buses and Routing

Available buses:
- Exhaust
- Engine Core
- Mech / Whine / Starter
- Gearbox / Shift
- Intake / Turbo Whine
- Turbo BOV
- Road / Tire
- Chassis Sub
- Brakes
- Explosions
- Wind

Lua Master routing tools:
- Auto Build Routing: creates folder and one child track per bus.
- Folder naming: `Car "Name"`.
- Cleanup Routing: removes generated folder/tracks for current linked source track.

## 13. Feature Coverage Checklist

All key mechanics covered in this guide:
- ignition state machine and startup flare
- Direct vs Physics mode
- D/S/M transmission behavior deltas
- Shift Intent logic and adaptive triggers
- throttle-drop BOV/crackle trigger
- auto-engage from neutral threshold
- exact upshift scheduler (speed/RPM/throttle/force fallback)
- exact downshift scheduler (intent, guards, speed gates)
- manual shift style differences (N->1 vs gear-to-gear)
- engine braking formula and RPM decel injection
- coasting, stop-hold, stop-lock logic
- speed override domain behavior and drift use case
- core engine size (volume, startup, shift impression, mechanical character)
- core engine character (Thump ↔ Rasp spectral shaping)
- thermal warm-up/cool-down influence on all subsystems
- cold-start severity and duration control
- routing architecture and bus descriptions
- telemetry channels for Lua UI gauges

## 14. Recommended Debug Workflow

1. Verify mode and transmission first.
2. Verify Shift Intent next.
3. Watch live RPM and speed telemetry in cockpit.
4. Tune RPM Target/Rev Limiter after intent and mode are correct.
5. Only then fine-tune transient layers (jolt/scrape/crackle/ALS).
