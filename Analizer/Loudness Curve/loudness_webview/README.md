# SBP Loudness Curve

Standalone REAPER WebView action using the ReaWebAPI Lua bridge, as in ReaSpeech Verify. Install ReaWebAPI from the [zaibuyidao ReaScripts ReaPack index](https://raw.githubusercontent.com/zaibuyidao/ReaScripts/master/index.xml), then load `SBP_Loudness_Curve.lua` as a REAPER action. Keep this folder together, including `profile.lua` and the `web` subfolder. The tool is self-contained: it does not require the parent PostMaster `core` folder and can be installed anywhere under REAPER Scripts. Existing PostMaster/Post Agent project naming settings are read when available; otherwise PRINTMASTER / BUS / #Location defaults apply. Future ideas are recorded in [PLAN.md](PLAN.md).

## Processing and curves

General parameters are grouped in the first row, with detailed limiting parameters in a separate block below. Modes:

- Normalize only: applies constant target minus measured LUFS-I plus Output trim; bypasses pre/post curves, limiters and smoothing. Drawings/settings are retained, with editing/dynamics controls disabled. Export uses two constant-gain endpoints.
- Normalize + shape: applies normalization and all shaping stages.
- Shape only: applies shaping without normalization. Use when integrated measurement is missing.

For example, measured -10 LUFS-I to target -23 gives -13 dB normalization. This gain is independent of dynamics cut/boost limits. Normalization is unavailable without measured I. The I statistic for constant gain excludes variable shaping; rerender to measure actual I and true peaks.

Editing tools and visibility switches are ordered **Pre volume → Upper limit → Lower limit → Post volume**. Pre volume is a gain curve before the limiters: it changes their input and therefore their reaction. Upper/lower curves define loudness boundaries, with separate ratios (default 1×). Dynamics cut/boost and silence gate constrain limiter correction only; the gate suppresses upward limiter correction below the pre-adjusted input threshold. Smoothing applies to limiter correction.

Post volume is an independent gain curve after limiter correction/smoothing. It is added without changing limits, ratios, limiter sampling or their cut/boost budget. Its control-point sampling is excluded from the limiter smoothing pass. **Output trim, dB** is a separate constant output gain (the former Post volume slider). Final correction = normalization + pre gain + limiter correction + post gain + output trim. Post volume has no fixed ±24 dB cap: its envelope gain follows the graph position relative to Target. Export accepts finite gains beyond the old cap and rejects nonfinite/unrepresentable envelope values or excessive point counts.

Drawing pre volume sets a desired input level relative to normalized measured history. Post volume is a conventional gain envelope: click adds one point, drag moves that same point, with no automatic side anchors. Its visible line displays gain relative to Target (zero gain at Target), independently of source loudness. Points interpolate using the selected curve mode; their influence can extend to neighboring envelope points. Both store gain offsets, so source changes can still appear inside held segments. Reset active curve resets only the selected curve: pre/post to zero gain, upper/lower to their numeric settings. New-report loading initializes all curves. Numeric limit changes reset that limit to a horizontal line. Target changes move the two boundaries together.

Curve mode applies to all four editable curves. Linear / smoothed interpolates gain/boundary points and smooths limiter correction. Step / hard boundaries holds prior values and bypasses smoothing. Export includes control-point times and points 2 ms before boundaries for short linear transitions. Pre/post curves themselves are not filtered by the limiter smoothing setting.

Editable curves use thinner lines than measured/corrected history. The selected tool stays opaque; inactive editing curves and handles are 30% opaque. Normalize only shows them faintly as bypassed. Green is final corrected estimate, purple is pre input, magenta is post output. Existing snapshot curves stay frozen and compatible; old manual drawings are retained in their snapshots, not reapplied to the live tool.

The selected Pre, Upper, Lower or Post button uses its curve's color: purple, orange, blue or magenta respectively.

## Graph and timeline

The target value is a fixed top-right badge with opaque background; its line is controlled by the Target switch. Level ticks default to absolute LUFS; target-relative dB remains selectable. Fit/focus/wide views combine with horizontal/vertical zoom and panning. Wheel zooms time at the pointer; Ctrl/Command+wheel zooms levels; Shift+wheel pans time. Navigate mode or Alt/middle drag pans both axes without editing. Reset view restores full time and target-centered levels. A new report resets the view. Curves clip at borders rather than flattening there; editing uses zoomed coordinates.

Switches control all displayed curves, snapshots, regions, waveform, grids and labels; visibility does not bypass processing. Hidden editable curves cannot be edited. Report history can be sparse, so this tool suits broad scene adjustment, not fast transient metering.

Project regions are read and clipped to the render range, with named colored blocks and overlap lanes above the graph. Render start in project, sec aligns project positions with report time. Changing offset refreshes regions; Refresh regions picks up project edits. Tooltips show original project times. Context commands reject active-project changes.

Load waveform accepts an absolute path/file URL to the matching rendered audio. REAPER builds/reads peaks incrementally through an independent PCM source, merges channel extrema and releases the source without inserting media. The [REAPER API](https://www.reaper.fm/sdk/reascript/reascripthelp.html#PCM_Source_GetPeaks) supplies up to 4096 overview bins in bounded chunks. Waveform amplitude is independent of LUFS, is not a true-peak measurement, and is not regenerated from predicted gain. File time 0 maps to report time 0; durations are not stretched, and mismatches are reported. Deep zoom retains coarse overview resolution. Loading a new report clears the waveform. Live regions/waveform are not included in snapshots.

## Snapshots and export

The separate library stores multiple named snapshots: original M/S data, measured I, predicted output, parameter values, four editing curves, effective constant trim, source name, capture time and render offset. Cards show sampled M/S medians/maxima at original report sample times. I is measured; M/S medians are not I. Successful exports also capture snapshots.

Snapshots survive report loads and M/S switches. Selected measured/predicted overlays use report-relative seconds without stretching. Compare matching render ranges and offsets. Captures are detached from later edits. Browser local storage keeps the library across restarts when available. Download library provides a portable JSON backup; Import library merges validated data without duplicate IDs. Maximum 100 snapshots, 20000 points each; import maximum 16 MB. Local-storage failure asks for a backup. Older snapshot formats remain displayable.

Enable PRINTMASTER's Volume envelope and set render start before export. The track name comes from Post Master Setup. Export creates an automation item, uses one evaluated reference level for the entire correction, refuses existing points/items in the render range and supports Undo. External points that form a background ramp across the range are also rejected. Fresh automation-item points and playback parameters are reset before inserting the correction, so a constant normalization stays horizontal. Editing/settings do not export automatically. HTML is parsed without executing its JavaScript.

## Validation

Run `python tests/loudness_webview.py`, `node tests/loudness_webview_ui.cjs`, and `python tests/verify.py`. Tests cover normalization, pre/post stage separation, pure-normalize bypass, export gains/boundaries, storage/report reloads, opacity, zoomed edits, region clipping, waveform loading/channel extrema and source cleanup with mock DOM/API. These do not verify native WebView appearance, real audio, storage/download support or gestures. The new changes require a live REAPER test.

Right-click (or double-click) within 12 pixels removes the nearest interior point of the active visible editing curve. Context menu is suppressed over the graph; boundary anchors are retained. Tests cover single-point insertion, active-only reset, and right-click deletion without changing another curve.

## Razor editing

Choose Mouse → Razor area, select an editing curve, and drag horizontally to define a block. Selection alone adds no points. Drag the Level handle vertically or adjust Level, dB to lift/lower the original curve inside that block; its original shape is retained. Drag the lower Ramp handle horizontally (left widens) or adjust Ramp, sec to extend symmetric transition regions beyond the selection. Edge anchors appear when level is nonzero. Gain/ramp adjustments always rebuild from the captured original curve, so changing a handle does not accumulate gain repeatedly.

Drag inside an existing block (away from the Level/Ramp handles) to move it in time. Drag either vertical edge to resize that boundary independently; visible edge grips and cursor changes identify the targets. Moving preserves width, gain and ramp duration and stops at the render boundaries. Resizing cannot invert the block. Both operations rebuild from its captured original curve, removing the previous correction from its former position. Drag outside the block to start a new selection.

Ramp 0 uses 2 ms transitions for a near-square block. Wider ramps interpolate back to the original curve at the outside anchors; these transition segments retain linear interpolation even in Step mode. Other step segments remain stepped. Pre Razor gain stays within ±24 dB; Post gain is uncapped by that range, with wider Razor level controls; limiter boundary edits stay within -80..0 LUFS. Ramps clip at render edges. Clear selection or right-click in Razor mode removes the selection overlay and retains applied points. Selecting another editing tool or resetting clears selection; Reset active curve still affects only that selected curve.

The operation is available for Pre volume, Upper limit, Lower limit and Post volume when shaping is enabled. Alt/middle drag still navigates. Automatic exports do not occur. UI tests verify selection without mutation, level anchors, direct ramp-handle dragging and retained points after clearing selection. Live mouse interaction in REAPER remains to be tested.

## Default curve and linked limits

Post volume is the active tool on startup. Its zero-gain reference remains at Target; the absolute LUFS graph scale is the default. Drawing anywhere in the visible graph maps to a post gain without the former ±24 dB clamp. Output trim is a constant gain after all processing; its slider range expands when a typed or fitted value exceeds the default ±24 dB. The pre/dynamics budgets retain their limits.

Link limits to Pre volume adds the same pre-gain offset to both upper and lower threshold curves during shaping, retaining each underlying curve and the gap between thresholds. It also reveals Pre/Upper/Lower overlays. Pre input and linked thresholds therefore move together; post gain still does not move thresholds. Editing a linked limit subtracts the pre offset before storing its underlying point. Unchecking restores independent thresholds without altering their saved shapes. Pure normalization bypasses the link. Snapshots record the checkbox state and frozen output. Controller tests cover link/unlink output, unchanged underlying threshold settings, and post points beyond 24 dB; Lua tests cover wider gain payloads.

## Loudness and dynamics analysis

Open the collapsible Loudness & Dynamics Analysis panel beneath the main graph. Views:

- Loudness distribution: time-weighted occupancy in LUFS ranges, before versus gain-model output, based on the selected M/S series. Weights use midpoint cells so irregular sample intervals do not count equally. Optional source-silence exclusion uses the tool's gate. Native REAPER histogram mode displays the report's own bins/percentages, including the -infinity lower bin, without pretending these can predict a corrected histogram.
- PLR / PSR proxy history: measured original PLR is a horizontal reference; source-derived and estimated PSR proxy histories are overlaid. PLR uses original overall True Peak minus measured integrated LUFS (or explicitly labeled Sample Peak fallback). No corrected PLR is inferred after shaping.
- Loudness / dynamics map: original LUFS-S versus PSR proxy and gain-model estimates, with an adjustable personal PSR guide.
- Gain history: the applied correction at original report sample times.

PSR proxy takes the maximum sampled channel peak in the preceding 3 seconds minus corresponding LUFS-S. Estimated PSR shifts sampled peaks and S by the model gain; it cannot reconstruct true-peak windows or recompute actual loudness integration. Constant gain leaves ratios unchanged. Sparse render histories may miss micro-dynamics and are always labeled proxies; the first 3 seconds are excluded. The guide is a user reference, not a delivery requirement or proof of compression. See [SSL Meter Pro definitions](https://support.solidstatelogic.com/hc/en-gb/articles/27215779947421-SSL-Meter-Pro-Plug-in-User-Guide) and [Dynameter interpretation](https://www.meterplugs.com/files/dynameter2-guide.pdf).

Cards show original True Peak, PLR and LRA, plus time-weighted sampled P95−P10 spread and PSR median before/estimated after. The percentile spread is not EBU LRA. Missing peak/global data remain unavailable, never replaced with fabricated values. The parser reads original table metrics, per-channel sample peak labels and histogram data without executing HTML. Snapshots retain original metadata and sampled peak values.

Analysis is evaluated only while its panel is open; it does not alter export, settings or the REAPER project. Additional checks: `node tests/loudness_analysis.cjs` verifies occupancy, weights, percentile/gate behavior, PLR basis and constant-gain ratio invariance; controller checks render all four views, and Python checks the real report's peak/histogram data. Native appearance and real post-render dynamics still require testing in REAPER.

## Edit history and rerender verification

Undo/Redo keeps up to 100 processing edits: curve gestures, active-curve resets, Razor edits and parameter changes. Sliders commit on release; numeric fields commit on change. Ctrl/Cmd+Z and Ctrl/Cmd+Shift+Z (or Ctrl+Y) work outside text controls. Loading a new report clears edit history. Browser Undo does not undo an exported REAPER automation item; use REAPER Undo for that.

Open Prediction / Rerender Comparison, choose a saved prediction and load the rerendered report. The selected M/S metric is compared with the saved source plus gain. Project offsets align samples; positive Alignment shift moves the prediction later. The plot shows measured minus predicted loudness, with signed bias, MAE, RMSE and maximum absolute error over overlapping finite samples. Statistics are sample averages; predictions are linearly interpolated and sampling may hide brief changes. Different durations require checking alignment. Current measured integrated loudness is shown separately; this is not an exact integrated-loudness prediction.

## Audio-based final integrated preview

Enter the render statistics path and **original rendered mono/stereo audio** from the same render in **Source files**. Both paths are required. **Load files** loads the report, builds the waveform and measures final LUFS-I automatically. **Reload audio** refreshes the waveform and repeats measurement for the loaded report. The preview reads this audio without modifying it, applies the same serialized gain curve as export, and scans original and corrected audio with FFmpeg ebur128, including the integrated absolute/relative gates and true peak. It does not average or take the median of LUFS-S/M. REAPER envelope scaling is projected through its native scaling API; 10 ms gain samples plus exact exported knots model its linear envelope segments. The existing envelope baked into the source is divided out. Existing PRINTMASTER automation in the export range is rejected, as for export.

**Fit final I to target** adjusts **Output trim** after all pre/limiter/post processing, rescans, and performs up to three passes. Internal aim is 0.2 LU; success is reported only within 0.5 LU. It also works in Normalize only. This is a gain-only preview, not a guarantee for a different render or nonlinear downstream FX. Rerender to confirm delivery LUFS-I and true-peak requirements. Original audio I must agree with the report within 0.3 LU before fitting; audio duration must match within 20 ms. A curve change invalidates the previous preview. Output trim is retained in Undo/Redo, saved parameters, and export, and remains active in Normalize only. It stays with other parameter settings when loading a new report. Verified preview I and true peak are saved with snapshots, allowing integrated error against a subsequently loaded rerender.

On Windows the read-only worker uses a local Python installation with NumPy, and `ffmpeg.exe`/`ffprobe.exe` from REAPER's UserPlugins folder. It runs hidden, communicates through temporary job files, and streams decoded native-rate double-precision audio to the scanner without writing a corrected render. Offline preview supports ranges up to six hours with validated mono/stereo or supported multichannel speaker layouts. No plugins are installed by the action. A missing runtime produces an error or timeout rather than an invented estimate.

Validation: `python tests/loudness_audio_preview.py` checks real scanner audio, constant-gain agreement with an independently rendered file, dynamic gain target fitting, mono/stereo, duration rejection and worker error output. UI tests cover a simulated 1.5 LU error, fit, export, Undo/Redo, stale predictions and mismatched source rejection. Lua tests verify native scaled-envelope projection. The user's source/rerender pair is still needed to demonstrate ±0.5 LU on their material.

References: [ITU-R BS.1770-5](https://www.itu.int/rec/R-REC-BS.1770-5-202311-I/en), [FFmpeg ebur128](https://ffmpeg.org/ffmpeg-filters.html#ebur128-1).

User-material check (2026-10-05): FFmpeg measured `test-Loudness3.wav` at -11.7 LUFS-I / -0.9 dBTP, and `test-Loudness4.wav` at -21.5 / -9.6. A constant -1.5 dB final correction to version 4 measured -23.0 / -11.1. Version 3 with -11.245159 dB (from its precise REAPER source I) measured -23.0. These verify the audio scanner and final constant correction on the supplied material; they do not reconstruct the old variable curve or prove its prediction before the version-4 render. New live exports require the original pre-export project state: overlapping automation is protected. The matching waveform path must refer to version 3 when previewing the new correction based on its report.

The separate Final gain control has been removed. Fit final I updates the existing Output trim number and slider without editing the Post volume envelope. Reset Output trim resets only this scalar. Old snapshots retain their original predicted histories; their legacy final gain is included in the displayed total trim.

Fit to target sits beside the Target value in General parameters. The **↻ Refine (Уточнити)** icon at the right end of the statistic tiles runs a fresh audio measurement without changing Target or Output trim; source / projected final I and true peak appear with the source-file paths. Loading only measures and does not change Output trim. Changes to curves invalidate the result and show sampled M/S estimates again; Refine restores verified audio I. Fit performs a fresh measurement before updating Output trim. File-URI audio paths are decoded consistently for waveform and loudness analysis.

## Compact main workspace

Source I / projected final I / target error / predicted true peak occupy one right-aligned line beside source actions. Report and waveform metadata are field tooltips. Fit sits beside the Target number; its slider remains below. Routine normalization explanations are hidden; actual invalid-normalization/export conditions remain visible. Graph instructions are under Graph help. Basic limiting controls have a collapsible section; it starts closed for windows below 950 px tall. Advanced limiting has its own collapsed, scrollable section. Export is immediately below the graph, before optional analysis and snapshot panels. Chart height adapts to available viewport height. Headless browser screenshots verified the default workspace at 1440×1080 and 1366×768; the real WebView remains the final appearance check.

The Before/After tiles switch to green **Before I / After I · verified** for a current, matching offline audio measurement (automatic load or Fit). Any curve/processing-parameter change invalidates verification and returns them to amber **Before/After M/S · est.** sampled medians. Labels change with the metric to avoid presenting a median as LUFS-I. Gain/trim fields retain their own meanings. Verification is keyed to the report revision, audio path, serialized exported curve and all processing settings; view navigation and visibility do not invalidate it. Undo back to the measured configuration can restore verification. This verifies the offline gain model, not a new REAPER render with downstream processing.

## Playback and replacing an export

Playback is a compact row below the graph. **File · A/B** streams the matching audio from a hidden Python helper bound to 127.0.0.1 using byte-range requests and supports **A · Original / B · Processed**. No media is uploaded and no tracks/files are modified. The supported browser formats are WAV, MP3, FLAC, OGG, M4A, AAC and WebM, without the former 128 MB transfer limit; decoder support depends on the installed WebView. Duration must match the report within 100 ms. Playback can start after the browser reads the header; the whole file is no longer copied or base64-encoded through the bridge. Play/Pause (▶/❚❚) and Stop (■) use icons with accessible labels. The same stream and browser buffer are reused for repeated Play and same-source report reloads. A lightweight HEAD check detects source overwrites before reuse; Reload audio or a changed audio path clears the cache. The helper serves only the selected file at an unguessable URL and exits on close or an expired heartbeat (180 seconds). A browser autoplay restriction can require pressing Play again once loading finishes.

**REAPER · exported mix** controls the current project's transport. Export the curve first to hear the edits through the project and its downstream FX. Pending browser edits are not applied to audio automatically. Play/Pause/Stop and **Mouse → Playback / seek** share a cursor aligned with graph zoom and Render start. Seek suppresses curve editing and right-click erasure while selected. **Alt+left click** temporarily seeks in every mouse mode without adding points. Middle-button dragging or Navigate mode pans the graph. The cursor also observes externally started REAPER playback while timeline monitoring is active. Recording disables transport controls. Only playback started by the tool is stopped on report/source change or window close; unrelated externally started playback is preserved. Starting playback through the tool stops at the report's end. For windows under 850 px high, graph height is reduced to retain the main controls and export row on screen.

**Replace existing curve** is off by default. It updates one automation item whose start and length match the full export range; it never adds a duplicate. Partial/multiple overlaps, named items belonging to another tool, shared pools and underlying points remain protected. An old unnamed export with matching bounds can be migrated. New exports tag the pool with the original reference level and source report identity, so preview/measurement after export use that original baseline without counting the exported gain twice. Keep the original audio/report loaded when replacing; a different rerender report is rejected. Failure to clear/insert points restores the original envelope chunk, and replacement remains covered by REAPER Undo.

Offline validation: `python tests/loudness_audition.py`, `python tests/loudness_stream.py`, `python tests/loudness_preview.py`, `node tests/loudness_preview_ui.cjs`, and the existing parser/controller/audio tests cover streaming helper launch/cache/lifecycle, source cleanup, pause/resume/seek, viewport and project offset alignment, recording/project switches, replacement without duplication, legacy migration and rollback. Native REAPER playback and WebView audio output still require a user check.

## Loudness constellation and fingerprints

The collapsed **Loudness constellation** panel reads either project regions or items on an exact named scene track. The track defaults to the shared Setup location track, normally `#Location`. Auto labels use take names first and then item notes, matching Post Master tags; Notes / Take names can be selected explicitly. Empty-item notes are supported, unnamed items get Scene N, ranges are clipped to Render start/duration, overlaps remain independent, and duplicate track names are rejected. No project items, notes or regions are modified. Up to 2000 scenes can be scanned in one selected range. Use Range / Time window for a smaller group in a long film.

Each scene is a bubble: x = scene loudness minus Target, y = selected dynamics. Size represents scene duration. Outline / filled bubbles show before / after and are connected. Click a bubble or scene name to focus the main graph and seek without starting playback. Blue = quieter than guide, red = louder, amber = dynamics outside guide, green = within guides, gray = unavailable. The ±LU and dynamics bounds are adjustable personal scene references; whole-program delivery standards do not require every scene to hit the same I.

The immediate report overview uses weighted sampled S medians and S P95−P10 spread. It never labels those as I or LRA, and report M/S windows may straddle scene cuts. **Measure scene audio** reads the matching original render with a supported speaker layout, resets an FFmpeg EBU R128 scanner at every scene boundary, and scans source plus the same native projected gain as export. Results include I, LRA, True Peak, PLR (TP − I), RMS and crest (maximum sample peak − RMS averaged over channels). Full-program source I must agree with the report within 0.3 LU. Meter-gated silence has no I; LRA is unavailable below 3 s and is flagged unstable below 60 s. Scenes shorter than 60 seconds carry an LRA-stability warning, following the EBU guidance against using programme LRA on such short material. After metrics measure the gain model, not downstream nonlinear processing. Changes to gain, report, source or scene definitions invalidate scene measurements and return the plot to the labelled sampled overview. Reload audio also clears the scene cache.

Snapshots now form a collapsed comparison table with before/after I, LRA, TP, PLR, crest, RMS, sampled M/S medians, audio/sampled M/S maxima, Target/trim and expandable scene fingerprints. Missing measurements are shown as —; no corrected I is inferred from an M/S median. Existing libraries remain readable. New matching full-audio measurements include RMS/crest/LRA for the fingerprints. Source-mismatched measurements are excluded. Each saved scene profile freezes source definitions, guides and available metrics independently of later reports.

**Save after export** is enabled by default to preserve the previous workflow. Its checkbox persists independently of the library; when disabled, successful exports do not add a snapshot, while Save snapshot remains available. A library means the entire local collection, not a separate audio asset: Download library writes one JSON backup, Import library merges its snapshots by unique ID. The block includes a collapsible explanation of this behavior.

Validation: `node tests/loudness_constellation.cjs` checks scene statistics and outlier classification; `python tests/loudness_scene_audio.py` independently checks synthetic loud/quiet/silent scenes, short scenes, RMS/crest, constant-gain invariance, absolute gain timing, source rejection and worker serialization. The controller and Lua tests cover read-only item labels, bounds, scene-cache freshness, fingerprint persistence, table rendering and export autosave preferences.


## A/B audio audition

**File · A/B** uses one streamed media element for both modes. Original has unity gain; Processed uses a Web Audio GainNode scheduled from the same native, scaled-envelope projection used by the offline measurement and export. It includes normalization, pre/limiter/post curves and Output trim, without writing an envelope or rendering a new audio file. Numerically collinear samples are removed before bounded bridge transfer; nonlinear native scaling and 2 ms Razor transitions remain intact. The two adjacent **A · Original / B · Processed** buttons highlight the active mode. Switching A/B preserves playback position and resumes playback if it was running; seek reschedules the gain at the new position. Projection is cached until the curve/report changes. Editing an active Processed curve pauses at the current position: press Play to refresh the projection and continue, rather than hearing an obsolete curve. This is a gain-model audition; REAPER downstream FX are heard through timeline playback. Playback mode and A/B choice are not saved or automatically started on restore.

Validation includes mock gain scheduling/seek/cache/stale-change tests and actual Web Audio output in a hidden Edge browser on a synthetic sine: a -13 dB projection produced about -13.07 dB measured RMS change. The full loaded workspace still fits 1366×768. Native WebView output remains a user check.

## Continue an editing session

Curve gestures, completed parameter changes, Undo/Redo, selected editing tool, graph view and visibility are automatically saved locally with the source report/audio paths and scene settings. **Resume session** reloads the recorded original source, checks report name/duration/I, restores the four editable curves and settings, rebuilds the waveform and repeats precise measurement. It does not export or start playback. Loading a new report normally starts a new working session and retains the independent snapshot library.

Each snapshot now has **Restore** beside Delete. New snapshots carry source paths so Restore can reload their original report/audio; legacy snapshots without paths require the matching original report to be loaded already. Re-render reports with a different source identity are rejected. Curves/parameters are validated before use, and failed restoration does not overwrite the last saved session. Saved audio/scene measurements are not treated as fresh after restoration; the audio measurement runs again.

**Download session / Open session** in the collapsed snapshot block provide a portable JSON editing backup, separate from Download/Import library. Audio and reports are referenced by path, not bundled; keep those original files. The session JSON stores the editing state, while a library contains the collection of frozen comparison snapshots. Controller tests cover restart resume, restored export equivalence, snapshot restore, source mismatch protection and malformed session rejection.

Next planned work: delivery profiles with LUFS/True Peak checks; more real source/rerender validation of variable gain; independent stem analysis based on the summed audio rather than summed LUFS values.


## Target profiles in General

Profile shares the existing General row. Selecting a profile sets Target through the normal target control, preserving the existing relative threshold offsets. It does not change Processing, Output trim, the pre/post drawings or compression ratios, and does not automatically Fit, measure, play or export. A fresh precise measurement is checked against the selected profile as described below. Manual Target changes switch to Custom. Profile is retained in Undo/Redo, snapshots and working sessions; older backups without a profile restore as Custom. Selecting a profile with an unchanged numeric target keeps verified measurements fresh.

| Profile | Integrated target | Reference maximum TP | Scope / official source |
| --- | --- | --- | --- |
| EBU R 128 | -23 LUFS | -1 dBTP | Programme loudness: [EBU R 128](https://tech.ebu.ch/publications/r128), [Tech 3343 v4.1](https://tech.ebu.ch/docs/tech/tech3343v4_1.pdf) |
| ATSC A/85 Short | -24 LKFS | -2 dBTP | Full-program short-form: [A/85:2026-07 Annex M](https://www.atsc.org/wp-content/uploads/2026/07/A85-2026-07-Annex-M.pdf). Long-form dialogue measurements are outside this tool's programme-I scanner. |
| Apple Podcasts | -16 LKFS | -1 dBTP | Overall loudness recommendation: [Apple audio requirements](https://podcasters.apple.com/support/893-audio-requirements) |
| Spotify Normal | -14 LUFS | -1 dBTP | Normal playback reference and mastering guidance, not an ingest requirement: [Spotify loudness normalization](https://support.spotify.com/us/artists/article/loudness-normalization/) |

These are target presets with I/TP checks, not complete delivery certification. True Peak values appear in the Profile tooltip and do not enable a peak limiter. Values were checked against the official sources on 2026-10-05. Controller tests cover all target choices, relative threshold shifts, unchanged post/trim/processing, manual Custom switching, Undo/Redo, snapshot/session persistence and old-session compatibility. Browser checks cover the A/B audio output and unchanged 1366×768 workspace height.


## Long-film usability

Original/processed audio measurement, Fit and scene scans show phase, percentage, scanned audio time and elapsed wall time in the existing source action row. Cancel stops the owned scanner processes. Cancelling Fit restores its initial Output trim; previous complete measurements and scene results remain available. Waveform peak-cache preparation also supports Cancel. Closing the tool cancels its outstanding worker and requests temporary-job cleanup.

Audio projection supports programme ranges up to six hours; reports support 200,000 samples (32 MB HTML limit) and export up to 200,002 correction points. Runtime allowance scales with programme length (at least 30 minutes, otherwise twice the duration plus five minutes), with a separate ten-minute no-progress watchdog. These bounds do not certify surround delivery; supported speaker layouts are described below.

Horizontal zoom reaches approximately a two-second view on long programmes. Visible waveform detail is fetched from REAPER's retained PCM source/cache, capped at 4,096 merged-channel peak bins per request. Eight recent viewport results are cached; pan/zoom requests are debounced and stale results discarded. Clear/reload/close releases the source. Loudness path drawing visits only visible samples and neighbouring interpolation anchors. Native constant-gain projection uses two endpoints, and playback reuses its serialized gain request between cursor updates.

For snapshots exceeding 20,000 history points, only the comparison overlay is reduced using per-bucket extrema; full fingerprint summaries, editable curves, parameters and source references are retained. The snapshot tooltip identifies this reduced display history. Existing compact layout is preserved; no additional vertical panel is introduced.

Validation covers real FFmpeg mono/stereo scans, scene measurement, live child cancellation and abandoned-job cleanup, native waveform-detail mocks, three-hour constant projection, dense exports, UI progress/Cancel and waveform cache reuse. A full-length film and live REAPER peak-building/playback still require a user trial.


## Optional A/B waveform

Enable **Waveform follows A/B** beside the playback buttons to display gain-adjusted peak bins in File / B · Processed. A · Original, timeline playback and the unchecked option use the original peaks. The preference is remembered locally. Prepared native preview gains are used when current; curve edits update the visual estimate immediately using the current dB correction until native gain is refreshed. Switching A/B redraws the waveform without reading or decoding the file again, modifying cached source peaks or exporting anything.

This is an amplitude estimate: each peak bin uses gain at its centre, so bins containing fast gain changes are approximate. Zooming improves peak-bin detail. The waveform uses the same fixed amplitude scale in A/B and clips its display at full scale; it does not include downstream REAPER effects or represent LUFS. Controller checks cover -13 dB native-gain scaling, original restoration, opt-out and no project writes.


## Peak statistics and mouse Scanner

The compact general statistics row includes Peak before → after. A fresh Refine/Fit measurement displays verified True Peak in dBTP. Edits revert to report TP (or SP when TP is unavailable) before and sampled report peak plus current gain after, explicitly labelled SP estimate in dBFS. Missing peak history displays —; it is never presented as measured True Peak. Tooltips identify units and measurement quality.

Select Mouse / Scanner to inspect report time, momentary and short-term loudness before → estimated after gain, total gain, and sampled peak if present. The readout and dashed cursor appear inside the graph without adding interface height. Values interpolate sampled report history at the cursor; they are not new audio measurements. Left/right clicks cannot edit in Scanner; Alt+click still seeks. Leaving the graph hides the readout. Scanner mode persists in editing sessions.


## Multichannel loudness measurement

Refine, automatic source measurement, Fit and scene scans support explicit speaker layouts: mono, stereo, 2.1, 3.0/3.0(back), 4.0, quad/quad(side), 5.0/5.0(side), 5.1/5.1(side), 6.1/6.1(back), and 7.1/7.1(wide)/7.1(wide-side). The file must identify its speaker layout; arbitrary channel counts, unknown multichannel layouts and ambisonics/object audio are rejected. Export such audio as a correctly labelled speaker-based WAV first. File channel labels must match actual channel order: this tool cannot discover a mislabelled file from its samples.

The same layout is explicitly supplied to each raw PCM scanner. Audio stays interleaved in its decoded channel order, and the same gain is applied to every channel. FFmpeg EBU R128 handles speaker weighting and excludes LFE from LUFS while True Peak and sample peaks still include every channel. RMS/crest remain the existing unweighted average over all channels, including LFE; they are not loudness-weighted values. Source metadata appears in the existing measurement line and audio-path tooltip and is retained in measured snapshots. No additional interface row is introduced.

Measurement does not downmix. File A/B playback in the browser can route/downmix according to browser and device capabilities; use REAPER playback to audition the actual surround routing. Waveform remains the merged-channel peak overview. Tests use real quad, 5.1, 5.1(side) and 7.1 float WAVs and verify constant/dynamic correction against separately generated WAV references, scene timestamps, LFE exclusion/inclusion and surround +1.5 LU weighting. Other listed layouts use the same validated metadata/PCM path, but have not each been independently audited in REAPER. Surround delivery remains subject to an actual REAPER rerender comparison.

References: [FFmpeg speaker layout/input options](https://www.ffmpeg.org/ffmpeg-all.html), [EBU R128 channel weighting implementation](https://github.com/FFmpeg/FFmpeg/blob/master/libavfilter/f_ebur128.c).


## Offline WAV stems (2026-10-05)

Open **STEMS · LOUDNESS & DYNAMICS** below Export. Enter absolute WAV paths for Dialogue/Music/SFX (or rename/add up to eight stems), then **Measure stems**. Load Master from a render report or the built-in audio analyzer to establish the shared time view; stem files can have different durations. Positive **Start offset** places a file later relative to the master render's zero. Keep offset zero for aligned full-length stem renders. Offset changes display alignment only: fingerprints always measure the whole file.

The native-rate FFmpeg audio scanner measures each stem once, with supported explicit speaker layouts and without applying master correction curves. The table shows integrated LUFS, LRA, True Peak, sample peak, PLR, crest, RMS and M/S maxima. M/S display can be switched individually or together (M dashed). Checkboxes hide stems; optional original-master M/S provides context. Horizontal zoom/time position follow the main graph; the level scale fits visible stem histories. Hover shows the nearest displayed M/S sample. Master Target is a mix reference, not a stem pass/fail criterion. Stem LUFS cannot be added to reconstruct the master; an exact summed-mix analysis requires aligned PCM summation.

Each stem uses one decoder and one meter, serially across the batch. The normal measurement progress/Cancel controls apply; results are committed after the entire batch succeeds. Cancellation/failure preserves prior measurements. File size/mtime are checked before and after scanning. Paths, labels, offsets and visibility persist locally. Measurements survive loading a new report while this window remains open; reopening the tool requires Measure stems, which reuses unchanged cached histories when available. Rescan whenever files change. Whole-file I/TP/LRA use all audio; the display retains first/last and M/S extrema in time buckets, bounded to 6,000 points per stem. No measurements or audio are stored in the local path preferences. Short files may lack valid M/S windows; LRA below 3 seconds is unavailable and short-programme LRA is less stable.

Validation: `loudness_stems.py` compares real WAV stem I/TP against unity-gain master scans, tests native 44.1 kHz, M/S window timing, silence, Unicode worker responses and bounded extrema retention. The controller regression covers serial batches, report reload, offset/visibility persistence, cancellation and unchanged master curves/export. The browser check covers the collapsible section, table/graph rendering, page width and unchanged 1366×768 main controls.

## Shared Master / stem curve editor

Use **Editor source** at the left of the View/zoom row directly above the graph to select **Master** or a measured stem. The buttons in the Source Files heading and **Edit** beside a stem select the same source. Return to **Master** in Editor source to restore its graph and settings. **Destination track** below the graph chooses the export track, not the source being edited. Master and every stem keep independent Pre/Post/limit curves, processing parameters, target, Output trim, view, Undo/Redo, audio estimates and destination track. Stem editing starts with Shape only, zero correction and compression ratios of 1; short files automatically select M history. Unavailable initial M/S windows remain gaps and do not stretch Fit view. Switching sources stops playback and reloads waveform peaks without automatically rerunning loudness measurement. **Refine/Fit** measures the active source/curve. Existing scene analysis and A/B operate on that source.

Choose **Destination track** in the existing export row; refresh updates the list. Selection uses REAPER track GUIDs, so duplicate names and renaming are safe. Master defaults to the profile PRINTMASTER destination; stems require an explicit track. Enable that track's Volume envelope before Refine/B playback/export. The same scaling/reference-level projection and protected automation-item exporter are used for every destination, including visible envelopes, Undo, complete-range replacement, pooled-item protection and rollback. Missing/deleted destinations disable export. Exports record the stem path/file identity as well as original I/name; a curve from another source is protected. Refine/scene scans reject a changed file identity. Rerender to account for downstream processing.

Each stem's curves/settings/destination are saved with its local path preferences. After reopening, load Master and measure the unchanged stems again to restore editing; changed files start with fresh curves. Master autosave is kept separately. Downloaded stem sessions and snapshot Restore require their matching WAV to have been measured, then switch to that source. Undo/Redo and measured estimates remain in memory per source. Initial stem export start is Master render start plus the stem Start offset; negative project starts are rejected at export. Stem overview remains original, aligned audio history; edited stems are displayed in the shared editor. No audio summation or summed-master prediction is implemented yet.

Validation: `loudness_source_export.py` runs the actual native command router with mocked transport/worker, and exercises duplicate/renamed/deleted GUID destinations, per-source target retention, busy guards, projected requests, source identity protection and isolated envelope writes. Controller tests cover independent settings, exact measurement freshness, Undo/Redo, export and restart restoration. Browser tests confirm active tabs, track picker, source switching and main controls within 1366×768. Live exports were not performed during automated checks.

## Native-rate precision and measured profile checks (2026-10-05)

The worker probes and preserves the original sample rate (8–192 kHz) for source, corrected PCM and each scene. PCM processing is double precision. No fixed 48 kHz conversion is performed. All channels keep their declared speaker layout. Source and corrected audio use the same filter chain. `libebur128` is not integrated.

I/M/S/LRA come from FFmpeg `ebur128` frame metadata at 0.001 LU resolution rather than its rounded 0.1 LU console summary. Peak measurement uses FFmpeg SWR double-precision 192 kHz oversampling followed by cumulative `astats` peak metadata in dB (six decimal places), avoiding the low precision of ebur128's linear-amplitude peak metadata. This also accounts for the final partial frame and resampler flush. Stats are aggregated by reading the temporary log incrementally, rather than loading its entire contents into memory. GUI values retain one decimal for readability; calculations, Fit, profile checks and snapshots retain the metadata values. Resolution does not imply guaranteed measurement accuracy.

A compact badge in the existing source action row shows **I/TP: PASS / FAIL** only with fresh precise gain-model measurements whose source I matches the report. Curve/source changes or legacy results yield **Refine**, not a stale PASS. Selecting a different profile at the same numeric target rechecks the fresh measurement without an unnecessary scan. Custom has no standard badge. PASS checks the stated programme-I and TP criteria only; it does not certify all delivery requirements, dialogue gating, codecs or downstream FX. These checks do not limit peaks automatically.

| Profile | I criterion | TP criterion | Scope |
| --- | --- | --- | --- |
| EBU R 128 | −23 ±0.2 LU | ≤−1 dBTP | QC measurement allowance from current R128-2023; no live-programme exception |
| ATSC A/85 Short | −24 ±2 LU | ≤−2 dBTP | Short-form full-program mix; no long-form dialogue-gated claim |
| Apple Podcasts | −16 ±1 LU | ≤−1 dBTP | Apple's overall loudness recommendation |
| Spotify Normal | −14 ±0.5 LU **tool editing guide** | ≤−1 dBTP; ≤−2 when measured I is above −14 | Stereo mastering guidance; badge says Guide, not delivery certification |

The earlier generic ±0.5 LU EBU discussion referred to older requirements/our fitting goal. Current R128-2023 specifies ±0.2 LU for QC measurement allowance; this is used by the profile check. The Fit goal remains ±0.2 LU before checking the selected profile.

References verified 2026-10-05: [R128-2023](https://tech.ebu.ch/docs/r/r128.pdf), [EBU Tech 3341](https://tech.ebu.ch/files/live/sites/tech/files/shared/tech/tech3341.pdf), [ATSC A/85 Annex M](https://www.atsc.org/wp-content/uploads/2026/07/A85-2026-07-Annex-M.pdf), [Apple requirements](https://podcasters.apple.com/support/893-audio-requirements), [Spotify mastering guidance](https://support.spotify.com/us/artists/article/loudness-normalization/).

Validation: `loudness_precision.py` verifies native-rate source/corrected WAV equivalence at 44.1/48/96 kHz, sub-tenth metadata, nonaligned scene boundaries, final partial-frame peaks, reconstructed EBU Tech 3341 calibration cases 1–2 and True Peak cases 15–19. Mono/stereo, surround/LFE and scene regression tests use the updated scanner. UI checks cover fresh/stale profile status, unrounded I/TP threshold decisions, profile changes and Spotify stereo scope. The official EBU v5 ZIP returned HTTP 403 from both current and legacy official URLs; the reconstructed subset is not a substitute for the complete official test set or ITU BS.2217 tests. No full compliance/certification claim is made.

## Editing readout and optional Snap

Moving or drawing an envelope point shows its time in seconds, plotted level and envelope value inside the graph. **Snap · 1 dB** beside View is optional and off by default. It snaps edited levels to integer ticks of the selected scale: absolute LUFS, or dB relative to Target. For a fractional target these are different grids. The preference is remembered locally. Existing points are not changed when enabling Snap. Razor level changes snap affected points while preserving outer anchors.

## Analysis sources and built-in Master history

**Analysis data / cache** in Source Files selects the Master history provider. Choose **REAPER render statistics** or **Built-in audio analyzer**, then **Load files**. Built-in mode requires only the original audio path; it builds whole-programme M/S history and an optional **Cumulative I curve**. The latter measures integrated loudness from file start, not a sliding window or the corrected output. Initial incomplete M/S windows remain gaps. Peak history uses sampled 100 ms sample peaks, not True Peak history. Whole-file fingerprint peaks retain the precise audio measurement. Display history is bounded to 6,000 points with extrema retention; measurements use the full audio. Switching the provider takes effect on the next load. Refine/Fit still analyze audio with the current gain curve for both providers.

Loudness & Dynamics Analysis, Loudness Constellation and Prediction / Rerender Comparison each have **Source / Follow editor**. Follow editor is enabled by default. Disable it to pin that panel to Master or a measured stem while editing another source. Scene refresh/measurement use the selected analysis source and its saved correction settings without switching the editor or exporting a curve. The stems overview continues to show multiple aligned original sources.

## Reduced export points and active envelopes

Preview, Refine/Fit, scene scans and export automatically share a reduced correction point set. Reduction uses the destination's actual envelope scaling and reference level, checking gain error at the original knots and quarter-segment positions with a conservative 0.005 dB threshold. It does not thin the loudness analysis graph or alter editable control points. First/last points and paired millisecond step anchors are preserved. A flat curve needs only two points; complex curves retain more. The export status reports the final point count and original count when reduced. This sampled tolerance is not a delivery loudness guarantee; downstream processing still requires a rerender check.

Export sets both **ACT 1** and **VIS 1 1** on the destination Volume envelope, preserving the remaining fields and unrelated state. Insertion failure restores the original envelope chunk, including its previous active/visible state. Existing destination, replacement, pool and source protection remains in effect. No automation recording mode is changed.

Validation: `loudness_reduce.py` tests a two-hour 72,001-point flat history (two endpoints), a smooth history in raw/nonlinear fader coordinates, dense interpolation error, millisecond step boundaries, agreement between projected/exported gains, inactive envelope activation and rollback. These tests use mocked REAPER; real timeline responsiveness and a long-film rerender remain to be checked in the user's project.

## Project cache

For a saved, writable REAPER project, the tool creates **SBP_LoudnessCache** beside its `.rpp` file. Persistent `audio-*.json` files contain original audio histories/fingerprints; the original audio is not copied. Cache identity includes path, file size, modification time, analyzer version and FFmpeg executable modification time. Unchanged histories are reused without decoding; changed files are rescanned. Temporary worker logs and playback control files also use this directory and are cleaned up after their jobs. Unsaved/unwritable projects fall back to TEMP. The available folder and loaded history cache appear under Analysis data / cache.

This location covers the tool's audio-analysis cache. WebView preferences, snapshots and editing autosaves remain in browser local storage; browser media caches and REAPER `.reapeaks` remain controlled by their engines. Precise corrected Refine/Fit and scene measurements are recalculated rather than reused from an original-history cache.

Validation: `loudness_cache.py` checks actual audio history, cumulative I, decode-free reuse, file-identity invalidation and project/TEMP placement. Controller tests exercise point readouts, optional absolute/relative snapping, pinned/linked analysis sources, independent scene scans and report-free Master/session restoration. Native routing tests cover report-free startup and independent-source scenes.

## Stable region strips on long timelines

Region rows are assigned on the complete sorted timeline, so panning/zooming does not move a region between rows. Boundary roundoff below one microsecond is ignored for lane assignment; actual overlaps retain separate rows. Blocks have no minimum border/padding width and remain clipped to their true time span, including subpixel regions. Full names and project times remain in hover tooltips. Controller tests cover an hour-long range, unordered regions, adjacent boundary roundoff and real overlaps; browser checks cover 54 adjacent regions and subpixel widths without visual overlap.

## Movable scene window for long films

The scene collector, audio worker and snapshot imports support up to 2000 scenes per selected range. In Loudness Constellation, **Range / Whole source** shows all available scenes within that limit. **Time window** selects scenes intersecting a source-relative window, with **Start / Duration** in minutes and a full-file time scale containing a highlighted window. Drag the window or click the scale; release to refresh the group; **Use graph view** copies the active editor's zoom/pan range. The button is unavailable for an independently pinned analysis source. Refresh/Measure scene audio use only the selected group. Scenes crossing the window boundary retain their full source-clipped boundaries and whole-scene fingerprints; the window does not trim their measurements. Controls live in the collapsible analysis panel and do not increase the main editor height. Window settings persist in sessions. Selecting a new window requires a fresh scene audio scan for measured values.

Collection filters the window before checking the count, so a project with more than 2000 total scenes can still analyze smaller groups. The overview looks up only each scene's local history instead of copying the entire film per scene. Tests cover 300 scenes from regions/items, nonzero project offsets, full boundary scenes, a project beyond the overall limit, movable selection, graph-view selection and matching measurement scope.

## Scene navigator and collapsible measurements

The full-file scene navigator shows four timeline divisions and the selected window's start/end. Window width corresponds to Duration and remains constant at the source's right boundary. Click outside the window to centre it there, or drag inside it without shifting the grab position. Arrow keys move by 10 seconds (Shift: 60 seconds); Home/End move to either edge. Pointer cancellation restores the previous position. Scene requests happen once on pointer/key release, not during movement. While dragging or waiting for the selected group, committed chart/table contents remain visible; background resize rendering is also held during the draft window.

**Scene measurements table** is independently collapsible, initially closed, and its preference is remembered locally. Open tables use a fixed bounded scrolling area with a sticky header, so row counts cannot shift the rest of the panel. Real-browser pointer checks verify unchanged table nodes and height during dragging, exactly one request on release, and stable height after the selected scene count changes. Controller checks cover cancellation, keyboard movement and the saved table preference.

## Space playback and editor scene boundaries

**Space** toggles the selected File A/B or REAPER timeline playback while the WebView has keyboard focus. Repeated keydown events do not retrigger it; loading, recording and busy guards remain active. Space inside text/number inputs, selects and contenteditable fields keeps their normal editing behaviour.

Beside Regions in the visibility row above the graph, **Scenes** enables a purple scene strip above the editor graph. It reads the scene source/track/label settings from Loudness Constellation, using the active editor source's duration and project offset. The read-only editor collection covers the full source (up to 10,000 scenes), separately from the analysis window and its measurement revision. Refresh regions also refreshes this strip. Changes to the scene source/track/labels refresh it automatically. Scene-strip visibility is remembered locally and in editing sessions. The graph makes room for the strip within the existing vertical budget.

**Snap to regions / scenes** is a separate optional temporal snap, off by default and remembered locally. It snaps initial Razor selection, either resized edge, or a moved block to the nearest boundary within eight screen pixels. Moving a block preserves its duration. Region/scene visibility does not disable boundary snapping. Scene boundaries are collected when either Scenes or temporal Snap is enabled. **Snap · 1 dB** remains independent and only snaps levels.

Controller tests cover Space play/pause and typing/repeat guards, scene collection isolation, Razor selection/edges/movement and opt-out. Native tests ensure editor scene collection does not alter the analysis revision. Real-browser tests verify actual audio Space play/pause, typing guard, scene-strip geometry and compact controls with Scenes enabled. No live REAPER transport was exercised.

With Snap · 1 dB enabled, the Razor Level slider and mouse level handle quantize their gain to whole dB; both the slider output and graph handle label show integers. Disabling it restores the 0.1 dB slider step. Temporal Snap is shown only in Razor mode, with its preference retained when hidden. Mouse choices are grouped as Editing (Edit curves / Razor area), Playback / navigation (Playback / seek / Navigate / pan) and Analysis (Scanner).

Corrected estimate uses a colored M/S ribbon by default. In Graph help / display, disable Corrected estimate ribbon to restore the green line. The 3 px curve has a continuous gradient relative to Target: −6 LU blue, −3 cyan, 0 green, +3 amber, +6 red (outer colors hold beyond ±6). These visual guides do not represent integrated loudness compliance or limiter thresholds. Measured M/S remains unchanged. The preference is retained locally and affects neither processing nor export.

Edit curves: pressing inserts a point at the existing envelope value without jumping to the mouse level. Hold and drag to change its level/time; existing points are selected by proximity in both axes. Optional 3 points adds unchanged anchors at the chosen ± seconds, limiting changes to the surrounding interval (existing interior points are retained). These controls appear only in Edit curves; preferences are retained locally.

Restoring a saved session or snapshot does not automatically scan original/processed audio for exact final loudness. Restored values remain estimates until Refine or Fit to target is requested. A newly loaded source still measures automatically. Loading report/audio history and waveform caches remains necessary to display the restored source.

Prediction / rerender comparison now includes a time axis, signed Δ LU ticks and a zero reference grid. Only valid overlapping M/S measurements above −70 LUFS (including the predicted post-gain level) enter error statistics. Invalid/silent samples and timeline gaps over three typical sample intervals break the curve; interpolation never crosses such gaps. Isolated valid samples appear as dots. This silence cutoff is a display/comparison guard, not the BS.1770 integrated gate.

File-only prediction (v0.1.2): Refine, Fit, file A/B and scene measurements apply the tool gain to the loaded WAV without requiring a clean destination envelope or even an export track. Existing automation/FX already baked into the WAV are not applied again. Destination automation does not block prediction. When available, its envelope scaling/reference is read only to preserve interpolation fidelity; otherwise raw linear-gain interpolation is used. Choosing a different destination invalidates the prior precision measurement. Export retains strict point/item/background-ramp/source protection and may still require resolving a conflict. File measurements are not a simulation of downstream project FX or timeline automation.


## macOS compatibility update — 0.1.3

Local source paths now support Windows drives and macOS/POSIX paths for reports, waveforms, stem analysis, scene measurement and file preview. Paste an absolute Finder path such as /Users/name/Renders/Mix.wav or /Volumes/Media/Mix.wav; local file:/// URLs are also accepted, with URL decoding only for URLs. Spaces and Unicode are preserved. Remote file URL hosts are rejected.

On macOS, Python uses python3 instead of pythonw.exe and searches /opt/homebrew/bin, /usr/local/bin and /usr/bin. NumPy must be installed for the selected Python. FFmpeg is found in REAPER UserPlugins as ffmpeg (no .exe), or in those executable folders; matching ffprobe is selected without the Windows suffix. The binaries must be executable. Cache uses the saved project folder when writable, otherwise TMPDIR (or /tmp). Command arguments are quoted for the host platform. Case-sensitive source identity is preserved outside Windows. Cmd shortcuts and Cmd+wheel already work.

Install the entire updated folder, including the new platform.lua module. Windows automated regressions and mocked macOS path/cache/waveform/worker launches passed. A native macOS REAPER/WebView run is still required to verify the installed extension, process launch, browser playback and audio dependencies on Intel/Apple Silicon.

Portable tests: python tests/loudness_platform.py and node tests/loudness_paths.cjs. Optional real-report parser tests now use SBP_LOUDNESS_REPORT_FIXTURE instead of a hardcoded Windows temporary report.


## File selection without WebView keyboard — 0.1.4

Browse buttons beside the report, original audio and each stem open REAPER native file dialogs. Select the file and then press Load files or Measure stems. Cancel leaves the old path unchanged; selecting does not start a scan. Native dialogs have a longer bridge timeout.

Paste path reads the macOS system clipboard through /usr/bin/pbpaste on an explicit button click, avoiding WebView Cmd+V focus issues. Copy a single absolute pathname (Finder Copy as Pathname) or local file URL, then click Paste path. On other systems the button uses browser clipboard access when available; Browse remains the fallback. This adds no required extension and does not change keyboard handling in ReaWebAPI itself. Native chooser/clipboard behavior is tested with mocked macOS APIs; actual macOS WebView testing remains required.
