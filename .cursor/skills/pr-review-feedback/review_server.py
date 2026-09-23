#!/usr/bin/env python3
"""Local viewer for pr-review-feedback dispositions.

Render plus collect only: shows code-reviewing findings for human
disposition and persists a structured envelope for the caller to act on.
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
        hidden = "" if i == 0 else " hidden"
        cards.append(f"""<section class="card finding-card" data-index="{i}"{hidden}>
      <header class="finding-meta"><span class="idx">#{i}</span>
        <span class="sev sev-{sev}">{sev}</span>
        <span class="type">{typ}</span>
        <span class="loc">{loc_html}</span></header>
      <div class="card-body">
        <p class="finding">{text}</p>
        <div class="controls">
          <div class="decision-row">
            <div class="control-group">
              <span class="control-label">Verdict</span>
              <div class="choice-row">
                <label><input type="radio" name="verdict-{i}" value="agree" checked> Agree</label>
                <label><input type="radio" name="verdict-{i}" value="disagree"> Disagree</label>
              </div>
            </div>
            <div class="control-group">
              <span class="control-label">Comment</span>
              <select name="comment-{i}">
                <option value="none" selected>None</option>
                <option value="inline">Inline</option>
                <option value="general">General</option>
              </select>
            </div>
          </div>
          <label class="reason"><span class="control-label">Reason <span class="optional">(disagree only, not posted)</span></span>
            <input type="text" name="reason-{i}" placeholder="Optional">
          </label>
        </div>
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
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>PR review feedback</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Poppins:wght@500;600&family=Lora:wght@400;500&display=swap" rel="stylesheet">
<style>
:root {{
  --bg: #faf9f5;
  --surface: #ffffff;
  --border: #e8e6dc;
  --text: #141413;
  --text-muted: #b0aea5;
  --accent: #d97757;
  --accent-hover: #c4613f;
  --green: #788c5d;
  --green-bg: #eef2e8;
  --red: #c44;
  --red-bg: #fceaea;
  --header-bg: #141413;
  --header-text: #faf9f5;
  --radius: 6px;
}}
* {{ box-sizing: border-box; margin: 0; padding: 0; }}
body {{
  min-height: 100vh;
  display: flex;
  flex-direction: column;
  font-family: 'Lora', Georgia, serif;
  background: var(--bg);
  color: var(--text);
}}
.header {{
  padding: 1rem 2rem;
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 1rem;
  background: var(--header-bg);
  color: var(--header-text);
}}
.header h1 {{
  font-family: 'Poppins', sans-serif;
  font-size: 1.25rem;
  font-weight: 600;
}}
.pr {{
  margin-top: .25rem;
  max-width: 72rem;
  overflow-wrap: anywhere;
  font-size: .8rem;
  opacity: .7;
}}
.progress {{ flex-shrink: 0; font-size: .875rem; opacity: .8; }}
.main {{
  width: 100%;
  max-width: 1100px;
  margin: 0 auto;
  padding: 1.5rem 2rem;
}}
.section, .card {{
  overflow: hidden;
  border: 1px solid var(--border);
  border-radius: var(--radius);
  background: var(--surface);
}}
.card + .card {{ margin-top: 1rem; }}
.finding-meta, .section-header {{
  padding: .75rem 1rem;
  border-bottom: 1px solid var(--border);
  background: var(--bg);
  font-family: 'Poppins', sans-serif;
}}
.finding-meta {{ display: flex; align-items: center; gap: .5rem; }}
.idx {{ font-size: .75rem; font-weight: 600; color: var(--text-muted); }}
.sev {{
  padding: .125rem .5rem;
  border-radius: 9999px;
  font-size: .6875rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: .03em;
}}
.sev-high {{ background: var(--red-bg); color: var(--red); }}
.sev-low {{ background: var(--green-bg); color: var(--green); }}
.type {{
  font-size: .6875rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: .03em;
  color: var(--text-muted);
}}
.loc {{ margin-left: auto; font: .75rem 'SF Mono', SFMono-Regular, Consolas, monospace; }}
.loc a, .loc span {{ color: var(--accent); text-decoration: none; }}
.loc a:hover {{ text-decoration: underline; }}
.card-body {{ padding: 1rem; }}
.finding {{ white-space: pre-wrap; font-size: .9375rem; line-height: 1.6; }}
.controls {{
  display: flex;
  flex-direction: column;
  gap: 1rem;
  margin-top: 1rem;
  padding-top: 1rem;
  border-top: 1px solid var(--border);
}}
.decision-row {{
  display: flex;
  align-items: flex-end;
  gap: 1.5rem;
  flex-wrap: wrap;
}}
.control-group {{
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: .4rem;
}}
.choice-row {{
  display: flex;
  align-items: center;
  gap: .85rem;
  min-height: 2.25rem;
}}
.control-label {{
  font-family: 'Poppins', sans-serif;
  font-size: .75rem;
  font-weight: 500;
  color: var(--text-muted);
  text-transform: uppercase;
  letter-spacing: .04em;
}}
.optional {{
  font-family: 'Lora', Georgia, serif;
  font-weight: 400;
  text-transform: none;
  letter-spacing: 0;
}}
label {{ font-size: .875rem; }}
input[type="radio"] {{ accent-color: var(--accent); }}
select, input[type="text"] {{
  padding: .5rem .625rem;
  border: 1px solid var(--border);
  border-radius: 4px;
  background: var(--surface);
  color: var(--text);
  font: .875rem 'Lora', Georgia, serif;
}}
.controls select {{ height: 2.25rem; min-width: 9rem; }}
select:focus, input[type="text"]:focus {{
  outline: none;
  border-color: var(--accent);
  box-shadow: 0 0 0 2px rgba(217, 119, 87, .15);
}}
.reason {{ flex: 1 1 100%; display: grid; gap: .4rem; }}
.reason input {{ width: 100%; }}
.empty {{ padding: 2rem; text-align: center; color: var(--text-muted); font-style: italic; }}
#stance {{ margin-top: 1.25rem; }}
.section-header {{
  font-size: .75rem;
  font-weight: 500;
  text-transform: uppercase;
  letter-spacing: .05em;
  color: var(--text-muted);
}}
.section-body {{ padding: 1rem; }}
.stance-options {{ display: flex; flex-wrap: wrap; gap: 1.25rem; }}
.note {{ display: grid; gap: .4rem; margin-top: 1rem; }}
.note input {{ width: 100%; }}
.pager {{
  margin-top: 1rem;
  display: flex;
  justify-content: center;
  align-items: center;
  gap: 1rem;
}}
.pager[hidden] {{ display: none; }}
.pager button {{
  padding: .4rem 1rem;
  border: 1px solid var(--border);
  border-radius: var(--radius);
  background: var(--surface);
  color: var(--text);
  cursor: pointer;
  font-family: 'Poppins', sans-serif;
  font-size: .8125rem;
  font-weight: 500;
}}
.pager button:disabled {{ opacity: .4; cursor: default; }}
.pager button:not(:disabled):hover {{ border-color: var(--accent); }}
#page-label {{
  min-width: 5rem;
  text-align: center;
  font-family: 'Poppins', sans-serif;
  font-size: .8125rem;
  color: var(--text-muted);
}}
.nav {{
  margin-top: 1.25rem;
  padding: 1rem;
  display: flex;
  flex-direction: column;
  justify-content: center;
  align-items: center;
  gap: .75rem;
  border: 1px solid var(--border);
  border-radius: var(--radius);
  background: var(--surface);
}}
#status {{ min-height: 1.1em; font-size: .75rem; color: var(--text-muted); text-align: center; }}
#submit {{
  padding: .5rem 1.5rem;
  border: none;
  border-radius: var(--radius);
  background: var(--accent);
  color: white;
  cursor: pointer;
  font-family: 'Poppins', sans-serif;
  font-size: .875rem;
  font-weight: 600;
  transition: background .15s;
}}
#submit:hover {{ background: var(--accent-hover); }}
@media (max-width: 640px) {{
  .header {{ align-items: flex-start; padding: 1rem; }}
  .main {{ padding: 1rem; }}
  .finding-meta {{ flex-wrap: wrap; }}
  .loc {{ width: 100%; margin-left: 0; overflow-wrap: anywhere; }}
  .decision-row {{ align-items: stretch; }}
}}
</style></head>
<body>
<header class="header">
  <div>
    <h1>PR Review Feedback</h1>
    <p class="pr">{pr_line}</p>
  </div>
  <div class="progress" id="progress">{len(findings)} finding{"s" if len(findings) != 1 else ""}</div>
