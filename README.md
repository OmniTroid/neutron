# Neutron

Proton-style runner for Windows Steam games on Apple Silicon macOS: Wine 11 under Rosetta, DXMT for D3D10/11, and Proton's lsteamclient bridged to the native Mac Steam client.

```sh
scripts/build.sh
./neutron run --appid <appid> path/to/Game.exe
```

`build.sh` produces `dist/` (one Wine runtime per graphics backend plus the Steam bridge). `run` prepares a per-app prefix and launches the game through Proton's `steam.exe` with the Mac Steam client running.
