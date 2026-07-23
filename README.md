# 🤖 n8n Job Tracker — LinkedIn/Indeed + DeepSeek + Notion

> Automated daily job search: scrape LinkedIn & Indeed → AI score with DeepSeek → save to Notion

[![n8n](https://img.shields.io/badge/n8n-2.30-blue?logo=n8n)](https://n8n.io)
[![Python](https://img.shields.io/badge/Python-3.10+-blue?logo=python)](https://python.org)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

## Overview

An n8n workflow that runs daily to:

1. **🔍 Scrape** the latest job postings from LinkedIn (via [JobSpy](https://github.com/speedyapply/JobSpy) — 4 region searches: Munich, Bavaria, Baden-Württemberg, Germany-wide)  
2. **🤖 Score** each job against your CV using DeepSeek LLM (7-dimension scoring: background, skills, experience, seniority, language, location, bonus)  
3. **📝 Save** the Top 10 matches to a Notion database with scores and match reasons

**Key features:**
- 🚫 Defense/Aerospace jobs automatically filtered out (citizenship restriction)
- 🚗 Automotive roles get -5 penalty on background match
- 📍 4-region search with 6:2:1:1 ratio (Munich : Bavaria : BW : Germany)
- 🌐 Bilingual: English & 中文 workflow files

### Language Versions

| File | Language |
|------|----------|
| `n8n-job-scraper-workflow_en.json` | English (node names, prompts, comments) |
| `n8n-job-scraper-workflow_zh.json` | 中文 (Chinese node names, prompts, comments) |

Both workflows are functionally identical. Import whichever suits your preference.

## Architecture

```
⏰ → 📄 Read CV.pdf → 📄 Extract PDF Text → 📄 Structure CV Text
    → 🔍 Search Config → 🌐 Scrape LinkedIn + Indeed (JobSpy, 4 regions)
    → 📋 Parse Job List → ✂️ Split Items → 🔄 Process Each Job (scoring loop)
        │
        ├── main[0] (loop): ✍️ Prepare Prompt → 🧠 LLM Chain → 📊 Parse Score → ↻
        │                                    │
        │                                    └──ai──▶ 🧠 DeepSeek
        │
        └── main[1] (done): 📊 Sort + Top10 (auto-filters Defense) → 🔄 Write Each
                                                                    │
                                                               🔝 Tier 1 (≥75) → 📝 Notion ⭐
                                                                    │ false
                                                               🔝 Tier 2 (≥60) → 📝 Notion 💪
                                                                    │ false
                                                                ⏭️ Skip
```

## Prerequisites

| Requirement | Version / Notes |
|-------------|----------------|
| [Python](https://www.python.org/) | >= 3.10 |
| [n8n](https://docs.n8n.io/hosting/installation/) | 2.30+ (self-hosted, npm install) |
| [DeepSeek](https://platform.deepseek.com/) API Key | Paid account |
| [Notion](https://www.notion.so/) Account | Free tier — create an internal integration |

## Quick Start

### 1. Clone & Install

```bash
git clone https://github.com/caozh502/n8n-job-tracker.git
cd n8n-job-tracker
pip install -r requirements.txt
```

### 2. Place Your CV

Put `CV.pdf` in the `cv/` folder. The workflow reads it automatically.

### 3. Start the Scraper Server

```bash
python scrape_jobs.py
# Or on Windows: double-click start_n8n.bat
```

### 4. Start n8n

```bash
# On Windows — requires N8N_RESTRICT_FILE_ACCESS_TO to read cv/ folder
set N8N_RESTRICT_FILE_ACCESS_TO=./cv
n8n start --port=5678
```

Or use the included `start_n8n.bat` which handles both steps.

### 5. Configure Credentials in n8n

Open `http://localhost:5678` in your browser, then:

| Credential | Type | What to enter |
|-----------|------|---------------|
| **DeepSeek** | `DeepSeek API` | Your DeepSeek API key |
| **Notion** | `Notion API` | Internal Integration Token |

### 6. Import the Workflow

1. Create a new workflow in n8n
2. **Import from File** → select one of:
   - `n8n-job-scraper-workflow_en.json` (English)
   - `n8n-job-scraper-workflow_zh.json` (中文)
3. Wire up the DeepSeek and Notion credentials when prompted
4. **Save** and **Execute Workflow**

## Project Structure

```
n8n-job-tracker/
├── n8n-job-scraper-workflow_en.json    # Main workflow (English)
├── n8n-job-scraper-workflow_zh.json    # Main workflow (中文)
├── scrape_jobs.py                      # JobSpy scraper → LinkedIn + Indeed
├── scraper_server.js                   # Local HTTP wrapper (n8n → Python bridge)
├── start_n8n.bat                       # One-click launcher (Windows)
├── notion_database_template.md         # Notion DB schema reference
├── requirements.txt                    # Python dependencies
├── README.md
├── .env.example                        # Environment variable template
├── .gitignore
├── cv/                                 # Place your CV.pdf here
└── LICENSE
```

## How the Scoring Works

DeepSeek evaluates each job against your CV across **7 dimensions** (100 total):

| Dimension | Weight | Description |
|-----------|--------|-------------|
| background_match | 0–10 | Domain / industry alignment (Automotive: -5) |
| skills_overlap | 0–25 | Technical skills match |
| experience_relevance | 0–25 | Project / role relevance |
| seniority | 0–10 | Seniority level fit |
| language_requirement | 0–10 | Language skills match |
| location_match | 0–10 | Geography preference |
| bonus | 0–10 | Company reputation, growth potential, perks |

**Total:** 100 (background_match + skills_overlap + experience_relevance + seniority + language_requirement + location_match + bonus)

**Defense/Aerospace jobs** are fully filtered out before sorting — they will never appear in your Top 10.

**Tier thresholds:**
- ★ **Highly Match** ≥ 75
- 💪 **Can Try** ≥ 60
- ❌ **Skip** < 60

### CV Processing

The workflow reads your CV (PDF) via `Read/Write Files from Disk`, extracts text with `Extract from File`, then passes the raw text directly to DeepSeek during scoring. No intermediate AI summarization.

### Multi-Region Search

4 separate LinkedIn searches are performed and deduplicated:

| Region | Results per search |
|--------|-------------------|
| Munich area | 24 |
| Bavaria | 8 |
| Baden-Württemberg | 4 |
| Germany-wide | 4 |

Approximately **30-40 unique jobs** after deduplication, all with full descriptions.

## Notion Database Schema

| Column | Type | Description |
|--------|------|-------------|
| Job Title | Title | Job title from LinkedIn |
| Company | Rich Text | Company name |
| Location | Select | Job location |
| Industry | Select | Auto-categorised industry |
| Score | Number | DeepSeek overall score (0–100) |
| Link | URL | Original LinkedIn job posting |
| Posted | Date | Posting date |
| Match Reason | Rich Text | AI-generated match rationale |

## Environment Variables

n8n supports `$env.VAR_NAME` expressions. Copy `.env.example` to `.env` and configure:

| Variable | Purpose |
|----------|---------|
| `N8N_RESTRICT_FILE_ACCESS_TO` | Allow n8n to read `cv/` folder (e.g. `./cv`) |
| `SCRAPER_PORT` | Scraper server port (default: 3456) |

> API keys (DeepSeek, Notion) are stored in n8n's credential system, not in this repo.

## Auto-Scheduling

1. Open the workflow in n8n
2. Click **Workflow Settings** (top-right)
3. Toggle **Active** to enable scheduled execution
4. The Schedule Trigger runs daily (configurable)

## Troubleshooting

| Problem | Likely Cause | Fix |
|---------|-------------|-----|
| Scraper returns 0 jobs | LinkedIn guest rate limit | Wait a few minutes, try again |
| `Access to the file is not allowed` | Missing `N8N_RESTRICT_FILE_ACCESS_TO` | Set env var or use `start_n8n.bat` |
| DeepSeek score is 0 | API key not configured | Check n8n credentials |
| Notion page not created | API token / DB ID wrong | Verify Notion integration token |
| `jobspy` module not found | Missing pip install | `pip install python-jobspy` |
| Loop runs only once | SplitInBatches wiring | See n8n loops documentation |

## Tech Stack

- **[n8n](https://n8n.io/)** — Workflow automation (self-hosted, free)
- **[JobSpy](https://github.com/speedyapply/JobSpy)** — Python job scraper (LinkedIn + Indeed)
- **[DeepSeek](https://platform.deepseek.com/)** — LLM for job scoring
- **[Notion API](https://developers.notion.com/)** — Job database storage

## Roadmap

- [x] LinkedIn job scraping (JobSpy)
- [x] Multi-region search with dedup
- [x] AI scoring with DeepSeek
- [x] Defense industry auto-filter
- [x] Automotive penalty deduction
- [x] Notion integration
- [x] Two-tier ranking system (⭐ / 💪)
- [x] Bilingual workflows (EN / 中文)
- [ ] Google Jobs support
- [ ] Daily email digest
- [ ] StepStone / Indeed DE support
- [ ] Docker deployment

## License

MIT — See [LICENSE](LICENSE)

## Contributing

PRs welcome! If you find a bug or have a feature idea, open an issue first.

---

*Built with [JobSpy](https://github.com/speedyapply/JobSpy) & [n8n Official Skills](https://github.com/n8n-io/skills).*

## Acknowledgments

- **[DailyJobMatch](https://github.com/Yulin27/DailyJobMatch)** — This project was inspired by and references their workflow architecture for job scraping, scoring, and Notion integration.
