# 🤖 n8n Job Tracker — Bundesagentur/JobSpy + OpenCode Go + Notion

> Automated daily job search: scrape German job boards → filter → AI-score against your CV → save the Top 10 to Notion → Telegram summary.

[![n8n](https://img.shields.io/badge/n8n-2.30+-blue?logo=n8n)](https://n8n.io)
[![Python](https://img.shields.io/badge/Python-3.10+-blue?logo=python)](https://python.org)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

## Overview

An n8n workflow that runs every weekday morning and:

1. **🔍 Scrapes** job postings — **[Bundesagentur für Arbeit Jobsuche v6](https://github.com/bundesAPI/jobsuche-api)** as the primary source (free, no signup, stable, full descriptions) plus **LinkedIn/Indeed via [JobSpy](https://github.com/speedyapply/JobSpy)** as best-effort secondary sources.
2. **🚫 Filters** internships/student roles, **military/defence postings** (see below), and anything already in the Notion database.
3. **🤖 Scores** each remaining job against your CV using **DeepSeek V4 Flash served by OpenCode Go** (7 dimensions, 100 points).
4. **📝 Saves** the Top 10 matches to a Notion database, then sends a **Telegram run summary**.

### Key features

- 🚫 **Defence/military filter** — company blocklist (Rheinmetall, Hensoldt, KNDS, BWI, Helsing, ARX Robotics, …) plus text signals (`Wehrtechnik`, `ITAR`, `Security Clearance`, `Staatsbürgerschaft`, `vs-nfd`, …) and a second safety net that zero-scores anything the model still labels as defence.
- 🔁 **Cross-run dedup** — the workflow reads the existing Notion rows first and skips postings it has already recommended (matched by link *and* job id).
- 🇩🇪 **Bundesagentur first** — 20+ Munich-area postings in seconds instead of fighting LinkedIn's rate limits.
- ⚙️ **Search config lives in the workflow** — the `🔍 搜索参数配置` node is the single source of truth for keywords, regions, result limits and BA settings (no more env-var drift).
- 📣 **Telegram summary + error workflow** — every run reports counts (scraped / filtered / skipped / written); hard failures post a separate alert via an Error Trigger workflow.
- 🛡️ **Fail-loud** — missing CV, scraper bridge down, or a failing model call all produce a visible error instead of a silent empty run.

## Architecture

```
⏰ Schedule (weekdays 07:00 Europe/Berlin)
  → 📄 Read CV.pdf → 📄 Extract PDF → 📄 Structure CV text
      → 🛡️ CV valid? ──no──▶ 📵 Telegram: CV missing
            │yes
            ▼
  🔍 Search config ──▶ 🌐 Scrape (BA + LinkedIn/Indeed via localhost:3456 bridge)
                              │                        └──error──▶ ❌ Scrape failed
                              ▼
                     📋 Parse jobs  (internship filter + defence filter + dedupe)
                              ▼
                     📥 Read existing Notion rows ──▶ 🔁 Drop already-seen jobs
                              ▼
                     ✂️ Split ──▶ 🔄 Score each job (loop)
                                     ✍️ Prompt → 🧠 OpenCode Go (DeepSeek V4 Flash) → 📊 Parse score
                              ▼ (loop done)
                     📊 Sort + Top 10 ──▶ 🔄 Write each
                                            ├─ score ≥ 7.5 → 📝 Notion ⭐
                                            ├─ score ≥ 6   → 📝 Notion 💪
                                            └─ else        → ⏭️ skip
                              ▼ (write loop done)
                     📣 Telegram run summary
```

## Prerequisites

| Requirement | Version / Notes |
|-------------|----------------|
| [Python](https://www.python.org/) | >= 3.10 (needs `python-jobspy` + `requests`) |
| [n8n](https://docs.n8n.io/hosting/installation/) | 2.30+ (self-hosted, npm install) |
| [OpenCode Go](https://opencode.ai/) API key | $10/mo subscription — serves `deepseek-v4-flash`, the scoring model |
| [Notion](https://www.notion.so/) account | Free tier — internal integration with access to the job database |
| Telegram bot (optional) | For the run summary and error alerts |

## Quick Start

### 1. Clone & install

```bash
git clone https://github.com/caozh502/n8n-job-tracker.git
cd n8n-job-tracker
pip install -r requirements.txt
```

### 2. Put your CV in place

`cv/CV.pdf` — the workflow reads it on every run (requires `N8N_RESTRICT_FILE_ACCESS_TO` to include that folder).

### 3. Start the services

Double-click `start_n8n.bat` (Windows). It starts the local scraper bridge on port `3456` and n8n on port `5678`, and waits until both answer.

```
http://localhost:3456/health   -> {"ok":true,...}
http://localhost:5678/healthz  -> 200
```

### 4. Configure credentials in n8n

| Credential | Type | What to enter |
|-----------|------|---------------|
| **OpenCode Go** | `Bearer Auth` | Your OpenCode Go API key — used by the `🧠 OpenCode DeepSeek 打分` HTTP Request node |
| **Notion** | `Notion API` | Internal integration token |
| **Telegram (Job Tracker)** | `Telegram API` | Bot token (only needed for notifications) |

### 5. Import the workflow

Import `n8n-job-scraper-workflow_zh.json` (canonical, Chinese) — wire up the three credentials when prompted, then activate the workflow.

## Why an HTTP Request node instead of the DeepSeek node?

The OpenCode Go endpoint (`https://opencode.ai/zen/go/v1/chat/completions`) **requires**:

- a `x-opencode-session` header — otherwise `400 MissingSessionID`
- a browser-like `User-Agent` — otherwise Cloudflare answers `403 error code 1010`

n8n's LangChain DeepSeek/OpenAI nodes cannot send custom headers, so scoring goes through a plain HTTP Request node with a `Bearer Auth` credential. The API key lives in n8n's credential store, never in the workflow JSON.

## Filtering rules

**Internship/student** — title or company matching `student`, `intern`, `werkstudent`, `praktik*`, `thesis`, `ausbildung`, `dual* studium`, `(bachelor|master)arbeit`.

**Defence/military** — dropped before scoring, on two independent signals:

| Layer | Examples |
|-------|----------|
| Company blocklist | Rheinmetall, Diehl, Hensoldt, KNDS, Krauss-Maffei, MBDA, Thales, Airbus Defence, Leonardo, Lockheed, RTX, Northrop, BAE, Elbit, L3Harris, Kongsberg, Anduril, Helsing, ARX Robotics, Quantum-Systems, Bundeswehr, BWI, IABG, GDELS, Iveco Defence, … |
| Text signals (title + description) | `defence`/`defense`, `military`, `Wehrtechnik`, `Rüstung`, `Verteidigung`, `ITAR`, `Security Clearance`, `Sicherheitsüberprüfung`, `Staatsbürgerschaft`, `Ü2/Ü3`, `vs-nfd`, `classified`, `MilSpec`, `Waffensystem`, `munition`, `Rakete`, `Fregatte`, `C4ISR`, … |
| Model verdict (safety net) | If the scorer nevertheless returns a defence/military `industry`, the job is forced to 0 points and can never be written to Notion. |

Civil aerospace/space (e.g. satellite startups) is deliberately **not** filtered — only military/defence context is.

**Already seen** — anything whose link or job id already exists in the Notion database is skipped before scoring (saves model calls).

## How the scoring works

DeepSeek V4 Flash (via OpenCode Go) rates each job against the CV across **7 dimensions** (100 points total):

| Dimension | Weight | Description |
|-----------|--------|-------------|
| background_match | 0–10 | Domain / industry alignment (Automotive: −5) |
| skills_overlap | 0–25 | Technical skills match |
| experience_relevance | 0–25 | Project / role relevance |
| seniority | 0–10 | Seniority fit |
| language_requirement | 0–10 | German/English requirements |
| location_match | 0–10 | Geography (Munich ≈ 10) |
| bonus | 0–10 | Company reputation, growth, perks |

Tiers: ★ ≥ 75 · 💪 ≥ 60 · below that is dropped. (Internally the score is normalised to 0–10 for the tier checks.)

## Notion schema

| Column | Type | Source |
|--------|------|--------|
| Job Title | Title | posting title |
| Company | Rich Text | employer |
| Location | Select | first part of the location |
| Industry | Select | model verdict |
| Score | Number | 0–10 match score |
| Link | URL | original posting |
| Posted | Date | posting date |
| Match Reason | Rich Text | model rationale |
| Notes | Rich Text | source board + per-dimension breakdown |

## Search configuration

All scraping parameters live in the `🔍 搜索参数配置` node (an object the workflow POSTs to the local bridge):

```json
{
  "keywords": "QA Engineer OR Test Automation OR Testingenieur OR HiL OR CI/CD OR Embedded OR DevOps",
  "hours_old": 24,
  "max_total": 30,
  "sites": ["linkedin", "indeed"],
  "locations": [["Munich, Germany", 8], ["Bavaria, Germany", 3]],
  "ba": {
    "enabled": true,
    "terms": ["Testautomatisierung", "Test Engineer", "QA Engineer", "Software Test",
              "HiL", "Embedded Software", "DevOps Engineer"],
    "location": "München", "radius_km": 30, "per_term": 12, "limit": 22, "detail_limit": 22
  }
}
```

The bridge (`scraper_server.js`) only forwards this JSON to `scrape_jobs.py` — the workflow stays the single source of truth. `GET /health` is used by the watchdog; `POST /` refuses concurrent scrapes with `429 scraper_busy`.

## Troubleshooting

| Problem | Likely cause | Fix |
|---------|--------------|-----|
| `403 error code 1010` from opencode.ai | Cloudflare blocks non-browser clients | Keep the `User-Agent` header on the LLM node |
| `400 MissingSessionID` | `x-opencode-session` header missing | Keep that header on the LLM node |
| Scraper returns 0 jobs | All sources failed | Check `logs`/stderr from the bridge; BA is normally never empty for Munich |
| `scraper_busy` (HTTP 429) | Two workflows scraping at once | Wait for the running scrape, or disable the overlapping trigger |
| `Access to the file is not allowed` | Missing `N8N_RESTRICT_FILE_ACCESS_TO` | Set it to the `cv/` folder (the start script does this) |
| Notion page not created | Token / database id wrong | Re-check the Notion credential and the database id in the Notion nodes |
| `jobspy` module not found | Missing pip install | `pip install -r requirements.txt` |
| Nothing runs at 07:00 | n8n not running, or workflow not activated | Start the services (autostart/watchdog) and activate the workflow |

## Keeping it running (Windows)

`start_n8n.bat` and friends keep both services alive without any hardcoded paths — node, the n8n CLI and the Python
interpreter are auto-detected (override with `SCRAPER_NODE`, `N8N_BIN`, `SCRAPER_PYTHON`).

| Script | What it does |
|--------|--------------|
| `start_n8n.bat` | One-click launcher: starts the bridge, then n8n, and waits until both health endpoints answer (no `taskkill /f /im node.exe` — it never touches unrelated Node processes) |
| `service_control.ps1 -Action start` | The actual start logic (health-gated, logs to `logs/startup.log`) |
| `service_control.ps1 -Action watch` | Watchdog: probes both services and restarts whichever is down (logs to `logs/watchdog.log`) |
| `watchdog.bat` / `watchdog_hidden.vbs` | Silent wrappers so the watchdog leaves no console window |
| `register_tasks.ps1` | Registers the 5-minute watchdog task (`schtasks /sc minute /mo 5`) |

Health endpoints: `http://localhost:3456/health` (bridge) and `http://localhost:5678/healthz` (n8n).

Autostart at logon is a shortcut in the user's Startup folder pointing at `start_hidden.vbs` — creating a logon-trigger
*scheduled task* needs administrator rights, a Startup shortcut does not. The 5-minute watchdog task works with normal
user rights.

Python must have `python-jobspy` installed; the scripts verify `import jobspy` before picking an interpreter.

## Roadmap

- [x] Bundesagentur für Arbeit as primary source
- [x] Internship + defence/military filtering
- [x] Cross-run dedup against Notion
- [x] OpenCode Go (DeepSeek V4 Flash) scoring
- [x] Telegram run summary + error workflow
- [x] English mirror of the workflow
- [x] Windows autostart + 5-minute watchdog (no hardcoded paths)
- [ ] Batch scoring (N jobs per model call) to cut runtime from ~15 min
- [ ] ATS feeds (Greenhouse/Lever/SmartRecruiters/Personio) for a target-company watchlist
- [ ] Application status sync with the personal application tracker database
- [ ] Docker deployment

## Tech stack

- **[n8n](https://n8n.io/)** — workflow automation (self-hosted, free)
- **[Bundesagentur für Arbeit Jobsuche v6](https://github.com/bundesAPI/jobsuche-api)** — primary job source (free API key `jobboerse-jobsuche`)
- **[JobSpy](https://github.com/speedyapply/JobSpy)** — LinkedIn/Indeed scraper (secondary)
- **[OpenCode Go](https://opencode.ai/)** — serves DeepSeek V4 Flash for scoring
- **[Notion API](https://developers.notion.com/)** — job database

## Notes for the published files

- The Telegram nodes in `n8n-job-scraper-workflow_zh.json` ship with a `YOUR_TELEGRAM_CHAT_ID` placeholder — put your own chat id in both Telegram nodes (or delete those nodes if you don't want notifications). The rest of the workflow is byte-identical to the working instance.
- `n8n-job-scraper-workflow_zh.json` (Chinese) and `n8n-job-scraper-workflow_en.json` (English) are the same workflow: identical nodes, connections and logic, with node names, prompts, Telegram messages and sticky notes translated. Use whichever language you prefer.
- The two files carry different `id` values, so importing both gives you two separate workflows instead of one overwriting the other. Activate only one of them (otherwise both run and the second run finds everything already in Notion).

## License

MIT — see [LICENSE](LICENSE)

## Acknowledgments

- **[DailyJobMatch](https://github.com/Yulin27/DailyJobMatch)** — inspired the workflow architecture
- **[bundesAPI/jobsuche-api](https://github.com/bundesAPI/jobsuche-api)** — documented the Bundesagentur endpoints
