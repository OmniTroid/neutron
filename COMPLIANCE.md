# Compliance

Neutron is built to comply with the [Steam Subscriber Agreement](https://store.steampowered.com/subscriber_agreement/) (SSA), Apple's [Developer Program License Agreement](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/) (DPLA) and the [macOS license](https://www.apple.com/legal/sla/) (SLA). This is the project's reading of those terms as of 2026-11-02, not legal advice or an endorsement by Valve or Apple.

## Valve

| Term | What Neutron does |
|---|---|
| Personal, non-commercial use through the Steam client (SSA 2.A) | Each user runs Valve's own client with their own account and signs in through it. The agreement names no required operating system. |
| No copying or redistribution of Steam | Neutron ships no Steam files. It fetches `SteamSetup.exe` from Valve's CDN at install time. |
| No modifying or reverse engineering Steam, or emulating Valve's protocols (SSA 2.G) | The client runs unmodified, and speaks to Valve itself. Wine implements Windows, not Valve's protocols. |
| No third-party software controlling Steam's processes or UI, no bots or scripts (SSA 4.B, 4.C) | Neutron acts only through Valve's entry points: `steam://` URLs and `-applaunch`, `-silent`, `-shutdown`. Steam's window stays visible, and Neutron injects nothing. |
| No interfering with anti-cheat (SSA 4.D) | Nothing is patched or bypassed. Neutron's launches pass `-insecure`, Valve's own option, so VAC stays out. |

## Apple

| Term | What Neutron does |
|---|---|
| No decompiling, disassembling, modifying or reverse engineering Apple software (SLA 2.N, DPLA 2.6) | Neutron and our patches do none of this to Apple's software. Neutron ships no D3DMetal. Metal behavior is established by black-box tests of the running API. |
| Outside-App-Store distribution (DPLA 3.2, 5.3, 5.4) | Releases are signed with Developer ID and notarized, with the Wine runtime inside the uploaded bundle. Nothing is hidden from Apple's checks, and Neutron does not present notarization as a security review. |
| No interfering with Apple's security features (DPLA 3.2) | Hardened runtime stays on, with four entitlements Apple documents: `allow-jit`, `allow-unsigned-executable-memory`, `disable-library-validation`, `allow-dyld-environment-variables`. |
| macOS in virtual machines (SLA 2.B(iii)) | Test VMs run on Apple hardware for development and testing, at most two copies per Mac. |

## EU interoperability

Neutron exists to run Windows-only games on macOS, which makes it interoperability software. The EU [Software Directive](https://eur-lex.europa.eu/eli/dir/2009/24/oj) leaves the ideas behind interfaces outside copyright (Art. 1(2)), lets a licensed user observe, study and test a program to learn how it works (Art. 5(3)), and voids contract terms that override this (Art. 8). The Court of Justice confirmed that a program's functionality is not protected by copyright ([SAS Institute, C-406/10](https://curia.europa.eu/juris/liste.jsf?num=C-406/10)). Wine's implementation of the Windows interfaces and Neutron's black-box Metal tests rest on these rules.


Each game has its own license, which is the user's to accept.
