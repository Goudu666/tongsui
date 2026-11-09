<div align="center">

# 同岁 · TONGSUI

**同一条巷子，同一年出生，同一生。**

*A two-player life simulation for childhood friends.*

</div>

---

《同岁》是一款**双人联机人生模拟**手游。两位玩家扮演同年出生、住在同一条巷子里的两个孩子，
从三岁那年的立春开始，各自过完自己的一生，又始终活在彼此的生命里。

你们会一起抓萤火虫、在课本上传纸条、考进不同的城市、为了一封迟到的信吵架、在某个冬天重逢……
直到其中一个人先走，另一个人还要再走一段路。

游戏结束时，两条人生线会被印成一幅**双色人生长卷**：
你的颜色是「青」，TA 的颜色是「梅」，两种颜色叠在一起的地方，是你们共同的回忆。

## 一句话卖点

> 不是"两个人一起玩一个游戏"，而是"两个人一起过一辈子"。

| 机制 | 一句话 |
| --- | --- |
| **双线一生** | 两条人生同步推进，各自上学、工作、生病、做选择，但互相影响 |
| **默契时刻** | 同一个难题分别摆在两人面前，不商量，选到一起就成了共同回忆 |
| **时间的密度** | 童年一回合是一个季节，老年一回合是五年。越长大，时间过得越快 |
| **距离与书信** | 长大后可能分隔两地，沟通从"隔窗喊一声"变成"写信，三回合后才到" |
| **回忆是货币** | 共同回忆会随时间褪色，但在人生的低谷，可以用一段回忆把对方拉起来 |
| **影子** | 你不在线时，你的角色会按你过去的习惯继续生活，对方不用等你 |
| **显影** | 拍一张你们现实中的照片，在手机端用 XDoG 算法显影成游戏里的双色线稿回忆 |

完整设计见 [docs/GDD.md](docs/GDD.md)。

## 技术栈

| 层 | 选型 | 理由 |
| --- | --- | --- |
| 客户端 | **Godot 4.7.2**（GDScript，Compatibility 渲染器） | 免费开源、APK 小（约 30 MB）、2D/UI 强、Shader 好写，一键导出 Android |
| 联机服务器 | **Nakama 3.41**（TypeScript 服务端逻辑）+ PostgreSQL 16 | 自带账号、好友、存储、通知、权威房间，双人回合制刚好合适 |
| 内容 | YAML 事件表 → 构建脚本 → 客户端 JSON + 服务端 TS | 策划/写作和代码分离，写剧情不用碰代码 |
| 部署 | Docker Compose + Caddy（自动 HTTPS），香港或东京一台 2C4G | 境外机房无需备案；香港到大陆延迟最低 |
| CI | GitHub Actions：构建服务端 + 导出 Android 调试 APK | push 一下，Actions 页面直接下载 APK |

详细架构见 [docs/TECH.md](docs/TECH.md)，部署见 [docs/DEPLOY.md](docs/DEPLOY.md)。

## 仓库结构

```
tongsui/
├── client/                 Godot 4 客户端（竖屏 1080×1920）
│   ├── scenes/main.tscn    入口场景
│   ├── scripts/            游戏逻辑（本地同屏原型 + 联机封装）
│   ├── shaders/            纸张/套色 shader、XDoG 显影 shader
│   └── data/events.json    由 content/ 生成，勿手改
├── server/                 Nakama TypeScript 服务端模块
│   └── src/                配对 RPC、权威回合房间、人生结算
├── content/events/         剧情事件（YAML，写剧情就改这里）
├── deploy/                 docker-compose、Nakama 配置、Caddyfile
├── tools/                  内容构建脚本、依赖获取脚本
└── docs/                   GDD / 技术方案 / 部署
```

## 快速开始

```bash
# 1. 改了剧情后重新生成内容（YAML → JSON / TS，生成结果已提交，第一次可跳过）
npm install
npm run content

# 2. 本地起服务器（需要 Docker）
npm run server:build
docker compose -f deploy/docker-compose.yml up -d
# Nakama 控制台：http://127.0.0.1:7351  (默认 admin / password，线上见 deploy/.env)

# 3. 客户端
#    用 Godot 4.7.2 打开 client/project.godot，F5 运行
#    默认是「同屏双人」原型：一台手机两个人轮流选，不需要服务器
#    联机模式需要先运行 tools/fetch_addons.sh 拉取 nakama-godot 插件和霞鹜文楷字体
#    同一台电脑开两个窗口测试联机：godot --path client -- --device=a / --device=b
```

打包 APK：push 到 GitHub 后，在 Actions → `build` 下载 `tongsui-debug-apk`；
或者本地在 Godot 编辑器里「项目 → 导出 → Android」。

## 路线图

- [x] **M0 骨架**：世界观、玩法、技术选型、内容管线、权威回合房间、同屏原型
- [ ] **M1 童年篇可玩**（3~12 岁，约 36 回合）：40 个事件、默契系统、回忆褪色、联机跑通
- [ ] **M2 分离与书信**：少年/青年篇、城市与距离、书信延迟、影子托管
- [ ] **M3 一生**：中老年、死亡与独行、双色人生长卷生成与分享
- [ ] **M4 显影**：照片 → XDoG 线稿 → 双色套印回忆卡
- [ ] 参赛：CiGA Game Jam / IndiePlay / 腾讯 GWB 游戏创作大赛

## 致谢与声明

品类灵感来自人生模拟类游戏。《同岁》的名字、角色、世界观、美术与全部剧情均为原创。
