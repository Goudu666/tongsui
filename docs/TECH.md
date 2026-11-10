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
| `lifeline_open {lifelineId}` | 任意一方 | 返回正在运行的房间 id，没有就从存档拉起（两人同时打开也只会有一个房间） |
| `lifeline_list` | 任意 | 我参与的人生线：两人名字、是否已配对、阶段、走到哪一天（大厅的「继续」） |

梅输入配对码后，服务器给青发一条通知（code 101 `partner_joined`），青的客户端收到就自动进房间开始投胎；
通知万一丢了，青的等待页每 5 秒也会问一次 `lifeline_open`。有人进房而对方不在房间里时发 code 102 `partner_online`。

房间（`lifeline` 权威 match，10 tick/秒）的阶段：`roll`（投胎）→ `life`（河畔里）→ `ended`。

| op | 方向 | 内容 |
| --- | --- | --- |
| 1 SNAPSHOT | s→c | `{lifelineId, names, life, you, online, tick}` 进房（含断线重连）、开局、每天结束时发。`life.world` 只带时钟、人物和事件（`event.chosen` 只说谁选了，`event.mine` 是我自己选的），不带 TA 的选项、今天的命运和随机数状态 |
| 2 ROLL | c→s | `{reroll: true}` 或 `{confirm: true}` |
| 3 ROLL_STATE | s→c | `{rolls}` 两人当前抽到的家庭、天赋、属性、剩余次数 |
| 4 MOVE | c→s | `{x, y, seq}` 约 10 Hz，seq 递增；服务器丢掉乱序旧包，限速（360 px/s，间隔最多按 1 秒算）和边界 |
| 5 ACT | c→s | `{spot}` 在某个点开始行动（距离、年龄、时间、家、钱都会校验） |
| 6 CHOOSE | c→s | `{optionId}` 事件里的选择，结算前可以改 |
| 7 WORLD | s→c | 5 Hz：`{tick, minute, schoolDay, actors{x,y,act,spot,sleep,seq}, needs, money, event, bond, hints}`；`actors[r].seq` 是服务器处理到的最后一条 MOVE |
| 8 EVENT | s→c | `{event}` 有事件开始了（只告诉谁参与、是否已选，不告诉选了什么） |
| 9 ERROR | s→c | `{message}` |
| 10 LOG | s→c | `{entries}` 事件结算、同框、一天结束、死亡、终局 |
| 11 PRESENCE | s→c | `{online}` |
| 12 PING | c→s | `{t}` 每 2 秒，测延迟 |
| 13 PONG | s→c | `{t, tick}` 只回给发的人 |

- 事件进行中时钟暂停；没选的人都离线时，等 30 秒后由影子代选。
- 掉线 10 秒之内影子不接手（切网络、进电梯）；超过 10 秒影子替他过日子；本人回来时影子手上的事（睡觉、上学除外）停下，把身体还给他。
- 每天结束、有人掉线、每 30 秒各存一次档。两人都下线后世界停住，2 分钟后房间关闭，存档里的 matchId 清空，下次打开从存档重新拉起。

### 一条人生线只有一个房间

`lifeline_open` 本身不写存档，拉起房间时由 `matchInit` 用**带版本号的条件写入**把自己的 matchId 写进存档：
两个人同一瞬间打开时只有一个能写成功，另一个在 `matchInit` 里抛 `DUP_MATCH:<赢家的 id>`，RPC 把赢家的房间返回给他。
刚写进去的 matchId 在 15 秒内一律当作活着（房间要等 `matchInit` 返回后才能被 `matchGet` 查到）。

### 断线重连（客户端 `lifeline_client.gd`）

- 会话存在 `user://session.cfg`，7 天内重开 App 不用重新登录；快过期时用 refresh token 刷新，刷新不了就重新设备登录。设备 id 在安卓上用 `OS.get_unique_id()`（ANDROID_ID，卸载重装不变）。
- **换手机找回**：大厅里「换手机找回」第一次打开时生成一个 10 位找回码，作为 Nakama custom id（`tongsui-recover-<码>`）绑到当前账号；新手机输入它，用 `authenticate_custom(create=false)` 登回同一个 user_id，人生线都在。之后这台手机一直用找回码这个身份登录。
- 三种情况触发重连：socket `closed`；在房间里 8 秒没收到任何消息（WORLD 是 5 Hz，这是看门狗）；App 从后台回来发现 3 秒以上没消息。
- 退避 1/2/4/8/10 秒重试，连上后重新 `lifeline_open`（房间可能已经关了重开）再进房；服务器重发快照，客户端把人放回服务器的位置，如果正卡在事件里就把选择框弹回来。
- 同一个人的新连接进房会顶掉旧连接：旧连接后来的 `leave` 不会把人踢下线，旧连接发来的消息也不算数。

### 同框的位置同步

