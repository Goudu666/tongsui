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

### 横屏版面

游戏锁横屏（`window/handheld/orientation=4`，横着拿，哪边朝上都行）。设计稿 1920×1080，`canvas_items` + `expand`：**高恒为 1080，手机越长越宽**（20:9 是 2400×1080），平板是变高。所以：

- 贴左右边的东西用锚点或 `hud.left()` / `hud.right()` 算，不写死 1920。刘海和圆角在左右两侧，让开的宽度用 `Kit.safe_sides()` 取（电脑上是 0）；真机上左右取两边里大的那个，手机翻 180 度（窗口大小不变，不会重排）刘海换了边也不会被挡。
- 河畔里的 HUD（`ui/hud.gd`）是「对门」构图：顶上一条横带（y 40~196），左边是我的（日历牌、四个圆表、零花钱），右边是对门的（两个圆、对门的牌：TA 在哪、在做什么），中间是常驻的关口纸带（`ui/goal_panel.gd`：我的分在左、尺在中间、对门的分在右）。右下角是行动按钮。对门走出画面时屏幕边上有个箭头指着 TA。
- 菜单页：`_show_screen()` 之后用 `_columns(body)` 拿左右两栏，左边写「这是什么」，右边放「要你做什么」。
- 传承（`legacy_ui.gd`）跟着两栏走：投胎页对门的老物件在右栏，我面前的三件在两栏下面通栏并排（`my_offer(body)`），定下来的按钮跟到它下面；结局页「留给河畔里」在右栏（`left_behind`），「再来一世」在左栏（`again`）。
- 弹窗：`_open_modal(宽度)`；选项用 `_options(box, 个数)` + `_option()` 并排成票（三个以内一行，四个 2×2，五六个三列）；左图右文用 `_columns(modal_body)`。内容比屏幕高时卡片内部滚动。
- 版面的规矩有单测看着：`client/tests/unit_layout.gd`（方向设置、HUD 各块在 16:9 到 21:9 和带刘海时不叠、选项列数）。
- 截图：`bash tools/shots/run.sh <目录>`，`RES=2400x1080` 看长屏，`NOTCH=110` 假装两边有刘海。

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
- `server/src/legacy.ts`：传承，一世走完留下什么、再来一世、投胎时带一件老物件；痕迹、街坊记住的事、藏着的天赋、住户本读归档（[LEGACY.md](LEGACY.md)）。
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
| `lifeline_open {lifelineId, protocol}` | 任意一方 | 返回正在运行的房间 id，没有就从存档拉起（两人同时打开也只会有一个房间）。回复里带服务器的 `protocol` 和内容指纹 `content` |
| `lifeline_list` | 任意 | 我参与的人生线：两人名字、是否已配对、阶段、第几世、走到哪一天（大厅的「继续」） |
| `lifeline_past {lifelineId, life}` | 任意一方 | 住户本：这条人生线上走完的某一世。只给挑过的那几样（结局、两个人的小传、回忆、留下的东西、街坊记住的事），不给长卷和随机数（[LEGACY.md](LEGACY.md) 第十一节） |
| `content_get {offset}` | 任意 | 分块取服务器这一版的剧情内容：`{version, total, offset, chunk, done}` |
| `server_info` | 任意 | `{protocol, minClientProtocol, content, lifeVersion, events}`，部署后自检用 |

梅输入配对码后，服务器给青发一条通知（code 101 `partner_joined`），青的客户端收到就自动进房间开始投胎；
通知万一丢了，青的等待页每 5 秒也会问一次 `lifeline_open`。有人进房而对方不在房间里时发 code 102 `partner_online`。

房间（`lifeline` 权威 match，10 tick/秒）的阶段：`roll`（投胎）→ `life`（河畔里）→ `ended`；两个人都点了「再来一世」，同一条人生线回到 `roll`（[LEGACY.md](LEGACY.md)）。

