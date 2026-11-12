// 出分层贴图（微缩模型画风）：node bake.js [trees far mid places fore …] [--only 名字] [--S 2]
// 先在 tools/art 下起 http 服务：python3 -m http.server 8765
// 拍出来的原图（S 倍、没虚化）写到 out/raw/，再跑 python3 post.py 缩小、虚化、减色，写进 client/art/layers/
const { chromium } = require('playwright');
const fs = require('fs');
const a = process.argv.slice(2);
const arg = (k, d) => { const i = a.indexOf('--' + k); return i >= 0 ? a[i + 1] : d; };
const what = a.filter((x, i) => !x.startsWith('--') && !(i > 0 && a[i - 1].startsWith('--')));
const only = arg('only', null);
const S = +arg('S', 2);

const ERAS = ['child', 'teen', 'young', 'middle', 'old'];
const SEASONS = ['spring', 'summer', 'autumn', 'winter'];
const jobs = [];
const want = k => what.length === 0 || what.includes(k);
if (want('trees')) for (const kind of ['huai', 'willow', 'young']) for (const season of SEASONS) jobs.push({ name: `tree_${kind}_${season}`, type: 'tree', kind, season });
if (want('far')) ERAS.forEach((era, i) => jobs.push({ name: `far_${era}`, type: 'far', era: i }));
if (want('places')) for (const kind of ['sea', 'village']) jobs.push({ name: `far_${kind}`, type: 'place', kind });
if (want('mid')) ERAS.forEach((era, i) => jobs.push({ name: `mid_${era}`, type: 'mid', era: i }));
if (want('fore')) for (const kind of ['street', 'river', 'green', 'school', 'market', 'sea', 'field']) jobs.push({ name: `fore_${kind}`, type: 'fore', kind });

(async () => {
  const out = __dirname + '/out/raw';
  fs.mkdirSync(out, { recursive: true });
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  for (const job of jobs) {
    if (only && !job.name.includes(only)) continue;
    const p = await b.newPage({ viewport: { width: 800, height: 600 } });
    p.on('console', m => console.log('[page]', m.text()));
    p.on('pageerror', e => { console.log('[err]', e.message); process.exit(1); });
    await p.goto('http://localhost:8765/diorama/layers3d/page.html');
    await p.waitForFunction(() => window.READY, null, { timeout: 60000 });
    const t = Date.now();
    const r = await p.evaluate(j => window.run(j), { ...job, S });
    const save = (u, f) => fs.writeFileSync(`${out}/${f}.png`, Buffer.from(u.split(',')[1], 'base64'));
    save(r.color, job.name);
    if (r.lit) save(r.lit, job.name + '_lit');
    console.log('✓', job.name, Date.now() - t, 'ms');
    await p.close();
  }
  await b.close();
})();
