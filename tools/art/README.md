# 美术生成器：河畔里的孔版套色

《同岁》的地图和角色不是手绘贴图，而是用 Python 程序"印"出来的：模拟孔版印刷（Risograph），
只有三块版（墨 `#2B2A33`、青 `#2E8B7A`、梅 `#D9485F`）和一张米白纸 `#F4EEE1`。

- 浅色用调幅网点，三块版网角不同（墨 45°、青 15°、梅 75°），网点带一点颗粒
- 青、梅两块版各错位一两个像素，像真的套印；两色叠在一起就是深紫
- 线条带一点手绘抖动，建筑草图式的方框四角出头

改一个数、重新跑一遍，整张地图的风格一起变，这是选程序化而不是手绘的原因。

## 运行

```bash
pip install pycairo numpy pillow
bash tools/fetch_addons.sh            # 需要里面的霞鹜文楷字体（招牌、地名）
python3 tools/art/build_map.py        # 地图 → client/art/map/
python3 tools/art/actors.py           # 角色 → client/art/actors/
```

生成结果已经提交，不改美术不用跑。生成后用 Godot 打开一次项目让它重新导入。

调某一块的时候只渲染那一块，快很多：

```bash
python3 tools/art/build_map.py --region 1400,250,500,450 --scale 1 --out /tmp/x.png --walk
```

`--walk` 把可走区域叠成淡青色、互动点画红圈。构建时会检查所有互动点和出生点都能走到。

## 结构

| 文件 | 内容 |
| --- | --- |
| `riso.py` | 印刷模拟：`Sheet`（一张纸三块版）、`Pen`（线、多边形、排线、砖缝、文字）、网点合成 |
| `build_map.py` | 跑所有地图模块，切片输出 + 可走区域 + 锚点 |
| `hepanli/common.py` | 布局常量（从 `client/data/content.json` 读 zone 和互动点）、可走区域、公共道具 |
| `hepanli/building.py` | 红砖楼：楼顶、剖切面、青家、楼道、梅家 |
| `hepanli/street.py` | 楼下老街「河畔里」与两侧人行道 |
| `hepanli/breakfast.py` | 早点铺、街角报刊亭 |
| `hepanli/river.py` | 海河步道、铁桥、水面、对岸 |
| `hepanli/school.py` `bikeshop.py` `south.py` | 小学、自行车铺、小花园和南边街坊 |
| `actors.py` | 青、梅五个人生阶段的精灵表 |

## 输出约定（引擎依赖这些）

- **地图**：2400×1600 世界像素，按 800×800 切成 3×2 片，2 倍输出（每片 1600×1600，低端机也不超 2048 纹理上限）。
  - `ground_{列}_{行}.png` 地面层，角色走在上面
  - `over_{列}_{行}.png` 上层（树冠、电线、床单、雨棚、桥架），白底，引擎里用正片叠底盖在角色身上
  - `walk.png` 可走区域，10 世界像素一格，白色能走（`client/scripts/world/nav.gd` 用它做 A* 寻路）
  - `anchors.json` 环境动画锚点：`steam` 热气、`pigeon` 鸽子、`kite` 风筝、`ripple` 涟漪、`flag` 红旗、`street_lamp` 路灯……
- **角色**：`{qing|mei}_{child|teen|young|middle|old}.png`，6 列 × 4 行，每格 96×128 世界像素（2 倍输出），脚底在格子 (48, 120)。
  行 0 朝下、1 朝上、2 朝右（朝左由引擎翻转），列 0 站、1~4 走、5 在忙；行 3 是睡觉、挥手、坐着。
- 地图里 zone 和互动点的坐标以 `content/map.yaml` 为准（服务器按它判定），美术只能围着它们画，不能挪。