| op | 方向 | 内容 |
| --- | --- | --- |
| 1 SNAPSHOT | s→c | `{lifelineId, names, life, you, online, protocols, tick}` 进房（含断线重连）、开局、每天结束、换世时发。`protocols` 是两边安装包的协议版本（不在线是 0）。`life.world` 只带时钟、人物和事件（`event.chosen` 只说谁选了，`event.mine` 是我自己选的），不带 TA 的选项、今天的命运和随机数状态 |
| 2 ROLL | c→s | `{reroll: true}`、`{confirm: true}`，或 `{heirloom: id \| null}` 挑一件老物件带上 / 放下 |
| 3 ROLL_STATE | s→c | `{rolls}` 两人当前抽到的家庭、天赋、属性、剩余次数，以及家业传了几代（`house`）、面前摆着的老物件（`offer`）、挑中的那件（`heirloomId`） |
| 4 MOVE | c→s | `{x, y, seq}` 约 10 Hz，seq 递增；服务器丢掉乱序旧包，限速（360 px/s，间隔最多按 1 秒算）和边界 |
| 5 ACT | c→s | `{spot}` 在某个点开始行动（距离、年龄、时间、家、钱都会校验） |
| 6 CHOOSE | c→s | `{optionId, guess?}` 事件里的选择，结算前可以改。`guess`：默契事件里猜 TA 选了哪一项，可以不带（见 [DUET.md](DUET.md)） |
| 7 WORLD | s→c | 5 Hz：`{tick, minute, slot, ready, playing, wait, rest, actors{x,y,act,spot,sleep,seq,tg,fr}, needs, money, event, bond, hints, stats, eff, goals, tracks}`；`actors[r].seq` 是服务器处理到的最后一条 MOVE，`tg` 是这次行动在搭伴，`fr` 是这件事从第几段开始（比现在早就撤不回）；`slot` 是一天五段里的第几段，`ready` 是两人这一段定了没有，`playing` 是这一段正在过；`goals[r]` 是下一个关口和每条线离得多远，`tracks[r]` 是现在走的路和今天的日程，`eff[r]` 是现在做事的效率 |
| 8 EVENT | s→c | `{event, locks}` 有事件开始了（只告诉谁参与、是否已选，不告诉选了什么）。关口（`kind: milestone`）带 `locks: {role: {optionId: 原因}}`，够不着的路客户端画成灰的 |
| 9 ERROR | s→c | `{message}` |
| 10 LOG | s→c | `{entries}` 事件结算、搭伴、一天结束、死亡、终局。关口的结算带 `results: {role: {score, unit, grade, option, track}}`，一天结束带 `gains`（每人今天长了多少） |
| 11 PRESENCE | s→c | `{online, protocols}` |
| 12 PING | c→s | `{t}` 每 2 秒，测延迟 |
| 13 PONG | s→c | `{t, tick}` 只回给发的人 |
| 22 PASS | c→s | `{}` 这一段就这么过（不做正经事） |
| 23 CANCEL | c→s | `{}` 改主意：撤回这一段定下的事（「就这么过」、行动、睡觉；前几段就开始的上学上班撤不了），进门的钱退回来 |
| 30 ECHO | c→s | `{turn, optionId}` 回话：补答影子替我选过的默契事件（`turn` 是那天的序号，`optionId` 为 null 是「不提了」）。结算作为一条 LOG 发给两个人 |
| 31 AGAIN | 双向 | c→s `{yes}` 一世走完以后点「再来一世」（`false` 是收回），票记在存档里；s→c `{again: {qing, mei}}` 谁点了，只发给协议 3 以上的连接。两人都点了，服务器把这一世归档、换成新的一世，改发 SNAPSHOT（见 docs/LEGACY.md） |

- 事件进行中时钟暂停；没选的人都离线时，等 30 秒后由影子代选。
- 时钟只在两个人都定下这一段以后才走（`worldPlay`，现实 1 秒 = 90 分钟），过完一段停在下一段的开头。一段里的行动按 `Actor.scale = 段长 × daily.slotUse ÷ 行动分钟数` 一次结算；顺手的事（`quick: true`）当场结算，不占这一段。
- 一个人定了，另一个在线的人 90 秒还不定，影子替他定；不在线的人由影子在在线的人定了以后定。
- 掉线 10 秒之内影子不接手（切网络、进电梯）；超过 10 秒影子替他过日子；本人回来时影子手上的事（睡觉、上学除外）停下，把身体还给他。
- 每天结束、有人掉线、每 30 秒各存一次档。两人都下线后世界停住，2 分钟后房间关闭，存档里的 matchId 清空，下次打开从存档重新拉起。

### 版本：服务器和安装包分开更新

服务器 `ship.sh` 一下就换了，手机要重装 APK，两边版本错开是常态。进房间前先对两样东西：

