#!/usr/bin/env python3
"""
Job scraper for the n8n job-tracker.

Sources
  1. Bundesagentur fuer Arbeit Jobsuche v6  (primary - official-ish, no signup, stable)
  2. LinkedIn + Indeed via JobSpy           (secondary - rate limited, treated as best effort)

Config is a JSON object passed as argv[1] (or on stdin). Output is a single JSON
object on stdout: {"count": N, "jobs": [...], "stats": {...}}.
Logs go to stderr so stdout stays machine-parseable.
"""
import base64
import html
import json
import math
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

# Windows quirk: when stdout is a pipe (spawned by the bridge) Python uses the ANSI code
# page (e.g. GBK) and printing non-ASCII ("München") raises UnicodeEncodeError, which made
# the whole run return 0 jobs. Force UTF-8 before anything writes output.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass

BA_BASE = "https://rest.arbeitsagentur.de/jobboerse/jobsuche-service"
BA_HEADERS = {
    "X-API-Key": "jobboerse-jobsuche",
    "Accept": "application/json",
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                  "(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
}

DEFAULT_CFG = {
    "keywords": "QA Engineer OR Test Automation OR Testingenieur OR Quality Engineer OR HiL OR CI/CD OR Embedded OR DevOps OR Software Test",
    "hours_old": 24,
    "max_total": 45,
    "sites": ["linkedin", "indeed"],
    "locations": [["Munich, Germany", 12], ["Bavaria, Germany", 4],
                  ["Baden-Württemberg, Germany", 2], ["Germany", 2]],
    "timeout_s": 90,
    "ba": {
        "enabled": True,
        "terms": ["Testautomatisierung", "Test Engineer", "QA Engineer", "Software Test",
                  "HiL", "Embedded Software", "DevOps Engineer"],
        "location": "München",
        "radius_km": 30,
        "per_term": 12,
        "limit": 22,
        "detail_limit": 22,
    },
}


def log(msg):
    print(f"[scraper] {msg}", file=sys.stderr, flush=True)


def _s(val):
    """pandas/None/NaN safe string."""
    if val is None:
        return ""
    if isinstance(val, float) and math.isnan(val):
        return ""
    return str(val)


def clean_html(raw):
    if not raw:
        return ""
    txt = re.sub(r"<br\s*/?>|</p>|</li>", "\n", raw, flags=re.I)
    txt = re.sub(r"<[^>]+>", " ", txt)
    return re.sub(r"[ \t]+", " ", html.unescape(txt)).strip()


def load_cfg():
    raw = sys.argv[1] if len(sys.argv) > 1 else ""
    if not raw or raw == "-":
        raw = sys.stdin.read()
    cfg = json.loads(json.dumps(DEFAULT_CFG))          # deep copy
    if raw.strip():
        try:
            user = json.loads(raw)
        except Exception as exc:                        # malformed config must not kill the run
            log(f"config parse failed ({exc}); falling back to defaults")
            user = {}
        if isinstance(user, dict):
            for k, v in user.items():
                if k == "ba" and isinstance(v, dict):
                    cfg["ba"].update(v)
                else:
                    cfg[k] = v
    return cfg


# --------------------------------------------------------------------------- BA

def ba_search(term, cfg, timeout):
    import requests
    ba = cfg["ba"]
    url = (f"{BA_BASE}/pc/v6/jobs?was={term}&wo={ba['location']}"
           f"&umkreis={ba['radius_km']}&size={ba['per_term']}&page=1&angebotsart=1")
    resp = requests.get(url, headers=BA_HEADERS, timeout=timeout)
    resp.raise_for_status()
    return resp.json().get("ergebnisliste", []) or []


def ba_detail(refnr, timeout):
    import requests
    url = f"{BA_BASE}/pc/v4/jobdetails/" + base64.b64encode(refnr.encode()).decode()
    resp = requests.get(url, headers=BA_HEADERS, timeout=timeout)
    resp.raise_for_status()
    return resp.json()


