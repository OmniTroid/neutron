# Platform risks

Neutron runs x86_64 Wine through Rosetta for Mac apps. Apple's [Linux VM translation docs](https://developer.apple.com/documentation/virtualization/running-intel-binaries-in-linux-vms)
show the two translation paths diverging:

| | Rosetta for Mac apps (Neutron today) | Intel translation in Linux VMs |
|---|---|---|
| macOS 27 | Available | Built into macOS; no Rosetta install |
| After macOS 27 | Only a subset aimed at older games (WWDC25; verify the exact scope) | Unchanged |

Ways off Rosetta for Mac apps:

- **Native arm64 Wine with an in-process x86 emulator** (Hangover-style, FEX as the WoW64/ARM64EC translator).
  Keeps DXMT, Metal and the Mac Steam bridge; DXMT already has an `arm64ec` cross file. Preferred for the main path.
- **ARM64 Linux VM with Valve's Linux Steam and Proton.** Cleanest story for VAC games, but:
  - Linux VM translation covers 64-bit x86 only; whether Valve's Linux client still needs 32-bit x86 decides
    Rosetta versus FEX in the guest.
  - Translation is set up inside the guest (mount the share, register the binfmt handler); a prebuilt image can do it.
  - Virtualization.framework gives Linux guests no 3D acceleration, so graphics need a separate path.
