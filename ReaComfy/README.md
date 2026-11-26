# ReaComfy 0.5.2 — REAPER ↔ ComfyUI

ReaComfy is a local bridge between REAPER and ComfyUI. It sends selected REAPER audio to a ComfyUI API workflow, processes it in the background, and returns one or more results to the timeline without leaving the DAW.

See [CHANGELOG.md](CHANGELOG.md) for the release history. Forum thread: https://forum.cockos.com/showthread.php?t=311369

## Features

- Glue the visible item section or use the original source file.
- Preserve item timing and return results to the source position or edit cursor.
- Return results to a new fixed lane or a new track.
- Handle multi-output workflows as separate tracks or fixed lanes.
- Import WAV or FLAC and resample returned audio to 48 kHz.
- Keep the launcher open while a ComfyUI job runs.
- Send and import files directly through the `REAPER Input` and `REAPER Output` ComfyUI nodes.
- Adjust workflow macros such as chunk size, overlap, text, language, strength, or model controls.
- Use any API-format workflow that follows the workflow contract below.

## Requirements

- REAPER with ReaScript enabled.
- ReaImGui for the graphical launcher.
- A running ComfyUI instance with its HTTP API enabled.
- Windows, macOS or Linux.
- Python 3 for the local bridge (`python` on Windows, `python3` on macOS/Linux by default).
- FFmpeg for 48 kHz conversion, WAV output and video export: in PATH, in `<REAPER resource folder>/UserPlugins/` (`ffmpeg.exe` on Windows, `ffmpeg` elsewhere), or on macOS in `/opt/homebrew/bin` or `/usr/local/bin`.

Included presets that need ComfyUI-ReaComfy 0.6.0 or newer (see its README for model installation):

- `nemotron_reuse_api.json` — NVIDIA Nemotron RE-USE: cleans noise, reverb, clipping and codec damage; returns `speech` and `removed` tracks.
- `zonos3_tts_api.json` — ZONOS3-Mini TTS: the selected item is the voice to clone; type the text and pick language (Ukrainian by default), emotion, pace, projection, mood and accent in the launcher. The first run installs ZONOS3 automatically (10-30 minutes, several GB); later runs start in seconds.
- `dblm_se_api.json` — DBLM-SE-1B generative denoise + dereverb (16 kHz result; follow with super resolution for full band).

The included passthrough workflow uses standard ComfyUI audio nodes. Workflows using denoise, dereverb, separation, restoration, or synthesis models may require additional custom nodes and models.

## Installation

ReaComfy has two parts that are installed separately.

### 1. ComfyUI nodes

Install **ReaComfy** (publisher `bogdan-sbp`) from ComfyUI-Manager / the Comfy Registry, or clone https://github.com/Bodzijun/ComfyUI-ReaComfy into `ComfyUI/custom_nodes/` and install its `requirements.txt`. Restart ComfyUI.

### 2. REAPER scripts (ReaPack)

1. Install ReaPack and ReaImGui (ReaImGui is in the default ReaTeam Extensions repository).
2. **Extensions → ReaPack → Import repositories...** and paste:
   `https://github.com/Bodzijun/SBP-Reaper-Scripts/raw/main/index.xml`
3. **Extensions → ReaPack → Browse packages**, search for **ReaComfy**, install it and apply.
4. Run **SBP_ReaComfy - Open workflow launcher** (`ReaComfy.lua`) from the action list. The remaining scripts are found automatically.

Optional configuration: copy `reaper/ReaComfy User Config.lua.example` to `reaper/ReaComfy User Config.lua` (ReaPack installs the package to `<REAPER resource path>/Scripts/SBP Reaper Scripts/ReaComfy/`; **Options → Show REAPER resource path** opens the resource folder). Set `bridge_python` to your Python executable, or leave it empty when `python` (Windows) or `python3` (macOS/Linux) is available in PATH. You can also set the `REACOMFY_PYTHON` environment variable. Set `comfy_url`, for example `http://127.0.0.1:8188`.
To keep personal presets outside the package (ReaPack updates replace packaged files), set `additional_workflows_dir` to one or more folders containing `_api.json` files. Separate multiple folders with `;` on every platform. `ReaComfy User Config.lua` is not part of the package and survives updates; keep a copy of `AI Workflow Macros.lua` if you edit it.

Start ComfyUI before running a workflow.