</header>
<main class="main">
<div id="findings">{''.join(cards)}</div>
<div class="pager" id="pager"{" hidden" if len(findings) <= 1 else ""}>
  <button type="button" id="prev" disabled>Previous</button>
  <span id="page-label">1 of {len(findings)}</span>
  <button type="button" id="next">Next</button>
</div>
<section class="section" id="stance">
  <div class="section-header">Review stance</div>
  <div class="section-body">
    <div class="stance-options">
      <label><input type="radio" name="decision" value="approve"> Approve</label>
      <label><input type="radio" name="decision" value="request_changes"> Request changes</label>
      <label><input type="radio" name="decision" value="no_action" checked> No action</label>
    </div>
    <label class="note"><span class="control-label">Note <span class="optional">(optional)</span></span>
      <input type="text" id="note">
    </label>
  </div>
</section>
<div class="nav">
  <p id="status"></p>
  <button id="submit">Submit Review</button>
</div>
</main>
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
const cards = [...document.querySelectorAll('.finding-card')];
let page = 0;
const prevBtn = document.getElementById('prev');
const nextBtn = document.getElementById('next');
const pageLabel = document.getElementById('page-label');
const progressEl = document.getElementById('progress');
function renderPage() {{
  if (!cards.length) return;
  cards.forEach((card, i) => {{ card.hidden = i !== page; }});
  if (pageLabel) pageLabel.textContent = (page + 1) + ' of ' + cards.length;
  if (prevBtn) prevBtn.disabled = page === 0;
  if (nextBtn) nextBtn.disabled = page === cards.length - 1;
  if (progressEl) progressEl.textContent = 'Finding ' + (page + 1) + ' of ' + cards.length;
}}
if (prevBtn) prevBtn.addEventListener('click', () => {{
  if (page > 0) {{ page -= 1; renderPage(); }}
}});
if (nextBtn) nextBtn.addEventListener('click', () => {{
  if (page < cards.length - 1) {{ page += 1; renderPage(); }}
}});
renderPage();
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
