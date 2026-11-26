# Changelog

All notable changes to ReaComfy are documented here.

## [0.5.1] - 2026-11-26

### Changed

- Workflow Launcher redesigned with tabs: **Workflow** (send, preset, parameters, run, import), **YuE2 / Music**, **Video** and **Settings**. The Workflow tab is always the one shown at launch; the other sections no longer open all at once.
- Consistent button colours by role: orange sends data to ComfyUI, green imports results, blue runs the workflow, red deletes, grey for utilities. Send and import groups are labelled, and every button has a hover tooltip.
- A status line at the bottom of the launcher shows the last action, errors and a running timer while a ComfyUI job is in progress (previously only in the REAPER Console).
- Workflow parameters are remembered per preset between sessions, with a **Reset to defaults** button.
- Video track settings moved to the Video tab.

### Fixed

- Preferences were written to REAPER's extstate file on every frame (~20 writes per frame); they are now written only when a value changes.
- An empty required parameter closed the launcher without running anything; the launcher now stays open, highlights the field and names it in the status line.
- The **Cancel** button inside the Workflow section closed the whole launcher; removed (the window close button remains).
- A failed Send/Import action no longer closes the launcher, so the error stays visible.
- Removed unused launcher actions for regions, MIDI, chords and arrangement (the standalone scripts are unchanged).
- Preset labels from files ending in `_API.json` no longer show the suffix.

## [0.5.0] - 2026-11-26

### Added

- `REAPER Voice Isolator (Inworld)` ComfyUI node: separates the foreground voice from noise, music and background with Inworld Voice Isolator (Apache-2.0, 48 kHz). Offline and streaming (realtime) models, strength blend, per-channel or mono processing, `voice` and `background` outputs.
- `voice_isolator_api.json` workflow preset with a strength macro in the launcher.
- The ComfyUI nodes are packaged as a standalone custom-node repository (`ComfyUI-ReaComfy`) with `pyproject.toml` for the Comfy Registry, `requirements.txt`, LICENSE and tests.

### Changed

- Cross-platform paths: all REAPER scripts now join paths with `/`, which REAPER and Lua accept on Windows, macOS and Linux. The user cache falls back to `HOME` when `USERPROFILE` is not set, and absolute POSIX paths are recognised.
- The default bridge Python is `python3` on macOS/Linux and `python` on Windows.
- Video export runs FFmpeg directly on macOS/Linux (PowerShell only on Windows) and looks for FFmpeg in REAPER `UserPlugins` and common Homebrew/system locations.
- The Python bridge looks for FFmpeg in the REAPER resource folder on all three platforms.
- Removed the machine-specific `G:\pinokio` path from the node documentation.
### Included from the former Unreleased section

- Added optional **Choose cached result when importing** mode. It lists recent cached ComfyUI audio files with timestamps, allowing a specific iteration (or several selected files) to be imported without pulling in results from later runs.
- Replaced the text-based cached-result selector in the ReaImGui launcher with a checkbox table, including multi-selection for stem imports.
- Track imports now use only the configured track name; output labels remain on takes, and a new track with the same base name is created when the destination position is occupied.
- Fixed reuse of multiple same-named output tracks: each selected result now searches all free tracks in the group before creating another one.
- Added `REAPER Dynamic Voice Match`, a voice-focused time-varying EQ match with voice gating, temporal smoothing, and limited correction for interview/lavalier recordings.
- Added `REAPER Dynamic Voice Leveler`, an offline voice-dynamics stabilizer with gating, attack/release smoothing, correction limits, and peak safety.
- Added `REAPER Reference Input` for separate target/reference audio workflows; the Send reference action now preserves the target path and writes `reference_path`.
- Added optional `REAPER Output` resampling. It is disabled by default; when enabled, choose 44100, 48000, or 96000 Hz.
- Fixed ComfyUI execution caching for `REAPER Input` and `REAPER Reference Input`: changing the REAPER manifest now invalidates the cached audio result.
- Moved Send reference audio into the main Direct ComfyUI Bridge and moved Import Video Output next to the other import controls.
- The main audio bridge button now reflects the selected input mode: direct source transfer or temporary Glue export.
- Added **Selected track** as a return destination and improved source-position fallback when a stale bridge status manifest lacks the original item position.
- Additional host-specific setup guidance and broader platform testing.

## [0.4.4] - 2026-10-18

### Fixed

- Guarded text import against corrupted edit-cursor values and out-of-range subtitle timestamps that could freeze REAPER.

## [0.4.3] - 2026-10-18

### Fixed

- Text importer now verifies created REAPER objects, selects imported items, and moves the edit cursor to the imported range for immediate visibility.

## [0.4.2] - 2026-10-18

### Fixed

- Fixed invalid Lua path escaping in `ReaComfy - Import Text Output.lua`, which prevented the script from loading.

## [0.4.1] - 2026-10-16

### Fixed

- Added a compatibility shim for ClearVoice with librosa 0.11+, restoring the removed `librosa.util.normalize` API without downgrading ComfyUI dependencies.

## [0.4.0] - 2026-10-15

### Added

- `REAPER Text Output` for exporting SRT/VTT/plain text from ComfyUI.
- REAPER import as note items, project regions, or markers.
- Importer button in the main launcher bridge block.
- Clear separation between text output import and audio result import.
- Multi-output audio import support for stem workflows.

## [0.3.0] - 2026-09-20

First public release after three development iterations.

### Added

- ReaComfy workflow launcher with resizable ReaImGui interface and persistent setup.
- API workflow presets with refresh support, macro controls, additional workflow folders, and editable ComfyUI host URL.
- Audio bridge for original-source and glue workflows, WAV/FLAC output, 48 kHz conversion, source-position return, lanes, tracks, and multi-output imports.
- Direct `REAPER Input` and `REAPER Output` nodes for editable ComfyUI pipelines.
- Video source transfer and FFmpeg export from a REAPER time selection or cutscene item.
- Configurable video and cutscene track names.
- `REAPER Video Input` outputs for path, native ComfyUI video, Woosh video, PrismAudio images, and FPS, with optional frame-duration limiting.
- Frame-duration limiting is opt-in; full-duration frame extraction is now the default for compatibility with existing video pipelines.
- Added `REAPER EQ Match`, a reference-based STFT/iSTFT correction node for controlling excessive spectral emphasis in cloned voices.
- Fixed multi-output node exchange: all `REAPER Output` files from one job are now imported, while stale files from previous jobs are ignored through per-job manifests.
- Video output import back to the REAPER timeline.
- YuE2 source export for lyrics, regions, MIDI, chords, arrangement plans, and reference audio.
- Multi-track MIDI export, section markers, chord-only ABC generation, score output, MIDI output, and score import.
- Cache cleanup and project-local cache manifests.
- Cross-platform path resolution and user configuration without personal workflow paths in the release package.
- Node descriptions and README documentation for inputs, outputs, workflow contracts, and custom presets.

### Fixed

- Windows path handling for spaces, Unicode, parentheses, and nested project folders.
- Stale manifest/result selection and cache collisions between consecutive jobs.
- Long chord and arrangement items spanning multiple REAPER regions.
- Return placement and timing for source-position imports.
