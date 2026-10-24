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
