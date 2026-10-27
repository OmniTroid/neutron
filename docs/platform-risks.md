# Platform risks

Neutron runs x86_64 Wine through Rosetta for Mac apps, which is going away for software like it.

| | Rosetta for Mac apps (Neutron today) | Intel translation in Linux VMs |
|---|---|---|
| macOS 27 | Available | Built into macOS; no Rosetta install |
| macOS 28 and later | Only "certain older, unmaintained games that rely on Intel-based frameworks" ([Apple](https://support.apple.com/en-us/102527)) | Unchanged ([Apple](https://developer.apple.com/documentation/virtualization/running-intel-binaries-in-linux-vms)) |

Valve's stance: on [Proton#10087](https://github.com/ValveSoftware/Proton/pull/10087) (building Proton on macOS
hosts), a Valve member wrote it's "difficult to advocate for any solution that depends on Rosetta 2" given the
phase-out. A reply posted as Apple's Developer Ecosystem Engineering confirmed Linux VM translation is separate from
that deprecation. Expect the same objection to upstreaming Neutron's macOS lsteamclient changes while Neutron
depends on Rosetta for Mac apps.

Ways off Rosetta for Mac apps:

- **Native arm64 Wine with an in-process x86 emulator** (Hangover-style, FEX as the WoW64/ARM64EC translator).
  Keeps DXMT, Metal and the Mac Steam bridge; DXMT already has an `arm64ec` cross file. Preferred for the main path,
  and the version of Neutron Valve could reasonably engage with.
- **ARM64 Linux VM with Valve's Linux Steam and Proton.** Cleanest story for VAC games; plan in
  [vm-gpu.md](vm-gpu.md). Caveats:
  - Linux VM translation covers 64-bit x86 only; whether Valve's Linux client still needs 32-bit x86 decides
    Rosetta versus FEX in the guest.
  - Translation is set up inside the guest (mount the share, register the binfmt handler); a prebuilt image can do it.
  - Virtualization.framework gives Linux guests no 3D acceleration, so graphics need a separate path.
