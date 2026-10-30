# Steam under Neutron

Neutron runs Valve's Windows Steam client, unmodified and with its window shown, in one Wine prefix
(`~/Library/Application Support/Neutron/steam`). Steam signs in, installs, updates, syncs Steam Cloud and launches
every game itself. Neutron uses only Valve's entry points: `steam://` URLs and `-applaunch`/`-silent`/`-shutdown`,
which a second `steam.exe` forwards to the running client. It reads state from files and registry values the client
writes (`appinfo.vdf`, `appmanifest_*.acf`, `ActiveProcess\ActiveUser`, `RunningAppID`). This follows Highball and
the [Steam Subscriber Agreement](https://store.steampowered.com/subscriber_agreement/) section 4.B, which rules out
third-party software "interacting with or controlling the processes or user interface of Steam".

Steam's browser UI draws from a GPU process into a window its UI process owns. That needs cross-process swap
chains in Wine's `winemac.drv` and in DXMT, the latter enabled with `DXMT_ALLOW_CROSS_PROCESS_SWAPCHAIN=1`.

## VAC

Unverified. Neutron launches every game with `-insecure` (Source games then skip VAC and secured servers), but a
game started from Steam's own window doesn't get it. VAC runs in user mode inside the client and the game, so Valve's real client is the setup where it could
work, but nobody has shown it accepting Wine on macOS. highball-db's own Counter-Strike 2 and Team Fortress 2 entries
record bot matches and main menus only.

Test with a secondary account: an official Counter-Strike 2 Casual match (official matchmaking refuses sessions VAC
can't verify), then Team Fortress 2 Casual with `status` showing a secure server.
