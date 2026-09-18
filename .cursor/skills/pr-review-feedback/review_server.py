#!/usr/bin/env python3
"""Local viewer for pr-review-feedback dispositions.

Render plus collect only: shows code-reviewing findings for human
disposition and persists a structured envelope for pr-reviewer to act on.
Stdlib only.
"""

import argparse
import html
import json
import subprocess
import webbrowser
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

FINDINGS: list = []
PR: dict = {}
OUTPUT_PATH: Path = Path("feedback.json")


def _kill_port(port: int) -> None:
    try:
        out = subprocess.run(
            ["lsof", "-ti", f":{port}"],
            capture_output=True,
            text=True,
        )
        for pid in out.stdout.split():
            if pid.strip().isdigit():
                subprocess.run(["kill", pid.strip()], capture_output=True)
    except (FileNotFoundError, OSError):
        pass


def _sha_link(pr: dict, location: str | None) -> str:
    if not location or not pr.get("url") or not pr.get("head_sha"):
        return ""
    base = pr["url"].rstrip("/")
    sha = pr["head_sha"]
    path = location.split(":")[0]
    nums = location.split(":", 1)[1] if ":" in location else ""
    start = end = ""
    if "-" in nums:
        start, end = nums.split("-", 1)
    else:
        start = end = nums
    try:
        s = int(start)
        e = int(end) if end else s
    except ValueError:
        return ""
    s = max(1, s - 1)
    e = e + 1
    return f"{base}/blob/{sha}/{path}#L{s}-L{e}"


def generate_html(findings: list, pr: dict) -> str:
    cards = []
    for i, f in enumerate(findings):
        text = html.escape(str(f.get("finding", "")))
        loc = f.get("location")
        loc_esc = html.escape(str(loc)) if loc else "general"
        link = _sha_link(pr, loc if isinstance(loc, str) else None)
        loc_html = (
            f'<a href="{html.escape(link)}" target="_blank" rel="noopener">{loc_esc}</a>'
            if link
            else f"<span>{loc_esc}</span>"
        )
        sev = html.escape(str(f.get("severity", "")))
        typ = html.escape(str(f.get("type", "")))
        cards.append(f"""<section class="card" data-index="{i}">
      <header><span class="idx">#{i}</span>
        <span class="sev sev-{sev}">{sev}</span>
        <span class="type">{typ}</span>
        <span class="loc">{loc_html}</span></header>
      <p class="finding">{text}</p>
      <div class="controls">
        <label>Verdict:
          <label><input type="radio" name="verdict-{i}" value="agree" checked> agree</label>
          <label><input type="radio" name="verdict-{i}" value="disagree"> disagree</label>
        </label>
        <label>Comment:
          <select name="comment-{i}">
            <option value="none" selected>none</option>
            <option value="inline">inline</option>
            <option value="general">general</option>
          </select>
        </label>
        <label class="reason">Reason (disagree only, not posted):
          <input type="text" name="reason-{i}" placeholder="optional">
        </label>
      </div>
    </section>""")
    if not cards:
        cards.append('<p class="empty">No findings — choose a stance and submit.</p>')

    pr_line = " ".join(
        html.escape(str(pr.get(k, "")))
        for k in ("url", "number", "head_sha", "head_ref", "base_ref")
        if pr.get(k)
    ) or "no PR metadata"
    findings_json = json.dumps(findings).replace("<", "\\u003c")
    pr_json = json.dumps(pr).replace("<", "\\u003c")

    return f"""<!doctype html>
<html><head><meta charset="utf-8">
<title>PR review feedback</title>
<style>
body{{font-family:system-ui,sans-serif;max-width:900px;margin:2rem auto;padding:0 1rem}}
.card{{border:1px solid #ddd;border-radius:8px;padding:1rem;margin:1rem 0}}
.idx{{font-weight:700;margin-right:.5rem}}
.sev{{padding:.1rem .5rem;border-radius:4px;font-size:.8rem}}
.sev-high{{background:#fde2e2}} .sev-low{{background:#e2f0fd}}
.type,.loc{{margin-left:.5rem;font-size:.85rem;color:#555}}
.finding{{white-space:pre-wrap}}
.controls{{display:flex;gap:1.5rem;flex-wrap:wrap;align-items:center}}
.reason{{flex:1 1 100%}} .reason input{{width:100%}}
#stance{{border-top:2px solid #333;margin-top:2rem;padding-top:1rem}}
#status{{color:#555;min-height:1.5em}}
button{{font-size:1rem;padding:.5rem 1.5rem}}
</style></head>
<body>
<h1>PR review feedback</h1>
<p class="pr">{pr_line}</p>
<div id="findings">{''.join(cards)}</div>
<div id="stance">
<h2>Review stance</h2>
<label><input type="radio" name="decision" value="approve"> approve</label>
<label><input type="radio" name="decision" value="request_changes"> request changes</label>
<label><input type="radio" name="decision" value="no_action" checked> no action</label>
<label style="display:block;margin-top:.5rem">Note (optional): <input type="text" id="note" style="width:100%"></label>
</div>
<p id="status"></p>
<button id="submit">Submit</button>
<script>
const FINDINGS = {findings_json};
const PR = {pr_json};
const N = FINDINGS.length;
const statusEl = document.getElementById('status');
let saveTimer = null;
function collect(st) {{
  const dispositions = [];
  for (let i = 0; i < N; i++) {{
    const verdict = document.querySelector(`input[name="verdict-${{i}}"]:checked`);
    const comment = document.querySelector(`select[name="comment-${{i}}"]`);
    const reason = document.querySelector(`input[name="reason-${{i}}"]`);
    dispositions.push({{
      index: i,
      verdict: verdict ? verdict.value : 'agree',
      comment: comment ? comment.value : 'none',
      reason: reason ? reason.value : ''
    }});
  }}
  const decision = document.querySelector('input[name="decision"]:checked');
  return {{
    pr: {{url: PR.url || '', head_sha: PR.head_sha || ''}},
    dispositions,
    review_decision: {{
      decision: decision ? decision.value : 'no_action',
      note: document.getElementById('note').value || ''
    }},
    status: st
  }};
}}
async function post(payload) {{
  const r = await fetch('/api/dispositions', {{
    method: 'POST', headers: {{'Content-Type': 'application/json'}},
    body: JSON.stringify(payload)
  }});
  if (!r.ok) throw new Error('save failed');
  return r.json();
}}
function scheduleDraft() {{
  statusEl.textContent = 'saving…';
  clearTimeout(saveTimer);
  saveTimer = setTimeout(async () => {{
    try {{ await post(collect('draft')); statusEl.textContent = 'draft saved'; }}
    catch (e) {{ statusEl.textContent = 'save failed'; }}
  }}, 400);
}}
document.addEventListener('change', scheduleDraft);
document.addEventListener('input', e => {{
  if (e.target.matches('input[type="text"]')) scheduleDraft();
}});
async function restore() {{
  try {{
    const r = await fetch('/api/dispositions');
    if (!r.ok) return;
    const s = await r.json();
    if (!s || s.status === 'empty') return;
    (s.dispositions || []).forEach(d => {{
      const v = document.querySelector(`input[name="verdict-${{d.index}}"][value="${{d.verdict}}"]`);
      if (v) v.checked = true;
      const c = document.querySelector(`select[name="comment-${{d.index}}"]`);
      if (c) c.value = d.comment;
      const rs = document.querySelector(`input[name="reason-${{d.index}}"]`);
      if (rs) rs.value = d.reason || '';
    }});
    const dec = (s.review_decision || {{}}).decision;
    if (dec) {{
      const el = document.querySelector(`input[name="decision"][value="${{dec}}"]`);
      if (el) el.checked = true;
    }}
    if (s.review_decision && s.review_decision.note)
      document.getElementById('note').value = s.review_decision.note;
    if (s.status === 'complete') statusEl.textContent = 'already submitted';
  }} catch (e) {{}}
}}
document.getElementById('submit').addEventListener('click', async () => {{
  try {{
    await post(collect('complete'));
    statusEl.textContent = 'submitted — you can close this tab';
  }} catch (e) {{ statusEl.textContent = 'submit failed'; }}
}});
restore();
</script></body></html>"""


