#!/usr/bin/env python3
"""Keep a linked worktree's compose stack off other worktrees' host ports.

docker-compose.yaml publishes many host ports as literals (grafana 15301, otelcol 8126, rbac-api 50056, rails-ws 8080 ...),
so PORT_OFFSET cannot move them and a second worktree's stack dies with "port is already allocated". This writes a
worktree-local, git-excluded docker-compose.override.yaml that republishes each literal port on a free one. Ports built
from PORT_OFFSET variables are already per-worktree and are left alone. Nothing in the repo changes.

Usage (run from inside the worktree; compose-ports.sh is a wrapper that adds python3 -I):
  compose-ports.sh write [--offset N] [--repair PORT ...] [--quiet]   regenerate the override
  compose-ports.sh list                                               what the override moved
  compose-ports.sh port SERVICE TARGET[/udp]                          the host port a service really listens on
  compose-ports.sh self-check                                         assertions, no Docker needed

Port choice, per literal mapping: the port it had last time (so a rerun never recreates containers), else stock+offset,
else the next free port above that (up to 200 steps). A port is free when nothing on the host is bound to it, it is not
Chromium-restricted, and nothing else in the stack publishes it. Ports this worktree's own containers already hold count
as free. --repair PORT marks a port that just failed to bind as taken, so that mapping moves on.

Exit: 0 ok | 1 cannot plan (names the mapping) | 2 usage | 3 `docker compose config` failed | 4 --repair named no port this tool assigned
"""
import argparse
import json
import os
import re
import socket
import subprocess
import sys
from pathlib import Path

BASE = "docker-compose.yaml"
OVERRIDE = "docker-compose.override.yaml"
WALK = 200

# kRestrictedPorts in Chromium's net/base/port_util.cc: a browser-facing service here looks healthy to curl but fails in Dispatch.
RESTRICTED = frozenset({
    1, 7, 9, 11, 13, 15, 17, 19, 20, 21, 22, 23, 25, 37, 42, 43, 53, 69, 77, 79, 87, 95, 101, 102, 103, 104, 109, 110,
    111, 113, 115, 117, 119, 123, 135, 137, 139, 143, 161, 179, 389, 427, 465, 512, 513, 514, 515, 526, 530, 531, 532,
    540, 548, 554, 556, 563, 587, 601, 636, 989, 990, 993, 995, 1719, 1720, 1723, 2049, 3659, 4045, 4190, 5060, 5061,
    6000, 6566, 6665, 6666, 6667, 6668, 6669, 6679, 6697, 10080,
})

# A published port written as plain digits: `- 8080:8080`, `- "50911:50911/udp"  # comment`. A line with ${...} is variable-driven.
LITERAL_LINE = re.compile(r"""^\s*-\s*["']?(\d+):(\d+)(?:/(tcp|udp))?["']?\s*(?:#.*)?$""")
# One line this tool wrote: `      - "17001:3000"  # stock 15301`.
OVERRIDE_LINE = re.compile(r"""^\s{6}-\s"(\d+):(\d+)(?:/(tcp|udp))?"\s+#\s*stock\s+(\d+)\s*$""")
SERVICE_LINE = re.compile(r"^  ([A-Za-z0-9._-]+):\s*$")


class PlanError(Exception):
    pass


class ConfigError(Exception):
    pass


def literal_ports(raw):
    """(published, target, proto) for every plain-digit port line in the compose text."""
    found = set()
    for line in raw.splitlines():
        m = LITERAL_LINE.match(line)
        if m:
            found.add((int(m.group(1)), int(m.group(2)), m.group(3) or "tcp"))
    return found


def parse_override(text):
    """{(service, stock, target, proto): new} for what an earlier run assigned."""
    sticky, service = {}, None
    for line in text.splitlines():
        m = SERVICE_LINE.match(line)
        if m:
            service = m.group(1)
            continue
        m = OVERRIDE_LINE.match(line)
        if m and service:
            sticky[(service, int(m.group(4)), int(m.group(2)), m.group(3) or "tcp")] = int(m.group(1))
    return sticky


