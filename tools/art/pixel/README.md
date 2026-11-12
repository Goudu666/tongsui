# 像素画管线（tools/art/pixel）

同岁的画面从孔版（网点、手抖墨线、米白纸）换成像素画。老的画法（scenes / layers / home / street / folks / actors）
都还在，像素版沿用它们画什么、画在哪，只换「怎么落成像素」。

## 规矩（所有像素资源都守）

- **3 个世界像素 = 1 个点**（`pxlib.PX`）。
- **格子原点**：世界坐标 `(0, -200)`（`pxlib.GRID0`，就是底图切片的左上角 `scenes.TOP`）。凡是按世界坐标摆回
  图上的东西（家里物件、街景、树），它的原点要落在格子上：`x % 3 == 0`、`(y + 200) % 3 == 0`，
  这样和底图的点对得上，不会半个点错开。
- **出图**：每个点最近邻放大 3 倍，**贴图 1 像素 = 1 世界像素**，引擎里这类贴图的缩放一律是 1。
- **调色板**：`palette.json`（59 色，材质本色钉死 + 从十几张图里聚出来的），所有东西共用，`pxlib.finish()` 默认就用它。
  不要各自重新聚色；缺色先看能不能用材质色表达。
- **抖动**：4×4 拜耳，只在渐变上（描线不抖）。
- **字**：缝合像素（fusion-pixel 8/10/12px，OFL，`fonts/`），按字高自动挑号，落在格子上。

## 文件

- `pxlib.py`：共用的一层。
  - `enable()`：换掉孔版味的画法（线不抖、排线变平涂、砖缝记进砖版、字换点阵字、窗玻璃记进玻璃版）。
    要在 `import scenes` 之后、画之前调一次。
  - `plates(g, crop)` → 各版浓度；`compose(...)` → 每个点的颜色 / 不透明度 / 描线；`finish(...)` → 调色板 + 抖动 → RGBA。
  - `up(arr, 3)`：放大出图。
- `pxscene.py`：十几张底图。`--preview <图> --x --w --out`、`--fit-palette`、`[图 id ...]` 出图到 `client/art/scenes/`。
- `pxactor.py`：两个主角（另一套画法：按材质四档上色、内外描线、点阵脸），出图到 `client/art/actors/`。

## 用 pxlib 改一个老生成器的套路

```python
pxlib.enable()
g = riso.Sheet(w + 2*M, h + 2*M, 1.0, origin=(x0 - M, y0 - M))   # scale 一定是 1.0，origin 落在格子上
...老代码照画...
d, pa, marks = pxlib.plates(g, (M, M + h, M, M + w))
col, alpha, line = pxlib.compose(d, pa, marks, gx=x0 // 3, gy=(y0 + 200) // 3)
rgba = pxlib.finish(col, alpha, line, gx=x0 // 3, gy=(y0 + 200) // 3)
png = pxlib.up(rgba, 3)
```
