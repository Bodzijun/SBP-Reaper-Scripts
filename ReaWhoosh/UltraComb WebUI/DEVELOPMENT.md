# UltraComb 3 — development and preview history

Separate effect and package. `../sbp_ultraComb.jsfx` (2.40) is preserved.
Install the whole directory under REAPER Effects, keeping relative paths.
Requires ReaWebAPI for the HTML editor. Without a hosted WebUI the copied
native gfx remains available. The supplied EEL include must remain installed.

The existing 87 parameter IDs are preserved; ID 88 is reserved for the native
channel. Existing projects continue using 2.40 and are not silently upgraded.
This is a separately identified FX; automatic preset/project migration is not
claimed. Copy saved parameter settings explicitly when comparing versions.

IN/OUT spectrograms are live time-frequency displays of raw input and final
output PCM, not generated animations. No data means no fabricated signal.
Opening the editor must not write parameter defaults. All graph curves apart
from the spectrograms are parameter-based illustrations, not measured responses.

Preview acceptance requires native automation, command/Undo, multiple-instance,
audio continuity and spectrogram tests. Do not publish before checking the
vendored SDK's matching runtime and full third-party notices.

## Preview verification

3.12.0 adds a second independent uc_adr instance using native 200–214. Source 6
and destinations 71–78 append to the existing Matrix IDs. Both MIDI sources use
the same sample-offset Note On bins, but dispatch independently by their own
mode; one event can trigger both once. Manual commands keep distinct counters
(adrTrigger ordinal 3, adr2Trigger ordinal 4). Raw IN/EXT detection, target values,
segment state and peak meters remain independent. ADR 2 scope is appended at 21;
Random/Morph reuse the typed policy with owner 211 for its timing bank. Snapshot
version 11 stores 214 slots and seeds v1–v10 defaults without renumbering IDs.

The stream stays a single read-only channel: 542 scalars/version 3, reserving
640 cells before MATRIX. Prefix 0–480 is retained. Eight appended destination
records at 481+i*6 carry amount/current/low/high/base/assigned. ADR 2 state is
529–534 (phase/value/on/detector/peak/threshold); 535–541 add timing/divisions
and tempo-derived segment bases. VIS and MATRIX still use 128-cell strides.
Decode accepts earlier 464/v1 and 481/v2 packets. Tests cover source 6 in all
polarities, Off neutrality, both MIDI counters at exact offsets, separate
trajectories, scoped bulk edits, snapshot migration and read-only display banks.
Mock-host browser checks cover independent settings, selected manual command,
mode-specific controls, source/destination menus and selector fit at four sizes.
Native REAPER compilation and audio acceptance remain separate.

3.11.0 appends native IDs 192–199 without renumbering 1–191. Free/Sync flags
192/193/194 default Free; separate division IDs 195/196 and 197–199 leave all
free Hz/ms values untouched. Twenty-two choices cover straight/triplet/dotted
notes and 1/2/4/8 bars. @block reads tempo, ts_num/ts_denom and beat_position;
@sample extrapolates quarter-note position. Unmodulated synced LFOs anchor to
transport while playing/recording. Rate cross-modulation instead integrates a
continuous tempo-derived rate, bounded to 1e-6–512 Hz; Free stays 0.02–12 Hz.
ADR internal duration ceiling is one hour to allow slow multi-bar segments;
Free callers retain the 30-second ceiling. Envelope detector times stay free.

Telemetry 2 is now 481 scalars, version 2 at offset 42. Prefix 0–41 and the
70-destination layout at 43–463 are retained. Offset 464 adds BPM, numerator,
denominator, beat, mode flags, divisions and tempo-derived base values. The
512-cell reservation/one-channel transport remains unchanged. Synced alias
widgets use original Hz/ms destination telemetry, not division indices.
Older 464/v1 packets are still accepted. RANDOM_SYNC policy adds an isolated
256-cell bank at 247840; positive owner requires Sync, negative requires Free.
Mode flags are Morph-only; Random edits only the active timing bank. Snapshot
version 10 stores 199 values and seeds v1–v9 records with new loaded defaults.

Source-executed tempo tests cover 30–300 BPM, 4/4, 3/4 and 7/8, Free identity,
seek/negative beat phase lock, rate cross-modulation and 64-second ADR stages.
Bulk tests compare native/Web policy in both timing modes and migrate v1–v10
A/B records. Mock-host browser checks cover native writes, independent LFO
modes, retained free values, ADR presets and four compact viewport layouts.
These tests do not replace native REAPER compilation/audio acceptance.

3.10.1 puts native range inputs at stacking level 2 and modulation strips at 1,
so the opaque native thumb covers overlapping marker pixels. Positioning and
pointer transparency are unchanged. FX Feed destination 2 now uses 200 ms in
the actual delay2_target formula, matrixTargets and VIS_SCALE[2]. Destination 1
Dry Delay is unchanged. Tests execute the actual formula at 44.1/48/96 kHz for
positive/negative depth and boundary bases, retaining the existing causal/glide
regressions. Browser checks verify thumb/marker stacking without base-value writes.

