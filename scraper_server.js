// 本地服务：接收 n8n HTTP 请求，执行 Puppeteer 抓取 LinkedIn 岗位
const http = require('http');
const { execFile } = require('child_process');
const path = require('path');

const PORT = process.env.SCRAPER_PORT || 3456;
const scraperPath = path.join(__dirname, 'scrape_linkedin.js');

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

    execFile('node', [scraperPath, keywords, location], {
      timeout: 180000,
      env: { ...process.env, NODE_PATH: path.join(__dirname, 'node_modules') }
    }, (err, stdout, stderr) => {
      if (err) {
        console.error('Scraper error:', stderr);
        res.end(JSON.stringify({ error: err.message, stderr }));
        return;
      }
      try {
        const jobs = JSON.parse(stdout);
        res.end(JSON.stringify({ count: jobs.length, jobs }));
      } catch(e) {
        res.end(JSON.stringify({ error: 'Parse failed', raw: stdout.substring(0, 500) }));
      }
    });
  });
});

server.listen(PORT, () => {
  console.log(`LinkedIn scraper server on http://localhost:${PORT}`);
});