The launcher's **YuE2 / Music** tab contains the **YUE2 SOURCES** block. Select any combination of **Lyrics from items**, **MIDI**, **Chords**, **Arrangement**, and **Reference audio**, then press one button to build a combined bridge manifest. Lyrics are read from media-item Notes on the configured lyrics track. Project regions provide the shared structure (`Intro`, `Verse`, `Chorus`, `Bridge`, and so on) for lyrics, chords, arrangement, and MIDI markers. MIDI can be limited to selected items or exported from the entire project. Track and folder names are configured next to their source checkboxes. For a reference, enter a track name to use its first audio item, or leave the field empty and select exactly one audio item. If the reference consists of multiple items, glue them into one item first. A live guitar, piano sketch, vocal idea, or other performance can then guide a ComfyUI workflow through the existing `REAPER Input` node. `REAPER Text Input` can select `lyrics`, `chords`, or `arrangement` from the combined manifest. The actual processing remains visible and editable in ComfyUI.

The user config is machine-specific and must not be committed to a public release.

The launcher's **Settings** tab includes **Clear ReaComfy cache**. It removes only bridge manifests, temporary MIDI/text files, and ReaComfy-generated result files from the project cache, runtime cache, and user fallback cache. It does not touch source audio, projects, workflows, or ComfyUI models.

For repeated iterations from one REAPER source, enable **Choose cached result when importing** in the **Settings** tab. The Import button then shows a ReaImGui checkbox table of dated cached `comfy_to_reaper_*.wav`/audio files. Select one iteration or several files for a stem set, then press **Import selected**. This lets you import only the desired iteration instead of all outputs accumulated by the same ComfyUI workflow run.

### Arrangement folder input

The **Send arrangement plan to ComfyUI** action reads all child tracks inside one REAPER folder. Set the folder's name in the launcher's **YuE2 / Music → Arrangement folder** field (default: `Arrangement`). Child track names become instrument/part names; item notes become optional performance instructions, and item/region positions provide the section timing. An item that spans several regions is repeated in every region it overlaps until its actual end. The folder itself is only a container, so tracks inside it may be named `Bass`, `Drums`, `Piano`, `Strings`, or any other roles. Lyrics and chord tracks should remain outside this folder and be sent with their dedicated actions.

## Basic workflow

1. Start ComfyUI.
2. Select one or more audio items in REAPER.
3. Open ReaComfy and select an API workflow.
4. Choose input preparation, file format, destination, and return position.
5. Adjust workflow macros if available.
6. Click **Run selected workflow** and wait for the status message in the REAPER Console.

For multiple selected items, use **Glue visible item**. This creates a temporary glued source while leaving the original items unchanged.

## Direct ComfyUI node exchange

Copy `ComfyUI/comfy_custom_nodes/reaper_bridge` into ComfyUI's `custom_nodes` directory and restart ComfyUI.

- **REAPER Input** reads selected REAPER item(s) prepared by the send action.
- **REAPER Output** writes result files and a manifest for REAPER to import.
- **REAPER Text Input** reads inline text (or a text file) from the bridge manifest.
- **REAPER MIDI → YuE2 Score** converts a MIDI file from the bridge manifest into YuE2 `score_abc`. Lyrics are supplied separately through **REAPER Text Input** (`field: lyrics`).
- The MIDI node accepts several instrumental parts through its optional `instrument_tracks` field (comma-separated part numbers such as `2,3,4`). The selected parts are merged into the instrumental voice while the vocal part remains separate.
- **REAPER Score Output** writes YuE2 ABC notation and lyrics back to the project cache and, by default, exports the score to a standard MIDI file using YuE2's own score exporter. Run `ReaComfy - Import Score Output.lua` in REAPER to place the latest generated MIDI at the edit cursor on a `YuE2 Score` track.
- **REAPER MIDI Output** accepts a workflow's `midi_path` (and optional `notes_json`), copies both into the project cache, and exposes them to `ReaComfy - Import MIDI Output.lua`. The MIDI is placed on a labelled track and the notes JSON is preserved on a `MIDI Notes` text item.
- **REAPER Video Input / Output** exchange video file paths with ComfyUI workflows. `REAPER Video Output` accepts `video_path`, copies the result to the project cache, and `Import Video Output` places it on the REAPER timeline.
- `REAPER Video Input` also exposes decoded `images` and `fps` outputs for frame-based nodes such as PrismAudio, plus `WOOSH_VIDEO` for Woosh V2A. PrismAudio's own node performs the required 4 FPS / 25 FPS resampling internally.

Connect `REAPER Input` to your processing graph and connect final audio outputs to one or more `REAPER Output` nodes. Use **Send selected item(s) to ComfyUI** and **Import ComfyUI result** in ReaComfy.