def fetch_ba(cfg, stats):
    ba = cfg["ba"]
    timeout = min(int(cfg.get("timeout_s", 90)), 60)
    seen, rows = set(), []
    for term in ba["terms"]:
        try:
            for it in ba_search(term, cfg, timeout):
                refnr = _s(it.get("referenznummer"))
                if not refnr or refnr in seen:
                    continue
                if _s(it.get("stellenangebotsart")).upper() not in ("", "ARBEIT"):
                    continue
                seen.add(refnr)
                rows.append((refnr, it))
        except Exception as exc:                       # one bad term must not kill the source
            msg = f"BA search '{term}' failed: {type(exc).__name__}: {exc}"
            log(msg)
            stats["errors"].append(msg)
    log(f"BA search: {len(rows)} unique postings")
    rows = rows[: int(ba["limit"])]

    # descriptions are only fetched for the shortlist (one detail call per posting)
    details = {}
    detail_rows = rows[: int(ba["detail_limit"])]
    if detail_rows:
        with ThreadPoolExecutor(max_workers=6) as pool:
            futs = {pool.submit(ba_detail, refnr, timeout): refnr for refnr, _ in detail_rows}
            for fut in as_completed(futs, timeout=timeout * 2):
                refnr = futs[fut]
                try:
                    details[refnr] = fut.result()
                except Exception as exc:
                    log(f"BA detail {refnr} failed: {type(exc).__name__}: {exc}")

    jobs = []
    for refnr, it in rows:
        det = details.get(refnr, {}) or {}
        locs = it.get("stellenlokationen") or det.get("stellenlokationen") or []
        adr = (locs[0].get("adresse") if locs else {}) or {}
        loc = ", ".join([p for p in (_s(adr.get("ort")), _s(adr.get("region")).title()) if p])
        desc = clean_html(_s(det.get("stellenangebotsBeschreibung")))
        if not desc:
            desc = " ".join(filter(None, [_s(it.get("hauptberuf")), clean_html(_s(it.get("alleBerufe")))]))
        jobs.append({
            "jobId": "ba:" + refnr,
            "title": _s(it.get("stellenangebotsTitel")),
            "company": _s(it.get("firma")) or _s(det.get("arbeitgeber")),
            "location": loc,
            "description": desc[:3000],
            "fullLink": _s(it.get("externeURL")) or
                        "https://www.arbeitsagentur.de/jobsuche/jobdetail/" + refnr,
            "site": "arbeitsagentur",
            "postedTime": _s(it.get("datumErsteVeroeffentlichung")),
            "remote": bool(it.get("homeofficemoeglich")),
        })
    stats["arbeitsagentur"] = len(jobs)
    log(f"BA: {len(jobs)} jobs normalized ({len(details)} with description)")
    return jobs


# ---------------------------------------------------------------------- JobSpy

