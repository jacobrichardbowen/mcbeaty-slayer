#!/bin/bash
# Four copies of the game (a host and three friends, all played by the bot
# AI) fight online over this machine for a minute, then each says where it
# sees every soldier at the same moment. This compares the four views.
#   GODOT=/path/to/godot tools/net_soak.sh [seconds] [address friends join]
set -e
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
LOGS=$(mktemp -d)
DEADLINE=$(python3 -c "import time; print(time.time() + ${1:-70})")
"$GODOT" --headless --path . -s tests/net_soak_test.gd -- host Host "$DEADLINE" > "$LOGS/Host.log" 2>&1 &
sleep 1
for who in Anna Boris Clara; do
	"$GODOT" --headless --path . -s tests/net_soak_test.gd -- join "$who" "$DEADLINE" "${2:-127.0.0.1}" > "$LOGS/$who.log" 2>&1 &
	sleep 0.5
done
wait
grep -h -A4 "SCRIPT ERROR" "$LOGS"/*.log && { echo "NET SOAK FAILED: script errors (logs in $LOGS)"; exit 1; }
python3 - "$LOGS" <<'PY'
import glob, json, math, sys
views = {}
for f in glob.glob(sys.argv[1] + "/*.log"):
    for line in open(f):
        if line.startswith("VIEW "):
            _, who, js = line.split(" ", 2)
            views[who] = json.loads(js)
if len(views) != 4:
    sys.exit("NET SOAK FAILED: only %s reported" % ", ".join(sorted(views)))
by_peer = {v["me"]: w for w, v in views.items()}
gaps = {"host -> friend": [], "friend -> host": [], "friend -> friend": []}
problems = []
for i, row in views["Host"]["soldiers"].items():
    owner = by_peer.get(row[4], "Host")  # whoever plays a soldier knows where it is
    truth = views[owner]["soldiers"][i]
    for who, v in views.items():
        seen = v["soldiers"][i]
        if who == owner:
            continue
        if seen[3] != truth[3]:
            # Only a death or respawn still on its way explains a disagreement.
            recent = [d for d in (views[owner]["deaths"].get(i), v["deaths"].get(i)) if d]
            if not recent or min(abs(max(recent) - v["at"]), abs(max(recent) - views[owner]["at"])) > 0.5:
                problems.append("%s sees soldier %s %s, %s says %s" % (who, i, "alive" if seen[3] else "dead", owner, "alive" if truth[3] else "dead"))
        elif truth[3]:
            path = "host -> friend" if owner == "Host" else ("friend -> host" if who == "Host" else "friend -> friend")
            gaps[path].append(math.dist(truth[:3], seen[:3]))
for path, d in gaps.items():
    if d:
        d.sort()
        print("%-16s median %.2f m, worst %.2f m (%d views)" % (path, d[len(d) // 2], d[-1], len(d)))
        if d[len(d) // 2] > 2.0:
            problems.append("%s views are %.1f m apart" % (path, d[len(d) // 2]))
scores = {w: tuple(v["scores"]) for w, v in views.items()}
print("scores", scores["Host"], "snapshot %d bytes" % views["Host"]["snapshot_bytes"])
if len(set(scores.values())) > 1:
    problems.append("scores differ: %s" % scores)
print("\n".join(problems))
print("NET SOAK", "FAILED" if problems else "PASSED")
sys.exit(1 if problems else 0)
PY
