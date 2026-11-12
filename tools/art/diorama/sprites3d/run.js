// node run.js jobs.json outdir：一张张拍精灵，存成 outdir/<id>.png（bake.py 写 jobs.json）。
// 要 tools/art 下有 http 服务（python3 -m http.server 8765）；没有就自己起一个。
const { chromium } = require('playwright');
const fs = require('fs'), path = require('path'), http = require('http'), { spawn } = require('child_process');
const PORT = 8765, ART = path.resolve(__dirname, '../..');
const URL = `http://localhost:${PORT}/diorama/sprites3d/page.html`;
const up = () => new Promise((ok) => http.get(URL, (r) => { r.resume(); ok(r.statusCode === 200); }).on('error', () => ok(false)));
(async () => {
  const [jobsPath, outDir] = process.argv.slice(2);
  const jobs = JSON.parse(fs.readFileSync(jobsPath, 'utf8'));
  fs.mkdirSync(outDir, { recursive: true });
  let srv = null;
  if (!(await up())) {
    srv = spawn('python3', ['-m', 'http.server', String(PORT)], { cwd: ART, stdio: 'ignore' });
    for (let i = 0; i < 50 && !(await up()); i++) await new Promise((r) => setTimeout(r, 100));
  }
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  const p = await b.newPage({ viewport: { width: 800, height: 600 } });
  p.on('console', (m) => { if (m.type() === 'error' || m.type() === 'warning') console.log('[page]', m.text()); });
  p.on('pageerror', (e) => { console.log('[err]', e.message); process.exit(1); });
  await p.goto(URL + '?v=' + Date.now());
  await p.waitForFunction(() => window.READY, null, { timeout: 60000 });
  const t0 = Date.now();
  for (let i = 0; i < jobs.length; i++) {
    const url = await p.evaluate((j) => window.renderJob(j), jobs[i]);
    const urls = Array.isArray(url) ? url : [url];
    const names = [jobs[i].id + '.png', jobs[i].id + '.catch.png'];
    urls.forEach((u, k) => fs.writeFileSync(path.join(outDir, names[k]), Buffer.from(u.split(',')[1], 'base64')));
    if ((i + 1) % 10 === 0) console.log(`${i + 1}/${jobs.length}  ${((Date.now() - t0) / (i + 1)).toFixed(0)} ms/张`);
  }
  console.log(`${jobs.length} 张 ${((Date.now() - t0) / 1000).toFixed(1)} s`);
  await b.close();
  if (srv) srv.kill();
})();
