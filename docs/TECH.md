# 技术方案

## 总览

```
 ┌──────────── Android 手机 A ────────────┐        ┌──────── 香港 / 东京 VPS ────────┐
 │ Godot 4.7（GDScript）                   │  WSS   │ Caddy  ── 自动 HTTPS             │
 │  ├ 地图 / 角色 / 套色 shader            │◀──────▶│  └ Nakama 3.41                  │
 │  ├ 显影：XDoG shader（照片不出手机）    │  443   │     ├ 设备登录 / 会话           │
 │  └ nakama-godot 客户端                  │        │     ├ RPC：配对码、开房、列表   │
 └─────────────────────────────────────────┘        │     ├ 权威房间 lifeline（10Hz） │
 ┌──────────── Android 手机 B ────────────┐        │     │  ├ sim.ts  投胎/事件/生死  │
 │                                         │        │     │  └ world.ts 时钟/行动/同框 │
 │                同上                     │◀──────▶│     └ Storage：人生存档          │
 └─────────────────────────────────────────┘        │  PostgreSQL 16                   │
                                                     └──────────────────────────────────┘
        content/*.yaml ──(tools/build-content.mjs)──▶ client/data/content.json
                                                          └─▶ server/src/content.generated.ts
```

## 为什么这么选

### 客户端：Godot 4.7.2

| 选项 | 结论 |
| --- | --- |
| **Godot 4** | ✅ 选它。免费开源无分成，导出 APK 约 30 MB，2D UI 和 shader 都顺手，GDScript 上手快，学生一个人能扛 |
| Unity | 生态最大，但包体大、授权条款变动过，2D 叙事游戏用不上它的长处 |
| Cocos Creator | 国内小游戏生态好，TypeScript 能和服务端共用代码；如果以后要上微信小游戏，可以考虑迁移 |
| Flutter / RN | 做 App 可以，做游戏的动画、shader、音效都要自己造轮子 |

使用 **Compatibility 渲染器**（OpenGL ES 3），覆盖面最广，低端安卓机也能跑。

### 服务器：Nakama + TypeScript

《同岁》的联机是**慢节奏实时**：两人在地图上走动（5 Hz 位置广播 + 客户端插值就够），共享一个时钟，事件时两人各自选择、服务器结算。不需要帧同步，也不需要 UDP。真正需要的是：

- 账号（设备登录即可，不用注册）
- 两人配对（配对码）
- 一个**权威**的房间：时钟、需求、行动、事件、结算都只在服务器上算（防作弊，也防两边状态不一致）
- 存档（一生要玩好几个晚上）
- 离线时的推送通知（M2）

Nakama 全部自带，开源，Docker 一条命令起；服务端逻辑可以用 TypeScript 写，编译成一个 JS 文件放进去。
相比自己用 Node/Go 写 WebSocket 服务器，省掉的是账号、会话、存储、房间生命周期这些不好玩但必须做对的东西。

备选：Colyseus（Node.js，更轻、更自由，但账号和存储要自己做）。

### 规则只写一份（服务器为准）

- `server/src/sim.ts`：人生层，投胎、事件结算、一天结束、生老病死。
- `server/src/world.ts`：一天之内的实时世界，共享时钟、走动限速、行动、需求衰减、同框、地点触发事件、影子。
- 两个文件都是纯函数，不依赖 Nakama，Node 里可以直接单测（`server/test/life.test.mjs`）。
- 客户端不做任何结算，只负责画、走、发指令。自己的角色走动由客户端预测，服务器限速后广播；对方的角色按广播插值。
- 唯一在客户端重复的规则是「回合 → 年龄标签」（`client/scripts/ui/life_time.gd`，只用于显示）。

## 房间协议

一条 **lifeline**（人生线）= 两个人的一生。

| RPC | 谁调用 | 作用 |
| --- | --- | --- |
| `lifeline_create {name}` | 青 | 新建人生线，返回 6 位配对码 |
| `lifeline_join {code, name}` | 梅 | 输入配对码加入，同时为两人各投一次胎 |
| `lifeline_open {lifelineId}` | 任意一方 | 返回正在运行的房间 id，没有就从存档拉起 |
| `lifeline_list` | 任意 | 我参与的人生线 |

房间（`lifeline` 权威 match，10 tick/秒）的阶段：`roll`（投胎）→ `life`（河畔里）→ `ended`。

