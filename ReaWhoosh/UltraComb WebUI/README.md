# SBP UltraComb 3.0.0

A stereo processor for metallic movement, inharmonic comb textures and creative
sound transformations. This is a separate effect from UltraComb 2.40.

## Install with ReaPack

1. Import the SBP repository in **Extensions → ReaPack → Import repositories**:
   https://raw.githubusercontent.com/Bodzijun/SBP-Reaper-Scripts/main/index.xml
2. Import zaibuyidao's repository for the WebUI runtime:
   https://raw.githubusercontent.com/zaibuyidao/ReaScripts/master/index.xml
3. In **Browse packages**, install **ReaWebAPI: Web Runtime for REAPER**
   version **0.3.8.31 or newer**, and **SBP UltraComb WebUI 3**.
4. Restart REAPER after installing/updating the ReaWebAPI extension.
5. Add **JS: SBP UltraComb WebUI 3** from the FX browser.

Publication of the UltraComb package is a separate maintainer step; the local
release files alone do not make the package available in the public index.

Release target: REAPER 7.80+ with ReaWebAPI 0.3.8.31+.
Windows requires the WebView2 Evergreen and VC++ x64 runtimes described by
[ReaWebAPI](https://github.com/zaibuyidao/ReaWebAPI#download-and-install).
Cross-platform installation packages are provided by ReaWebAPI upstream.
UltraComb has been developed/tested on Windows; macOS/Linux host acceptance
is not claimed. ReaPilot Bridge is a development tool and is not required.

## Install manually

Copy the complete `SBP UltraComb WebUI 3` directory from the manual release ZIP
into REAPER's `Effects` directory (Options → Show REAPER resource path).
Keep the association JSON, EEL include, `webui/` and `licenses/` alongside the
main JSFX. ReaWebAPI itself must still be installed separately.

Without a valid hosted WebUI the legacy native graphics remain available, but
they do not expose all of the version 3 controls. Use the WebUI for the complete
interface. ReaPack installs the same relative runtime file layout.

## Signal and modulation

- **Core:** parallel Dry/FX Feed delays, feedback, Disperser and Frequency Shift.
- **Creative chain:** reorder Freeze, Pitch, Doubler, Ring, Metal, Saturation,
  Filter and Chorus. Core stays first.
- **Modulation:** independent LFO 1/LFO 2 with Rate, Depth and Phase; triggered
  Motion and an input Envelope follower, with IN 1/2 or EXT 3/4 detection.
- **Matrix:** eight routes and 48 targets, including both LFOs' Rate/Depth.
  Rate modulation uses octaves; amount/depth values are bounded and smoothed.
- **Morph/Randomize:** typed controls, complete A/B snapshots and matching
  native/Web randomization policy. Gentle randomization preserves modes.
  Changed matrix links fade through zero; Randomize varies existing route
  amounts rather than inventing links.
- **Output:** gain, optional Hard/Soft clipping, and selectable ceiling.
- **Displays:** live input/output spectrograms with four palettes. Other graphs
  illustrate parameter models and modulation telemetry, not measured responses.

All 134 exposed controls are native JSFX parameters available for REAPER
automation. Slot 88 is reserved for the WebUI transport. **Core Feedback** is
native parameter **6**, named `Core Comb Feedback` in the parameter list.
The effect uses channels 1/2 for audio and channels 3/4 only as detector inputs.

## A/B, projects and updates

Existing UltraComb 2.40 instances are unchanged. Version 3 has its own FX identity;
automatic conversion of 2.40 projects/presets is not provided.

Morph stores the current complete parameter state with STORE A/STORE B.
When loading old 64/84-value snapshots, newer controls inherit the loaded value
at both ends; store A and B again to define different values for them.
Global gain/blend, output protection, chain order/capture, routing mode, held
Freeze capture, utilities and transport stay excluded from bulk changes.

For preview-to-release testing, close the editor and insert a fresh instance.
Avoid Full recompile/reset with the hosted editor open: it previously caused
a hang in the development session. Preserve any project settings before replacing
an instance. ReaWebAPI protocol v1 and the package-local SDK copies are required.

## Included sources and notices

The package is distributed as editable source. SDK copies remain unchanged from
ReaWebAPI 0.3.8.31. See [THIRD_PARTY.md](THIRD_PARTY.md) and `licenses/` for
provenance, the complete LGPL/GPL texts and the retained DSP component notices.
The SDK files can be replaced/rebuilt from their pinned upstream source.

Maintainer packaging/validation instructions are in repository-only
`PACKAGING.md`; preview history is in repository-only `DEVELOPMENT.md`.
