# SBP SFX Spot Assistant

AI-assisted SFX spotting and generation tool for REAPER. It analyzes video frames with a local Ollama vision model, produces concise UCS-style tags, displays them in a ReaImGui viewer, and generates audio through MMAudio or StableDaw.

## Features

- Single-frame or beginning/middle/end analysis.
- Short/literal and creative/layered Ollama modes.
- AMB, FOLEY, HARD FX and DESIGN tag groups.
- Click-to-copy tags, Copy All, per-category copy and Select All.
- MMAudio video-conditioned generation with variations and seeds.
- StableDaw prompt-only Design FX generation.
- Automatic WAV/MP4 conversion, placement and item naming in REAPER.
- Project-local cache and metadata written to generated item Notes.
- Persistent settings for tracks, models, prompts and generation parameters.

## Installation

Copy this folder into the REAPER Scripts directory and run:

```text
sbp_SFX_Spot_Assistant.lua
```

Keep these files together:

```text
sbp_SFX_Spot_Assistant.lua
sbp_Analyze_SFX_Spot_with_Ollama.lua
```

The analyzer file is an internal dependency loaded by the Assistant.

## REAPER setup

Create a scene track named `__SFX_SCENES__` and place scene/cut items on it. Set the exact source-video track name in `SCRIPT SETTINGS` (default: `na zvuk`). The edit cursor must be over a scene item. Generation uses the time selection when enabled; otherwise it uses the scene item range.

Generated audio is placed on a free track beginning with `__SFX_AI_GENERATED__`.

## Dependencies

- REAPER 6/7+.
- ReaImGui (install through ReaPack).
- FFmpeg.
- Python 3.11+.
- Ollama with a vision-capable model.
- Optional Pinokio MMAudio service.
- Optional Pinokio StableDaw service.

## Ollama

Default endpoint: `http://localhost:11434/api/chat`. Select the model and frame mode in `SCRIPT SETTINGS`. The analyzer writes results between `--- AI SFX ANALYSIS ---` and `--- END AI SFX ANALYSIS ---` in the scene item's Notes.

## MMAudio

MMAudio uses the source video plus prompt/tags and returns an MP4, which is converted to WAV with FFmpeg. Variations run sequentially with independent seeds. Existing items are preserved; free generated tracks are reused when possible.

## StableDaw

StableDaw is used for prompt-only Design FX. Default API: `http://127.0.0.1:8600/api/generate`. The endpoint is synchronous and returns raw WAV bytes. StableDaw must be running in Pinokio. The `stable-audio-3-small-sfx` model belongs in StableDaw's own `models` directory; the REAPER script does not download model weights.

## Cache

Temporary clips, generated audio and logs are stored in the project media cache under `SBP_SFX_Cache`. Matching source/range/prompt/seed requests reuse cached files. Use `CLEAR CACHE` in `SCRIPT SETTINGS` when needed.

## macOS

The UI and tag logic are portable. Current MMAudio/StableDaw runners are Windows-first because they use PowerShell and Windows default paths. macOS requires platform-specific shell commands and configured executable paths.

## Troubleshooting

- No analysis: check Ollama, vision model, cursor position, scene/video track names and FFmpeg path.
- No generation: confirm the Pinokio service, Python/client paths and API port (`8600` for StableDaw; `5173` is normally its web UI).
- ReaImGui errors: update/install ReaImGui through ReaPack and restart REAPER.

## Changelog

### 1.0.0

Initial unified release with Ollama spotting, UCS tag viewer, MMAudio and StableDaw generation, persistent settings, cache management and automatic REAPER placement.