3.10.0 adds read-only modulation feedback for 70 stable destination slots (two are
legacy-only). Native stream 2 grows to 464 scalar values on ONE transport channel,
points/fftSize 512; no additional subscriptions or per-sample work are introduced.
The original 0..41 prefix is unchanged. Layout: 42=version 1, 43=Matrix active,
44..113=smoothed matrix sum, 114..183=current bounded control, 184..253=min domain,
254..323=max domain, 324..393=base slider, 394..463=assignment flags. Domain ranges
use uc_matrix_convert at source extrema, preserving Auto/Uni/Bi and signed depth
before amount, sum all sixteen routes and clamp to +/-1. Native current values
read smoothed module trajectories where present; remaining controls are the
post-matrix clamped targets. Mix indicators may report the control target while
a module is off, rather than its gated zero contribution. Disperser models use
native configuration values, not inversion of the interpolated all-pass coefficients.
WEB_MOD reserves 512 cells; MATRIX follows, then MATRIX_TARGET and five 128-cell
mapping tables. CHORUS_MEMORY aligns after VIS_KIND. Allocation checks cover
44.1–768 kHz, and snapshot tests prohibit writes outside WEB_MOD or to sliders.
The shared mapping is feedbackTargets; native tables are generated from it and
the parameter registry. Helpers must remain in @init before @slider, and retain
global read access. Keep native limit definitions aligned with feedbackLimits.
UI overlays are absolute/read-only siblings, with a two-phase read/layout/write
pass to avoid moving or wrapping the input. Custom Core Feedback also registers
a widget. Current-value graphs use assigned feedback only, expire after 500 ms,
and repaint once on removal/off/stale to restore their base model. Modulation
animation changes no native parameter and adds no random/morph controls.
Tests execute native snapshot math, verify signed/bipolar summed domains, current
trajectories, metadata mapping, old decoders, memory/slider immutability and stale
handling. Browser mock tests cover moving markers, base thumb/number preservation,
Core/Filter/Chorus models, All Parameters, pointer transparency and no host writes
on four viewport sizes. Native REAPER compilation/listening remains separate.

3.9.1 is display-only. Header status nodes remain for stream lifecycle handling
but are hidden and excluded from the fixed two-column header grid. Three equal
tab columns and a light active fill preserve geometry and visual symmetry.
Goniometer geometry reserves a line below its circle for MONO, above correlation.
Spectrum replaces repeated max-bin values at resolved frequencies with bounded
monotone Hermite interpolation in dB. Exact bin-centre anchors retain narrow peaks;
subpixel bands transition smoothly to peak pooling. Spectrum positions are now
explicit normalized coordinates, rather than an assumed 256-point uniform grid.
Tests retain measured levels, verify strictly monotone low-end ramps and bounded
values. Browser checks vary header statuses and view modes without any tab movement,
compare IN/OUT geometry and verify MONO remains below the circle on four viewports.
Native FFT size, PCM publication, parameter ranges and audio DSP are unchanged.

3.9.0 preserves all native parameter IDs, ranges and DSP smoothing. Shift 12 is
linear by default in the UI; optional Fine is the previous signed cubic mapping.
The choice is a local preference, not a native parameter or bulk-edit target.
Stereo Offset 137 retains its prior fine mapping. Both mappings are tested for
exact inverse/step behavior and preference switching must not write to the host.
New analysis-view wraps the existing Spectrogram and adds log-frequency L/R
Spectrum curves and PCM goniometry. Stereo is Side=(R-L)/sqrt(2), Mid=(L+R)/sqrt(2).
Correlation smooths linked L/R powers and cross product over 250 ms; undefined
single-sided/silent correlation displays a dash. Linked visual gain retains shape,
and non-spectrogram canvases use matching CSS/drawing dimensions to preserve aspect.
Association streams 0/1/2 are unchanged. Optional 3=inputStereo and 4=outputStereo
publish the same unmodified interleaved 512-frame capture as raw audio, not spectrum.
Capture gating includes either PCM subscription; no new audio memory is needed.
Per-side stream tokens close superseded subscriptions and reject old callbacks;
switching FFT/Spectrogram reuses a stream. Only one stream per side plus modulation
is open. Reset recovery closes all tokens and restores the selected stream types.
Tests execute native capture/publish statements and preserve channel phase and
timestamps. Browser mock checks live mono/antiphase/silence, pause/resume, routing
races, preference persistence and no host writes. Real REAPER acceptance is separate.

