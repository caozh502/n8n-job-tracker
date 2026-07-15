# 🤖 n8n Job Tracker — LinkedIn + DeepSeek + Notion

> Automated daily job search: scrape LinkedIn → AI score with DeepSeek → save to Notion

[![n8n](https://img.shields.io/badge/n8n-2.30-blue?logo=n8n)](https://n8n.io)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)]()

## Overview

An n8n workflow that runs daily to:

1. **🔍 Scrape** the latest LinkedIn job postings (Munich area, 24h filter) using Puppeteer
2. **🤖 Score** each job against your CV using DeepSeek LLM (6-dimension scoring: skills, experience, seniority, language, location, industry)
3. **📝 Save** top matches to a Notion database with scores and match reasons

**Output:** 15 best-matching jobs per day, ranked by score with match reasons.

### Language Versions

| File | Language |
|------|----------|
| `n8n-job-scraper-workflow_en.json` | English (node names, prompts, comments) |
| `n8n-job-scraper-workflow_zh.json` | 中文 (Chinese node names, prompts, comments) |

Both workflows are functionally identical. Import whichever suits your preference.

## Architecture

```
┌─────────────┐    ┌──────────────────┐    ┌──────────────┐
│  Puppeteer   │───▶│  DeepSeek LLM    │───▶│   Notion DB  │
│  scrape      │    │  score + rank    │    │   save       │
│  LinkedIn    │    │                  │    │              │
└─────────────┘    └──────────────────┘    └──────────────┘
       ▲                                        │
       │        ┌──────────────────┐             │
       └────────│  scraper_server  │◄────────────┘
                │  (local HTTP)    │
                └──────────────────┘
```

## Prerequisites

| Requirement | Version / Notes |
|-------------|----------------|
| [Node.js](https://nodejs.org/) | >= 18 |
| [n8n](https://docs.n8n.io/hosting/installation/) | 2.30+ (self-hosted) |
| [Google Chrome](https://www.google.com/chrome/) | Installed (for Puppeteer) |
| [DeepSeek](https://platform.deepseek.com/) API Key | Paid account |
| [Notion](https://www.notion.so/) Account | Free tier works — create an internal integration |

## Quick Start

### 1. Clone & Install

```bash
git clone https://github.com/your-username/n8n-job-tracker.git
cd n8n-job-tracker
npm install
```

### 2. Start n8n

```bash
n8n start --port=5678
```

### 3. Start the Scraper Server

```bash
node scraper_server.js
```

The scraper server runs on `http://localhost:3456` and acts as a bridge between n8n and Puppeteer.

### 4. Configure Credentials in n8n

Open `http://localhost:5678` in your browser, then:

| Credential | Type | What to enter |
|-----------|------|---------------|
| **DeepSeek** | `DeepSeek API` | Your DeepSeek API key |
| **Notion** | `Notion API` | Internal Integration Token |

### 5. Import the Workflow

1. Create a new workflow in n8n
2. **Import from File** → select `n8n-job-scraper-workflow.json`
3. Wire up the credentials to the nodes that ask for them
4. **Save** and **Execute Workflow**

### 6. Customise Your CV

Edit the **📄 读取 CV (PDF/TXT)** Code node in the workflow and replace the placeholder CV text with your actual profile. This text is what DeepSeek uses to match against job descriptions.

## Project Structure

```
n8n-job-tracker/
├── n8n-job-scraper-workflow_en.json    # Main workflow (English)
├── n8n-job-scraper-workflow_zh.json    # Main workflow (中文)
├── scrape_linkedin.js               # Puppeteer scraper — opens LinkedIn, extracts jobs + descriptions
├── scraper_server.js                # Local HTTP server wrapping the scraper
├── run_scrape.bat                   # Batch wrapper for the scraper (Windows)
├── notion_database_template.md      # Notion DB schema reference
├── README.md
├── .env.example                     # Environment variable template
├── .gitignore
├── cv/                              # Place your CV.pdf here
└── package.json
```

## How the Scoring Works

DeepSeek evaluates each job against your CV across **7 dimensions** (0–100 total):

| Dimension | Weight | Description |
|-----------|--------|-------------|
| background_match | 0–10 | Domain / industry alignment |
| skills_overlap | 0–25 | Technical skills match |
| experience_relevance | 0–25 | Project / role relevance |
| seniority | 0–10 | Seniority level fit |
| language_requirement | 0–10 | Language skills match |
| location_match | 0–10 | Geography preference |
| bonus | 0–10 | Company reputation, perks, growth |

**Tier thresholds:**
- ★ **Highly Match** ≥ 75
- 💪 **Can Try** ≥ 60
- ❌ **Skip** < 60

## Notion Database Schema

The workflow writes to a Notion database with these columns:

| Column | Type | Description |
|--------|------|-------------|
| Job Title | Title | Job title from LinkedIn |
| Company | Rich Text | Company name |
| Location | Rich Text | Job location |
| Industry | Rich Text | Auto-categorised industry |
| Score | Number | DeepSeek overall score (0–100) |
| Link | URL | Original LinkedIn job posting |
| Posted | Date | Posting date |
| Match Reason | Rich Text | AI-generated match rationale |

## Environment Variables

n8n supports `$env.VAR_NAME` expressions. Copy `.env.example` to `.env` and configure:

```bash
# Chrome path (required for Puppeteer)
CHROME_PATH=C:\Program Files\Google\Chrome\Application\chrome.exe

# Scraper server port
SCRAPER_PORT=3456
```

> **Note:** DeepSeek and Notion API keys are stored in n8n's built-in credential system, not in this repo. They are not exposed in the workflow export.

## Auto-Scheduling

The workflow includes a **Schedule Trigger** node. To run daily:
1. Open the workflow in n8n
2. Click **Workflow Settings** (top-right)
3. Toggle **Active** to enable scheduled execution

The trigger is set to run daily (configurable in the Schedule Trigger node).

## Troubleshooting

| Problem | Likely Cause | Fix |
|---------|-------------|-----|
| Scraper returns 0 jobs | LinkedIn guest rate limit | Wait a few minutes, try again |
| DeepSeek score is 0 | API key not configured | Check n8n credentials for DeepSeek |
| Notion page not created | API token / DB ID wrong | Verify Notion integration token |
| Loop runs only once | SplitInBatches wiring | See [n8n Loops Skill](https://github.com/n8n-io/skills) |
| `localhost:3456` refused | Scraper server not running | `node scraper_server.js` |

## Tech Stack

- **[n8n](https://n8n.io/)** — Workflow automation (self-hosted, free)
- **[DeepSeek](https://platform.deepseek.com/)** — LLM for job scoring
- **[Puppeteer](https://pptr.dev/)** — Headless Chrome for LinkedIn scraping
- **[Notion API](https://developers.notion.com/)** — Job database storage
- **[n8n Official Skills](https://github.com/n8n-io/skills)** — Best practices for n8n workflow design

## Roadmap

- [x] LinkedIn job scraping with Puppeteer
- [x] AI scoring with DeepSeek
- [x] Notion integration
- [x] Two-tier ranking system
- [ ] Support for multiple search keywords
- [ ] Daily email digest
- [ ] Indeed / StepStone support
- [ ] Docker deployment

## License

MIT — See [LICENSE](LICENSE)

## Contributing

PRs welcome! If you find a bug or have a feature idea, open an issue first.

---

*Built with [n8n Official Skills](https://github.com/n8n-io/skills) for workflow best practices.*
