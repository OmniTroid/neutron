# Third-party notices

Neutron is not affiliated with, endorsed by, or sponsored by Valve Corporation. Steam and the Steam logo are
trademarks of Valve Corporation. Game names and artwork shown in the app come from the user's own Steam client cache.

Neutron's own code is under the BSD 3-Clause License in `LICENSE`. Full license texts referenced below are in
`licenses/` (in the app: `Neutron.app/Contents/Resources/licenses`).

## Modified components

| Component | License | Source |
|---|---|---|
| Wine 11.18 `winemac.drv` (`patches/winemac-dxmt.patch`) | LGPL-2.1-or-later (`Wine-LGPL-2.1.txt`) | <https://dl.winehq.org/wine/source/11.x/wine-11.18.tar.xz> plus the patch in this repository |
| Proton `lsteamclient` (`patches/lsteamclient-macos.patch`) | Steamworks SDK License, Copyright Valve Corporation (`lsteamclient-Steamworks-SDK.txt`) | <https://github.com/ValveSoftware/Proton> at the commit in `versions.env`, plus the patch in this repository |
| Proton `steam_helper` (`steam.exe`) | BSD-3-Clause, Copyright (c) 2015-2022 Valve Corporation (`Proton-BSD-3-Clause.txt`) | same as above, unmodified |

## Bundled in Neutron.app

| Component | License | Source |
|---|---|---|
| Wine 11.18 (macOS build by Gcenx) | LGPL-2.1-or-later (`Wine-LGPL-2.1.txt`) | <https://github.com/Gcenx/macOS_Wine_builds/releases/tag/11.18>, <https://gitlab.winehq.org/wine/wine> |
| wine-mono 11.3.0 | MIT and others (`SPDX-MIT.txt`, see upstream) | <https://gitlab.winehq.org/mono/wine-mono> |
| wine-gecko 2.47.4 | MPL-2.0 (`SPDX-MPL-2.0.txt`) | <https://gitlab.winehq.org/wine/wine-gecko> |
| DXMT v0.80 | MIT, Copyright (c) 2023 Feifan He (`DXMT-MIT.txt`) | <https://github.com/3Shain/dxmt/releases/tag/v0.80> |
| MoltenVK | Apache-2.0 (`MoltenVK-Apache-2.0.txt`) | <https://github.com/KhronosGroup/MoltenVK> |
| Vulkan Loader | Apache-2.0 (`SPDX-Apache-2.0.txt`) | <https://github.com/KhronosGroup/Vulkan-Loader> |
| Sparkle 2.10.0 | MIT (`Sparkle-MIT.txt`) | <https://github.com/sparkle-project/Sparkle> |
| swift-argument-parser 1.5.0 | Apache-2.0 with Runtime Library Exception (`swift-argument-parser-Apache-2.0.txt`) | <https://github.com/apple/swift-argument-parser> |

### Support libraries in the Wine build (built by MacPorts)

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
| DepotDownloader 3.4.0 | GPL-2.0 | <https://github.com/SteamRE/DepotDownloader> |