def plan(cfg, raw, offset, sticky, repair, mine, free_fn):
    """Decide a host port for every literal mapping. Returns (per-service port lists, assignments)."""
    literals = literal_ports(raw)
    services = cfg.get("services", {})

    def published(p):
        return int(p["published"]) if p.get("published") else None

    fixed = set()  # ports in the stack we leave alone
    for svc in services.values():
        for p in svc.get("ports", []):
            pub = published(p)
            if pub is not None and (pub, int(p["target"]), p.get("protocol", "tcp")) not in literals:
                fixed.add((pub, p.get("protocol", "tcp")))

    taken, lists, assignments = set(fixed), {}, []

    def usable(port, proto):
        if not 1024 <= port <= 65535 or port in RESTRICTED or port in repair or (port, proto) in taken:
            return False
        return (port, proto) in mine or free_fn(port, proto)

    for name in sorted(services):
        ports = services[name].get("ports", [])
        if not any(published(p) is not None and (published(p), int(p["target"]), p.get("protocol", "tcp")) in literals for p in ports):
            continue
        entries = []
        for p in ports:
            pub, tgt, proto = published(p), int(p["target"]), p.get("protocol", "tcp")
            if pub is None:
                continue
            if (pub, tgt, proto) not in literals:
                entries.append((pub, tgt, proto, None))  # baked at the value resolved now
                continue
            base = pub + offset
            candidates = ([sticky[(name, pub, tgt, proto)]] if (name, pub, tgt, proto) in sticky else []) + list(range(base, base + WALK + 1))
            chosen = next((c for c in candidates if usable(c, proto)), None)
            if chosen is None:
                raise PlanError(f"{name}: no free host port for {pub}->{tgt}/{proto} between {base} and {base + WALK}")
            taken.add((chosen, proto))
            assignments.append((name, pub, tgt, proto, chosen))
            entries.append((chosen, tgt, proto, pub))
        lists[name] = entries
    return lists, assignments


def render(lists, offset):
    out = [
        "# Worktree-local (git-excluded), written by compose-ports.sh in the git-worktree-setup-custom skill. Do not edit by hand.",
        f"# docker-compose.yaml publishes these host ports as literals, so two worktrees' stacks collide. Republished here",
        f"# on free ports (stock + PORT_OFFSET {offset}, or the next free one). Only host ports change: services still reach",
        "# each other by compose DNS. `!override` replaces a service's whole port list. Delete this file for the stock ports;",
        "# `compose-ports.sh write` regenerates it and keeps each port it already chose.",
        "services:",
    ]
    for name in sorted(lists):
        out.append(f"  {name}:")
        out.append("    ports: !override")
        for pub, tgt, proto, stock in lists[name]:
            spec = f"{pub}:{tgt}" + ("/udp" if proto == "udp" else "")
            out.append(f'      - "{spec}"' + (f"  # stock {stock}" if stock is not None else ""))
    return "\n".join(out) + "\n"


# --- environment ---------------------------------------------------------------------------------------------------

def host_free(port, proto):
    kind = socket.SOCK_DGRAM if proto == "udp" else socket.SOCK_STREAM
    s = socket.socket(socket.AF_INET, kind)
    try:
        if proto != "udp":
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind(("0.0.0.0", port))
        return True
    except OSError:
        return False
    finally:
        s.close()


def compose_config(*extra):
    p = subprocess.run(["docker", "compose", *extra, "config", "--format", "json"], capture_output=True, text=True)
    if p.returncode != 0:
        raise ConfigError((p.stderr or p.stdout).strip()[-600:])
    return json.loads(p.stdout)


def own_ports(project):
    """(host port, proto) pairs this compose project's running containers publish."""
    p = subprocess.run(["docker", "ps", "--filter", f"label=com.docker.compose.project={project}", "--format", "{{.Ports}}"],
                       capture_output=True, text=True)
    return {(int(m.group(1)), m.group(2)) for m in re.finditer(r":(\d+)->\d+/(tcp|udp)", p.stdout)}


def resolve_offset(arg):
    if arg is not None:
        return arg
    if os.environ.get("PORT_OFFSET", "").isdigit():
        return int(os.environ["PORT_OFFSET"])
    env_local = Path(".env.local")
    if env_local.is_file():
        m = re.search(r"^\s*PORT_OFFSET=\"?(\d+)\"?\s*$", env_local.read_text(), re.M)
        if m:
            return int(m.group(1))
    raise PlanError("no PORT_OFFSET: pass --offset, export it, or pin it in .env.local (worktree-setup.sh does)")


