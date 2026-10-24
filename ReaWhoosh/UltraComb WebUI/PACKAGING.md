# UltraComb 3 — release and ReaPack packaging

## What to upload

Upload the complete `ReaWhoosh/UltraComb WebUI/` directory to the same path in
`Bodzijun/SBP-Reaper-Scripts`. Preserve every subdirectory and filename.
The `.jsfx` is the only package entry point; its `@provides` includes the
association JSON, EEL SDK, `webui/*`, README, notices and `licenses/*`.
`tools/`, this document and `DEVELOPMENT.md` remain source-repository files and
are not installed by ReaPack. No ZIP needs to be indexed or unpacked by ReaPack.

```text
ReaWhoosh/UltraComb WebUI/
  sbp_ultraComb_webui.jsfx       @version 3.0.0 and @provides
  sbp_ultraComb_webui.json       association, same basename as the JSFX
  reaweb_jsfx.inc               unmodified pinned EEL SDK
  webui/                       all runtime HTML/CSS/MJS/JSON files
  licenses/                    complete third-party license texts
  README.md
  THIRD_PARTY.md
  tools/                       validation and packaging, repository only
  PACKAGING.md                 this document, repository only
  DEVELOPMENT.md               preview notes, repository only
```

The original `ReaWhoosh/sbp_ultraComb.jsfx` remains version 2.40 and is neither
replaced nor included in the new package.

## Local verification

With Node.js 24 from the repository directory:

```powershell
Set-Location 'ReaWhoosh/UltraComb WebUI'
node tools/build-registry.mjs
node tools/package.mjs
Get-ChildItem tools/test*.mjs | ForEach-Object { node $_.FullName; if ($LASTEXITCODE) { throw 'Test failed' } }
```

The package validator checks the file set, every local runtime reference,
case-sensitive path identity, required license inclusion and the pinned SDK
contents. This does not replace the official ReaPack parser or native REAPER
compilation/listening. `parameters.json` must be regenerated after slider/policy
changes; CI refuses a stale registry.

If Ruby/reapack-index is installed, run `reapack-index --check .` at the repository
root. The existing `.github/workflows/reapack.yml` runs the official indexer in
GitHub Actions; the release adds UltraComb validation before that step.

## Publish after review

1. Review the UltraComb folder and the workflow changes. Keep unrelated working
   files out of the release commit. Do not rename the package after publishing.
2. Commit the complete folder and workflow update, then push to `main`.
3. Wait for **ReaPack Indexer** in GitHub Actions to succeed. It generates and
   commits `index.xml`; manual XML editing is not needed for this workflow.
4. Check that category `ReaWhoosh/UltraComb WebUI` contains
   `sbp_ultraComb_webui.jsfx` at version `3.0.0`, with all provided files.
5. Synchronize the SBP repository in ReaPack and install the package in a clean
   REAPER profile to verify the actual installed layout and WebUI association.

Users import the existing repository URL:
https://raw.githubusercontent.com/Bodzijun/SBP-Reaper-Scripts/main/index.xml

ReaWebAPI is a separate user-installed dependency from:
https://raw.githubusercontent.com/zaibuyidao/ReaScripts/master/index.xml
Package name: **ReaWebAPI: Web Runtime for REAPER**, version 0.3.8.31 or newer.
Its extension binaries must not be copied into the UltraComb package. The
required dependency is documented in `@about` and README; it is not automatically
installed by this JSFX package. Restart REAPER after installing the extension.

For each later change, increment `@version`, keep `@changelog` to 1–3 short lines,
regenerate the registry, validate, commit all changed runtime files together and
push. Normal version history is kept by ReaPack's generated index.

## Optional manual ZIP

```powershell
node tools/package.mjs --output 'E:/Codex/releases/UltraComb-3.0.0-stage'
Compress-Archive -LiteralPath 'E:/Codex/releases/UltraComb-3.0.0-stage/Effects','E:/Codex/releases/UltraComb-3.0.0-stage/package-manifest.json' -DestinationPath 'E:/Codex/releases/SBP-UltraComb-3.0.0.zip'
```

Use a new staging directory for each build. The ZIP is for manual installation
and sharing; GitHub/ReaPack uses the source files listed by `@provides`.

## Acceptance status

Automated arithmetic, bulk-edit, serialization, registry and layout checks are
available. The development session confirmed clean FX Feed movement in pre34;
pre35/pre36 added modulation/bulk changes after that listening check.
Before public release, verify the final freshly inserted JSFX in REAPER:
native compilation, audio, both LFOs and matrix cross modulation, Randomize,
stored A/B after project reload, parameter automation, spectrogram recovery
and more than one instance. macOS/Linux host acceptance remains unverified.
Do not use Full recompile/reset with the hosted editor open; that path caused
a hang during development. This source preparation does not publish a release.

Official reference:
https://github.com/cfillion/reapack-index/wiki/Packaging-Documentation
