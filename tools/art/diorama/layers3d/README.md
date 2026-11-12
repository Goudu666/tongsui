# 分层（微缩模型画风）：远景、中景、门外、树、前景

画什么、多大照 `tools/art/layers.py`（孔版时的契约：远景 2048×620、门外 2048×300、中景 2048×640、前景 2048×240、树 = 画布 × 1.25），
只是每样东西用 three.js 搭成圆角的小模型，按 `../README.md` 的斜投影和太阳（`../scene3d/render.js` 的 LOOKS.toy）拍。

- `kit.js`：斜投影的根、材质、圆角块 / 圆球 / 锥台 / 管子，`shoot()` 拍白天一张 + 夜里亮窗一张（灰度）
- `trees.js`：槐树 / 柳树 / 小树 × 四季（骨架每种一个种子，四季不跳）
- `strips.js`：远景（五个年代）、门外（海边、乡下）、中景（五个年代）、前景（七种）；横着无缝
- `bake.js`：Playwright 驱动，原图（2 倍超采样）写到 `out/raw/`
- `post.py`：缩回原大小、按远近虚化（远景轻、中景几乎不虚、前景重；横条左右接着虚）、写进 `client/art/layers/`

```
cd tools/art && python3 -m http.server 8765 &      # 已经起了就不用
cd tools/art/diorama/layers3d
node bake.js                     # 全部（约 10 分钟）；node bake.js trees far mid places fore，--only huai 只出名字里带它的
python3 post.py --preview /mnt/project-files/tongsui/art/diorama/layers_preview.png
```

`_lit.png` 还是灰度（L）：引擎 `far_layer.gdshader` 读它的 r 点灯；暖色由引擎上。
