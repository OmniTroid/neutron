# Platform risks

Neutron runs x86_64 Wine through Rosetta for Mac apps, which is going away for software like it.

| | Rosetta for Mac apps (Neutron today) | Intel translation in Linux VMs |
|---|---|---|
| macOS 27 | Available | Built into macOS; no Rosetta install |
| macOS 28 and later | Only "certain older, unmaintained games that rely on Intel-based frameworks" ([Apple](https://support.apple.com/en-us/102527)) | Unchanged ([Apple](https://developer.apple.com/documentation/virtualization/running-intel-binaries-in-linux-vms)) |

Valve's stance: on [Proton#10087](https://github.com/ValveSoftware/Proton/pull/10087) (building Proton on macOS
hosts), a Valve member wrote it's "difficult to advocate for any solution that depends on Rosetta 2" given the
phase-out. A reply posted as Apple's Developer Ecosystem Engineering confirmed Linux VM translation is separate from
that deprecation. Expect the same objection to anything Neutron asks of Valve while it depends on Rosetta for Mac
apps.

Ways off Rosetta for Mac apps:

- **Native arm64 Wine with an in-process x86 emulator** (FEX as the WoW64/ARM64EC translator). Keeps DXMT and Metal,
  and is the version of Neutron Valve could reasonably engage with. Preferred for the main
  path. It exists:
  - CodeWeavers ships it in [CrossOver Preview](https://www.codeweavers.com/blog/mjohnson/2026/7/31/crossover-preview-the-right-to-bear-arm64-on-mac)
    (2026-07-31) with a custom macOS port of FEX and arm64 DXMT; CrossOver 27 is targeted for early 2027.
  - macOS 26.5 added what it needs: an x18 custom ABI mode, 4K-page processes, a resizable PAGEZERO and per-thread
    hardware TSO (`thread_set_x86_64_compat()`), all behind the restricted entitlement
    `com.apple.developer.cross-architecture-support` with a provisioning profile
    ([wine-devel, 2026-08-07](https://list.winehq.org/hyperkitty/list/wine-devel@list.winehq.org/thread/CKG5CEN2BE5VRXZ7O7NX4YUSBH3247WH/)).
    Whether Apple grants it to a distributed third-party app is undocumented; that decides whether Neutron can ship it.
  - Upstream Wine has only preparatory macOS arm64 changes; upstream FEX has
    ["no plans for MacOS support"](https://github.com/FEX-Emu/FEX/issues/5046), so Neutron would carry Wine and FEX
    patches (or [FEX-darwin](https://github.com/dbc-hbin/FEX-darwin)) until CodeWeavers' work lands upstream.
- **ARM64 Linux VM with Valve's Linux Steam and Proton.** Cleanest story for VAC games; plan in
  [vm-gpu.md](vm-gpu.md). Caveats:
  - Linux VM translation covers 64-bit x86 only; whether Valve's Linux client still needs 32-bit x86 decides
    Rosetta versus FEX in the guest.
  - Translation is set up inside the guest (mount the share, register the binfmt handler); a prebuilt image can do it.
  - Virtualization.framework gives Linux guests no 3D acceleration, so graphics need a separate path.
