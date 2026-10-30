# Neutron

A macOS frontend for Valve's Windows Steam client, running unmodified under CrossOver's Wine ([OmniTroid/wine](https://github.com/OmniTroid/wine)) with DXMT ([OmniTroid/dxmt](https://github.com/OmniTroid/dxmt)) for Direct3D 10/11. Steam installs, updates and launches the games; Neutron only uses Steam's own command-line options and `steam://` URLs, as [Highball](https://github.com/gauthierpiarrette/highball) does.

```sh
git submodule update --init --recursive
scripts/build.sh && swift build -c release
.build/release/neutron start
.build/release/neutron launch <appid>
scripts/bundle-app.sh && open build/Neutron.app
```

`bundle-app.sh` embeds `dist/` and the CLI (`Contents/Helpers/neutron`), signs with the `Developer ID Application` certificate of `$NEUTRON_TEAM_ID` when present (ad-hoc otherwise), notarizes when the notarytool keychain profile `$NEUTRON_NOTARY_PROFILE` (default `neutron`) exists, and writes `build/Neutron.dmg`.

```sh
scripts/release.sh 0.2
```

Publishes a notarized build: the DMG to release `v0.2`, and the Sparkle archive, deltas and `appcast.xml` to the rolling `updates` release the app checks. Update archives are signed with the EdDSA key that `generate_keys` keeps in the login keychain.

`build.sh` builds the `external/` submodules into `dist/`; `WINE_SRC` and `DXMT_SRC` override either with a local checkout, a ref of its remote, or `<git URL>#<ref>` (Wine and the DXMT overlay; the first run also builds LLVM 15 for DXMT, about an hour). `neutron compat <appid>` shows a game's entry in `data/compat.json`, generated from [highball-db](https://github.com/gauthierpiarrette/highball-db) by `scripts/update-compat-db.sh`; blocked titles need `install --force`.
