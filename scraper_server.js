// Local bridge: n8n (HTTP Request) -> Python scraper (Bundesagentur + JobSpy).
//
//   GET  /health  -> liveness probe (used by the watchdog)
//   POST /        -> body = scraper config JSON, passed straight to scrape_jobs.py
//
// The config (keywords, locations, BA settings, limits) comes from the n8n
// workflow, so the workflow is the single source of truth for search config.
const http = require('http');
const fs = require('fs');
const path = require('path');
const { execFile } = require('child_process');

const PORT = Number(process.env.SCRAPER_PORT || 3456);
const DEFAULT_TIMEOUT_MS = Number(process.env.SCRAPER_TIMEOUT_MS || 300000);
const scraperPath = path.join(__dirname, 'scrape_jobs.py');

// Resolve the interpreter explicitly - the n8n process does not necessarily
// inherit the PATH that has a python with jobspy installed.
const PYTHON_CANDIDATES = [
  process.env.SCRAPER_PYTHON,
  path.join(process.env.LOCALAPPDATA || '', 'hermes', 'hermes-agent', 'venv', 'Scripts', 'python.exe'),
  'python',
].filter(Boolean);

function resolvePython() {
  for (const cand of PYTHON_CANDIDATES) {
    if (cand === 'python') return cand;                 // last resort: PATH lookup
    try { if (fs.existsSync(cand)) return cand; } catch (_) { /* ignore */ }
  }
  return 'python';
}
const PYTHON = resolvePython();

let busy = false;                                        // one scrape at a time
const log = (...a) => console.log(new Date().toISOString(), ...a);

function send(res, status, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(status, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) });
  res.end(body);
}

const server = http.createServer((req, res) => {
  if (req.method === 'GET' && (req.url === '/health' || req.url === '/')) {
    return send(res, 200, { ok: true, python: PYTHON, busy, port: PORT });
  }
  if (req.method !== 'POST') {
    return send(res, 405, { error: 'method_not_allowed', message: 'Use POST with a JSON config body' });
  }
  if (busy) {
    return send(res, 429, { error: 'scraper_busy', message: 'another scrape is still running' });
  }

  let body = '';
  req.on('data', (c) => { body += c; if (body.length > 1e6) req.destroy(); });
  req.on('end', () => {
    let cfg = {};
    const trimmed = (body || '').trim();
    if (trimmed) {
      try { cfg = JSON.parse(trimmed); }
      catch (e) { return send(res, 400, { error: 'invalid_json', message: String(e.message).slice(0, 200) }); }
    }

    const timeout = Number(cfg.scraper_timeout_ms || DEFAULT_TIMEOUT_MS);
    busy = true;
    const started = Date.now();
    log(`scrape start (timeout ${timeout}ms, ba=${!!(cfg.ba && cfg.ba.enabled)}, sites=${JSON.stringify(cfg.sites || [])})`);

    const childEnv = { ...process.env, PYTHONUTF8: '1', PYTHONIOENCODING: 'utf-8' };
    execFile(PYTHON, [scraperPath, JSON.stringify(cfg)],
      { timeout, maxBuffer: 64 * 1024 * 1024, env: childEnv },
      (err, stdout, stderr) => {
        busy = false;
        const took = ((Date.now() - started) / 1000).toFixed(1);
        if (stderr) log(`scraper stderr:\n${stderr.trim().split('\n').slice(-12).join('\n')}`);
        let data = null;
        try { data = JSON.parse(stdout); } catch (_) { data = null; }

        if (err && !data) {
          log(`scrape FAILED after ${took}s: ${err.message}`);
          return send(res, 500, {
            error: 'scraper_failed',
            message: String(err.message).slice(0, 300),
            stderr: String(stderr || '').slice(-800),
          });
        }
        if (!data) {
          log(`scrape FAILED after ${took}s: unparseable output`);
          return send(res, 500, {
            error: 'scraper_unparseable',
            stdout_head: String(stdout || '').slice(0, 500),
            stderr: String(stderr || '').slice(-800),
          });
        }
        if (data.fatal) {                     // the scraper reported a hard failure
          log(`scrape FATAL after ${took}s: ${((data.stats && data.stats.errors) || []).join(' | ')}`);
          return send(res, 500, {
            error: 'scraper_fatal',
            message: (((data.stats && data.stats.errors) || []).join(' | ')).slice(0, 300),
            jobs: [], count: 0,
          });
        }
        log(`scrape done in ${took}s: ${data.count || 0} jobs`);
        return send(res, 200, data);
      });
  });
});

server.listen(PORT, () => log(`${path.basename(scraperPath)} bridge listening on http://localhost:${PORT} (python: ${PYTHON})`));
