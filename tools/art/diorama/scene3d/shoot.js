// node shoot.js <图> --x 1000 --w 2133 --scale 0.9 --variant toy --backdrop --out /tmp/a.png
// 要先在 tools/art 下起 http 服务：python3 -m http.server 8765
const { chromium } = require('playwright');
const fs = require('fs');
const a = process.argv.slice(2);
const arg = (k, d) => { const i = a.indexOf('--' + k); return i >= 0 ? a[i + 1] : d; };
const flag = k => a.includes('--' + k);
(async () => {
  const sc = a[0];
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  const p = await b.newPage({ viewport: { width: 1600, height: 900 } });
  p.on('console', m => console.log('[page]', m.text()));
  p.on('pageerror', e => { console.log('[err]', e.message); process.exit(1); });
  const q = `scene=${sc}&x=${arg('x', 0)}&w=${arg('w', 2133)}&scale=${arg('scale', 1)}&variant=${arg('variant', 'toy')}&backdrop=${flag('backdrop') ? 1 : 0}`;
  const t = Date.now();
  await p.goto('http://localhost:8765/diorama/scene3d/page.html?' + q);
  await p.waitForFunction(() => window.DONE, null, { timeout: 600000 });
  const r = await p.evaluate(() => window.RESULT);
  const data = await p.evaluate(() => document.getElementById('out').toDataURL('image/png'));
  const out = arg('out', `/tmp/${sc}.png`);
  fs.writeFileSync(out, Buffer.from(data.split(',')[1], 'base64'));
  console.log(sc, out, r, Date.now() - t, 'ms');
  await b.close();
})();
