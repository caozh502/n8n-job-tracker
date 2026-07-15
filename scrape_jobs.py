#!/usr/bin/env python3
"""
JobSpy-based job scraper — replacement for Puppeteer LinkedIn scraper.
Returns JSON to stdout for the n8n scraper_server to consume.
"""
import json, sys, os, re
from jobspy import scrape_jobs

def main():
    keywords = sys.argv[1] if len(sys.argv) > 1 else 'QA Engineer OR Test Automation OR Testingenieur OR Quality Engineer OR HiL OR CI/CD OR Embedded OR DevOps OR Software Test'
    location = sys.argv[2] if len(sys.argv) > 2 else 'Munich, Bavaria, Baden-Württemberg, Germany'

    try:
        jobs = scrape_jobs(
            site_name=["linkedin", "indeed"],
            search_term=keywords,
            location=location,
            results_wanted=60,
            hours_old=24,
            country_indeed='germany',
            linkedin_fetch_description=True,
        )
    except Exception as e:
        print(json.dumps({"error": str(e), "jobs": []}))
        sys.exit(1)

    results = []
    for _, row in jobs.iterrows():
        title = str(row.get('title', '') or '')
        company = str(row.get('company', '') or '')
        location = str(row.get('location', '') or '')
        desc = str(row.get('description', '') or '')
        site = str(row.get('site', '') or '')
        job_type = str(row.get('job_type', '') or '').lower()
        job_url = str(row.get('job_url', '') or '')
        date = str(row.get('date_posted', '') or '')
        # Handle NaN from pandas
        for var in ['title', 'company', 'location', 'desc', 'site', 'job_type', 'job_url', 'date']:
            val = locals()[var]
            if val.lower() == 'nan':
                locals()[var] = ''

        # Filter: skip part-time/contract/internship; keep if unknown
        PART_TIME = ['parttime', 'part-time', 'contract', 'temporary', 'internship', '实习']
        if job_type and any(pt in job_type for pt in PART_TIME):
            continue

        # Extract job ID from URL
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
