// 出底图贴图：node bake.js <图> [<图> …] --variant toy
// 每张图按 scenes.SLICE（1024 世界像素）切片、ART_SCALE（1.25）倍出 RGBA，写到 out/tiles/<图>_<k>.png，再由 bake.py 收进 client/art/scenes/
const { chromium } = require('playwright');
const fs = require('fs');
const a = process.argv.slice(2);
const arg = (k, d) => { const i = a.indexOf('--' + k); return i >= 0 ? a[i + 1] : d; };
const ids = a.filter((x, i) => !x.startsWith('--') && !(i > 0 && a[i - 1].startsWith('--')));
const SLICE = 1024, SCALE = +arg('scale', 1.25);
(async () => {
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  fs.mkdirSync(__dirname + '/out/tiles', { recursive: true });
  for (const sc of ids) {
    const data = JSON.parse(fs.readFileSync(`${__dirname}/out/${sc}.json`));
    const n = Math.ceil(data.width / SLICE);
    const tiles = [...Array(n).keys()].map(k => k * SLICE);
    const p = await b.newPage({ viewport: { width: 800, height: 600 } });
    p.on('pageerror', e => { console.log('[err]', e.message); process.exit(1); });
    const t = Date.now();
    await p.goto(`http://localhost:8765/diorama/scene3d/page.html?scene=${sc}&w=${SLICE}&scale=${SCALE}&variant=${arg('variant', 'toy')}&tiles=${tiles.join(',')}`);
    await p.waitForFunction(() => window.DONE, null, { timeout: 900000 });
    const urls = await p.evaluate(() => window.TILES);
    urls.forEach((u, k) => fs.writeFileSync(`${__dirname}/out/tiles/${sc}_${k}.png`, Buffer.from(u.split(',')[1], 'base64')));
    console.log(sc, n, 'tiles', Date.now() - t, 'ms');
    await p.close();
  }
  await b.close();
})();