| op | 方向 | 内容 |
| --- | --- | --- |
| 1 SNAPSHOT | s→c | `{lifelineId, names, life, you, online}` 进房、开局、每天结束时发 |
| 2 ROLL | c→s | `{reroll: true}` 或 `{confirm: true}` |
| 3 ROLL_STATE | s→c | `{rolls}` 两人当前抽到的家庭、天赋、属性、剩余次数 |
| 4 MOVE | c→s | `{x, y}` 约 10 Hz，服务器限速（360 px/s）和边界 |
| 5 ACT | c→s | `{spot}` 在某个点开始行动（距离、年龄、时间、家、钱都会校验） |
| 6 CHOOSE | c→s | `{optionId}` 事件里的选择，结算前可以改 |
| 7 WORLD | s→c | 5 Hz：`{minute, schoolDay, actors, needs, money, event, bond, hints}` |
| 8 EVENT | s→c | `{event}` 有事件开始了（只告诉谁参与、是否已选，不告诉选了什么） |
| 9 ERROR | s→c | `{message}` |
| 10 LOG | s→c | `{entries}` 事件结算、同框、一天结束、死亡、终局 |
| 11 PRESENCE | s→c | `{online}` |

- 事件进行中时钟暂停；没选的人都离线时，等 30 秒后由影子代选。
- 每天结束、有人掉线、每 30 秒各存一次档。两人都下线后世界停住，2 分钟后房间关闭。

## 内容格式

内容都在 `content/` 下，运行 `npm run content` 校验并生成客户端/服务端数据（生成的文件需要提交）。

| 文件 | 内容 |
| --- | --- |
| `events/*.yaml` | 剧情事件 |
| `families.yaml` | 投胎能抽到的人家：家境、零花钱、属性加成、家庭标记 |
| `talents.yaml` | 先天天赋 |
| `map.yaml` | 地图：地点（矩形区域）、互动点、行动（时长、需求/属性变化、花钱挣钱、同框效果、条件） |

事件格式：

```yaml
- id: c_roof_summer      # 全局唯一
  kind: mirror           # mirror 默契事件（两人都到场）/ solo 各自的事
  stage: childhood       # childhood / teen / young / middle / old
  where: roof            # 地点，见 map.yaml 的 zones；solo 不写则早上醒来触发
  when: [1080, 1300]     # 可选，游戏分钟（1080 = 18:00）
  hint: 楼顶好像有人在收凉席。   # 可选，地图上飘着的提示
  seasons: [summer]      # 可选，仅童年有季节
  weight: 3              # 抽取权重
  requires: { minAge: 6, flags: [erhu], notFlags: [] }   # 可选，flags 可以是家庭/天赋/事件打的标记
  title: 楼顶的夏夜
  text: 夏天晚上，楼顶比屋里凉快……
  options:
    - id: stars
      text: 躺在凉席上数星星
      tags: [gentle]                     # 性格标签，训练影子
      effects:
        self:  { mood: 10, mind: 1 }     # 属性 body/mind/charm/luck（0~10）+ 需求 hunger/energy/mood/clean（0~100）
        other: { mood: 5 }               # 对对方的影响
        bond:  { sync: 1, close: 1 }     # sync 默契 / close 亲近 / distance 距离
        flags: [saw_stars]
  resonance:                             # mirror 专用：两人选到同一项
    stars: { text: ……, memory: 第四十七颗星, bond: { sync: 3 } }
  dissonance: { text: ……, bond: { close: 1 } }   # mirror 专用：选得不一样
```

## 测试

```bash
npm run content          # 内容校验
npm run server:test      # 编译 + 投胎规则 + 60 条全影子人生 + 世界规则单点 + 模拟一遍联机流程
```

CI（`.github/workflows/build.yml`）还会在真实的 Nakama 容器里加载模块并调用一次 `lifeline_create`，然后导出 Android 调试 APK。

## 显影（M4）的技术路线

1. **M4.0**：`client/shaders/xdog.gdshader` 单 pass 实时预览（已写好原型）。
2. **M4.1**：改成两 pass 可分离高斯（SubViewport），速度快 5 倍；加流场（ETF）让线条沿边缘方向更顺，即 FDoG。
3. **M4.2**：用 Godot 的 `Image` 把 SubViewport 结果烘焙成 PNG，作为回忆卡存档；只发给搭档。
4. **M4.3（可选）**：端侧人像分割（如 MediaPipe Selfie Segmentation 导出的 TFLite，通过 Godot Android 插件调用），人物用玩家专色，背景用墨色，两人合照时两人各自上自己的颜色。

这一块很适合作为计算机视觉方向的个人作品：传统算法（XDoG/FDoG）+ 端侧部署 + 实际产品场景。

## 已知待办

- 客户端是最小可用：地图和角色是代码画的墨线占位，还没有手绘贴图、动画、音效；没处理断线重连、重新进入已有的人生线（`lifeline_list`）。
- 地图没有碰撞（合作游戏，信任客户端走位），M1 加简单的墙体。
- 少年以后的阶段还在用河畔里这一张地图；M2 加分开的城市地图、书信、危机场景、回忆唤起、蝴蝶事件。
- 字体：霞鹜文楷完整版约 25 MB，正式打包前用 `pyftsubset` 裁成常用 3500 字 + 游戏里出现的字。
- 正式发布需要自己的 release keystore（不要提交到仓库）。
