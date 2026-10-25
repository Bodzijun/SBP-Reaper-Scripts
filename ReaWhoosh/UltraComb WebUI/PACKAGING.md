# UltraComb 3 — release and ReaPack packaging

## Runtime layout, version 3.13.2

ReaPack installs exactly four files, at the existing package path:

```text
sbp_ultraComb_webui.jsfx   package entry point; existing project identity
sbp_ultraComb_webui.json   WebUI association; entry = webui/packed.html
reaweb_jsfx.jsfx-inc      byte-identical pinned EEL SDK, renamed for FX-list exclusion
webui/packed.html               self-contained UI, registry, editable sources and full licenses
```

The original `../sbp_ultraComb.jsfx` remains version 2.40. The new package keeps
its existing JSFX filename/path. No ZIP/7z decoding, CDN or network dependency is
introduced. ReaWebAPI is installed separately, as before.

## Source repository and build

Upload the complete source folder to `ReaWhoosh/UltraComb WebUI` in the existing
repository. Keep `webui/`, `licenses/`, README, THIRD_PARTY, tools and development
notes in Git; these are source/build inputs, not separately installed assets.
The main JSFX `@provides` names only the three companion runtime files above.
The generated `webui/packed.html` must be committed alongside changed sources.

```powershell
node tools/build-registry.mjs
node tools/build-webui.mjs
node tools/package.mjs
Get-ChildItem tools/test*.mjs | ForEach-Object { node $_.FullName; if ($LASTEXITCODE) { throw 'Test failed' } }
```

The bundler preserves module scopes/names, does not minify or evaluate strings,
and rejects unsupported imports/exports or cycles. Complete original module
sources are stored in the HTML's `ultracomb-sources` JSON block. The original
registry is embedded separately. LICENSES in the footer opens all notices.
The EEL SDK file is renamed only; its pinned contents remain unchanged.

CI checks the registry and deterministic HTML, package layout, SDK hashes and
tests before running the official ReaPack indexer. If Ruby/reapack-index is
available locally, also run `reapack-index --check .` at the repository root.

## Update existing installations

Back up the installed folder first. Copy the four new files, then remove only
obsolete assets known to belong to an earlier package. In this development
installation the cleanup verifies every old file against the previous manifest
before removing it. It retains both main JSFX paths, so existing projects keep
their effect identity. Never delete an entire Effects folder or the FX cache.
ReaPack updates track removed provided files through the package manifest;
verify the actual upgrade in a clean profile before publication.

Close/reopen WebUI after installing, then refresh the FX browser with F5. Entries
already cached by REAPER can persist until rescan. Two installed copies still
produce two real UltraComb entries; removing either copy requires checking which
path existing projects use.

## Stage / publish

```powershell
node tools/package.mjs --output 'E:/Codex/releases/UltraComb-3.13.2-stage'
```

Use a new staging directory each time. Manual ZIP distribution may contain that
stage's Effects folder; ReaPack uses the ordinary four files in `@provides`.
Review and commit the complete source/build output, then push only when authorized.
GitHub Actions generates `index.xml`; local preparation is not publication.

Repository: https://raw.githubusercontent.com/Bodzijun/SBP-Reaper-Scripts/main/index.xml
Runtime: https://raw.githubusercontent.com/zaibuyidao/ReaScripts/master/index.xml
ReaWebAPI: Web Runtime for REAPER, 0.3.8.31 or newer, installed separately.
Native compilation, hosted inline-script policy, audio and actual clean-profile
ReaPack upgrade/FX-browser acceptance require REAPER testing.
