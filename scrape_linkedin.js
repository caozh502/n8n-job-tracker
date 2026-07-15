const puppeteer = require('puppeteer-core');
const chromePath = process.env.CHROME_PATH || 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';

async function main() {
  const browser = await puppeteer.launch({executablePath:chromePath,headless:'new',args:['--no-sandbox','--disable-setuid-sandbox']});
  const page = await browser.newPage();
  await page.setViewport({width:1400,height:900});
  await page.setExtraHTTPHeaders({'Accept-Language':'de-DE,de;q=0.9'});

  const kw = process.argv[2] || 'QA Engineer';
  const loc = process.argv[3] || 'Munich, Germany';
  const url = `https://www.linkedin.com/jobs/search?keywords=${encodeURIComponent(kw)}&location=${encodeURIComponent(loc)}&f_TPR=r86400`;
  console.error('Fetching:', url);
  await page.goto(url,{waitUntil:'networkidle2',timeout:30000});

  // Wait for job results to actually render
  try {
    await page.waitForFunction(
      () => document.querySelectorAll('a[href*="/jobs/view/"]').length >= 3,
      {timeout: 15000}
    );
  } catch(e) {
    console.error('Warning: timed out waiting for job links');
  }
  await new Promise(r => setTimeout(r,2000));

  // Scroll to load more — LinkedIn lazy-loads results in chunks
  let prevCount = 0;
  for (let i = 0; i < 10; i++) {
    await page.evaluate(() => window.scrollBy(0, 800));
    await new Promise(r => setTimeout(r, 1000));
    const current = await page.evaluate(() => {
      const seen = new Set();
      document.querySelectorAll('a[href*="/jobs/view/"]').forEach(a => {
        if (a.href.includes('trk=public_jobs_topcard')) return;
        const m = a.href.match(/-(\d+)(?:\?|$)/);
        if (m) seen.add(m[1]);
      });
      return seen.size;
    });
    if (current > prevCount) {
      prevCount = current;
      console.error(`  Scrolled: ${current} jobs found`);
    } else {
      break; // No new jobs loaded, stop scrolling
    }
  }

  // First pass: collect all job cards with metadata (title, company, location)
  const cards = await page.evaluate(() => {
    const seen = new Set(); const out = [];
    document.querySelectorAll('a[href*="/jobs/view/"]').forEach(a => {
      if (!a.href || a.href.includes('trk=public_jobs_topcard')) return;
      const m = a.href.match(/-(\d+)(?:\?|$)/);
      if (!m || seen.has(m[1])) return; seen.add(m[1]);

      let company = '', location = '';
      const cm = a.href.match(/-at-([^/]+?)-?\d+(?:\?|$)/i);
      if (cm) company = cm[1].replace(/-/g,' ').replace(/\s+/g,' ').trim().replace(/\b\w/g,c=>c.toUpperCase());

      // Try to find location near this link
      const card = a.closest('li, div, [class*="job-card"]');
      if (card) {
        const body = card.textContent.replace(/\s+/g, ' ').trim();
        // Extract Chinese-locale location: "德国 拜恩 城市名"
        let locM = body.match(/德国\s+拜恩\s+(\S+?)(?:\s+|$)/);
        if (locM) location = locM[1];
        else {
          // German-locale: look for "München" or "Munich" near company name
          const cities = ['München','Munich','Berlin','Hamburg','Frankfurt','Stuttgart',
                         'Köln','Düsseldorf','Poing','Ottobrunn','Penzberg','Augsburg',
                         'Nürnberg','Ingolstadt','Regensburg','Erding','Garching',
                         'Unterschleißheim','Neubiberg','Taufkirchen','Ismaning'];
          for (const city of cities) {
            if (body.includes(city)) { location = city; break; }
          }
        }
      }

      out.push({jobId:m[1], title:a.textContent.trim(), company, location, fullLink:`https://www.linkedin.com/jobs/view/${m[1]}/`});
    });
    return out;
  });

  console.error('Found', cards.length, 'jobs');

  // Second pass: visit each job detail page to get descriptions
  const results = [];
  const maxJobs = 30;

  for (let i = 0; i < Math.min(cards.length, maxJobs); i++) {
    const c = cards[i];
    try {
      await page.goto(c.fullLink, {waitUntil:'networkidle2',timeout:15000});
      await new Promise(r => setTimeout(r, 1500));

      const desc = await page.evaluate(() => {
        const el = document.querySelector('.description__text, .show-more-less-html__markup, article');
        let t = el ? el.textContent.trim() : '';
        return t.replace(/\s+/g, ' ').trim().substring(0, 3000);
      });

      results.push({...c, description: desc});
      console.error(`  [${i+1}/${maxJobs}] ${c.title.substring(0,40)} — ${desc.length} chars, loc:${c.location || '?'}`);
    } catch(e) {
      results.push({...c, description: ''});
    }
  }

  console.log(JSON.stringify(results));
  await browser.close();
}
main().catch(e => {console.error('Fatal:',e.message);process.exit(1);});
