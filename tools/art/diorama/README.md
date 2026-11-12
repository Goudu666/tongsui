# 微缩模型管线（tools/art/diorama）

用户选的画风是 **C 微缩模型**（样张 tools/art/style_lab/styles/diorama.js、/mnt/project-files/tongsui/art/styles/diorama_*.jpg）：
桌上一盒玩具屋，圆角方块、塑料小人、低太阳软影、环境光遮蔽、灯有辉光、移轴景深。
所有贴图都用 three.js 在 Playwright 的 Chromium（swiftshader WebGL2）里离线渲染，引擎只摆贴图。

## 共同的规矩（所有渲染器都守，画面才是同一盒模型）

- **坐标**：游戏世界坐标 x 向右、y 向下（世界像素），z 朝镜头（离后墙多远）。three.js 里用 (x, -y, z)。
- **镜头：斜投影正交**（不是透视）。屏幕 x = x；屏幕 y = y + (z - Z_REF) * K，K = 0.28。
  z = Z_REF 那一面和世界坐标一一对上（人走的那条线 Z_REF = 120），离镜头近的东西往下挪、露出顶面。
  这样横着切多少片都接得上，锚点（灯、出口、互动点）不用改。
- **光（白天一版，夜色和灯由引擎叠）**：
  - 太阳从左上前方来：方向 (−0.55, 0.75, 0.62)（three 坐标，y 向上）归一化，颜色 #FFE6C4，强度 3.2；
  - 半球光 天 #CFE0FF / 地 #B89A80，0.9；
  - ACES Filmic，曝光 1.0，sRGB 输出；PCFSoft 影子，影子贴图 ≥ 2048；GTAO 或 SSAO 半径 ~24 世界像素。
- **材质**：墙 roughness 0.95 + 细噪点贴图；砖墙用砖贴图；木头 0.75；金属 0.45/0.35；
  小人一律塑料 roughness 0.42。圆角盒 RoundedBoxGeometry，圆角 ≈ 最短边 × 0.12（最多 6）。
- **配色**：tools/art/style_lab/mats.js 的 MAT 是材质本色，沿用；青 #2E8B6E 系、梅 #D94A3A 系是两个主角的颜色。
- **出图**：RGBA PNG，透明背景；贴图倍率沿用孔版时的常数（底图 1.25，主角 2.0，行动表 1.5，见各文件）。

## 文件
- `scene3d/`（十四张底图，从 scenes.py 录下来搭成 3D）、`pose3d/`（主角和街坊的小人）、`layers3d/`（远景、中景、树、前景）、`sprites3d/`（家里物件、街景）、`folks3d/`（街坊路人，借 pose3d 的小人），各自的 README 写怎么跑。
- 老的孔版生成器（scenes.py、actors.py、folks.py、layers.py、home.py、street.py）直接跑出的是平面孔版图，会把 3D 贴图盖掉：要跑 diorama 下对应的管线。
- `tools/art/pixel/` 是作废的像素版管线，留档不用。
- `node_modules` 链到 ../style_lab/node_modules（three 0.170）。起一个 http 服务：`python3 -m http.server 8765`（在 tools/art 下）。
