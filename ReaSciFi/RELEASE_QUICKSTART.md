# SBP ReaSciFi - Release Quick Start

A short guide to publish alongside the release.

## 1) Quick Start

1. Add `sbp_ReaSciFi.lua` to REAPER via ReaPack or manually.
2. Run the script and make sure ReaImGui v0.10.0.2+ is installed.
3. Select a target track:
   - either with the `Pick` button,
   - or manually in the `Track` field.
4. Enable `Auto Preview` to hear changes immediately while editing.

## 2) Basic Workflow

1. Choose `Mode`:
   - `One-Shot` for short SFX,
   - `Drone` for beds/ambience.
2. Choose a `Family` (generator character).
3. Optionally apply a `Quick Profile` -> `Go`.
4. Shape the sound with macro controls in `Layers`, `Post FX`, and `Modulation`.
5. When satisfied, press `PRINT` or `BATCH PRINT`.

## 3) Print and Batch Render

### PRINT

- Creates one offline render to a stem track:
  - `ReaSciFi Renders` (Stereo),
  - `ReaSciFi Renders (Surround)` (5.1).

### BATCH PRINT

- Parameters:
  - `Count` - number of renders,
  - `Prefix` - item naming base (`Prefix_001`, `Prefix_002`, ...),
  - `Randomize each` - generate a new variation before each render.
- Batch mode prompt at start:
  - `Yes` -> each render goes to a NEW track,
  - `No` -> all renders go sequentially to ONE track,
  - `Cancel` -> abort batch.

## 4) Important Notes for One-Shot

- One-Shot is triggered by MIDI NoteOn.
- During offline Print/Batch, the script automatically inserts a temporary MIDI trigger and removes it after rendering.
- If no Time Selection is set, One-Shot uses a short fallback range near the cursor (to avoid unnecessarily long renders).

## 5) Post FX (Engine 2) - How to Hear the Effect Consistently

1. Raise `Character` (typical sweet spot is 0.4-0.8).
2. Increase `E2 Grain / Spectral / Reverse Mix`.
3. For clearer effect, enable `High CPU Mode`.
4. Keep in mind: different `Family` values have different Post FX sensitivity.

## 6) Quick Troubleshooting

- No sound:
  - check target track,
  - check `Gain dB`,
  - in Drone mode, check `Preview Gate`.
- Wrong track is being updated:
  - disable/check `Follow`,
  - press `Push To FX`.
- Batch is too slow:
  - reduce `Count`,
  - disable `Randomize each`,
  - try `Economy` CPU mode.

## 7) Recommended Pre-Release Smoke Test

1. One-Shot: PRINT + BATCH (with and without Time Selection).
2. Drone: PRINT + BATCH in Stereo and Surround.
3. Verify `Yes/No/Cancel` batch-dialog scenarios.
4. Verify Morph A/B/Mix between user presets.
5. Verify Randomize masks + Undo.

## 8) Short Release Blurb (Ready to Paste)

SBP ReaSciFi is a modular sci-fi generator for REAPER with One-Shot and Drone workflows.
This release adds User Morph (A/B + Mix), Batch Render with auto-naming, and randomize-per-item.
The Post FX section is refined, with context tooltips added for faster onboarding.
One-Shot offline rendering is now stable: automatic MIDI trigger injection in Print/Batch prevents silence.
Batch UX is improved with one-time mode selection (new track per item or one shared track).
A compact production quickstart is included for fast setup and pre-release smoke testing.
