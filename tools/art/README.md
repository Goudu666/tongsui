# 美术生成器：河畔里的孔版套色

《同岁》的场景和角色不是手绘贴图，而是用 Python 程序"印"出来的：模拟孔版印刷（Risograph），
只有三块版（墨 `#2B2A33`、青 `#2E8B7A`、梅 `#D9485F`）和一张米白纸 `#F4EEE1`。

- 浅色用调幅网点，三块版网角不同（墨 45°、青 15°、梅 75°），网点带一点颗粒
- 青、梅两块版各错位一两个像素，像真的套印；两色叠在一起就是深紫
- 线条带一点手绘抖动，建筑草图式的方框四角出头

改一个数、重新跑一遍，十一张图的风格一起变，这是选程序化而不是手绘的原因。

## 运行

```bash
pip install pycairo numpy pillow
bash tools/fetch_addons.sh            # 需要里面的霞鹜文楷字体（招牌、地名）
python3 tools/art/scenes.py           # 十一张侧视横图 → client/art/scenes/
python3 tools/art/scenes.py street    # 只重画一张
python3 tools/art/actors.py           # 角色（侧视骨骼）→ client/art/actors/（约 80 秒）
python3 tools/art/folks.py            # 横版街坊和路人 → client/art/folks/（先 npm run content 出 client/data/folks.json）
python3 tools/art/layers.py           # 远景、中景、四季的树、前景 → client/art/layers/
python3 tools/art/street.py           # 街坊、车、年代道具 → client/art/street/
```

生成结果已经提交，不改美术不用跑。生成后用 Godot 打开一次项目让它重新导入。

调某一段的时候只渲染那一段，快很多：

```bash
python3 tools/art/scenes.py --preview street --x 1200 --w 1600 --scale 0.5 --out /tmp/x.png
```

## 结构

| 文件 | 内容 |
| --- | --- |
| `riso.py` | 印刷模拟：`Sheet`（一张纸三块版）、`Pen`（线、多边形、排线、砖缝、文字）、网点合成 |
| `scenes.py` | 侧视横版的十一张图：零件（楼面、窗、门、招牌、雨棚、树、电线杆、路灯、家具）+ 每张图一个 `draw_<图>` |
| `actors.py` | 青、梅五个人生阶段的侧视精灵表：一副骨架（髋、膝、踝、肩、肘）按关键帧摆姿势，衣裳和头发套在骨架上 |
| `layers.py` | 视差层：远景天际线和中景屋顶（每个年代一张，带一张夜里亮灯的窗户图）、三种树的四季、四种前景条 |
| `actor_acts.py` | 主角的二十套专属动作（写作业、吃饭、颠球、跳皮筋、修车、炒菜、钓鱼、下棋、弹琴、放风筝…）和四个情绪动作，套在 `actors.py` 的骨架上，道具在 hook 里跟着关节画 |
| `folks.py` | 横版街坊（一人一种营生：摇蒲扇、织毛衣、吆喝、剃头、遛狗、推婴儿车、指挥…）和六种路人，同一副骨架、浅一档的网点 |
| `street_fig.py` | 街坊的参数化小人：体型、朝向、站/坐、衣裳、手里拿的东西，一个字典画一个人 |
| `street.py` | 街景图集：街坊、公告栏、电话亭、快递柜、共享单车、面的、出租、骑车的人、对岸天际线 |

## 立体感（`scenes.py` 的 `RELIEF`）

孔版是平的。合成完每张底图再过一遍 `relief()`：成块的实地（招牌、雨棚、檐口、门、家具，比 `min_size` 细的墨线不算）往右下投一道软影子，
墙从上往下慢慢沉，每层地面往上一截再压一道（墙脚的环境光遮蔽），地面线往下也压一小截。影子是偏冷的墨色，不是黑。
光从左上来，只管「东西立不立得起来」；那天是早是晚、冷暖怎么分，交给引擎里的光与空气那一层（`client/shaders/grade.gdshader`，见 docs/TECH.md）。
改 `RELIEF` 里的数，十一张图一起变。

## 输出约定（引擎依赖这些）

- **场景**：每张图一条横图，坐标用这张图自己的（`content/maps/<图>.yaml`：x 从 0 到 width，地面在 floors − top，单层图都是 760）。
  - 竖着从 y = −200 画到 1000，横着按 1024 世界像素切片，1.25 倍输出（每片 1280×1500），64 色调色板 PNG：`<图>_<k>.png`
  - `anchors.json`：每张图的灯（`street_lamp` 路灯、`window_light` 窗、`hall_lamp` 楼道灯、`stall_light` 摊子、`far_light` 远处），画到灯的时候顺手记下，夜版按它烘灯光图
  - 引擎：`client/scripts/world/scene_art.gd`（切片常数和这里一致），`print_light.gd` 换图时 `relight`
  - 画的规矩：出口的地方画门、楼梯或路口，引擎只挂牌子；互动点的 x 以 content 为准，家具围着它画；年代会变的东西（告示内容、车、价钱）不进底图