- **协议版本**（`main.ts` 的 `PROTOCOL_VERSION` / `MIN_CLIENT_PROTOCOL`，`protocol.gd` 的 `VERSION` / `MIN_SERVER`）。
  客户端在 `lifeline_open` 里报自己的版本：低于 `MIN_CLIENT_PROTOCOL` 的直接被拒，界面上显示「安装包太旧」；服务器比客户端要求的还旧则提示更新服务器。
  改了消息的含义就把两边的版本一起加一；旧包确实不能用了才提高 `MIN_CLIENT_PROTOCOL`。
  新旧安装包可以进同一个房间：3 版起客户端进房时在 `join_match` 的 metadata 里报 `protocol`，房间记着每个连接的版本（`LifelineMatch.protocols`，不进存档），
  新消息用 `sendSince` 只发给版本够的连接，快照和 `PRESENCE` 把两边的版本告诉客户端，界面上才说得清「等 TA 更新安装包」。
- **内容指纹**（`CONTENT.version`，`npm run content` 时对内容算的 SHA-256 前 12 位）。
  客户端发现服务器的指纹和手里的不一样，就用 `content_get` 把服务器这一版下载下来（约 17 万字符，分 4 块），
  缓存到 `user://content_cache.json`，然后才进房间（`content_store.gd`）。**改剧情只需要更新服务器，手机不用重装**；没联网时用安装包里带的那份。
  地图贴图不在内容里，改了地图美术仍然要出新包。

### 存档

- 一条人生线一个存储对象（`lifelines/<id>`），里面的 `life` 就是全部状态（`LifeState`，含随机数状态）。**规则代码不能把状态放在 `LifeState` 以外**（模块级变量、闭包），`arch.test.mjs` 的「存档往返」会查：同一个种子，中途任意时刻存档再读档，结果必须和一口气跑完一模一样。
- **结构升级**：`save.ts` 的 `LIFE_VERSION` 和 `lifeUpgrade`。改 `LifeState` 的结构时版本加一，在 `lifeUpgrade` 里补一段从上一版升上来的代码。存档比服务器新（服务器被回滚）时拒绝打开。
- **内容修复**：`lifeRepair`。存档里记着事件、行动、点位的 id，剧情改了以后这些 id 可能已经不在了；房间拉起时把悬空的引用摘掉（今天的命运作废、卡着的事件取消、做到一半的行动停下、抽卡阶段抽到的人家没了就重抽），并写进服务器日志。新加「指向内容 id」的存档字段时，在这里加一条。
- **走完的一世单独归档**：两个人都点了「再来一世」，房间先把走完的那份 `LifeState` 写到 `lifeline_past/<id>.<第几世>`，再把存档换成新的一世。
  存档里跨世带着的只有 `LifeState.legacy`（有界），长卷不摞在存档里。票（`LifeState.again`）在存档里，归档完没存就断了的，重新拉起后接着换，结果一样。
- **单写者**：房间是存档唯一的写入者，每次带着上次写入的版本号做条件写入。写不进去而存档里的 matchId 已经是别的房间时，这个房间不再写、下一跳退场，不会把对方的进度盖回去。
- **出错回滚**：`matchLoop` 里规则代码抛错时（`faultClose`），内存里的状态可能只改了一半，不存；存档停在上一个存档点（最多丢 30 秒），记下 `faults` 和 `lastFault`，清掉 matchId 后关房。客户端自动重连，从存档重新拉起。日志里搜 `room fault` 能看到人生线 id、回合、时刻、卡着的事件和调用栈。
- 客户端发来的消息先验形状（必须是 JSON 对象、消息号必须是客户端该发的），不合格只回 `ERROR`。

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
| `map.yaml` | 地图：地点（矩形区域）、互动点、行动（时长、需求/属性变化、花钱挣钱、搭伴效果、条件）。一个互动点可以用 `actions` 挂几个行动，按年纪取第一个合适的 |
| `events/milestones.yaml` | 人生关口：`kind: milestone` 的事件，按 `age` 到来，选项上的 `min` 是分数线。格式见文件头 |
| `tracks.yaml` | 人生路线：由标记推出来的日程（白天去哪、去多久、长什么、挣多少）。按顺序匹配，最后一条兜底 |
| `endings.yaml` | 结局：两个人的结局（pair）和每个人的一生小结（lives），按顺序匹配，最后一条兜底 |
| `rules.yaml` | 数值规则：投胎预算、成长、衰老、检定、寿命、亲近（规则代码在 `server/src/growth.ts`，说明见 [GROWTH.md](GROWTH.md)） |
| `checks.yaml` | 检定：挂在已有事件的选项上，成不成看属性和运气 |
| `duet.yaml` | 接话：「搭上了」（按事件 id 挂上去的互补选项组合）、猜 TA 和回话的旁白。格式见文件头和 [DUET.md](DUET.md) |

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
  # 选得不一样、但正好一个抛一个接的组合（「搭上了」）不写在这里，写在 content/duet.yaml 的 catches 里
