<div align="center">

# 同岁 · TONGSUI

**同一栋楼，同一年出生，同一生。**

*A two-player life-sim RPG set in an old Tianjin neighborhood.*

</div>

---

《同岁》是一款**双人联机人生模拟 RPG**。故事发生在天津市区一片虚构的老楼「河畔里」：
两位玩家同年出生，住在一栋红砖楼的三楼对门。

开局各自**投胎**：抽家庭（说相声的顾家、楼下早点铺的周家、跑海运的许家……）、抽天赋、抽属性。
然后两个人**同框**出现在地图上：一起下楼买煎饼果子、去楼顶放鸽子、在海河边放风筝、上学、写作业、回家睡觉。
饿了要吃，困了要睡，零花钱要省着花。有些事只有你们俩**同时走到某个地方**才会发生。

就这样从三岁过到老。游戏结束时，两条人生会被印成一幅**双色人生长卷**：
你的颜色是「青」，TA 的颜色是「梅」，两种颜色叠在一起的地方，是你们共同的回忆。

## 一句话卖点

> 不是"两个人一起玩一个游戏"，而是"两个人一起过一辈子"。

| 机制 | 一句话 |
| --- | --- |
| **投胎** | 开局抽家庭、天赋、属性，3 次重抽，看得见对门抽到了什么 |
| **同框** | 两个角色在同一张天津老楼地图上实时走动，一起做同一件事有额外效果 |
| **过日子** | 饱腹、精力、清洁、心情；吃饭、上学、写作业、打工、睡觉，共享一个时钟 |
| **默契时刻** | 事件绑在地点上，两人都到场才发生；分别私下选择，选到一起就成了共同回忆 |
| **时间的密度** | 只过"被记住的日子"：童年一个季节一天，老年五年一天 |
| **影子** | 你不在线时，你的角色按需求和习惯自己过日子，还会去找 TA 玩 |
| **显影** | 拍一张你们现实中的照片，在手机端用 XDoG 算法显影成游戏里的双色线稿回忆 |

完整设计见 [docs/GDD.md](docs/GDD.md)。文字和场景细节的写法（天津做底色，不做噱头）见 [docs/tianjin_style.md](docs/tianjin_style.md)。

## 技术栈

| 层 | 选型 | 理由 |
| --- | --- | --- |
| 客户端 | **Godot 4.7.2**（GDScript，Compatibility 渲染器） | 免费开源、APK 小（约 30 MB）、2D/UI 强、Shader 好写，一键导出 Android |
| 联机服务器 | **Nakama 3.41**（TypeScript 服务端逻辑）+ PostgreSQL 16 | 自带账号、存储、通知和权威实时房间（10 Hz），两人同框走动、共享时钟都在服务器上算 |
| 内容 | YAML（事件、家庭、天赋、地图）→ 构建脚本 → 客户端 JSON + 服务端 TS | 写剧情、加人家、改地图都不用碰代码 |
| 部署 | Docker Compose + Caddy（自动 HTTPS），香港或东京一台 2C4G | 境外机房无需备案；香港到大陆延迟最低 |
| CI | GitHub Actions：服务端单测 → 两个真 Godot 客户端连真 Nakama 端到端联机 → 导出签名 APK；打 tag 自动发 Release | push 一下，Actions 页面直接下载 APK |

详细架构见 [docs/TECH.md](docs/TECH.md)，部署见 [docs/DEPLOY.md](docs/DEPLOY.md)。

## 仓库结构

```
tongsui/
├── client/                 Godot 4 客户端（横屏 1920×1080，锁横向）
│   ├── scenes/main.tscn    入口场景
│   ├── scripts/            界面流程、地图与角色、联机封装
│   ├── shaders/            纸张/套色 shader、XDoG 显影 shader
│   ├── audio/              配乐、环境音、音效（由 tools/audio 合成）和声景表
│   └── data/content.json   由 content/ 生成，勿手改
├── server/                 Nakama TypeScript 服务端模块
│   └── src/                配对 RPC、权威实时房间、投胎、世界（时钟/需求/行动/同框）、人生结算
├── content/                剧情事件、家庭、天赋、地图（YAML，写内容就改这里）
├── deploy/                 docker-compose、Nakama 配置、Caddyfile
├── tools/                  内容构建脚本、依赖获取脚本
└── docs/                   GDD / 技术方案 / 部署 / 天津文风圣经 / 声音设计
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
#    「先逛逛河畔里」不需要服务器，只能走动，用来看地图
#    nakama-godot 插件已经在仓库里；tools/fetch_addons.sh 只用来拉霞鹜文楷字体
#    同一台电脑开两个窗口测试联机：godot --path client -- --device=a / --device=b
#    两台手机在局域网里联调：电脑上起服务器，手机的联机大厅「服务器设置」填电脑的局域网 IP（如 192.168.1.5）
```

打包 APK：push 到 GitHub 后，在 Actions → `build` 页面底部 Artifacts 下载 `tongsui-*.apk`；
打 tag（`git tag v0.2.0 && git push --tags`）会自动发 GitHub Release。
本地出包：`docker run --rm -v "$PWD":/w -w /w barichello/godot-ci:4.7.2 bash tools/ci/build_apk.sh`。
APK 连哪台服务器、怎么配正式签名，见 [docs/DEPLOY.md](docs/DEPLOY.md)。

## 路线图

- [x] **M0 骨架**：世界观、玩法、技术选型、内容管线、投胎、实时同框房间、影子、客户端原型
- [ ] **M1 童年篇可玩**（3~12 岁，36 个日子）：手绘地图与角色、40 个事件、天津话 NPC、音效
- [ ] **M2 分离与书信**：少年/青年篇、分开的城市地图、书信延迟、回忆唤起
- [ ] **M3 一生**：中老年、死亡与独行、双色人生长卷生成与分享
- [ ] **M4 显影**：照片 → XDoG 线稿 → 双色套印回忆卡
- [ ] 参赛：CiGA Game Jam / IndiePlay / 腾讯 GWB 游戏创作大赛

## 致谢与声明

品类灵感来自人生模拟 RPG。《同岁》的名字、角色、世界观、美术、音乐音效与全部剧情均为原创（声音全部程序合成，没有采样，见 docs/AUDIO.md）；
「河畔里」是虚构的地方，城市氛围取自天津市区，不涉及真实店铺与品牌。