- **场景的天是透明的**：底图只印地面以上的楼、树坑和地面。`<图>_mask.png` 是这张图的不透明度（四分之一大小），夜版按它少压天空。`anchors.json` 里每张图多了 `layer`（地平线、远景底边）和 `trees`（每棵树的位置、高、种类，引擎在那儿摆一棵会晃的树）。
- **视差层**（`layers.py`，`scene_art.gd` 摆）：从后往前是天空着色器（`sky.gdshader`：网点渐变、云、太阳、月亮、星星）→ 远景 `far_<年代>.png` → 中景 `mid_<年代>.png` → 底图 → 树 `tree_<种>_<季>.png`（`sway.gdshader` 晃）→ 前景 `fore_<种>.png` → 天气粒子 → 夜版。
  远景和中景都是 2048 宽、首尾接得上的横条，`_lit.png` 是同样大小的灰度图，标出哪些窗户夜里会亮（`far_layer.gdshader` 按格子随时间开灯关灯）。年代 0~4 对应童年到老年，楼一代比一代高。
- **角色**：`{qing|mei}_{child|teen|young|middle|old}.png`，8 列 × 3 行，每格 200×220（2 倍输出），脚底在格子 (100, 206)，都朝右（朝左由引擎翻转）。
  行 0 是走路八帧（一步一个周期）；行 1 列 0~3 站着（列 3 眨眼）、列 4~7 在忙；行 2 列 0~1 坐、2~3 睡、4~7 招手；
  行 3 高兴 / 泄气，行 4 击掌 / 挠头（各 4 帧）。引擎按走过的距离推帧（`actor.gd` 的 `STRIDE`），所以快慢都不滑步。
  体态随年纪变：小孩走路一颠一颠（`hop`）、少年微含胸、中年发福（`belly`）、老人驼背屈膝（`lean`、`knee_bend`）。
- **专属动作表**：`{qing|mei}_{stage}_act.png`，8 列 × 10 行、1.5 倍输出（2400×3300，省显存）。每行两套 4 帧循环，顺序是 `actor_acts.ACTS`，
  和 `actor.gd` 的 `ACT_LOOP` 一一对应（`client/tests/unit_life.gd` 对着查）。行动 id 对到哪一套在 `actor.gd` 的 `ACTION_LOOP` / `DUTY_LOOP`。
  脸上的表情是 `actors._face` 的 expr（笑、大笑、说话、唱、专心、琢磨、使劲、难过、嚼、不好意思…），头可以低头抬头（pose 的 `tilt`）。
- **街坊**：`client/art/folks/<图>.png` 一位一行（列 0~3 营生、4~7 歇着），`walkers.png` 一种路人一行 8 帧走路，`index.json` 记谁在哪一行。
  谁在哪张图、哪个年纪、几段在、搭什么腔写在 `content/maps/<图>.yaml` 的 `npcs`（`npm run content` → `client/data/folks.json`）；
  新加一位要在 `folks.py` 的 `FOLKS` 里给他长相和营生，不然 `folks.py` 和 `unit_life` 都会报。运行时 `client/scripts/world/folks.gd`。

## 街景：随年代更替的那一层

底图（`scenes.py`）只画不会变的东西。会来、会走、会老的东西单独一层：

- `content/street.yaml` 写谁、站哪、哪个人生阶段在、几点在、走近了说什么；`npm run content` 编译成 `client/data/street.json`，并检查精灵名、年代名、行动名
- `tools/art/street.py` 把每个精灵画成一小张印张，拼成 `client/art/street/atlas.png`（2 倍输出）+ `sprites.json`（每个精灵的位置、帧数、脚底锚点）
- `client/scripts/world/street_life.gd` 按人生阶段和钟点摆出来：街坊和主角一起按 y 排序，走近了冒一句话；街上的车按年代换，上下班时段变密（它的坐标还是俯视大地图的，横版改成一张图一层之前先不挂）

这一层只是街景，不进服务端、不参与结算。加一位街坊：在 `street.py` 里用 `person(...)` 画，在 `street.yaml` 里摆，跑上面两条命令。

分寸：这是一条普通的老街，不是景点。不摆城市名片，不堆方言，街坊只叫行当不起姓（姓留给玩家可能投胎到的那几户人家）。
年代靠街上的东西自己说：面的换成小出租，黑板报换成公告栏，对岸的烟囱换成楼。越往后越虚，老年只留不变的。
