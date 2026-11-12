# 《同岁》仿真微缩 · glb

由 `tools/art/diorama/real/` 生成（`python3 tools/art/diorama/real/make.py glb figures`），three.js 0.170 的 GLTFExporter。

## 主角：`<role>_<stage>.glb`

`role` = `qing`（青）/ `mei`（梅），`stage` = `child` / `teen` / `young` / `middle` / `old`，共 10 个。
造型甲（大头 Q 版，`pose3d/figure.js` + `figures.py` 的 DESIGNS["a"]），身材、衣服、发型、脸和精灵表一样。

- **单位：米**（1 世界像素 = 1 cm）。身高 = 精灵表里的 H：child 1.12 m，teen 1.52 m，young 1.72 m，middle 1.70 m，old 1.60 m（梅同年纪差不多）。
- **朝向**：脸朝 **+Z**，头顶 +Y，人的右手在 **−X**（glTF 习惯；Godot 导进来脸朝 +Z）。横版里往右走 = 绕 Y 转 +90°。
- **原点**：两脚中间的地面（脚底 y = 0）。
- **休息姿势**：A 字（胳膊往外张 35°，肘、膝伸直），头正，身子不前倾，没有表情帧（默认睁眼）。
- **材质**：glTF PBR（`KHR_materials_sheen`、`KHR_materials_clearcoat`）。底色是纯色（`baseColorFactor`），布纹 / 头发丝 / 皮肤刷痕只放了法线贴图（512²，box 投影的 UV）；脸是贴图（1024×512 PNG，五官画在头那个球上，经纬度 UV）。
  `toy/` 下是同一副模型的现行塑料材质（不带贴图，脸照样有），两套随挑。

### 部件（每个是一个 mesh，轴心 = 关节，按骨骼父子挂好）

| 名字 | 轴心在哪 | 父 | 里头有什么 |
| --- | --- | --- | --- |
| `pelvis` | 髋（两腿根中间） | — | 裤腰 / 裙子 / 长大衣下摆 / 腰带 |
| `torso` | 腰（髋往上 0.16 × 躯干长） | pelvis | 上衣、领子、拉链、外套、扣子、书包、脖子 |
| `head` | 脖子顶 | torso | 脸（带贴图的球）、耳朵、鼻子、眼镜 |
| `hair` | 同 head | head | 头发壳、刘海、翘毛 / 马尾 / 揪揪 / 发髻、发卡、头绳 |
| `upper_arm_R` / `_L` | 肩 | torso | 肩头球、上臂（袖子） |
| `lower_arm_R` / `_L` | 肘 | upper_arm | 肘球、前臂、袖口 |
| `hand_R` / `_L` | 腕 | lower_arm | 手（圆手套） |
| `thigh_R` / `_L` | 髋关节（髋往左右 0.27 × 腰宽） | pelvis | 大腿（裤子 / 短裤） |
| `shin_R` / `_L` | 膝 | thigh | 膝球、小腿、袜子 |
| `shoe_R` / `_L` | 脚踝 | shin | 鞋（鞋面、鞋头、鞋底、搭扣） |

`R` / `L` 是人自己的右 / 左（右 = 走路时朝镜头那一侧 = 精灵里的「近侧」）。
节点上只有平移（休息姿势下没有旋转），所以动画直接转节点就行；部件之间是硬接（球关节遮缝），不蒙皮。
根节点的 `extras` 里写了 role、stage、身高（米）、朝向。

## 场景：`street_looktest.glb`

look test 那一段街（世界 x ≈ 600–3300），**没有斜投影**（斜切只在拍 2D 图时加在根上）。
根节点 `street_real` 缩放 0.01（= 米），下面一层 `world_px` 里是原始的世界像素坐标：three (x, −y, z)，y 朝上，
世界 y 向下 → three −y；z = 离后墙多远（人走的线 z = 120 世界像素 = 1.2 m）。里头有两个主角（走路的一帧，不是分件）、槐树、远景中景背景板。
为了不让文件太大（17 MB）：贴图缩到 512²、不透明的存 JPEG，粗糙度贴图换成常数（GLTFExporter 会给每个材质另合一张 metallicRoughness 图）。
正经用的贴图在 `../textures/`（1024²，`materials.json` 里有每种铺多大）。
注意：这是从 2D 显示列表搭的「浮雕」——墙是 4 cm 厚的板、门窗招牌贴在墙面上、家具摆在 z 0–110 之间，
镜头基本正对着看才成立；侧着转过去会看出薄。`preview_qing.png` / `preview_mei.png` 是把主角 glb 读回来拍的（正面带关节点、侧面、45°、炸开）。

## 导不过去 / 要在 Godot 里另做的

- **贴花**（墙根的脏、窗台下的雨水印、墙根地上的灰）是半透明面片 + alpha 贴图，导出来是 `alphaMode: BLEND` 的普通面片，Godot 里能用，但最好换成 `Decal` 节点。
- **招牌上的字**是 canvas 画的贴图，导成 PNG（alpha cutout）没问题。
- **景深、色差、暗角、颗粒、影调曲线**是 look test 的后期，不在 glb 里：Godot 里用 Camera 的 DOF（或自己的 tilt-shift shader）+ 一个后处理 shader。
- **GTAO** 不在 glb 里；gl_compatibility 没有 SSAO，砖、地砖、木板这些贴图的 albedo 里已经轻轻烤进了 AO，`_ao.png` 也单给了。墙根、角落的大尺度遮蔽靠贴花（墙根的脏）顶上。
- **环境光**（天空 PMREM）不在 glb 里：Godot 用 WorldEnvironment 的 sky。玻璃要反天才像玻璃。
- 灯（太阳、天光）不导。
