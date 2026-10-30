# Third-party notices

Neutron is not affiliated with, endorsed by, or sponsored by Valve Corporation. Steam and the Steam logo are
trademarks of Valve Corporation. Game names and artwork shown in the app come from the user's own Steam client cache.

Neutron's own code is under the BSD 3-Clause License in `LICENSE`. Full license texts referenced below are in
`licenses/` (in the app: `Neutron.app/Contents/Resources/licenses`).

## Modified components

| Component | License | Source |
|---|---|---|
| Wine from CrossOver 26.3.0 sources | LGPL-2.1-or-later (`Wine-LGPL-2.1.txt`) | <https://github.com/OmniTroid/wine> at the commit pinned by the `external/wine` submodule; base: <https://media.codeweavers.com/pub/crossover/source/crossover-sources-26.3.0.tar.gz> |
| DXMT | MIT, Copyright (c) 2023 Feifan He (`DXMT-MIT.txt`) | <https://github.com/OmniTroid/dxmt> at the commit pinned by the `external/dxmt` submodule; upstream <https://github.com/3Shain/dxmt> |

## Bundled in Neutron.app

| Component | License | Source |
|---|---|---|
| wine-mono 10.4.1 | MIT and others (`SPDX-MIT.txt`, see upstream) | <https://gitlab.winehq.org/mono/wine-mono> |
| wine-gecko 2.47.4 | MPL-2.0 (`SPDX-MPL-2.0.txt`) | <https://gitlab.winehq.org/wine/wine-gecko> |
| LLVM 15.0.7, linked into DXMT's `winemetal.so` | Apache-2.0 WITH LLVM-exception (`LLVM-Apache-2.0-with-LLVM-exception.txt`) | <https://github.com/llvm/llvm-project/tree/llvmorg-15.0.7> |
| MoltenVK | Apache-2.0 (`MoltenVK-Apache-2.0.txt`) | <https://github.com/KhronosGroup/MoltenVK> |
| Vulkan Loader | Apache-2.0 (`SPDX-Apache-2.0.txt`) | <https://github.com/KhronosGroup/Vulkan-Loader> |
| Sparkle 2.10.0 | MIT (`Sparkle-MIT.txt`) | <https://github.com/sparkle-project/Sparkle> |
| highball-db game entries (`data/compat.json`) | CC0-1.0 | <https://github.com/gauthierpiarrette/highball-db> |
| Are We Anti-Cheat Yet? data, via highball-db (`data/compat.json`) | MIT, Copyright (c) 2021 Starz0r, Curve (`highball-db-anticheat-MIT.txt`) | <https://github.com/AreWeAntiCheatYet/AreWeAntiCheatYet> |
| swift-argument-parser 1.5.0 | Apache-2.0 with Runtime Library Exception (`swift-argument-parser-Apache-2.0.txt`) | <https://github.com/apple/swift-argument-parser> |

### Support libraries for Wine (from Gcenx's Wine 11.18 build, built by MacPorts)

| Library | License |
|---|---|
| Brotli | MIT |
| bzip2 | bzip2-1.0.6 |
| FreeType | FTL |
| GMP | LGPL-3.0-or-later or GPL-2.0-or-later |
| GnuTLS | LGPL-2.1-or-later |
| ICU 76 | Unicode-3.0 |
| libffi | MIT |
| libiconv, libcharset | LGPL-2.1-or-later |
| libidn2 | LGPL-3.0-or-later or GPL-2.0-or-later |
| libinotify-kqueue | MIT |
| libpcap | BSD-3-Clause |
| libpng 1.6 | libpng-2.0 |
| libtasn1 | LGPL-2.1-or-later |
| libunistring | LGPL-3.0-or-later or GPL-2.0-or-later |
| libxml2, libxslt, libexslt | MIT |
| LZ4 | BSD-2-Clause |
| MacPorts legacy-support | see <https://github.com/macports/macports-legacy-support> |
| p11-kit | BSD-3-Clause |
| SDL 2 | Zlib |
| XZ Utils (liblzma) | 0BSD |
| zlib | Zlib |
| Zstandard | BSD-3-Clause |

Copyright in each library belongs to its respective authors. Corresponding source for the LGPL components is
available from the upstream projects above and the MacPorts ports they were built from
(<https://github.com/macports/macports-ports>); on request, the maintainer of Neutron will provide it directly.

## Downloaded at runtime, not bundled

| Component | License | Source |
|---|---|---|
| Steam for Windows (`SteamSetup.exe`), installed unmodified into Neutron's Wine prefix | Steam Subscriber Agreement, Copyright Valve Corporation | <https://store.steampowered.com/about/> |
