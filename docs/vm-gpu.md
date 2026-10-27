# Plan: GPU for a Linux VM backend

Goal: run Valve's Linux Steam and Proton, unmodified, in an ARM64 Linux VM with playable D3D11 performance, as an
opt-in backend for VAC games and a hedge against Rosetta for Mac apps ([platform-risks.md](platform-risks.md)).

The game's frames go DXVK (D3D11 to Vulkan) → Venus (guest Vulkan over virtio-gpu) → host Vulkan on Metal → a Mac
window. Each hop is its own work item:

| Hop | Today | Needed |
|---|---|---|
| Hypervisor | Virtualization.framework gives Linux guests 2D only; libkrun/krunkit on Hypervisor.framework already does Venus | libkrun, or on macOS 27 Neutron's own virtio-gpu device via [`VZCustomVirtioDevice`](https://developer.apple.com/documentation/virtualization/vzcustomvirtiodevice) with [`VZVirtioSharedMemoryRegion`](https://developer.apple.com/documentation/virtualization/vzvirtiosharedmemoryregion) for host memory in the guest |
| Transport | Venus, copies through shared buffers; virglrenderer gained macOS support in 2026 ([MR 1600](https://gitlab.freedesktop.org/virgl/virglrenderer/-/merge_requests/1600)) | Blob resources mapped into guest memory, no per-frame copies |
| Host Vulkan | MoltenVK: no geometry shaders or transform feedback, which DXVK requires for D3D11 | [KosmicKrisp](https://www.lunarg.com/kosmickrisp-achieves-vulkan-1-4-conformance-on-apple-silicon/) (Vulkan 1.4 conformant, 2026-09-29) once geometry shaders ([!44786](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/44786)) and transform feedback ([!44928](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/44928)) land |
| Presentation | krunkit has no display | Guest windows over virtio-gpu cross-domain into an NSWindow with a Metal layer, zero-copy via IOSurface; mostly new code |
| x86 | Linux VM translation, 64-bit only | Same, or FEX in the guest if Steam still needs 32-bit x86 |

D3D12 (vkd3d-proton) needs more Vulkan features still and comes after D3D11.

Prior art: [steamac](https://github.com/fxgl/steamac) runs SteamOS under libkrun with Venus on a patched KosmicKrisp
and reports roughly 60% more frame rate than on MoltenVK; it also forwards DXMT calls to a host Metal executor at
about 3x DXVK over Venus, at the cost of letting guest programs run code on the host. Self-reported numbers.

## Phase 0: measure (days)

1. Podman with the krunkit provider (Venus and MoltenVK), an ARM64 Fedora guest; then steamac's patched KosmicKrisp.
2. `vulkaninfo` and `vkcube`: which features and extensions reach the guest.
3. A DXVK sample, then TF2 through Proton: what fails, frame rate.
4. The same on Neutron's DXMT path as the baseline.

Output: a feature gap list and a performance ratio. Continue only if the gaps are concrete and the ratio is
plausible for the games that need VAC.

## Phase 1: correctness

Track KosmicKrisp's geometry shader and transform feedback work, rerun the matrix.

## Phase 2: presentation and speed

Cross-domain presentation into a Neutron window, blob memory, then profile against the DXMT baseline. On macOS 27,
decide between libkrun and a `VZCustomVirtioDevice` GPU inside Virtualization.framework, which also gets Apple's
built-in x86 translation.

Dependencies Neutron doesn't control: libkrun, krunkit, virglrenderer (Venus), Mesa/KosmicKrisp, MoltenVK.
