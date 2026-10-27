# Draft: VAC through a background Windows Steam client

Status: paused. The headless proof of concept below works, but controlling the client through DevTools conflicts
with the [Steam Subscriber Agreement](https://store.steampowered.com/subscriber_agreement/) (2026-09-10), section 4.B:
no unauthorized third-party software "in interacting with or controlling the processes or user interface of Steam".
A conforming version runs the unmodified client with its window shown and drives it only through Valve's entry
points (`steam://` URLs, `-applaunch`, `-silent`), as Highball does; that needs Steam's UI to render, which on
upstream Wine waits on DXMT's cross-process swap chains ([dxmt#166](https://github.com/3Shain/dxmt/pull/166),
[wine!11058](https://gitlab.winehq.org/wine/wine/-/merge_requests/11058)). VAC itself is still untested.

## Proof of concept (`neutron windows-steam start|login|launch|stop`)

- Steam's window can't be presented under Wine on macOS (Chromium's GPU path needs cross-process swap chains,
  which DXMT doesn't support yet; the software path never reaches the window). Its UI runs fine though.
- The prefix uses Wine's null display driver, seeded before the prefix exists: no window appears at any point,
  including Wine's own setup. A fresh install reaches the login screen in about a minute.
- Neutron drives the client over Chromium DevTools (`-cef-enable-debugging -devtools-port <random free port>`,
  loopback only, recorded in the prefix for later commands): sign-in state
  from `g_PopupManager`, login by reading the QR image from the hidden login page, shutdown and launch through
  `SteamClient`. Chromium's sandbox stays on.
- Runtime is wine-staging 11.18; Steam still crashes now and then while updating itself, so `start` relaunches it.
- Open: the DevTools port is unauthenticated (plan: use it only for the one-time QR login, then
  drop the marker and use `-applaunch`, `steam://install` and the `ActiveUser`/`RunningAppID` registry values);
  install and launch need a signed-in account to test; prompts Steam shows (Steam Guard, EULAs) must be relayed.

## Idea

For VAC games only, Neutron runs Valve's own Windows Steam client, unmodified and minimized, in a shared Wine
prefix, and launches the game through it. That client loads VAC exactly as it does on Windows; nothing is faked
or bypassed. All other games keep using the lsteamclient bridge to Mac Steam.

## Why it might work

- Proton's VAC support comes from Valve; under plain Wine nobody has shown VAC initializing ("VAC secured"), and
  Valve has published no position on Wine or CrossOver. CodeWeavers rates CS2 "Runs Well" on CrossOver 26.3.0,
  but that rating covers gameplay, not VAC. ([community findings](https://github.com/piwas-21/cs2-apple-silicon/blob/main/research/steam-vac-findings.md),
  [CodeWeavers](https://www.codeweavers.com/unleash/counter-strike-2-on-mac))
- CrossOver's Wine source is LGPL and public (codeweavers.com/crossover/source); it carries the fixes that keep
  Steam's Chromium UI (steamwebhelper) working on macOS, which upstream Wine lacks.

## Design

| Piece | Plan |
|---|---|
| Runtime | Build from CrossOver's Wine source; likely also replaces `patches/winemac-dxmt.patch`, since CrossOver exports `macdrv_functions` |
| Prefix | One shared `prefixes/steam`; `SteamSetup.exe /S` on first use |
| Client | `steam.exe -silent -cef-disable-gpu`, started on demand, kept in the tray, quit when the last VAC game exits |
| Login | Interactive once in the Windows client (Steam Guard there); remembered afterwards |
| Library | Register a Neutron-owned folder as a Steam library: `steamapps/common/<installdir>` links to `library/<appid>`, plus an `appmanifest_<appid>.acf` from appinfo (buildid, installed depots) so the client adopts files DepotDownloader already fetched |
| Launch | `steam.exe -applaunch <appid>`; track the session through `HKCU\Software\Valve\Steam\RunningAppID` |
| Bridge | Not used for these games; the prefix keeps Valve's real `steamclient64.dll` |
| UI | Steam's cache marks VAC games; the app shows a "VAC" badge and an opt-in "Play with VAC (Windows Steam)" mode with a plain warning that it's unofficial |

Side benefit: the Windows client does Steam Cloud's pre-launch download and launch records itself, so these games
avoid the conflicts the bridge path causes.

## Experiment (decides whether to build any of this)

Use a secondary Steam account with no inventory.

1. Fresh prefix on the current runtime; `wine SteamSetup.exe /S`. If steamwebhelper fails, rebuild the runtime from
   CrossOver source and retry.
2. Start `steam.exe -cef-disable-gpu`, log in, install TF2 through the Windows client.
3. Launch TF2 with `-condebug`, join a Valve casual server, run `status`.

Success: no "insecure mode" line in `tf/console.log`, the server connection holds, and `status` reports a secure
server. Repeat with CS2 for a game with stricter integrity checks (`signaturescheckedonlaunch`).

## Open questions

- Does VAC initialize under Wine and Rosetta at all, and does it stay connected?
- Does the Windows client accept a library populated by DepotDownloader, or re-download and re-verify?
- How do Mac Steam and the Windows client coexist on one account (presence, "playing on another device")?
- How often do Steam client updates break it under Wine?
- Ban risk: unofficial and unverified; the opt-in warning has to say so.
