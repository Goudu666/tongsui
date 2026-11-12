# 画风样张（style lab）

用户觉得孔版网点 + 墨线太像水墨画，这里试四种新画法。做法：两张图（楼下傍晚、家里早上）先写成一份**显示列表**（`scene.js`：盒子、多边形、椭圆、线、字、灯，每样带材质名 `m`、离后墙的距离 `z`、厚度 `d`），再让四套渲染器各画一遍，所以四种风格里东西的位置一模一样。

| 渲染器 | 画法 |
| --- | --- |
| `styles/flat.js` | A 暖光平涂：不描线，本色 → 正片叠底打光（上暖下冷、对面楼的大影子、投影）→ 自发光 → 轮廓光 → 光晕 |
| `styles/pixel.js` | B 像素：480×270 原生，逐个阈值栅格化，逐像素打光，k-means 聚 40 色调色板，天和光晕拜耳抖动，站着的东西描一圈深边 |
| `styles/diorama.js` | C 微缩模型：three.js 把显示列表搭成 3D（圆角盒、挤出多边形、球、管子），低太阳 PCF 软影 + GTAO + 辉光 + 移轴，背景板和木头底座 |
| `styles/anime.js` | D 动画电影背景：A 的底子 + 积云、硬边冷影、玻璃反天、光束、辉光、镜头光斑 |

材质的本色在 `mats.js`，各画风在它上面打光、调色、减色。`r2d.js` 是 2D 共用的投影（z > 0 的东西按 `env.K` 往下挪一点，像略微俯视）和挤出。

## 跑

```bash
cd tools/art/style_lab
npm install
# 字体（不进仓库）：得意黑 SmileySans、fusion-pixel 12px 简中，放 fonts/ 下
mkdir -p fonts && cd fonts
curl -sSLO https://github.com/atelier-anchor/smiley-sans/releases/download/v2.0.1/smiley-sans-v2.0.1.zip && unzip -o smiley-sans-v2.0.1.zip
curl -sSL -o fusion.zip https://github.com/TakWolf/fusion-pixel-font/releases/download/2025.03.14/fusion-pixel-font-12px-proportional-ttf-v2025.03.14.zip && unzip -o fusion.zip -d fusion
cd ..
python3 -m http.server 8765 &        # 3D 那套是 ES 模块，要走 http
node shoot.js flat                    # → out/flat_street.png、out/flat_home.png
node shoot.js pixel street            # 只出一张
```

需要 Playwright 的 Chromium（3D 用 swiftshader 的 WebGL2）。四套里 2D 每张 1~25 秒，3D 每张约 6 秒。

样张和对比页：/mnt/project-files/tongsui/art/styles/。
