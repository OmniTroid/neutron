# Windows Steam for VAC games

Status: implemented, blocked on rendering, VAC untested. `neutron windows-steam start|status|install|launch|stop`
runs Valve's unmodified Windows client with its window shown and talks to it only through Valve's entry points:
`steam://` URLs and `-applaunch`/`-silent`/`-shutdown`, which a second `steam.exe` forwards to the running client.
State comes from the registry values the client writes (`ActiveProcess\ActiveUser`, `AutoLoginUser`,
`RunningAppID`). This is how Highball does it, and stays within the
[Steam Subscriber Agreement](https://store.steampowered.com/subscriber_agreement/) section 4.B, which an earlier
headless proof of concept driving the client over Chromium DevTools did not (removed).

Blocker: Steam's window is black on upstream and staging Wine (Chromium needs cross-process swap chains:
[dxmt#166](https://github.com/3Shain/dxmt/pull/166), [wine!11058](https://gitlab.winehq.org/wine/wine/-/merge_requests/11058)).
Highball's renders on CrossOver-derived Wine with `-cef-disable-gpu`. `NEUTRON_STEAM_WINE` points Neutron at another
Wine to test with.

## Idea

For VAC games only, Neutron runs Valve's own Windows Steam client, unmodified and minimized, in a shared Wine
prefix, and launches the game through it. That client loads VAC exactly as it does on Windows; nothing is faked
or bypassed. All other games keep using the lsteamclient bridge to Mac Steam.

## Why it might work

- Proton's VAC support comes from Valve; under plain Wine nobody has shown VAC initializing ("VAC secured"), and
  Valve has published no position on Wine or CrossOver. CodeWeavers rates CS2 "Runs Well" on CrossOver 26.3.0,
  but that rating covers gameplay, not VAC. ([community findings](https://github.com/piwas-21/cs2-apple-silicon/blob/main/research/steam-vac-findings.md),
  [CodeWeavers](https://www.codeweavers.com/unleash/counter-strike-2-on-mac))
- highball-db reports Counter-Strike 2 playing online under Highball's Windows Steam (unverified here).
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
