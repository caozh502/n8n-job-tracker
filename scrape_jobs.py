#!/usr/bin/env python3
"""
JobSpy-based job scraper — multi-location search + description fetch.
Returns JSON to stdout for the n8n scraper_server to consume.
"""
import json, sys, os, re, math
from jobspy import scrape_jobs

def _s(val):
    """Safely convert pandas value to string, replacing NaN with empty string."""
    if isinstance(val, float) and math.isnan(val):
        return ''
    return str(val) if val is not None else ''

def main():
    keywords = sys.argv[1] if len(sys.argv) > 1 else 'QA Engineer OR Test Automation OR Testingenieur OR Quality Engineer OR HiL OR CI/CD OR Embedded OR DevOps OR Software Test'
    location_hint = sys.argv[2] if len(sys.argv) > 2 else 'Munich, Germany'

    try:
        # Phase 1: Search multiple locations (no descriptions, fast)
        all_rows = []
        seen_urls = set()
        locations = [
            ('Munich, Germany', 24),
            ('Bavaria, Germany', 8),
            ('Baden-Württemberg, Germany', 4),
            ('Germany', 4),
        ]

        for loc, limit in locations:
            jobs = scrape_jobs(
                site_name=["linkedin", "indeed"],
                search_term=keywords,
                location=loc,
                results_wanted=limit,
                hours_old=24,
                country_indeed='germany',
                linkedin_fetch_description=True,
            )
            for _, row in jobs.iterrows():
                url = _s(row.get('job_url'))
                if not url or url in seen_urls:
                    continue
                seen_urls.add(url)
                all_rows.append(row)

    except Exception as e:
        print(json.dumps({"error": str(e), "jobs": []}))
        sys.exit(1)

    results = []
    for row in all_rows:
        title = _s(row.get('title'))
        company = _s(row.get('company'))
        location = _s(row.get('location'))
        desc = _s(row.get('description'))
        site = _s(row.get('site'))
        job_type = _s(row.get('job_type')).lower()
        job_url = _s(row.get('job_url'))
        date = _s(row.get('date_posted'))

        # Filter: skip part-time/contract/internship
        PART_TIME = ['parttime', 'part-time', 'contract', 'temporary', 'internship', '实习']
        if job_type and any(pt in job_type for pt in PART_TIME):
            continue

        job_id = ''
        for pattern in [r'/jobs/view/(\d+)', r'/_(\d+)', r'/job/(\d+)']:
            m = re.search(pattern, job_url)
            if m:
                job_id = m.group(1)
                break
        if not job_id:
            job_id = str(hash(job_url))[-10:]

        results.append({
            "jobId": job_id,
            "title": title,
            "company": company,
            "location": location.replace('·', ',').strip() if '·' in location else location,
            "description": desc[:3000] if desc else '',
            "fullLink": job_url,
            "site": site,
            "postedTime": date,
        })

    print(json.dumps({"count": len(results), "jobs": results}))

if __name__ == '__main__':
    main()
