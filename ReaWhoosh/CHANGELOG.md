# ReaWhoosh changelog

## 4.01 — 2026-08-12

- Fixed External Input routing and a true transparent bypass when the Filter pad is disabled.
- Audio Pitch and Physical Doppler now bypass the granular engine at 0 semitones, so Grain Size does not change an unshifted external source.
- Stereo generation no longer creates Surround Path X/Y automation lanes.
- Improved pad point selection and edge dragging.
- Extended External mixer makeup gain to +12 dB.

## 4.0 — 2026-08-12

Release date: 2026-08-12

## Highlights

- New compact UI 2.0: Generator Rack, fixed performance workspace and aligned Effects/Actions strip.
- Five design modes: Whoosh, Rise, Soft, Whoosh + Hit and Rise + Hit.
- Rebuilt Hit Engine with Body, Sub, Crack, metallic Crash, Tone, Drive, Ducking and reliable Chopper/Panning bypasses.
- Expanded source design: oscillator shapes, unison, FM, Noise Crackle, Chua, Sub and Ring Metal controls.
- More stable creative FX: improved reverb routing/diffusion, Chopper smoothing and source-aware signal routing.
- Safer workflow: Tail Preview, Replace/Next timeline slot/New layer generation, Bounce and true A/B variations.
- External Parameter Link now offers normalized ranges, alphabetical parameter lists, locking and randomization.
- Right-click resets every active slider to its factory default.

## Compatibility

- Existing JSFX parameter indices are preserved. New JSFX controls are append-only, so existing REAPER automation remains valid.
- Existing presets continue to load. Newly added parameters use safe defaults when absent.

## Cleanup

- Removed dormant duplicate UI implementation left from the pre-UI-2.0 layout.