- **自己**：客户端预测（点哪走哪，330 px/s），每 0.1 秒带 seq 上报。WORLD 回来的 `seq` 对应的那条上报位置如果和服务器位置一致，就什么都不做（不会被 200 ms 前的旧位置往回拽）；被限速或边界截过才把差值平滑地补上，差太多（换天回家、被事件叫过去）直接到位。
- **对方**：插值缓冲（`snapshot_buffer.gd`）。按 WORLD 里的 `tick` 估计服务器时钟（`server_clock.gd`），画面落后服务器 0.25 秒播放，两帧之间线性插值，所以是匀速走而不是一顿一顿地追；包来晚了按速度外推最多 0.25 秒；两帧之间跳太远就不插值。

## 内容格式

内容都在 `content/` 下，运行 `npm run content` 校验并生成客户端/服务端数据（生成的文件需要提交）。

| 文件 | 内容 |
| --- | --- |
| `events/*.yaml` | 剧情事件 |
| `families.yaml` | 投胎能抽到的人家：家境、零花钱、属性加成、家庭标记 |
| `talents.yaml` | 先天天赋 |
| `map.yaml` | 地图：地点（矩形区域）、互动点、行动（时长、需求/属性变化、花钱挣钱、同框效果、条件） |
| `endings.yaml` | 结局：两个人的结局（pair）和每个人的一生小结（lives），按顺序匹配，最后一条兜底 |

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
  requires: { minAge: 6, flags: [erhu], notFlags: [] }   # 可选，flags 可以是家庭/天赋/事件打的标记（mirror 看两人的并集）
  # requires 还可以写：minClose/maxClose 亲近、minSync/maxSync 默契、minDistance/maxDistance 距离、
  #   alone: true（只在对方已经离开以后，仅 solo）/ false（只在两人都在世时）
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
    stars: { text: ……, memory: 第四十七颗星, bond: { sync: 3 }, flags: [p_stars] }   # flags：共同标记，两人都得到，必须 p_ 开头
  dissonance: { text: ……, bond: { close: 1 }, flags: [] }   # mirror 专用：选得不一样
```

`npm run content` 的校验除了格式，还会检查：性格标签只能是 gentle / adventure / solitude / responsible / competitive / patient；
只有童年能写 seasons；mirror 不能放在某一家屋里；要求了某个标记却没有任何地方会打上它时给出警告（多半是拼错了）。

结局格式见 `content/endings.yaml` 文件头。服务器在两人都离开后调用 `lifeEnding` 算出结局，存进 `LifeState.ending`（`{ pair, lives: { qing, mei } }`），
并把结局文字写进最后一条 `end` 日志，客户端的长卷直接显示。

## 测试

```bash
npm run content          # 内容校验
npm run server:test      # 编译 + 投胎规则 + 60 条全影子人生 + 世界规则单点 + 假 Nakama 里的联机流程（配对、并发开房、重连、防泄露、影子宽限）
                         # + 剧情测试：1500 条随机人生，保证每个事件、每个结局都走得到

# 下面两个要先起一台本地 Nakama（docker compose，见 README）
npm --prefix server run e2e                   # 两个 Node 机器人连真 Nakama：配对通知、16 次并发打开、走动同步、换连接重连、掉线再进
GODOT=godot bash tools/net_e2e.sh             # 两个无头 Godot 客户端（用游戏里真正的联机代码）配对、投胎、同框走动，其中一个中途硬断网自动重连
godot --headless --path client -s res://tests/unit_net.gd   # 插值缓冲、服务器时钟、地址解析的单测，不需要服务器
```

CI（`.github/workflows/build.yml`）还会在真实的 Nakama 容器里加载模块并调用一次 `lifeline_create`，然后导出 Android 调试 APK。

## 显影（M4）的技术路线

1. **M4.0**：`client/shaders/xdog.gdshader` 单 pass 实时预览（已写好原型）。
2. **M4.1**：改成两 pass 可分离高斯（SubViewport），速度快 5 倍；加流场（ETF）让线条沿边缘方向更顺，即 FDoG。
3. **M4.2**：用 Godot 的 `Image` 把 SubViewport 结果烘焙成 PNG，作为回忆卡存档；只发给搭档。
4. **M4.3（可选）**：端侧人像分割（如 MediaPipe Selfie Segmentation 导出的 TFLite，通过 Godot Android 插件调用），人物用玩家专色，背景用墨色，两人合照时两人各自上自己的颜色。

这一块很适合作为计算机视觉方向的个人作品：传统算法（XDoG/FDoG）+ 端侧部署 + 实际产品场景。

## 已知待办

- 客户端是最小可用：地图和角色是代码画的墨线占位，还没有手绘贴图、动画、音效。
- 地图没有碰撞（合作游戏，信任客户端走位），M1 加简单的墙体。
- 少年以后的阶段还在用河畔里这一张地图；M2 加分开的城市地图、书信、危机场景、回忆唤起、蝴蝶事件。
- 字体：霞鹜文楷完整版约 25 MB，正式打包前用 `pyftsubset` 裁成常用 3500 字 + 游戏里出现的字。
- 正式发布需要自己的 release keystore（不要提交到仓库）。
