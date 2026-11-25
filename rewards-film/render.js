// Renders the film to rewards-film.mp4.  Usage: node render.js [--stills]
const http = require('http'), fs = require('fs'), path = require('path');
const { spawn } = require('child_process');
const { chromium } = require('playwright');

const ROOT = __dirname, FPS = 24, DURATION = 13;
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp' };

// rewards/manifest.json is rebuilt from whatever images are in rewards/
const imgs = fs.readdirSync(path.join(ROOT, 'rewards')).filter(f => /\.(png|jpe?g|webp)$/i.test(f)).sort();
fs.writeFileSync(path.join(ROOT, 'rewards', 'manifest.json'), JSON.stringify(imgs));

const server = http.createServer((req, res) => {
  const p = path.join(ROOT, decodeURIComponent(req.url.split('?')[0]));
  if (!p.startsWith(ROOT) || !fs.existsSync(p) || fs.statSync(p).isDirectory()) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'Content-Type': MIME[path.extname(p)] || 'application/octet-stream' });
  fs.createReadStream(p).pipe(res);
});

(async () => {
  await new Promise(r => server.listen(0, r));
  const url = `http://127.0.0.1:${server.address().port}/index.html`;
  const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
  page.on('pageerror', e => console.error('page error:', e.message));
  page.on('console', m => m.type() === 'error' && console.error('console:', m.text()));
  await page.goto(url);
  await page.waitForFunction('window.ready === true', null, { timeout: 120000 });
  const shot = async i => { await page.evaluate(n => window.renderFrame(n), i); return page.screenshot({ type: 'png' }); };

  if (process.argv.includes('--stills')) {
    fs.mkdirSync(path.join(ROOT, 'stills'), { recursive: true });
    for (const t of [0.6, 1.6, 2.4, 3.3, 4.5, 6.8, 9, 11, 12.2]) {
      fs.writeFileSync(path.join(ROOT, 'stills', `t${t}.png`), await shot(Math.round(t * FPS)));
      console.log('still', t);
    }
  } else {
    const out = path.join(ROOT, 'rewards-film.mp4');
    const ff = spawn('ffmpeg', ['-y', '-v', 'error', '-f', 'image2pipe', '-framerate', String(FPS), '-i', '-',
      '-c:v', 'libx264', '-preset', 'slow', '-crf', '15', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', out], { stdio: ['pipe', 'inherit', 'inherit'] });
    const total = FPS * DURATION;
    for (let i = 0; i < total; i++) {
      if (!ff.stdin.write(await shot(i))) await new Promise(r => ff.stdin.once('drain', r));
      if (i % 24 === 0) console.log(`frame ${i}/${total}`);
    }
    ff.stdin.end(); await new Promise(r => ff.on('close', r));
    console.log('wrote', out);
  }
  await browser.close(); server.close();
})();