def is_linked_worktree():
    git = lambda a: subprocess.run(["git", "rev-parse", a], capture_output=True, text=True).stdout.strip()
    return git("--git-dir") != git("--git-common-dir")


# --- commands ------------------------------------------------------------------------------------------------------

def cmd_write(args):
    if not is_linked_worktree():
        print("compose-ports: main checkout, nothing to shift (it owns the stock ports).", file=sys.stderr)
        return 0
    offset = resolve_offset(args.offset)
    cfg = compose_config("--profile", "*", "-f", BASE)
    raw = Path(BASE).read_text()
    override = Path(OVERRIDE)
    previous = override.read_text() if override.is_file() else ""
    sticky = parse_override(previous)

    repair = set(args.repair)
    if repair:
        assigned = set(sticky.values())
        unknown = sorted(repair - assigned)
        if unknown:
            print(f"compose-ports: port(s) {', '.join(map(str, unknown))} are not ones this tool assigned. A port that follows "
                  f"PORT_OFFSET (Rails API, databases ...) or one held by a non-compose process cannot be moved here: "
                  f"change PORT_OFFSET in .env.local, delete .env and rerun worktree-setup.sh.", file=sys.stderr)
        if not repair & assigned:
            return 4

    lists, assignments = plan(cfg, raw, offset, sticky, repair, own_ports(cfg.get("name", "")), host_free)
    text = render(lists, offset)
    changed = text != previous
    if changed:
        override.write_text(text)
    if not args.quiet or changed:
        moved = [(a[0], sticky[key], a[4]) for a in assignments
                 if (key := (a[0], a[1], a[2], a[3])) in sticky and sticky[key] != a[4]]
        verb = "wrote" if changed and not previous else ("updated" if changed else "unchanged:")
        print(f"compose-ports: {verb} {OVERRIDE} ({len(assignments)} host ports shifted, offset {offset})", file=sys.stderr)
        for s, old, new in moved:
            print(f"compose-ports:   {s} moved {old} -> {new}", file=sys.stderr)
    return 0


def cmd_list(_args):
    override = Path(OVERRIDE)
    if not override.is_file():
        print("compose-ports: no override; every service publishes its stock ports.", file=sys.stderr)
        return 0
    rows = sorted(parse_override(override.read_text()).items())
    for (service, stock, target, proto), new in rows:
        print(f"{service:<28} {new:>6} -> {target}/{proto}   (stock {stock})")
    return 0


def cmd_port(args):
    target, _, proto = args.target.partition("/")
    cfg = compose_config("--profile", "*")  # with the override, exactly as `docker compose up` will publish
    for p in cfg.get("services", {}).get(args.service, {}).get("ports", []):
        if str(p["target"]) == target and p.get("protocol", "tcp") == (proto or "tcp") and p.get("published"):
            print(p["published"])
            return 0
    print(f"compose-ports: {args.service} publishes no host port for {args.target}", file=sys.stderr)
    return 1


