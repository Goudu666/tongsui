// 仿真微缩（real）look test 的驱动：Playwright + swiftshader。先在 tools/art 下起 http 服务（python3 -m http.server 8765）。
//   node shoot.js street --x 900 --w 2133 --scale 0.9 --post --out a.png         拍一张（--post：景深、色差、暗角、颗粒；不加就是素的）
//        [--figs a|b|none] [--top Y --bottom Y]（只拍一段高度，特写用） [--json '{"sunK":3}']（别的参数直接传给 render）
//   node shoot.js street --glb scene.glb --x 900 --w 2133                          导场景 glb（米，没有斜切）
//   node shoot.js --figure qing_teen --glb qing_teen.glb [--mats real|toy]         导一个主角的分件 glb（A 字休息姿势）
const { chromium } = require('playwright');
const fs = require('fs');
const a = process.argv.slice(2);
const arg = (k, d) => { const i = a.indexOf('--' + k); return i >= 0 ? a[i + 1] : d; };
const flag = (k) => a.includes('--' + k);
// 两个主角站在哪：青走在前头半步，梅跟着（都朝右）
const FIG_SETS = {
  a: [{ who: 'mei_teen', frame: 'walk_b', x: 1600, dz: -14, design: 'a' }, { who: 'qing_teen', frame: 'walk_a', x: 1672, dz: 10, design: 'a' }],
  b: [{ who: 'mei_teen', frame: 'walk_b', x: 1600, dz: -14, design: 'b' }, { who: 'qing_teen', frame: 'walk_a', x: 1672, dz: 10, design: 'b' }],
  none: [],
};
(async () => {
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--js-flags=--max-old-space-size=8192'] });
  const p = await b.newPage({ viewport: { width: 1600, height: 900 } });
  p.on('console', (m) => { if (!/GPU stall|WebGL/.test(m.text())) console.log('[page]', m.text()); });
  p.on('pageerror', (e) => { console.log('[err]', e.message); process.exit(1); });
  await p.goto('http://localhost:8765/diorama/real/page.html?v=' + Date.now());
  await p.waitForFunction(() => window.READY, null, { timeout: 120000 });
  const t = Date.now();
  const opt = Object.assign({
    scene: a[0] && !a[0].startsWith('--') ? a[0] : 'street', x: +arg('x', 900), w: +arg('w', 2133), scale: +arg('scale', 0.9),
    post: flag('post'), figs: FIG_SETS[arg('figs', 'a')], look: arg('look', 'real'),
  }, arg('top') ? { top: +arg('top'), bottom: +arg('bottom') } : {}, JSON.parse(arg('json', '{}')));
  if (arg('preview')) {   // node shoot.js --preview a.glb,b.glb --out sheet.png（glb 要在 tools/art 下能用 http 取到）
    const u = await p.evaluate((l) => window.previewGlbs(l), arg('preview').split(','));
    fs.writeFileSync(arg('out'), Buffer.from(u.split(',')[1], 'base64'));
    console.log('✓', arg('out'));
  } else if (arg('figure')) {
    const s = await p.evaluate((o) => window.glbFigure(o), { who: arg('figure'), design: arg('design', 'a'), mats: arg('mats', 'real') });
    fs.writeFileSync(arg('glb'), Buffer.from(s, 'base64'));
    console.log('✓', arg('glb'), Date.now() - t, 'ms');
  } else if (arg('glb')) {
    const s = await p.evaluate((o) => window.glbScene(o), opt);
    fs.writeFileSync(arg('glb'), Buffer.from(s, 'base64'));
    console.log('✓', arg('glb'), Date.now() - t, 'ms');
  } else {
    const r = await p.evaluate((o) => window.go(o), opt);
    const data = await p.evaluate(() => document.getElementById('out').toDataURL('image/png'));
    const out = arg('out', '/tmp/real.png');
    fs.writeFileSync(out, Buffer.from(data.split(',')[1], 'base64'));
    console.log('✓', out, r, Date.now() - t, 'ms');
  }
  await b.close();
})();