class ReviewHandler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _send_json(self, obj, code=200):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/":
            body = generate_html(FINDINGS, PR).encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif self.path in ("/api/dispositions", "/api/feedback"):
            if OUTPUT_PATH.exists():
                try:
                    self._send_json(json.loads(OUTPUT_PATH.read_text()))
                except (json.JSONDecodeError, OSError):
                    self._send_json({"status": "empty"}, 500)
            else:
                self._send_json({"status": "empty"})
        else:
            self.send_error(404)

    def do_POST(self):
        if self.path not in ("/api/dispositions", "/api/feedback"):
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length", 0))
        try:
            payload = json.loads(self.rfile.read(length or 0) or b"{}")
        except json.JSONDecodeError:
            self.send_error(400, "invalid JSON")
            return
        status = payload.get("status", "draft")
        if status not in ("draft", "complete"):
            status = "draft"
        record = {
            "pr": {
                "url": PR.get("url", ""),
                "head_sha": PR.get("head_sha", ""),
            },
            "dispositions": payload.get("dispositions", []),
            "review_decision": payload.get("review_decision", {}),
            "status": status,
        }
        OUTPUT_PATH.write_text(json.dumps(record, indent=2))
        self._send_json({"ok": True, "status": status})


def main() -> None:
    global FINDINGS, PR, OUTPUT_PATH
    ap = argparse.ArgumentParser(description="Serve PR findings for human disposition.")
    ap.add_argument("--findings", required=True, help="Path to findings JSON array file")
    ap.add_argument("--pr", default="", help="Path to PR metadata JSON file")
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--output", default="feedback.json", help="Where to write dispositions")
    ap.add_argument("--no-open", action="store_true", help="Don't auto-open a browser")
    args = ap.parse_args()

    FINDINGS = json.loads(Path(args.findings).read_text())
    PR = json.loads(Path(args.pr).read_text()) if args.pr else {}
    OUTPUT_PATH = Path(args.output)

    _kill_port(args.port)
    server = HTTPServer(("127.0.0.1", args.port), ReviewHandler)
    url = f"http://127.0.0.1:{args.port}/"
    print(f"Serving {len(FINDINGS)} findings at {url}")
    print(f"Writing dispositions to {OUTPUT_PATH.resolve()}")
    if not args.no_open:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
