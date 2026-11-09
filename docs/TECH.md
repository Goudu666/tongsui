# 技术方案

## 总览

```
 ┌──────────── Android 手机 A ────────────┐        ┌──────── 香港 / 东京 VPS ────────┐
 │ Godot 4.7（GDScript）                   │  WSS   │ Caddy  ── 自动 HTTPS             │
 │  ├ UI / 动画 / 套色 shader              │◀──────▶│  └ Nakama 3.41                  │
 │  ├ 显影：XDoG shader（照片不出手机）    │  443   │     ├ 设备登录 / 会话           │
 │  └ nakama-godot 客户端                  │        │     ├ RPC：配对码、开房、列表   │
 └─────────────────────────────────────────┘        │     ├ 权威房间 lifeline          │
 ┌──────────── Android 手机 B ────────────┐        │     │  └ sim.ts 结算每一回合     │
 │                同上                     │◀──────▶│     └ Storage：人生存档          │
 └─────────────────────────────────────────┘        │  PostgreSQL 16                   │
                                                     └──────────────────────────────────┘
        content/events/*.yaml ──(tools/build-content.mjs)──▶ client/data/events.json
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

《同岁》的联机是**回合制**：两人各自选完，服务器结算一次。不需要帧同步，也不需要 UDP。真正需要的是：

- 账号（设备登录即可，不用注册）
- 两人配对（配对码）
- 一个**权威**的房间，保证结算只发生在服务器（防作弊，也防两边状态不一致）
- 存档（一生要玩好几个晚上）
- 离线时的推送通知（M2）

Nakama 全部自带，开源，Docker 一条命令起；服务端逻辑可以用 TypeScript 写，编译成一个 JS 文件放进去。
相比自己用 Node/Go 写 WebSocket 服务器，省掉的是账号、会话、存储、房间生命周期这些不好玩但必须做对的东西。

备选：Colyseus（Node.js，更轻、更自由，但账号和存储要自己做）。

### 规则只写一份（服务器为准）

- 规则核心在 `server/src/sim.ts`：纯函数，不依赖 Nakama，Node 里可以直接单测。
- 客户端的 `client/scripts/sim/local_life.gd` 是它的 GDScript 版本，**只用于同屏原型和离线体验**。联机时客户端不做任何结算，只显示服务器发来的结果。
- 改规则时两边一起改；以后规则稳定了，可以考虑客户端也只做显示，把同屏模式也接到一个本地起的服务器上。

## 房间协议

一条 **lifeline**（人生线）= 两个人的一生。

| RPC | 谁调用 | 作用 |
| --- | --- | --- |
| `lifeline_create {name}` | 青 | 新建人生线，返回 6 位配对码 |
| `lifeline_join {code, name}` | 梅 | 输入配对码加入，此时生成两人的初始人生 |
| `lifeline_open {lifelineId}` | 任意一方 | 返回正在运行的房间 id，没有就从存档拉起 |
| `lifeline_list` | 任意 | 我参与的人生线 |

房间（`lifeline` 权威 match，1 tick/秒）消息：

| op | 方向 | 内容 |
| --- | --- | --- |
| 1 SNAPSHOT | s→c | `{lifelineId, names, life, you, progress}` 进房时发一次 |
| 2 CHOOSE | c→s | `{optionId}` 可以在结算前改主意 |
| 3 RESOLVED | s→c | `{entries, state}` 一回合结算完毕 |
| 4 PROGRESS | s→c | `{chosen, online}` 对方是否选好、是否在线（**不包含对方选了什么**） |
| 9 ERROR | s→c | `{message}` |

结算条件：本回合需要选择的人都选好了；或者已选的人在线、没选的人**离线超过 30 秒**，由影子代选。
每回合结算后写一次存档，所以房间随时可以关，两人都下线 2 分钟后房间自动关闭。

## 内容格式

剧情事件写在 `content/events/*.yaml`，运行 `npm run content` 校验并生成客户端/服务端数据（生成的文件需要提交）。

```yaml
- id: c_firefly          # 全局唯一
  kind: mirror           # mirror 默契场景 / solo 各自场景
  stage: childhood       # childhood / teen / young / middle / old
  seasons: [summer]      # 可选，仅童年有季节
  weight: 3              # 抽取权重
  requires: { minAge: 6, flags: [guitar], notFlags: [] }   # 可选
  title: 萤火虫
  text: 傍晚，巷口的草丛里亮起了一点光。
  options:
    - id: catch
      text: 拿玻璃瓶去装
      tags: [adventure]                  # 性格标签，训练影子
      effects:
        self:  { heart: 1 }              # body 体魄 / mind 心智 / charm 魅力 / heart 心情
        other: { heart: 1 }              # 对对方的影响
        bond:  { sync: 1, close: 1 }     # sync 默契 / close 亲近 / distance 距离
        flags: [caught_firefly]          # 给自己打标记，供以后的事件 requires
  resonance:                             # mirror 专用：两人选到同一项
    catch: { text: ……, memory: 一瓶萤火虫, bond: { sync: 3 } }
  dissonance: { text: ……, bond: { close: 1 } }   # mirror 专用：选得不一样
```

## 测试

```bash
npm run content          # 内容校验
npm run server:test      # 编译 + 跑 200 条完整人生 + 模拟一遍联机流程（配对、同房、校验、存档、影子、关房）
```

CI（`.github/workflows/build.yml`）还会在真实的 Nakama 容器里加载模块并调用一次 `lifeline_create`，然后导出 Android 调试 APK。

## 显影（M4）的技术路线

1. **M4.0**：`client/shaders/xdog.gdshader` 单 pass 实时预览（已写好原型）。
2. **M4.1**：改成两 pass 可分离高斯（SubViewport），速度快 5 倍；加流场（ETF）让线条沿边缘方向更顺，即 FDoG。
3. **M4.2**：用 Godot 的 `Image` 把 SubViewport 结果烘焙成 PNG，作为回忆卡存档；只发给搭档。
4. **M4.3（可选）**：端侧人像分割（如 MediaPipe Selfie Segmentation 导出的 TFLite，通过 Godot Android 插件调用），人物用玩家专色，背景用墨色，两人合照时两人各自上自己的颜色。

这一块很适合作为计算机视觉方向的个人作品：传统算法（XDoG/FDoG）+ 端侧部署 + 实际产品场景。

## 已知待办

- 客户端联机界面只是最小可用，还没处理断线重连、重新进入已有的人生线（`lifeline_list`）。
- 书信、危机场景、回忆唤起、蝴蝶事件的规则还没进 `sim.ts`。
- 字体：霞鹜文楷完整版约 25 MB，正式打包前用 `pyftsubset` 裁成常用 3500 字 + 游戏里出现的字。
- 正式发布需要自己的 release keystore（不要提交到仓库）。
