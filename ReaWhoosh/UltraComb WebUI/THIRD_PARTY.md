# Third-party components

## ReaWebAPI SDK — LGPL-3.0-or-later

Copyright (C) 2026 zaibuyidao.

The following unmodified SDK source contents are included:
- `reaweb_jsfx.jsfx-inc` (renamed to hide it from the FX list) from `runtime/jsfx/reaweb_jsfx.inc`
- `webui/jsfx-webui.mjs` (embedded editable source in `webui/packed.html`) from `runtime/jsfx-webui.mjs`

Pinned release: **v0.3.9.10**, commit
`fe1bafea26595f705f595699cae33a432d74e1d4`.

Upstream source:
https://github.com/zaibuyidao/ReaWebAPI/tree/fe1bafea26595f705f595699cae33a432d74e1d4

Verified Git blob IDs:
- EEL include: `37e0ba61957b9c6f9ea5fedfcd0158c3b068524b`
- JavaScript helper: `098bc2d445554d913d44517f0d06b6c9d1d33fc2`

The SDK and examples use LGPL-3.0-or-later according to that revision's
[LICENSE.md](licenses/ReaWebAPI-LICENSE.md). The full terms are provided in
[licenses/COPYING.LESSER](licenses/COPYING.LESSER) and the incorporated
[licenses/COPYING](licenses/COPYING).
Full license texts and editable WebUI sources are embedded in `webui/packed.html`.
The JS helper retains its unmodified source in the `ultracomb-sources` JSON
block and is scope-bundled without minification for execution. The matching
source project and build tools are available from the pinned package repository.
Editable SDK sources are included in the package; the native ReaWebAPI extension
and browser runtime binaries are installed separately and are not redistributed
by this package.

## Saike WSOLA library — MIT

The main JSFX retains Joep Vanlier's WSOLA library and original notice:
Copyright (c) 2020, 2022 Joep Vanlier.
A duplicate of the complete notice is in [licenses/Saike-MIT.txt](licenses/Saike-MIT.txt).

## Spectral pitch processing — Wide Open License

The main JSFX retains the Stephan M. Bernsee attribution and Wide Open License:
Copyright 1999-2009 Stephan M. Bernsee.
A duplicate of the complete notice is in [licenses/Bernsee-WOL.txt](licenses/Bernsee-WOL.txt).

These notices describe the respective third-party components; this packaging
change does not replace existing notices or relicense unrelated source code.
