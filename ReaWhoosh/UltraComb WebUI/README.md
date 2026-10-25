# SBP UltraComb 3.14.0

A stereo processor for metallic movement, inharmonic comb textures and creative
sound transformations. This is a separate effect from UltraComb 2.40.

## Install with ReaPack

1. Import the SBP repository in **Extensions → ReaPack → Import repositories**:
   https://raw.githubusercontent.com/Bodzijun/SBP-Reaper-Scripts/main/index.xml
2. Import zaibuyidao's repository for the WebUI runtime:
   https://raw.githubusercontent.com/zaibuyidao/ReaScripts/master/index.xml
3. In **Browse packages**, install **ReaWebAPI: Web Runtime for REAPER**
   version **0.3.9.10 or newer**, and **SBP UltraComb WebUI 3**.
4. Restart REAPER after installing/updating the ReaWebAPI extension.
5. Add **JS: SBP UltraComb WebUI 3** from the FX browser.

Publication of the UltraComb package is a separate maintainer step; the local
release files alone do not make the package available in the public index.

Release target: REAPER 7.80+ with ReaWebAPI 0.3.9.10+.
Windows requires the WebView2 Evergreen and VC++ x64 runtimes described by
[ReaWebAPI](https://github.com/zaibuyidao/ReaWebAPI#download-and-install).
Cross-platform installation packages are provided by ReaWebAPI upstream.
UltraComb has been developed/tested on Windows; macOS/Linux host acceptance
is not claimed. ReaPilot Bridge is a development tool and is not required.

## Install manually

Copy the complete `SBP UltraComb WebUI 3` directory from the manual release ZIP
into REAPER's `Effects` directory (Options → Show REAPER resource path).
Keep `sbp_ultraComb_webui.json`, `reaweb_jsfx.jsfx-inc` and `webui/packed.html` alongside
the main JSFX. ReaWebAPI itself must still be installed separately.

Without a valid hosted WebUI the legacy native graphics remain available, but
they do not expose all of the version 3 controls. Use the WebUI for the complete
interface. ReaPack installs the same relative runtime file layout.

## New in 3.14.0

- Update the embedded ReaWebAPI SDK to **0.3.9.10**. The matching installed
  runtime is required; the extension remains a separate ReaPack dependency.
- Existing DSP streams now recover through the SDK after preset resets,
  session replacement and audio-device recovery, preserving their subscriptions.
  Silent valid streams stay connected. The UI only retries missing initial
  streams, with three bounded retries; it no longer tears down all streams
  because no packets arrived during a timeout.
- Delegate unmodified Space to native **DAW keyboard** routing. REAPER's current
  shortcut binding is respected outside editable fields; normal typing remains
  intact. Remove the custom Play/Stop interception.
- Keep the four-file package and the original WebUI app root. DSP algorithms,
  native parameter IDs and the existing local labels/units/groups are unchanged.

## Changes in 3.13.2

- Feedback slider, capture dot and return arrow use yellow accents. Feedback
  label/value use the normal dark interface text.

## Changes in 3.13.1

- Keep the editor in its original `webui` application root. This fixes
  APP_ID_CONFLICT when upgrading an already-open ReaWebAPI session.

## Changes in 3.13.0

- The installed package now has only four files: JSFX, its association JSON,
  `reaweb_jsfx.jsfx-inc` and self-contained `webui/packed.html`. WebUI code, styles,
  parameter registry, complete license texts and editable module sources are
  bundled into the HTML. LICENSES in the footer opens the full notices.
- Original modules remain editable in the source repository. Build with
  `node tools/build-registry.mjs`, then `node tools/build-webui.mjs`.
- The packaging removes the loose MJS/CSS/license files that REAPER listed as
  fake JS effects. After upgrading, refresh the FX browser with F5. Two installed
  copies still produce two real UltraComb entries; projects retain their paths.

## Changes in 3.12.1

- Matrix sources display Off, LFO 1, LFO 2, Envelope, ADR 1, ADR 2; native IDs
  and saved routing remain unchanged.
- ADR shape shortcuts use the same pale green as active analyzer tabs.
- Violet feedback amount/capture indicators share a return arrow beneath the
  chain, pointing from the selected capture point back to Core. Zero Feedback
  dims/dashes the arrow. Core capture points have a small local return loop.

## Changes in 3.12.0

- Two independent **ADR 1 / ADR 2** sources, selected with bottom buttons like
  LFO 1 / LFO 2. Each keeps its own segment times/curves, FREE/SYNC divisions,
  input/sidechain threshold, trigger mode and loop direction.
- MIDI Note On can trigger both ADRs when both use MIDI mode. Manual TRIGGER
  affects the selected ADR only; each audio detector can use IN 1/2 or EXT 3/4.
- Matrix source **ADR 2** and eight new ADR 2 destinations; its controls support
  automation, Randomize and Morph, including a separate ADR 2 scope.
- Warm sand-coloured RISE/FALL/TRI/PULSE presets distinguish shape shortcuts
  from trigger modes. Compact layout keeps the bottom selector visible.
- Native IDs 200–214 are appended; old parameter IDs and A/B snapshots remain.
  Reinsert the effect to load the expanded parameter list.

## Changes in 3.11.0

- **FREE / SYNC** timing for LFO 1, LFO 2 and ADR. FREE preserves Hz/ms values;
  SYNC uses separate automatable musical-division parameters. Switching back
  restores the previous FREE values.
- Divisions include straight notes, triplets (T), dotted notes (D), and
  **1 / 2 / 4 / 8 bars**. Bars follow the current project time signature;
  all timings follow project BPM. ADR preview shows bars in SYNC.
- Playing/recording locks unmodulated SYNC LFO phase to project beat position,
  including seeking. Stopped transport runs at the tempo-derived rate for audition.
  Matrix Rate modulation continuously scales that rate in octaves; a modulated
  rate runs continuously rather than remaining locked to the beat grid.
- ADR retains Audio / Manual / Loop / MIDI triggering and Ping-Pong direction.
  SYNC changes segment durations, not their trigger source. Envelope-follower
  Attack/Release remain physical response times, independent of tempo.
- Randomize respects FREE/SYNC and preserves each inactive timing bank; it does
  not switch timing modes. Morph stores both banks and switches mode/division
  choices discretely. Old A/B snapshots load with FREE as the default.
- Native parameters 192–194 select timing mode; 195–199 select LFO/ADR divisions.
  Existing IDs remain unchanged. Reinsert the effect to load the new parameters;
  avoid Full recompile/reset while a hosted WebUI is open.

## Changes in 3.10.1

- Native slider thumbs paint above the read-only cyan modulation strip/marker.
- FX Feed matrix depth expands from 25 to **200 ms per unit Amount**, with the
  physical delay still clamped to 0–200 ms. Matrix span labels and live range
  telemetry use the same scale. Existing FX Feed routes therefore have eight
  times the former depth; divide Amount by eight to retain an earlier depth.

## Changes in 3.10.0

- Matrix destinations have a separate **cyan modulation strip**: the translucent
  band shows the assigned range and a thin marker shows the current native value.
  The normal thumb and number stay at the base setting. This covers all available
  matrix targets, the shared Feedback slider and All Parameters. Hover shows the
  current value/range; an orange marker indicates a value outside the base slider's
  display range. Read-only indicators do not intercept mouse input.
- Core Comb / Disperser / Shift, Filter and Chorus models use fresh DSP feedback
  for assigned parameters. These remain parameter models, not measured spectra.
  Native module trajectories are used where available; other controls report the
  bounded value after the smoothed matrix. Chorus Mix affects trace brightness.
- Ranges combine all sixteen routes, polarity, signed amounts/source depths,
  enabled sources and matrix/parameter limits. Multiple sources show their summed
  result. Disabled assigned sources retain their marker with a collapsed range.
  Matrix Off or telemetry older than 500 ms hides the strips and restores base
  models. No base parameter, automation or DSP state is written by the display.
- Reinsert the effect to load the expanded native telemetry. Original parameter
  IDs, A/B snapshots, audio processing and the prior 42-field control prefix remain
  compatible; the live overlays require the new DSP frame.

## Changes in 3.9.1

- Analyzer header statuses are hidden; IN/OUT and the three fixed-width tabs
  retain the same geometry during stream changes. Active tabs use a light fill.
- MONO sits below the goniometer circle, above the correlation meter.
- Spectrum uses monotone interpolation between resolved FFT bins, with exact
  low-frequency bin anchors and peak pooling where multiple bins share a pixel.
  This removes low-end stair steps without changing FFT resolution or audio DSP.

## Changes in 3.9.0

- Frequency Shift defaults to **LINEAR** slider sensitivity: equal movement gives
  equal Hz changes across the range. **FINE** restores the former cubic law for
  finer control near zero. Switching sensitivity preserves the current frequency.
  This is a remembered UI preference; native parameter values, automation and DSP
  smoothing are unchanged. The typed numeric field remains exact.
- IN and OUT have independent **Spectrogram / Spectrum / Stereo** buttons.
  Spectrum shows separate L/R frequency curves; Stereo shows a real PCM goniometer
  and a smoothed correlation meter (mono +1, antiphase -1). Silence and single-sided
  input show no valid correlation rather than a made-up value. The trace uses
  linked visual auto gain, which does not change audio.
- Analysis selections are remembered. Pause/Clear work for all views; History
  and color maps apply when a Spectrogram is visible. Stereo opens a raw PCM
  stream in place of that side's FFT stream. Only two audio analysis streams
  plus modulation are active, avoiding duplicate telemetry. Changing a display
  never writes an audio parameter. Fresh DSP is required for the new PCM streams.

## Changes in 3.8.0

- Comb plots stop drawing separate teeth when their extrema would be closer than
  four pixels (at most twelve periods). The dense remainder is a smooth shaded
  range, accounting for fractional-delay attenuation. Frequency spacing and audio
  processing do not change.
- ADR Attack, Decay and Release each extend to **30,000 ms / 30 s**: a complete
  shape can span **90 seconds**, or 180 s for a Ping-Pong round trip. Long graph
  axes show seconds. Native automation, matrix targets and Random/Morph cover
  the expanded ranges; Random uses a conservative 15 s maximum per segment.
- **MIDI** is a separate ADR mode alongside Off / Attack / Manual / Loop. Each
  incoming Note On with positive velocity retriggers the complete one-shot form
  at its sample offset. Note Off and held notes do not loop/hold the envelope;
  simultaneous chord notes coalesce into one start. All MIDI channels/buses are
  accepted and MIDI is passed through. Notes must actually reach this FX instance
  via the track's MIDI input/items/routing; the computer's ordinary typing keys
  are not a global MIDI source. Manual mode continues to use the Trigger button,
  which is also available as a manual override in MIDI mode.

## Changes in 3.7.0

- Filter has two rows of four native modes: LP / HP / BP / Notch and
  **Peak / Vowel / Comb+ / Comb−**. All modes are available to Random and Morph;
  existing mode numbers and all other parameter IDs remain unchanged.
- **Peak:** a resonant boost; Resonance controls its gain and width.
  **Vowel:** two normalized bandpasses at Cutoff and 2.4×Cutoff.
  **Comb±:** feed-forward interference with positive/negative delayed polarity;
  Cutoff sets tooth spacing (delay = 1/Cutoff), Resonance sets notch depth.
  Comb is normalized, with no internal feedback. It can color the main Core loop
  without introducing another resonant feedback loop. Its private stereo history
  stays warm; delay motion and mode changes are smoothed.
- The response graph matches the native digital filter, including phase when
  blended with dry, normalized BP, both Vowel peaks and fractional Comb delay.
  Drive warms the curve/fill from green through orange to red (0 / 12 / 24 dB).
  Color is a Drive cue; the graph remains a linear response model, not a live
  harmonic spectrum of the saturated signal.

## Changes in 3.6.1

- ADR preview ends at Release, without a misleading horizontal tail.
- In Loop mode, **Forward / Ping-Pong** selects repeated forward passes or the
  complete forward/reverse cycle (A-D-R, then R-D-A). Reverse playback retains
  each segment's curve; the live position retraces the graph. One round trip
  takes twice the displayed A+D+R duration. Direction is native parameter 191,
  supports automation, Random and Morph, and defaults to Forward in older states.

## Changes in 3.6.0

- MOD now has **LFO / ENV / ADR**. ADR Attack mode already provides input-triggered
  ramps, so Motion is retired from the panel, new matrix assignments, bulk scopes
  and All Parameters. Its native IDs and saved routes remain readable for compatibility.
- ADR has independent **A Curve / D Curve / R Curve**, paired with Attack / Decay /
  Release. Negative values bend early, zero is linear, positive values bend late.
  The graph follows each segment independently. IN 1/2 and EXT 3/4 triggering,
  threshold meter, Manual trigger and Loop remain available.
- All three curves support REAPER automation, matrix modulation, Random and Morph.
  Attack Curve retains ID 147; Decay/Release Curve append IDs 189/190. Older saved
  shared curves are copied to both new segments and A/B endpoints when loaded.
- Existing matrix source/target numbers remain stable. The two retired Motion
  destinations are hidden from new assignments; the new D/R curve targets are 69/70.

## Changes in 3.5.0

- **16 matrix routes**, with single-line controls and a shared column header.
  Divider lines and repeated field labels are removed to fit more visible rows.
- Every route has native **AUTO / UNI / BI** polarity. AUTO retains the source's
  native range: LFOs are bipolar; Motion, Envelope and ADR are unipolar before
  their depth control. UNI maps an LFO to 0–1; BI maps an active unipolar source
  from 0–1 to -1–+1 around the target's base value. Negative Amount still inverts
  the route. Disabled LFO/Motion/ADR sources and zero source depth remain neutral.
  An enabled, idle unipolar source at zero becomes -1 in BI; this is intentional.
- The matrix now has **68 targets**, including LFO phases, Motion decay/threshold,
  Envelope depth/sensitivity/attack/release, ADR threshold and Doubler low/high cut.
  Enum switches, held Freeze capture length and stage-count modulation remain
  outside the continuous matrix. Motion/ADR meters show the effective native
  threshold when the matrix modulates it.
- Randomize and Morph have independent **module Scope** selectors, including
  Shift, ADR, each LFO, Envelope and Matrix. All preserves the previous bulk
  behavior and its existing protected global/utility controls. The older Pitch
  family, Tone and Modulation scopes retain their membership; Pitch FX and
  Motion provide narrower choices. Morph Scope limits subsequent updates and
  does not undo changes already made under another scope.
- Randomize varies depth only on assigned routes and preserves Source, Target
  and Polarity. Morph treats polarity as part of a route's identity, fading its
  depth through zero before switching Source/Target/Polarity. All 16 routes and
  all new settings are native automation parameters and saved in presets.
- Snapshot v7 reads v1–v6 and seeds added controls safely. Old first-eight route
  IDs are unchanged. New routes 9–16 use IDs 148–171, polarity uses 172–187, and
  Morph Scope is 188. Matrix accumulators use independent 128-cell banks.

Reinsert the effect after updating. Expanded Target and Scope enums change
normalized external parameter-link/MIDI positions; check such selector mappings.

## New in 3.4.0

- Modulation families are **LFO / Motion / ENV / ADR**. Independent LFO 1/2
  selection now sits below the LFO controls; their existing IDs/settings remain.
- Motion has a fixed **0–1100 ms** preview: Decay changes the visible length and
  slope, matching the native 2 ms rise + 3 ms plateau + linear decay. The right
  meter shows the actual selected IN 1/2 or EXT 3/4 detector level/peak in dB
  with a Threshold line. Without fresh telemetry it shows no invented level.
- **ADR** is a three-segment source: Attack to 1, Decay to Bend Level, Release
  to 0. It has no held sustain or arbitrary-point MSEG editor. Attack/Manual/Loop
  modes, a manual TRIGGER, Curve, IN/EXT detection and RISE/FALL/TRI/PULSE shape
  shortcuts support ramps and simple modulation shapes. Retriggers start from
  the current output; Attack mode rearms after the detector falls below half
  the threshold. The graph is a base-parameter model plus a real DSP position.
- Native parameters **140–147** cover ADR mode/source/threshold/shape. ADR is
  appended as matrix source **5**, with timing/level/curve destinations **53–57**.
  It requires Matrix routing, defaults Off and has no fixed effect assignment.
- All ADR controls support automation and Morph. Randomize covers mode/shape
  while preserving the chosen detector input; gentle randomization retains Off.
  Snapshot v6 reads v1–v5 and seeds absent controls from their loaded values.
- The modulation stream carries 40 control values through one SDK transport
  channel (not PCM), retaining the old LFO/Doubler offsets. Native audio paths
  are unchanged when ADR is Off and its routes are unassigned.

Reinsert the effect to load the longer native parameter list and stream layout;
avoid Full recompile/reset with the hosted editor open. Existing source/target
IDs retain their meanings; normalized links to the expanded matrix selectors
should be checked when updating.

## New in 3.3.0

- **Stereo Offset, Hz** (native parameter 137): -1000 to +1000 Hz. Left uses
  Shift minus Offset; Right uses Shift plus Offset. Small values create stereo
  beating; larger values create opposing metallic translations.
- **Sideband** (138): +1 is the original signed Shift, 0 mixes both sidebands
  equally (ring modulation), -1 selects the opposite signed Shift. Intermediate
  values blend continuously; negative Shift reverses the physical upper/lower
  sidebands. Ring naturally has lower energy than a single isolated sideband.
- **Shift Mix** (139): blends the processed signal with the signal immediately
  before Frequency Shift, inside Core and before Post Shift feedback capture.
  It is independent of the global Dry / FX blend.
- All three controls are smoothed, native/automatable, covered by Morph and
  Randomize, and available as matrix destinations 50–52. Neutral defaults
  **Offset 0 / Sideband +1 / Mix 1** exactly retain the prior shifter algorithm.
- Shift stays horizontal; the three new controls use the space below it. The
  schematic shows separate L/R paths, solid main/dotted opposite sidebands,
  dry contribution and an elliptical rotor that becomes a line in Ring mode.
  It shows base parameters, not the live audio/modulated spectrum.
- Snapshot format v5 reads v1–v4 and seeds the added controls from loaded values.
  Reinsert the effect to load the longer native parameter list; avoid Full
  recompile/reset while WebUI is open. Existing parameter/route IDs are retained.
  The extended matrix Target enums change normalized external-link mappings;
  check any MIDI/parameter-link mappings that address Target selector positions.

## New in 3.2.2

- Measurement units follow control names (for example, `Spread, %`), keeping
  numeric fields and vertical faders aligned without a separate unit row.
- Disperser's automatic vertical scale changes continuously instead of jumping
  between rounded limits. The displayed group-delay model and audio DSP are
  unchanged; the peak readout remains in milliseconds.
- Frequency Shift shows reference harmonics and their equal-Hz translation,
  including reflection around 0 Hz for negative frequencies. The rotor indicates
  direction at a deliberately scaled speed. This is a parameter schematic,
  not a measured spectrum or a live oscillator-phase display; reduced motion
  disables the animation. Audio parameters and preset formats are unchanged.

## New in 3.2.1

- Doubler now has two independent stereo pitch voices. Voice Pitch is their
  common centre; Detune offsets one voice down and the other up. Width blends
  their stereo placement while preserving the incoming main signal.
- After a genuine quiet gap (below -90 dB long enough to drain the histories),
  the next sound starts with repeatable read-head positions and a soft voice
  fade-in. Short pauses and transients do not reset an existing tail. Narrow
  tonal signals can still have frequency-dependent stereo width.
- Shared Core numeric fields sit beside their horizontal sliders. Disperser
  vertical sliders expand into the saved space; the shared block stays anchored.
- Parameter IDs/ranges and Morph/Randomize coverage are unchanged. Doubler's
  sound changes because Detune now affects two opposing voices.

## New in 3.2.0

- **Spread Curve** (native parameter 136): -1 concentrates section centres near
  the edges, 0 exactly preserves the original distribution, +1 concentrates
  them near Center. Span/endpoints remain unchanged before frequency limits.
- Curve is available to automation, the modulation matrix (destination 49),
  Morph and Randomize. Snapshot format v4 reads old v1/v2/v3 records and seeds
  Curve at its loaded setting when it was absent.
- Disperser now plots the underlying all-pass cascade's **group delay in ms**,
  with a section-centre strip, Center guide and frequency scale. Q changes
  peak height/width; this is a base-parameter model before Phase Subtract,
  not an amplitude response or live measurement.
- Center is the primary horizontal slider. Shared Core controls remain anchored.
- The unmodified JavaScript SDK helper is updated to ReaWebAPI v0.3.9.2,
  including bounded startup `STALE_SESSION` recovery. The EEL SDK is unchanged.
  The native extension is installed separately.
- Controls stay disabled if an older, still-loaded DSP exposes a mismatched
  parameter list. Reinsert the effect to load the new native controls; this
  prevents a new parameter control from addressing an old host Bypass slot.

## New in 3.1.0

- Dry Delay and FX Feed now both span **0–200 ms**; defaults remain 0 and 3 ms.
- Comb has a fixed millisecond scale and animated branch wave illustrations.
  These are labelled schematics, not captured audio or an oscilloscope.
- Shared Core drive/blend/return/feedback controls stay at the bottom across tabs.
- Dedicated Comb buffers follow the other variable-size banks and retain the
  existing fractional interpolation and delay smoothing at high sample rates.

Delay parameter IDs and 0.1 ms steps are unchanged. The expanded maxima alter
the mapping of normalized controls: a 0.5 normalized value now means 100 ms,
rather than 25 ms. Check existing normalized MIDI/parameter-link mappings when
updating. Existing values stored explicitly in milliseconds retain their meaning.
The 3.1.0 update did not change the Disperser distribution; 3.2.0 adds Curve with a neutral default.

## Signal and modulation

- **Core:** parallel Dry/FX Feed delays, feedback, Disperser and Frequency Shift.
- **Creative chain:** reorder Freeze, Pitch, Doubler, Ring, Metal, Saturation,
  Filter and Chorus. Core stays first.
- **Modulation:** independent LFO 1/LFO 2, input Envelope
  follower and three-segment ADR ramps, with selectable IN 1/2 or EXT 3/4 detection.
- **Matrix:** sixteen routes and 68 targets, including both LFOs' Rate/Depth/Phase.
  Rate modulation uses octaves; amount/depth values are bounded and smoothed.
- **Morph/Randomize:** typed controls, complete A/B snapshots and matching
  native/Web randomization policy. Gentle randomization preserves modes.
  Changed matrix links fade through zero; Randomize varies existing route
  amounts rather than inventing links.
- **Output:** gain, optional Hard/Soft clipping, and selectable ceiling.
- **Displays:** live input/output spectrograms with four palettes. Other graphs
  illustrate parameter models and modulation telemetry, not measured responses.

All 186 active WebUI controls (plus four retained legacy controls) are native JSFX parameters available for REAPER
automation. Slot 88 is reserved for the WebUI transport. **Core Feedback** is
native parameter **6**, named `Core Comb Feedback` in the parameter list.
The effect uses channels 1/2 for audio and channels 3/4 only as detector inputs.

## A/B, projects and updates

Existing UltraComb 2.40 instances are unchanged. Version 3 has its own FX identity;
automatic conversion of 2.40 projects/presets is not provided.

Morph stores the current complete parameter state with STORE A/STORE B.
When loading old 64/84/135/136/139/147-value snapshots, newer controls inherit the loaded value
at both ends; store A and B again to define different values for them.
Global gain/blend, output protection, chain order/capture, routing mode, held
Freeze capture, utilities and transport stay excluded from bulk changes.

For preview-to-release testing, close the editor and insert a fresh instance.
Avoid Full recompile/reset with the hosted editor open: it previously caused
a hang in the development session. Preserve any project settings before replacing
an instance. ReaWebAPI protocol v1 and the package-local SDK copies are required.

## Included sources and notices

The package is distributed as editable source. SDK copies remain unchanged from
ReaWebAPI 0.3.9.2. See [THIRD_PARTY.md](THIRD_PARTY.md) and `licenses/` for
provenance, the complete LGPL/GPL texts and the retained DSP component notices.
The SDK files can be replaced/rebuilt from their pinned upstream source.

Maintainer packaging/validation instructions are in repository-only
`PACKAGING.md`; preview history is in repository-only `DEVELOPMENT.md`.
