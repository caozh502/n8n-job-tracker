// 本地服务：接收 n8n HTTP 请求，执行 JobSpy 抓取 LinkedIn + Indeed 岗位
const http = require('http');
const { execFile } = require('child_process');
const path = require('path');

const PORT = process.env.SCRAPER_PORT || 3456;
const scraperPath = path.join(__dirname, 'scrape_jobs.py');

const server = http.createServer((req, res) => {
  res.setHeader('Content-Type', 'application/json');
  
  if (req.method !== 'POST') {
    res.end(JSON.stringify({ error: 'Use POST' }));
    return;
  }

  let body = '';
  req.on('data', chunk => body += chunk);
  req.on('end', () => {
    let params;
    try { params = JSON.parse(body); } 
    catch(e) { res.end(JSON.stringify({ error: 'Invalid JSON' })); return; }

    const keywords = params.keywords || 'QA Engineer';
    const location = params.location || 'Munich';

    console.log(`Scraping: ${keywords} in ${location}`);

    execFile('python', [scraperPath, keywords, location], {
      timeout: 120000,
    }, (err, stdout, stderr) => {
      if (err) {
        console.error('Scraper error:', stderr);
        res.end(JSON.stringify({ error: err.message, stderr: stderr.substring(0, 500) }));
        return;
      }
      try {
        const data = JSON.parse(stdout);
        res.end(JSON.stringify({ count: data.count || data.jobs?.length || 0, jobs: data.jobs || data }));
      } catch(e) {
        res.end(JSON.stringify({ error: 'Parse failed', raw: stdout.substring(0, 500) }));
      }
    });
  });
});

server.listen(PORT, () => {
  console.log(`JobSpy scraper server on http://localhost:${PORT}`);
});
