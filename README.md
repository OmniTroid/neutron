# Neutron

Proton-style runner for Windows Steam games on Apple Silicon macOS: Wine 11 under Rosetta, DXMT for D3D10/11, and Proton's lsteamclient bridged to the native Mac Steam client.

```sh
scripts/build.sh && swift build -c release
.build/release/neutron install <appid> --user <steam-user>
.build/release/neutron run --appid <appid>
```

`build.sh` produces `dist/` (one Wine runtime per graphics backend plus the Steam bridge); the `neutron` CLI and the `NeutronKit` engine it shares with the app are a Swift package. `install` downloads the Windows build with DepotDownloader into `~/Library/Application Support/Neutron/library`; `run` launches it through Proton's `steam.exe` with the Mac Steam client running.
