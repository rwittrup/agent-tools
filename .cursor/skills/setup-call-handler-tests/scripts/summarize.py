#!/usr/bin/env python3
"""Summarize a text-sim run: real verdicts plus the timeline events that prove behavior.

usage: summarize.py [output_dir] [--grep REGEX]
  output_dir  defaults to the newest dir under feature_scenarios/output
  --grep      only show events whose 'type/name' matches (default: tool_call,
              location, error events)

results.json 'success' / run_complete.success_count only mean "conversation
completed". The verdict is post_call.verdict, so that is what this prints.
"""
import glob, json, os, re, subprocess, sys

args = sys.argv[1:]
pattern = None
if "--grep" in args:
    i = args.index("--grep"); pattern = re.compile(args[i + 1]); del args[i:i + 2]
root = subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip()
base = os.path.join(root, "apps/go/call-handler/cmd/text-conversation/feature_scenarios/output")
out = args[0] if args else sorted(glob.glob(base + "/*/"))[-1]
res = json.load(open(os.path.join(out, "results.json")))
for c in res["conversations"]:
    pc = c.get("post_call") or {}
    print(f"[{(pc.get('verdict') or 'no-judge').upper()}] {c['test_name']}\n  {pc.get('reason', '')}")
    tl = json.load(open(os.path.join(out, "timelines", c["timeline_file"])))
    for e in tl:
        text = json.dumps(e.get("details", {}))
        hit = pattern.search(f"{e['type']}/{e['name']}") if pattern else e["type"] in ("tool_call", "location", "error")
        if hit:
            print(f"  {e['timestamp'][11:19]} {e['type']}/{e['name']} {text[:220]}")
