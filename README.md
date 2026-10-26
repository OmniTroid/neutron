# Neutron

Proton-style runner for Windows Steam games on Apple Silicon macOS: Wine 11 under Rosetta, DXMT for D3D10/11, and Proton's lsteamclient bridged to the native Mac Steam client.

```sh
scripts/build.sh && swift build -c release
.build/release/neutron install <appid> --user <steam-user>
.build/release/neutron run --appid <appid>
scripts/bundle-app.sh && open build/Neutron.app
```

`bundle-app.sh` embeds `dist/` and the CLI (`Contents/Helpers/neutron`), signs with the `Developer ID Application` certificate of `$NEUTRON_TEAM_ID` when present (ad-hoc otherwise), notarizes when the notarytool keychain profile `$NEUTRON_NOTARY_PROFILE` (default `neutron`) exists, and writes `build/Neutron.dmg`.

`build.sh` produces `dist/` (the Wine runtime, per-backend overlays and the Steam bridge); the `neutron` CLI and the `NeutronKit` engine it shares with the app are a Swift package. `install` downloads the Windows build with DepotDownloader into `~/Library/Application Support/Neutron/library`; `run` launches it through Proton's `steam.exe` with the Mac Steam client running. `Neutron.app` does the same from a library of your owned Windows games.
