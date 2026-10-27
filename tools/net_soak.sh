#!/bin/bash
# Four copies of the game (a host and three friends, all played by the bot
# AI) fight online over this machine for a minute, then each says where it
# sees every soldier at the same moment. This compares the four views.
#   GODOT=/path/to/godot tools/net_soak.sh [seconds] [direct]
# By default friends join with the host's code through tests/fake_internet.py
# (a STUN server, the message board, and a strict home router in front of
# the host, with lag and loss); "direct" connects them straight to it.
set -e
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
LOGS=$(mktemp -d)
SECONDS_LEFT=${1:-70}
DEADLINE=$(python3 -c "import time; print(time.time() + $SECONDS_LEFT)")
VIA=direct
if [ "${2:-}" != direct ]; then
	python3 tests/fake_internet.py --seconds $((SECONDS_LEFT + 4)) > "$LOGS/internet.txt" 2>&1 &
	INTERNET=$!
	VIA=fake:34780:34781:34790
	sleep 0.5
fi
"$GODOT" --headless --path . -s tests/net_soak_test.gd -- host Host "$DEADLINE" $VIA > "$LOGS/Host.log" 2>&1 &
GAMES=$!
sleep 1
for who in Anna Boris Clara; do
	"$GODOT" --headless --path . -s tests/net_soak_test.gd -- join "$who" "$DEADLINE" $VIA > "$LOGS/$who.log" 2>&1 &
	GAMES="$GAMES $!"
	sleep 0.5
done
wait $GAMES
if [ -n "${INTERNET:-}" ]; then
	wait $INTERNET
	cat "$LOGS/internet.txt"
fi
grep -h -A4 "SCRIPT ERROR" "$LOGS"/*.log && { echo "NET SOAK FAILED: script errors (logs in $LOGS)"; exit 1; }
python3 - "$LOGS" "$VIA" <<'PY'
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
if views["Host"]["code"] == "" and sys.argv[2] != "direct":
    problems.append("the host got no join code")
scores = {w: tuple(v["scores"]) for w, v in views.items()}
print("scores", scores["Host"], "snapshot %d bytes" % views["Host"]["snapshot_bytes"])
if len(set(scores.values())) > 1:
    problems.append("scores differ: %s" % scores)
print("\n".join(problems))
print("NET SOAK", "FAILED" if problems else "PASSED")
sys.exit(1 if problems else 0)
PY