3.8.0 preserves 191 native slots. ADR timing 143/144/146 expands to 30000 ms in
sliders, native clamps, matrix destination clamps, preview and bulk metadata.
Random timing is logarithmic up to 15000 ms; Morph/automation reach the full range.
ADR Mode 140 appends MIDI=4; its five choices remain buttons. MIDI capture runs in
@block with midirecv/midisend and ext_midi_bus=1. REAPER automatically forwards
SysEx through midirecv (see https://www.reaper.fm/sdk/js/midi.php). Positive-velocity
Note On messages become per-sample event bins after FILTER_MEMORY; @sample advances
the existing atomic trigger counter only in MIDI mode with Matrix active. Bins
adapt to samplesblock, bounded by the remaining 8M-cell local memory. Coincident
notes coalesce; delayed notes retrigger from current output. All short messages
retain original offset, data and bus. Manual and audio-triggered modes ignore notes.
Tests execute the actual capture/sample code with mixed buses/channels/offsets,
velocity-zero Note Off, CC/program changes, held notes, Manual and disabled routing.
An accelerated envelope clock exercises all 90 seconds; short envelopes retain
the existing native-rate checks. Native MIDI hardware acceptance remains separate.
Comb UI detail ends when adjacent extrema are less than 4 px apart, with a 12-period
cap. The remaining log-frequency range displays analytical magnitude bounds,
including the linear interpolation kernel. No audio coefficient changes. Plot
tests bound the real response and browser checks cover the compact five-button
ADR mode row, maximum timing and dense Comb band.

3.7.0 expands native Filter Mode 75 from 0..3 to 0..7, preserving the original
four enum values and the 191-slot layout. Peak adds 3*Resonance*normalized BP to
the driven input. Vowel combines normalized BP(f) and 0.7*BP(2.4*f), scaled by 1.2;
the second center clamps to 0.45*sample_rate. New mode weights use the existing
10 ms crossfade. All SVFs and histories stay warm for smooth mode selection.
Comb +/- is (input +/- .98*Resonance*delayed)/(1+.98*Resonance), without feedback.
It uses separate FILTER_MEMORY after both Core rings, size ceil(srate/20)+4 per
channel. Fractional reads wrap with floor and guard the sub-ULP rounding-to-size
edge. A two-stage 25 ms delay glide prevents abrupt read-speed changes. Memory
allocation is tested through 768 kHz; disabled output stays exact at settled mix 0.
The graph evaluates the exact TPT transfer with complex dry blend and linear
delay interpolation. Drive changes graph hue/fill, not its linear-response shape.
Source-executed tests compare complex impulse responses for all eight types at
44.1/48/96 kHz, bound Comb feedback, exercise automation and independent stereo
memory, silence, Off identity, plot bounds and native bulk policy. Native host
compilation/listening remains separate.

3.6.1 adds native 191 ADR Loop Direction, default Forward. Ping-Pong uses reverse
stages 4/5/6 to read the original release/decay/attack curves backwards. Telemetry
phase reverses along the same model, and a round trip is 2*(A+D+R). Direction is
only presented in Loop, fits the detector row's vacated space, and participates
in Random/Morph. Snapshot v9 adds one field; v8=190 remains readable. The drawn
curve ends at total duration; extra plot margin is no longer a flat hold segment.
Source-executed tests cover all six stages, reverse/model agreement and return to
Forward/Off at 44.1/48/96 kHz. Native REAPER acceptance remains separate.

3.6.0 consolidates new triggered modulation in ADR. Motion's tab, new source/target
choices, bulk scope and four controls (42/45/46/116) are hidden from WebUI; their
native slots and saved routes retain legacy DSP behavior. The four controls are
protected from Random/Morph. This avoids invalidating host automation or existing
route numbers. Source 2 and targets 60/61 are compatibility-only slots.
ADR 147 is now Attack Curve; new 189/190 are Decay/Release Curve. Each segment
has an independently smoothed exponent, used by both native processing and preview.
Targets 69/70 cover D/R curves. Banks remain 128 cells and telemetry stays 42 fields.
Morph count is 190; snapshot v8 reads v1–v7 and copies the old shared curve to the
new native controls and both endpoint pairs. New parameters inherit ADR bulk policy.
Tests execute mixed curves and automated changes at 44.1/48/96 kHz, independently
vary each graph segment, verify new curve Random/Morph and old-shape migration.

3.5.0 adds sixteen native route descriptors, per-route AUTO/UNI/BI and independent
module scopes for Randomize/Morph. Old 89–112 route fields remain; new routes are
148–171, polarities 172–187 and Morph Scope 188. 188 typed rows fit the existing
256-cell bulk banks; v7 snapshots read all older formats with neutral additions.
Route identities include polarity, and their amounts cross zero before any
identity change. Randomize never invents links/polarity and skips unassigned rows.
Source conversion is before source depth, preserving signed Envelope depth and
zero-depth neutrality. Disabled sources are gated after conversion so an Off
ADR cannot become -1 when BI is selected. Enabled idle unipolar BI is -1 by design.
Matrix target count grows to 68; its two banks now have a 128-cell stride and
the Chorus allocation follows the enlarged banks. Allocation checks include
44.1–768 kHz. Effective Motion/ADR thresholds extend telemetry to 42 values,
still one SDK transport channel, with backward-compatible 40-value decoding.
The actual native helper/router tests cover all sixteen descriptors, conversion
modes, inactive-source safety, signed depth, all destinations and route clearing.
Bulk tests compare native/Web randomization across all twenty-one scopes,
exercise scoped Morph and every polarity-aware route, and read v1–v7 snapshots.
The dialog uses one shared header, no divider lines and one-line amount fields.
Native REAPER compilation/listening remains a separate acceptance step.

3.4.0 adds the eight ADR native controls (140–147), source 5 and targets 53–57.
The three-segment one-shot has audio hysteresis, a manual command, Loop mode,
continuous retrigger from the current value, smoothed shape targets and no fixed
destination. Off plus unassigned routes is neutral. Source and target enums append
to existing IDs; old meanings remain. Bulk format v6 reads v1–v5, covers 147
typed rows and preserves detector selection during randomization.
The source-executed ADR/Motion fixture tests 44.1/48/96 kHz, curve/model agreement,
quiet/held signal, hysteresis, Manual/Loop, retrigger continuity and mode switches.
Motion preview uses a fixed 1.1 s window; live detector/peak and attack age are
appended to the modulation vector with ADR phase/value/enabled/detector/peak.
The vector is now 40 floats with one transport channel, so the unmodified SDK's
32-channel limit is respected. Old 21/29/32-value packets still decode; there is
no fabricated input level without fresh detector fields. Doubler offsets remain.
MOD header groups LFO/Motion/ENV/ADR; LFO instance selection is below its controls.
ADR uses compact paired controls and real parameter presets for common ramps.
Native compilation, command delivery and live listening remain host acceptance.

3.3.0 appends native controls 137–139 for Shift Stereo Offset, Sideband and Mix.
Independent L/R oscillator phases use base-minus/plus-offset Hz and retain
separate zero-shift bypass glides. Sideband continuously weights the quadrature
branch (+1 original, 0 ring, -1 opposite); Mix blends before Post Shift capture.
All targets have 10 ms sample-rate-independent smoothing. Neutral defaults are
sample-identical to a preserved 3.2.2 arithmetic fixture at 44.1/48/96 kHz,
including the original base-frequency automation and zero-shift transition.
Additional spectral tests cover stereo frequencies, both sidebands, equal-side
Ring, partial wet/dry blends, silent input and zero-shift-channel identity.
Extreme automation checks finite/clamped states at 8–192 kHz.
Matrix targets 50–52 append to the existing meanings within the 64-cell banks;
139 typed bulk rows, v5 snapshots and v1–v4 migration cover all new controls.
The Shift schematic has separate stereo paths, sideband/dry weights, Nyquist
folding and a continuous scaled rotor whose phase does not jump when tuning.
The primary Shift remains horizontal, with three secondary vertical faders;
common Core controls remain anchored. Native host/listening acceptance is separate.

3.2.2 is an interface update: units follow parameter names, and value fields
no longer carry a separate unit span/row. Disperser's rounded auto ceiling
caused repeated visual height jumps during Center sweeps; continuous 15%
headroom removes that discontinuity without changing coefficient/audio code.
The readout still reports the physical peak group delay in milliseconds.
Shift now shows a signed equal-Hz translation of reference harmonics with
negative-frequency folding and a deliberately slowed direction rotor. It is
labelled a schematic; zero Shift stays idle, reduced motion freezes it, and
hidden windows suspend its animation. A source-executed shifter fixture checks
the signed and folded frequencies against the unchanged native DSP arithmetic.
No audio parameter, routing, automation or serialization format changed.

3.2.1 replaces the shared Doubler pitch voice with two independent stereo
histories/read-head pairs, centred on Voice Pitch with opposing Detune offsets.
Width cross-blends their channel placement and keeps the main stereo signal.
The second pitch history fits inside the existing reserved Double bank; allocation
checks cover 44.1–768 kHz. After input stays below -90 dB for both histories plus
30 ms, the next attack reseeds both heads and softly fades the added voices in.
It does not retrigger on ordinary attacks/short gaps. Parameter IDs and ranges,
matrix routes and snapshot formats are unchanged.
The source-executed non-ACF pitch/Doubler fixture checks high-pitch repeated
bursts at 44.1/48/96 kHz, independent opposing detune, short-gap continuity,
disabled stereo passthrough, extreme pitch/detune/delay automation and a
missing-rearm regression. These are arithmetic checks, not native compilation.
Shared Core number fields now sit beside their tracks; Disperser uses the
remaining column height for longer faders. Host compilation/listening is separate.

3.0.0pre36 makes both Off LFO previews flat regardless of the stored waveform.
Morph/Randomize now use a typed row for every one of the 135 native slots,
including LFO depth/phase, LFO 2, independent Chorus, SAT, Feedback Sat and the
previously omitted Doubler gain/delay/passband/polarity controls. Bulk buffers
use separate 256-cell banks outside the existing plot/routing/audio allocations.
Native and WebUI Randomize share the generated policy and matching interpolation:
positive logarithmic controls interpolate geometrically, continuous controls
linearly, and enums switch directly between A/B states at the midpoint.
Gentle randomization below 50% preserves switches/modes; Matrix mode skips
inactive legacy local LFO controls and the retired Motion LFO mode.

Morph stores complete A/B parameter snapshots. Matrix links with the same
Source/Target interpolate their signed Amount; changed links fade their Amount
to zero, switch the assignment at the midpoint, and fade the new Amount in.
Randomize varies Amount only on already assigned routes; it does not invent
Source/Target links or change detector inputs. Chain order/capture, routing mode,
output protection, global gain/blend, held Freeze capture and utility/transport
controls remain excluded under the existing bulk-edit protection policy.
Serialization v3 stores 135 values per endpoint, reads the old 64/84-value formats
and seeds newly added controls from loaded settings at both endpoints. Store A/B
again to define distinct endpoint values for the newly covered controls.
The bulk regression test executes the actual native bodies, compares native/Web
randomization across every scope and tests old/new serialization. Native REAPER
compilation/listening remains a separate acceptance step.

3.0.0pre35 adds an independent LFO 2 (native IDs 131–135) alongside LFO 1,
Motion and Envelope. Both LFOs have Off/Sine/Saw/Square/Random, Rate, Depth and
Phase controls, live telemetry and host automation. The eight matrix routes now
offer 48 destinations grouped by module, including both LFOs' Rate and Depth,
Core drive/blend/return, Disperser Q/spread, and effect mix/tone/delay controls.
Rate modulation is multiplicative in octaves (±4 octaves at full amount);
depth modulation is additive in percentage points and limited to 0–100%.
Both LFOs consume the preceding control tick's smoothed matrix values, so self
and cross modulation are causal. Modulation never overwrites parameter bases.
Sources default Off, LFO 2 defaults Off, and module enable states remain explicit.
Discrete modes, Freeze length and Disperser stage count are intentionally excluded
from continuously modulated destinations. Existing route IDs 0–11 retain their
meanings; the expanded native route enums change normalized automation scaling.
Reinsert the test effect to load the new DSP; avoid Full recompile/reset with
the hosted editor open. Arithmetic/browser tests do not establish native audio
acceptance. Original 2.40 remains unchanged.

3.0.0pre34 fixes the concrete cause of fractional delay stepping: EEL's `%`
operator truncates both operands to integers, unlike JavaScript's remainder.
The old circular address calculation erased the interpolation fraction, so even
smoothed FX Feed moves read whole samples in steps. All five fractional reader
sites (Comb/Dry, FX Feed, Doubler/Chorus, legacy Dry and Metal) now wrap with
`p - floor(p / size) * size`. Integer counters/index wraps remain unchanged.
The regression harness now enforces EEL integer remainder semantics and rejects
fractional operands. Prior JS-only interpolation tests did not model this EEL
behavior and were insufficient. Regression cases reproduce the old whole-sample
jump and verify sub-sample continuity across delay changes and ring boundaries.
Original 2.40 and native parameter IDs/ranges remain unchanged.

3.0.0pre33 writes/reads the SDK's empty v2 serialization record directly when
no durable SDK state/resource banks are registered. This preserves the prior
12-byte format and generation/handshake renewal without waiting on the SDK's
state-bank gate. The ordinary SDK serializer remains the fallback for registered
banks. The change follows a REAPER hang during full recompile with the WebUI
open; it removes a possible unbounded wait but does not establish that this
was the sole cause. Vendored SDK files remain untouched. Native recompile/reset
acceptance after recovery is still required; do not forcibly close unsaved work.

3.0.0pre32 replaces the Ring illustration with its actual gain equation:
g = 1 + Depth * Mix * (sin(carrier) - 1). Carrier changes cycle count in labelled
time windows; Depth/Mix change the offset and bipolar excursion. Metal now
shows six fundamental modal regions on a logarithmic frequency axis: Size moves
centres, Decay changes width, Tone weights/damps regions and Mix scales them.
These are control models, not measured spectra (Metal's comb modes also have
overtones which are not drawn). Off keeps muted previews editable.
Disperser and Metal coefficient targets are now cached until their own inputs
change. Editing FX Feed no longer repeats their expensive unchanged bank
configuration. Native click diagnosis is ongoing; this optimization is not a
claim that real-time clicks are resolved.

3.0.0pre31 keeps Pitch Shift, Mix and Transient Recovery in the Pitch panel.
Decay and manual Trigger belong to the independent Motion source; the old
Pitch Depth/Rate remain explicitly labelled Legacy in All Parameters, with IDs
and ranges preserved. Recovery still controls spectral onset detection, but no
longer changes the independent Doubler's crossfade window (fixed at 50 ms).
FX Feed now uses two cascaded 25 ms delay glides and four-point interpolation,
blended back to linear below 3 samples to keep the feedback read causal.
Both glide stages initialize at the preset delay. Moving-delay pitch bending
and the existing feedback topology are retained. This addresses interpolation
and velocity discontinuities; native listening acceptance remains required.

3.0.0pre30 replaces the fixed Freeze boundary lines with a shaded loop window.
Width follows Loop length on a fixed linear 0–500 ms axis, with a direction
arrow and Mix-dependent fill brightness. Off retains the editable window in a
muted color. This is a control diagram, not a captured waveform or DSP playback
position. Only the WebUI drawing changed; native audio processing is unchanged.

3.0.0pre29 deliberately changes the Doubler diagram into a control schematic:
X is Width, Y is requested Voice Delay (fixed 0-100 ms), Pitch/Detune changes
circle radius and Mix/Gain controls brightness. Internal read-head latency no
longer affects endpoint positions. Live telemetry may still supply effective
semitones/voice level, but cannot override the diagram's Delay or Width axes.
CONTROL MODEL replaces the DSP delay stamp. The real audio latency still includes
pitch-buffer/width behavior; no audio processing changed. Tests verify pitch and
read-head motion leave endpoint coordinates unchanged, pitch changes radius,
Mix/Gain does not change radius and Delay round trips still work.

3.0.0pre28 reduces Doubler diagram jumps during pitch read-head replacement.
The latency estimate now weights both read heads during active crossfades;
the first crossfade frame still uses the sole head actually rendered that frame.
The diagram eases geometric values on an independent animation clock (100 ms
time constant) instead of jumping on packet arrival. Delay target changes snap
to the parameter model immediately, preserving the pre27 Delay round-trip fix.
Values in the numeric summary remain native estimates; the drawn geometry is
smoothed. Only estimate/display calculations changed, not voice buffer reads,
audio crossfade weights or output samples. Model/browser regressions cover
read-head step smoothing, convergence, manual delay priority and stale data.
Native behavior after pitch changes still needs confirmation in REAPER.

3.0.0pre27 fixes Doubler graph feedback after Delay edits. The Y axis is fixed
at 0-250 ms, so changing delay no longer auto-zooms the triangle. Native telemetry
v3 uses field 28 for the smoothed Voice Delay control value instead of pitch mix.
Packets differing from the current Delay by more than 0.2 ms, or older than
500 ms, cannot override the parameter model. Dragging owns the visualization;
expired telemetry triggers a redraw even without new events. The actual delay
can still exceed Voice Delay because the pitch read heads and width add latency.
Tests cover delay round trips, target mismatches, expiration and fixed-axis
geometry. Native driver/FX behavior requires a reload and host confirmation.
Audio processing is unchanged.

3.0.0pre26 restores standard Doubler graph height and replaces the old delay ticks
with a stereo-voice diagram. Blue is the main signal; orange endpoints are L/R of
one added stereo voice, not two independent pitch voices. X is schematic width
(the DSP uses inter-channel delay offsets, not a pan law); Y is delay in ms.
Point size follows normalized mix/gain, dashed branches indicate inversion,
the pitch label combines pitch/detune and the small rail shows the voice passband.
The existing telemetry packet expands from 21 to 29 channels, preserving the first
21 fields and appending L/R delay estimates, semitones, voice amount, width, gain,
polarity and pitch mix. Values come from the DSP's existing state, not new audio
processing. Delays are read-head-based estimates, not cross-correlation measurements
and do not include frequency-dependent filter group delay. When unavailable,
PARAMETER MODEL uses a 40 ms nominal pitch-buffer estimate; it is not live data.
The modulation view accepts both packet lengths during reloads. Browser mocks
verify native delay rendering, equal graph heights, centered controls and layout;
geometry/model tests verify delay, width, pitch, gain and bypass behavior.
Real-host validation of the expanded telemetry stream still needs FX reload.

3.0.0pre25 moves native DSP status to the bottom-right status bar, centers All
Parameters independently of status text length and right-aligns header controls.
Vertical faders use compact centered numeric fields (max 64 px), units on a
separate reserved line and a shared value/track center axis. Horizontal Comb,
Shift and secondary controls keep their existing layouts. Browser checks cover
all eight module panels plus Disperser, center-axis geometry, status relocation,
header alignment and no panel overflow at four window sizes. DSP is unchanged.

3.0.0pre24 updates the header to SBP ULTRACOMB 3, same-size version numeral,
green ULTRA lettering and wider global faders. The status now reflects recent
native spectrum packets instead of retaining the last SDK error indefinitely.
Channel errors show STREAM OFFLINE, restored packets show DSP LIVE and stale
packets become STREAM IDLE. This is telemetry status, not a direct audio-driver
health probe. Reconnection refreshes SDK capabilities and authoritative params
before reopening streams, without replaying edits. Browser mocks cover outages,
stale sessions, inactivity and recovery; a real driver disconnect/reconnect still
requires host confirmation. Audio processing is unchanged.

3.0.0pre19 removes the separate Filter Drive preview and changes the Comb tab's
Dry Delay/FX Feed controls to full-width horizontal sliders. Other Core tabs
retain vertical faders. Filter response headroom and gradient remain unchanged.
Browser checks cover orientation, width and no Core scrolling at four sizes.
DSP/audio processing is unchanged.

3.0.0pre18 is UI/label-only: filter 0 dB is vertically centered with +36 dB
headroom, a subtle response-area gradient and an explicit cutoff-frequency
sample so narrow resonance is not missed between display pixels. The BP model
uses the SVF's unnormalized band-pass magnitude. A small Drive transfer preview
matches the filter pre-shaper's static formula; it is not a signal meter.
The parallel Tap branch is now labeled Dry throughout WebUI, native names,
matrix destinations and legacy gfx. Feedback Tap labels become Capture.
Parameter IDs, numeric ranges and DSP processing remain unchanged.

3.0.0pre17 separates SAT Amount (slider 23, renamed without changing its ID or
range) from Feedback Saturation (124). Input Drive moves to the common Core
controls. SAT has independent Enable (125), extra Drive (126), Mix (127), Tone
(128), Asymmetry (129) and Curve (130: Soft/Cubic/Rational/Hard). Feedback color
reads only 124; the movable SAT reads only its own controls. New Feedback Sat
defaults to zero, so previous linked feedback coloration is not auto-migrated.
Set it explicitly when comparing an existing active-feedback setup.
Curve weights, drive, mix, amount, tone and asymmetry are smoothed. Asymmetry
subtracts the silence bias and uses a 10 Hz DC blocker; Tone tilts low/high bands
around 1.5 kHz. Linked RMS compensation remains in place. Neutral Soft settings
match the previous SAT arithmetic. Shape plots illustrate the memoryless curve,
not the tone/DC filters or time-varying compensation. New controls are native
automation/preset parameters but not part of the old random/morph engine.
Static/browser and arithmetic-body tests cover separation, control differences,
silence, finite output and disabled identity. Native compile/audio confirmation
is still required after loading the updated effect in REAPER.

3.0.0pre16 is UI-only: equal side panel colors, a subtly darker Core and Core
feedback/capture controls. Route dots are independent accessible power buttons;
Saturation power sets/restores its Amount because that module has no enable.
Chorus Delay and Morph span their panels. The Chorus parameter schematic uses
a fixed two-second horizontal window, rate-dependent cycles, depth-dependent
visual amplitude and delay-dependent vertical offset (not a measured delay plot).
Aurora/Ember/Ice/Mono spectrogram palettes share the same -90..0 dB scale for
both streams. Palette selection persists locally; changing it clears history
to avoid mixed color interpretations. Browser checks cover layout, route power,
startup enablement, Chorus graph changes, full-width Morph and palette selection.

3.0.0pre15 splits Doubler and Chorus into independent reorderable modules.
Doubler retains pitch/detune, voice mix, width, gain, absolute voice delay,
filters and polarity, but no embedded chorus excursion. Chorus uses its own
stereo buffer, phase and smoothed rate/depth/width/delay/mix controls. Its blend
is convex (no correlated-signal boost), with zero contribution when disabled.
Existing rate/depth sliders 57/58 now belong to Chorus; new sliders 118-123
provide order position, enable (Off by default), mix, width, delay and feedback
tap. Seven-module order plus a Chorus insertion position gives 40320 orders.
New controls are native preset/automation parameters, but original random/morph
does not yet include sliders above 84. The legacy gfx routing editor still shows
seven modules; Chorus editing/reordering is provided by WebUI and native params.
Browser checks cover both panels without scrolling at four window sizes.
`tools/test-chorus.mjs` evaluates the actual compatible arithmetic bodies at
44.1/48/96 kHz for dry identity, silence, bounded output and measurable change;
this does not replace native EEL compilation or live REAPER audio acceptance.

3.0.0pre14 captures unmodified Space on controls and calls the documented host
GetPlayState/OnPlayButton/OnStopButton transport APIs. Both keydown and keyup
default button activation are suppressed; auto-repeat cannot repeatedly toggle
transport. Numeric edits commit before playback, while search/text entry retains
spaces. Browser regression tests use a mocked host to verify transport calls,
focused-tab stability, held-key behavior and search input. Native shortcut
behavior still requires confirmation in the REAPER WebView.

3.0.0pre13 adds independent Motion and Envelope detector sources (sliders 116/117).
IN 1/2 is the default; EXT 3/4 reads only the additional sidechain input pins.
The JSFX declares four input and two output pins; sidechain audio is not mixed
into the main output. Configure the REAPER track for four channels and route
the sender's 1/2 to this track's 3/4. Missing sidechain means a silent detector,
not a fallback to main input. Existing detector smoothing remains in place.
Legacy Motion retains its original post-core detector unless EXT is selected.
Native sidechain routing and audible behavior require live-host confirmation.

3.0.0pre11 simplifies shared Motion to OFF/ATTACK, Decay and Trigger Threshold.
The shared Motion DSP treats the former LFO value as Off and no longer consumes
the Motion Rate parameter. Original slider IDs/declarations and the legacy DSP
mode remain unchanged for compatibility. UI labels are adapted without remapping
stored enum values: Off is 0, Attack is 2. Browser and static checks pass;
audible shared Motion behavior still needs host confirmation.

3.0.0pre10 unifies LFO Off/Sine/Saw/Square/Random into one segmented row.
Short enum controls use segmented buttons; larger destination lists remain menus.
Sliders 114 (shared LFO depth, percent) and 115 (phase offset, degrees) are native
automatable parameters. Depth scales every LFO matrix route; route Amount stays
independent. Depth and phase offset are smoothed; legacy routing ignores both.
LFO telemetry carries effective phase and scaled output. Native audible behavior
of the new controls still requires acceptance testing after effect reload.

3.0.0pre8 always schedules a control render on an authoritative parameter
snapshot, including default-valued snapshots. Previously unchanged values could
leave initial controls disabled until a tab forced a render. Range tracks now
use dark unfilled segments, subtle accent gradients and light circular handles.
The browser regression test covers a mock native connection at all defaults
without clicking tabs. DSP/audio processing is unchanged from pre7.

3.0.0pre7 fixes a critical EEL case-insensitive collision: the route index
`matrix_target` overwrote the `MATRIX_TARGET` memory pointer. This could corrupt
audio buffers even with all routes Off. The index is now `matrix_destination`.
Regression checks require each WebUI/matrix buffer pointer to be assigned only
once, case-insensitively. Reload the FX instance to rebuild any corrupted DSP
buffers; merely changing a route does not repair an already affected instance.
Native audio confirmation is still required, at a muted/conservative test level.

3.0.0pre6 replaces per-effect source tabs with shared LFO, Motion and Envelope.
The eight-route native matrix uses sliders 89-112 (source, target, signed amount)
and slider 113 selects Matrix (default) or Legacy Fixed compatibility routing.
All original slider IDs and transport slider 88 remain unchanged. Shared sources
run without enabling their former effect module. Matrix mode bypasses the old
fixed LFO/envelope contributions; the compatibility mode restores those paths.
All routes start Off with zero amounts. Target ranges at full amount are:
Tap/Feed 25 ms, Disperser 4 oct, Shift 5000 Hz, Pitch/Double 24 st, Ring 10000 Hz,
Metal 2 oct, Filter 6 oct, Feedback 0.5 and Output 12 dB. Routes sum per target,
clamp to [-1,1], smooth at audio rate and respect destination limits.
Matrix routes are native preset/automation parameters, but are not yet included
in the original random/morph snapshot engine. Older previews' fixed-modulation
settings require Legacy Fixed mode for comparison; no migration is claimed.
Browser tests cover eight editable rows, clearing routes, three source tabs,
112 exposed controls and four window sizes. Native compile/audio acceptance
is still required after reloading this version in REAPER.

3.0.0pre5 adds source-family tabs, waveform models and a 21-channel native audio
telemetry stream containing phase/value/enabled triples for seven sources.
The moving point uses DSP values; no live point is fabricated in browser preview.
Random and input envelope use recent output history instead of a predicted wave.
Existing assignments open in a separate dialog; arbitrary matrix editing is still
the next DSP stage. The Comb assignment label is corrected to Tap Delay.
The native 21-channel stream requires live-host acceptance after reloading the FX.

3.0.0pre4 is the layout-only first modulation stage: three columns (30/40/30),
central Core and a left modulation source editor with existing assignments.
All seven existing modulation groups keep their native parameters and DSP
destinations. This is not yet a freely assignable modulation matrix. Shared
independent LFOs, arbitrary routing and modulated-value overlays are stage two.
The Input Envelope editor moved from the footer into the modulation column.
Browser checks cover all seven sources and no Core scrolling at four sizes.

3.0.0pre3 reconnects on SDK capability changes, transport parameter changes,
and unexpected stream closure/error, coalescing notifications for 100 ms.
The stalled-stream watchdog remains a fallback for runtimes without events.
Visibility callbacks now use the SDK's boolean argument. Event-to-audio timing
after a real REAPER preset reset still needs host acceptance testing.

3.0.0pre2 adds stalled-stream recovery (including preset reset) and immediate
local slider feedback. Host updates are coalesced into animation frames.
Native reset recovery and audible control latency require a new host test;
the browser preview cannot validate REAPER transport latency.

- Static tests pass: all 87 original slider declarations, parameter scales,
  module coverage and all 5040 module orders.
- Browser checks pass at 900, 1140, 1280 and 1440 pixel widths, including
  parameter search, module plots and synthetic spectrogram rendering.
- The separate effect loads in REAPER and reports HOST CONNECTED. Both native
  spectrum streams report LIVE at 48 kHz in the silent test project.
- Audible processing, non-silent native spectrograms, automation gestures,
  snapshot/Undo and instance isolation still need acceptance testing.

The local browser preview uses `?preview=1`; it is not connected to REAPER
and intentionally does not simulate audio.

3.12.1 changes WebUI only: source option display order is 0/1/4/3/5/6, with
retired source 2 still hidden and all native IDs unchanged. ADR preset colours
match active analyzer tabs. Violet Feedback/capture indicators and a pointer-
transparent SVG show the selected return path into Core, including local Core
capture and a dim/dashed zero state. Route reorder/capture changes rebuild the
path; resize remeasures its endpoints without parameter writes. Browser checks
cover all 16 menus, stable source values, colours, capture endpoints, Core loop,
zero feedback and resize at four viewports. Native DSP body is unchanged.

3.13.0 changes distribution only. tools/build-webui.mjs deterministically bundles
the acyclic named-import modules in isolated scopes, inlines CSS/registry, and
embeds the exact editable sources and complete license texts. Runtime is four
files; source webui/ and licenses/ stay in Git. The SDK EEL include is renamed
to reaweb_jsfx.jsfx-inc without content changes. Browser tests request only the
HTML and verify ADR2/Sync, matrix, parameters and notices at four viewports.
Migration backs up both installations and deletes only previous-manifest files
whose hashes match. Native FX cache is never edited. Hosted WebUI/FX-browser
acceptance remains separate. No DSP algorithm or parameter IDs changed.

3.13.1 retains the original ReaWebAPI application root: the generated editor is
webui/packed.html, not the package-root HTML. Existing app IDs are already bound
to the webui directory; changing that root during a live session causes
APP_ID_CONFLICT. Four-file packaging and all DSP/parameter IDs are unchanged.

3.14.0 pins ReaWebAPI v0.3.9.10 / fe1bafea26595f705f595699cae33a432d74e1d4.
The EEL include is byte-identical; JS helper blob is
098bc2d445554d913d44517f0d06b6c9d1d33fc2. The app keeps SDK-managed stream
owners across capabilities/session changes. The one-second timer updates status
only. Initial opens are deduplicated and missing slots retry at 250/750/1500 ms;
existing streams are not closed by those retries. Visibility and analyzer-mode
changes still explicitly close/reopen their owned streams; epochs/tokens reject
late opens. Terminal SDK errors are reported without a periodic reopen loop.
Association dawKeyboard=true replaces keyboard.mjs; no Play/Stop JS handler is
installed. Local generated parameter labels/units remain independent of the new
parameter.enum metadata. Tests exercise actual SDK reconnect/session reset,
silence, suspended/offline DSP, listener identity, bounded errors and cleanup.
Installed DLL SHA-256 matches the official 0.3.9.10 release. Native keyboard,
reset and audio-device acceptance remain REAPER checks.