### YuE2: lyrics and song structure from REAPER regions

YuE2 can use section tags such as `[Intro]`, `[Verse]`, `[Pre-Chorus]`, `[Chorus]`, `[Bridge]`, and `[Outro]`. ReaComfy can build this structure from REAPER regions:

1. Name regions with a section name, for example `Verse 1`, `Pre-Chorus`, or `Chorus`.
2. Put the lyrics for each section in media-item Notes on a track named `Lyrics` or `Lyric` inside that region. If no note is present, the active take name is used as a fallback. Notes on `Chords` or other tracks are ignored by the lyrics collector.
3. Run **ReaComfy - Send regions as lyrics.lua** from the REAPER action list.
4. In ComfyUI, connect **REAPER Text Input** to the YuE2 lyrics/text input (for example `Compose → lyrics`).

The script writes `reaper_to_comfy.json` in the project cache. The manifest contains the generated tagged lyrics and the region timing metadata. Region names are normalized to YuE2 tags; unknown names are preserved as readable section labels. This is a text-only exchange and does not require the ReaComfy audio input/output nodes.

Select one or more MIDI items and run **ReaComfy - Send MIDI source to ComfyUI.lua**. Items on the same REAPER track are merged into one MIDI track; items from different REAPER tracks are exported as separate named tracks in a Type 1 MIDI file. A single external MIDI file is passed through directly. Project regions inside the selected range are written as MIDI Marker Events, so YuE2 can preserve `Intro`, `Verse`, `Chorus`, `Bridge`, and `Outro` sections when `without_sections` is disabled. Then use **REAPER MIDI → YuE2 Score** in your workflow. It outputs YuE2 ABC notation and lyrics, which can be edited with `FL_YuE2_ScoreEditor` or passed directly to YuE2 `Compose`. YuE2 and its model files are not bundled with ReaComfy; install the YuE2 node pack and model separately according to its license and documentation.

## Creating your own workflow

1. Build and test the workflow in ComfyUI.
2. Use **Save (API Format)** or **Export (API)**, not the visual canvas JSON.
3. Save the file with a name ending in `_api.json`.
4. Put it in `workflows/` for a public preset or `workflows_private/` for local experiments.
5. Refresh the preset list in ReaComfy.

For automatic REAPER processing, an API workflow must contain:

- exactly one standard `LoadAudio` node;
- at least one audio save node such as `SaveAudio`, `SaveAudioMP3`, `SaveAudioOpus`, or `SaveAudioAdvanced`;
- audio connections from `LoadAudio` through the processing graph to every save node.

ReaComfy replaces the `LoadAudio` filename at runtime, waits for the prompt, downloads every save-node output, and imports each output. The save node's `filename_prefix` becomes the result label.

Keep output duration aligned with input duration for correct timeline placement. Denoise, dereverb, EQ, de-ess, enhancement, and stem separation are good fits. Text-to-speech, music generation, and time-stretching may need a dedicated workflow and deliberate placement settings.

### Workflow macros

Add optional controls in `reaper/AI Workflow Macros.lua`:

```lua
["my_denoise_api.json"] = {
  { label = "Strength", node = "12", input = "strength",
    min = 0.0, max = 1.0, default = 0.35, format = "%.2f" },
  { label = "Prompt", node = "7", input = "prompt",
    kind = "string", multiline = true, default = "" },
}
```

The `node` value is the ID from the API JSON. Numeric, boolean, choice, and text inputs are supported. A workflow without macros still works.

## Validation

Run this command with the Python configured for your machine:

```powershell
python bridge/reaper_comfy_bridge.py --base-url http://127.0.0.1:8188 validate
```

Expected output:

```text
OK: ComfyUI API and required workflow nodes are available.
```

## Release packaging

The ReaPack package contains `ReaComfy.lua`, `reaper/`, `bridge/`, `workflows/`, this README and the changelog. The ComfyUI nodes are published separately in ComfyUI-ReaComfy. Never include `workflows_private/`, runtime results, local user config, personal models or machine-specific paths.

## Troubleshooting

- **ComfyUI is unreachable:** check `comfy_url` and confirm the server is running.
- **Python is not found:** set an absolute `bridge_python` path in `ReaComfy User Config.lua`.
- **A node is missing:** install the required custom node pack or use a standard-node workflow.
- **No result is imported:** check the REAPER Console and the project `REAPER_AI_CACHE` for `latest_result.json` and returned audio files.
- **The output sounds wrong:** adjust the workflow in ComfyUI, export API Format again, and replace the `_api.json` preset.