def fetch_jobspy(cfg, stats):
    try:
        from jobspy import scrape_jobs
    except Exception as exc:
        msg = f"jobspy import failed: {exc}"
        log(msg)
        stats["errors"].append(msg)
        return []

    timeout = int(cfg.get("timeout_s", 90))
    keywords = cfg.get("keywords", "")
    hours_old = int(cfg.get("hours_old", 24))
    sites = cfg.get("sites", ["linkedin", "indeed"])

    def one_location(loc, limit):
        return scrape_jobs(
            site_name=sites,
            search_term=keywords,
            location=loc,
            results_wanted=limit,
            hours_old=hours_old,
            country_indeed="germany",
            linkedin_fetch_description=True,
        )

    frames, seen = [], set()
    for loc, limit in cfg.get("locations", []):
        try:
            with ThreadPoolExecutor(max_workers=1) as pool:
                fut = pool.submit(one_location, loc, limit)
                jobs = fut.result(timeout=timeout)     # a hung scrape is abandoned, not fatal
            n = 0
            for _, row in jobs.iterrows():
                url = _s(row.get("job_url"))
                if not url or url in seen:
                    continue
                seen.add(url)
                frames.append(row)
                n += 1
            log(f"jobspy {loc}: {n} new rows")
        except Exception as exc:                       # per-location isolation
            msg = f"jobspy '{loc}' failed: {type(exc).__name__}: {exc}"
            log(msg)
            stats["errors"].append(msg)

    out = []
    part_time = ("parttime", "part-time", "contract", "temporary", "internship")
    for row in frames:
        job_type = _s(row.get("job_type")).lower()
        if job_type and any(pt in job_type for pt in part_time):
            continue
        url = _s(row.get("job_url"))
        site = _s(row.get("site")) or "other"
        job_id = ""
        for pattern in (r"/jobs/view/(\d+)", r"/_(\d+)", r"/job/(\d+)"):
            m = re.search(pattern, url)
            if m:
                job_id = m.group(1)
                break
        if not job_id:
            job_id = str(abs(hash(url)))[-12:]
        out.append({
            "jobId": f"{site}:{job_id}",
            "title": _s(row.get("title")),
            "company": _s(row.get("company")),
            "location": _s(row.get("location")).replace("·", ",").strip(),
            "description": _s(row.get("description"))[:3000],
            "fullLink": url,
            "site": site,
            "postedTime": _s(row.get("date_posted")),
        })
    stats["jobspy"] = len(out)
    for site in sites:
        stats[site] = sum(1 for j in out if j["site"] == site)
    log(f"jobspy: {len(out)} jobs normalized")
    return out


# ------------------------------------------------------------------------- main

_LEGAL = re.compile(r"\b(gmbh|mbh|ag|kg|kgaa|ohg|ug|se|co|inc|ltd|llc|sarl|bv|nv|plc|gruppe|group)\b\.?", re.I)


def norm_company(name):
    """'imbus AG' and 'imbus' must dedupe as the same employer."""
    return re.sub(r"\s+", " ", _LEGAL.sub(" ", (name or "").lower())).strip(" .,-")


def dedupe(jobs):
    """Dedupe by normalized link, then by (title, normalized company)."""
    seen_link, seen_tc, out = set(), set(), []
    for j in jobs:
        link = (j.get("fullLink") or "").split("?")[0].rstrip("/").lower()
        tc = ((j.get("title") or "").lower().strip(), norm_company(j.get("company")))
        if link and link in seen_link:
            continue
        if tc in seen_tc:
            continue
        if link:
            seen_link.add(link)
        seen_tc.add(tc)
        out.append(j)
    return out


def main():
    started = time.time()
    cfg = load_cfg()
    stats = {"errors": [], "elapsed_s": 0}
    jobs = []

    if cfg.get("ba", {}).get("enabled"):
        try:
            jobs += fetch_ba(cfg, stats)
        except Exception as exc:
            msg = f"BA source failed: {type(exc).__name__}: {exc}"
            log(msg)
            stats["errors"].append(msg)

    if cfg.get("sites"):
        try:
            jobs += fetch_jobspy(cfg, stats)
        except Exception as exc:
            msg = f"jobspy source failed: {type(exc).__name__}: {exc}"
            log(msg)
            stats["errors"].append(msg)

    jobs = dedupe([j for j in jobs if j.get("title") and j.get("fullLink")])
    jobs = jobs[: int(cfg.get("max_total", 45))]
    stats["total"] = len(jobs)
    stats["elapsed_s"] = round(time.time() - started, 1)
    log(f"done: {len(jobs)} jobs in {stats['elapsed_s']}s; errors={len(stats['errors'])}")
    print(json.dumps({"count": len(jobs), "jobs": jobs, "stats": stats}, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:          # always emit JSON for the bridge, but fail loudly
        import traceback
        msg = f"fatal: {type(exc).__name__}: {exc}"
        print(json.dumps({"count": 0, "jobs": [], "fatal": True,
                          "stats": {"errors": [msg]}}))
        print(f"[scraper] {msg}", file=sys.stderr, flush=True)
        print(traceback.format_exc(), file=sys.stderr, flush=True)
        sys.exit(2)
