#!/bin/bash
# Regenerates data/compat.json from highball-db at $HIGHBALL_DB_COMMIT (versions.env): the CC0 curated game entries
# and the MIT anti-cheat map, keyed by Steam app ID. The ODbL predictions are not used.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/versions.env"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

curl -fsSL "https://codeload.github.com/gauthierpiarrette/highball-db/tar.gz/$HIGHBALL_DB_COMMIT" | tar -xz -C "$WORK"
SRC=$(echo "$WORK"/highball-db-*)
cp "$SRC/db/anticheat.LICENSE" "$ROOT/licenses/highball-db-anticheat-MIT.txt"

python3 -I - "$SRC" "$HIGHBALL_DB_COMMIT" "$ROOT/data/compat.json" <<'EOF'
import glob, json, sys

src, commit, out = sys.argv[1:]
games = {}
anticheat = json.load(open(f"{src}/db/anticheat.json"))["games"]
for entry in anticheat.values():
    if entry.get("steam_appid"):
        games[str(entry["steam_appid"])] = {
            "title": entry["title"],
            "status": "anticheat-only",
            "anticheat": {"names": entry.get("anticheats", []), "macVerdict": entry.get("macVerdict")},
        }

for path in sorted(glob.glob(f"{src}/db/games/*.json")):
    game = json.load(open(path))
    if not game.get("steam_appid"):
        continue
    notes = (game.get("notes") or "").split(". ")[0].strip()
    games[str(game["steam_appid"])] = {k: v for k, v in {
        "title": game["title"],
        "status": game["status"],
        "renderer": game.get("renderer"),
        "launchArgs": game.get("launchArgs"),
        "anticheat": game.get("anticheat") and {k: game["anticheat"].get(k) for k in ("names", "macVerdict")},
        "nativeMac": (game.get("nativeMac") or {}).get("available") or None,
        "lastVerified": game.get("lastVerified"),
        "summary": notes[:240] + ("." if notes and not notes.endswith(".") else ""),
    }.items() if v not in (None, "", [])}

json.dump({
    "source": f"https://github.com/gauthierpiarrette/highball-db/tree/{commit}",
    "license": "Curated entries CC0-1.0; anti-cheat data MIT (Are We Anti-Cheat Yet?, see licenses/highball-db-anticheat-MIT.txt)",
    "games": games,
}, open(out, "w"), indent=1, sort_keys=True)
print(f"wrote {len(games)} games to {out}")
EOF