def cmd_self_check(_args):
    raw = '\n'.join([
        "services:", "  rails-ws:", "    ports:", "      - 8080:8080",
        "  api:", "    ports:", '      - "${RAILS_API_PORT:-3000}:3000"',
        "  audio-client:", "    ports:", '      - "50911:50911"', '      - "50911:50911/udp"', "      - 8101:8080  # comment",
        "  mixed:", "    ports:", "      - 7000:7000", '      - "${X:-9000}:9000"',
        "  low:", "    ports:", "      - 2000:2000",
        "  low2:", "    ports:", "      - 1000:1000",
    ])
    cfg = {"name": "t", "services": {
        "rails-ws": {"ports": [{"published": "8080", "target": 8080, "protocol": "tcp"}]},
        "api": {"ports": [{"published": "4700", "target": 3000, "protocol": "tcp"}]},
        "audio-client": {"ports": [{"published": "50911", "target": 50911, "protocol": "tcp"},
                                   {"published": "50911", "target": 50911, "protocol": "udp"},
                                   {"published": "8101", "target": 8080, "protocol": "tcp"}]},
        "mixed": {"ports": [{"published": "7000", "target": 7000, "protocol": "tcp"}, {"published": "9100", "target": 9000, "protocol": "tcp"}]},
        "low": {"ports": [{"published": "2000", "target": 2000, "protocol": "tcp"}]},
        "low2": {"ports": [{"published": "1000", "target": 1000, "protocol": "tcp"}]},
        "no-ports": {},
    }}
    free = lambda busy: (lambda port, proto: port not in busy)
    failures = []

    def check(name, cond):
        if not cond:
            failures.append(name)

    assert literal_ports(raw) >= {(8080, 8080, "tcp"), (50911, 50911, "tcp"), (50911, 50911, "udp"), (8101, 8080, "tcp")}
    check("variable-driven line is not literal", (3000, 3000, "tcp") not in literal_ports(raw))

    lists, asg = plan(cfg, raw, 1700, {}, set(), set(), free(set()))
    got = {(s, o): n for s, o, _t, _p, n in asg}
    check("shifts by offset", got[("rails-ws", 8080)] == 9780)
    check("api (variable-driven) untouched", "api" not in lists)
    check("tcp and udp both shifted, kept distinct", got[("audio-client", 50911)] == 52611 and len([a for a in asg if a[0] == "audio-client" and a[1] == 50911]) == 2)
    check("mixed service bakes its variable-driven port", (9100, 9000, "tcp", None) in lists["mixed"])

    _, asg = plan(cfg, raw, 1700, {}, set(), set(), free({9780}))
    check("walks past a busy port", [a[4] for a in asg if a[0] == "rails-ws"] == [9781])

    _, asg = plan(cfg, raw, 1700, {("rails-ws", 8080, 8080, "tcp"): 9790}, set(), set(), free(set()))
    check("sticky port kept while free", [a[4] for a in asg if a[0] == "rails-ws"] == [9790])
    _, asg = plan(cfg, raw, 1700, {("rails-ws", 8080, 8080, "tcp"): 9790}, set(), set(), free({9790}))
    check("sticky port dropped when busy", [a[4] for a in asg if a[0] == "rails-ws"] == [9780])

    _, asg = plan(cfg, raw, 1700, {}, set(), {(9780, "tcp")}, free({9780}))
    check("own container's port counts as free", [a[4] for a in asg if a[0] == "rails-ws"] == [9780])
    _, asg = plan(cfg, raw, 1700, {("rails-ws", 8080, 8080, "tcp"): 9780}, {9780}, {(9780, "tcp")}, free(set()))
    check("--repair moves even an own port", [a[4] for a in asg if a[0] == "rails-ws"] == [9781])

    _, asg = plan(cfg, raw, 4000, {}, set(), set(), free(set()))  # low: 2000 + 4000 = 6000, Chromium-restricted
    check("skips a Chromium-restricted port", [a[4] for a in asg if a[0] == "low"] == [6001])

    _, asg = plan(cfg, raw, 3700, {}, set(), set(), free(set()))  # low2: 1000 + 3700 = 4700, the api's variable-driven port
    check("avoids a port another service publishes", [a[4] for a in asg if a[0] == "low2"] == [4701])

    try:
        plan(cfg, raw, 70000, {}, set(), set(), free(set()))
        check("refuses above 65535", False)
    except PlanError:
        pass

    lists, asg = plan(cfg, raw, 1700, {}, set(), set(), free(set()))
    again = parse_override(render(lists, 1700))
    check("render/parse round trip", {(s, o, t, p): n for s, o, t, p, n in asg} == again)

    if failures:
        print("compose-ports self-check FAILED: " + "; ".join(failures), file=sys.stderr)
        return 1
    print("compose-ports self-check ok")
    return 0


def main(argv):
    ap = argparse.ArgumentParser(prog="compose-ports", description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    w = sub.add_parser("write")
    w.add_argument("--offset", type=int)
    w.add_argument("--repair", type=int, action="append", default=[])
    w.add_argument("--quiet", action="store_true")
    sub.add_parser("list")
    p = sub.add_parser("port")
    p.add_argument("service")
    p.add_argument("target")
    sub.add_parser("self-check")
    args = ap.parse_args(argv)
    if args.cmd != "self-check":
        top = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip()
        if not top:
            print("compose-ports: run from inside the worktree", file=sys.stderr)
            return 2
        os.chdir(top)
    try:
        return {"write": cmd_write, "list": cmd_list, "port": cmd_port, "self-check": cmd_self_check}[args.cmd](args)
    except PlanError as e:
        print(f"compose-ports: {e}", file=sys.stderr)
        return 1
    except ConfigError as e:
        print(f"compose-ports: `docker compose config` failed: {e}", file=sys.stderr)
        return 3


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