```

`npm run content` 的校验除了格式，还会检查：性格标签只能是 gentle / adventure / solitude / responsible / competitive / patient；
只有童年能写 seasons；mirror 不能放在某一家屋里；要求了某个标记却没有任何地方会打上它时给出警告（多半是拼错了）。

关口和路线是核心玩法的骨架（设计见 [GDD.md](GDD.md) 第 4 节）。规则在 `server/src/sim.ts`（`lifeTrack` 路线、`lifeOptionLock` 上锁、`lifeGoal` 目标）
和 `server/src/world.ts`（`worldPickAction` 点位上现在能做什么、`worldDuty` 日程、`worldFinish` 里的搭伴倍率和状态效率）。
分数线调完要跑 `node tools/paths.mjs`：十二种活法的机器人把人生过完（最后一道关在七十岁），打印每条线有多少人够得着。
`server/test/paths.test.mjs` 把四件事钉成断言：不上心的够不着高线、活法比出身重要、搭伴比一个人强、一个人够不着所有的线。

结局格式见 `content/endings.yaml` 文件头。服务器在两人都离开后调用 `lifeEnding` 算出结局，存进 `LifeState.ending`（`{ pair, lives: { qing, mei } }`），
并把结局文字写进最后一条 `end` 日志，客户端的长卷直接显示。

## 测试

```bash
npm test                 # 下面两条一起跑
npm run content          # 内容校验（字段名写错、规则代码按名字引用的行动/标记缺失都会报错），生成两端数据
npm run server:test      # 编译 + 投胎规则 + 60 条全影子人生 + 世界规则单点 + 假 Nakama 里的联机流程（配对、并发开房、重连、防泄露、影子宽限）
                         # + 成长规则（growth.test.mjs）：投胎预算 / 成长 / 衰老 / 检定和搭把手 / 寿命 / 亲近 / v3 存档升级，只测规则的形状，不绑具体的数
                         # + 剧情测试：1500 条随机人生，保证每个事件、每个结局都走得到
                         # + 架构测试（arch.test.mjs）：版本握手与内容下载 / 坏消息 / 存档往返 / 剧情改了以后旧存档还能打开 /
                         #   出错回滚 / 单写者 / 两端契约（消息号、协议版本、年龄阶段表、走动限速这些两边各抄一份的东西有没有走样）
npm run balance          # 平衡模拟：机器人按真实规则过 1200 条人生，打印成长曲线、寿命、结局的分布（改了 rules.yaml 以后跑，见 GROWTH.md）
                         # + 接话测试（duet.test.mjs）：搭上了 / 猜 TA / 回话 / 存档修复 / 带猜测和回话的联机流程
                         # + 传承测试（legacy.test.mjs）：留下什么 / 再来一世的票和可复现 / 摆和挑 / 带上以后多了什么 / v5 存档升级 /
                         #   房间里的归档、断在半路接着换、新旧安装包混搭 / 老物件压不过活法
                         #   痕迹只记上一世 / 藏着的天赋要先出过那件事、一头宽一头窄 / 街坊记住的事只记一回不给东西 / v6 存档升级 / 住户本读归档的白名单
GODOT=godot bash tools/ci/client_unit.sh      # 客户端单测 client/tests/unit_*.gd，不需要服务器

# 下面两个要先起一台本地 Nakama（docker compose，见 README）
npm --prefix server run e2e                   # 两个 Node 机器人连真 Nakama：配对通知、16 次并发打开、走动同步、换连接重连、掉线再进、版本握手、内容下载
GODOT=godot bash tools/net_e2e.sh             # 两个无头 Godot 客户端（用游戏里真正的联机代码）配对、投胎、同框走动，其中一个中途硬断网自动重连
```

CI（`.github/workflows/build.yml`）：服务端构建和全部单测 → 真 Nakama 里加载模块并跑机器人端到端 → 两个真 Godot 客户端联机（`tools/ci/e2e_online.sh`）→ 客户端单测 → 部署脚本冒烟 → 导出 APK。
`tools/net_e2e.sh`（带断网重连的那套 Godot 端到端）目前只能手动跑，还没进 CI。

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
