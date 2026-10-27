# Plan: GPU for a Linux VM backend

Goal: run Valve's Linux Steam and Proton, unmodified, in an ARM64 Linux VM with playable D3D11 performance, as an
opt-in backend for VAC games and a hedge against Rosetta for Mac apps ([platform-risks.md](platform-risks.md)).

The game's frames go DXVK (D3D11 to Vulkan) → Venus (guest Vulkan over virtio-gpu) → host Vulkan on Metal → a Mac
window. Each hop is its own work item:

| Hop | Today | Needed |
|---|---|---|
| Hypervisor | Virtualization.framework: 2D only for Linux guests | libkrun/krunkit on Hypervisor.framework, which already does Venus |
| Transport | Venus, copies through shared buffers | Blob resources mapped into guest memory, no per-frame copies |
| Host Vulkan | MoltenVK: no geometry shaders or transform feedback, which DXVK requires for D3D11 | KosmicKrisp (Mesa's Vulkan on Metal, aiming at conformance) or emulation of both |
| Presentation | krunkit has no display | Guest windows over virtio-gpu cross-domain into an NSWindow with a Metal layer, zero-copy via IOSurface; mostly new code |
| x86 | Linux VM translation, 64-bit only | Same, or FEX in the guest if Steam still needs 32-bit x86 |

D3D12 (vkd3d-proton) needs more Vulkan features still and comes after D3D11.

## Phase 0: measure (days)

1. Podman with the krunkit provider (Venus and MoltenVK), an ARM64 Fedora guest.
2. `vulkaninfo` and `vkcube`: which features and extensions reach the guest.
3. A DXVK sample, then TF2 through Proton: what fails, frame rate.
4. The same on Neutron's DXMT path as the baseline.

Output: a feature gap list and a performance ratio. Continue only if the gaps are concrete and the ratio is
plausible for the games that need VAC.

## Phase 1: correctness

Swap the host Vulkan for KosmicKrisp (or add geometry shader and transform feedback emulation), rerun the matrix.

## Phase 2: presentation and speed

Cross-domain presentation into a Neutron window, blob memory, then profile against the DXMT baseline.

Dependencies Neutron doesn't control: libkrun, krunkit, virglrenderer (Venus), Mesa/KosmicKrisp, MoltenVK.
