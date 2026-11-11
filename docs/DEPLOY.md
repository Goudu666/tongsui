# 部署：香港 / 东京

## 选哪里

| | 香港 | 东京 |
| --- | --- | --- |
| 到大陆延迟 | 低（华南尤其明显），选 CN2 / 优化线路更稳 | 稍高，晚高峰波动更大 |
| 备案 | 不需要 | 不需要 |
| 适合 | 两个人都在大陆 | 有人在日本/海外，或者想顺便做日服 |
| 可选厂商 | 阿里云 / 腾讯云 轻量应用服务器（香港） | 腾讯云东京、AWS Lightsail 东京、Vultr 东京 |

**建议：两个人都在国内就选香港**，买阿里云或腾讯云的**轻量应用服务器（香港）**就行。

《同岁》是慢节奏实时（位置 5 Hz 广播 + 插值），对延迟不算敏感，但**晚高峰丢包**会让对方的角色走路一卡一卡。白天测哪家都快，差别在晚上 8~11 点：买之前看看是不是 CN2 / 优化线路，便宜的普通线路高峰期容易绕路丢包。

配置：**2 核 2 GB 起步就够**（Nakama + PostgreSQL 空载约 300 MB 内存）。想留余量做测试服就选 2 核 4 GB。系统选 **Ubuntu 24.04** 或 **Debian 12**。

## 现在线上那台：香港 cakery 机器（原生部署，`deploy/native/`）

《同岁》现在和甜心蛋糕屋（cakery）、sing-box 共用香港那台 GCE 机器（`34.92.141.255`，Mac 上的 ssh 别名 `cakery`）。
那台机器的 80 / 443 / 8443 / 8787 已经有人用，所以**不走下面的 Docker + Caddy 一键脚本**，而是：

| | |
| --- | --- |
| 服务 | `tongsui.service`（Nakama 3.41.0 官方二进制，用户 `tongsui`，`MemoryMax=768M`） |
| 数据库 | 本机 PostgreSQL（apt 装的 `postgresql.service`），库 `nakama`、角色 `tongsui`，只听 localhost |
| 目录 | `/opt/tongsui/`：`bin/nakama`、`modules/index.js`、`config.yml`（640，含密钥）、`secrets.env`（600，第一次生成后不再变）、`data/`、`client-server.json` |
| 端口 | Nakama 7348 / 7349 / 7350 / 7351 全绑 127.0.0.1；公网只有 nginx 新增的 **8080**（`/etc/nginx/sites-available/tongsui`，HTTP + WebSocket 反代到 7350） |
| 客户端地址 | `{"host": "34.92.141.255", "port": 8080, "scheme": "http", "server_key": "…"}`，已写进仓库变量 `TONGSUI_SERVER` |
| 备份 | `tongsui-backup.timer` 每天 04:30 JST `pg_dump` 到 `/opt/tongsui-backups/`，保留 14 天；更新前也自动备份一次 |
| 防火墙 | GCE 规则 `allow-cakery-web`（标签 `cakery-server`）本来就放行 tcp:8080；机器上没开 ufw |

**第一次部署和以后更新都是同一条**（在 Mac 上跑；构建模块 → scp → `sudo setup.sh`：备份 → 换模块 → 重启 → 检查 → nginx -t 后 reload）：

```bash
cd ~/tongsui && git pull
bash deploy/native/ship.sh          # 默认目标就是 ssh 别名 cakery
```

> ⚠️ **别对这台机器跑 `deploy/ship.sh` / `deploy/install.sh`**：它们会装 Docker、开 ufw 只放 22/80/443、让 Caddy 占 80/443，会把 cakery 和 sing-box 弄坏。
> `setup.sh` 只新增自己的东西，不碰 cakery、sing-box、nginx 里已有的 server；nginx 用 `reload` 不用 `restart`，cakery 正连着的 WebSocket 不会断。

运维（在服务器上，`ssh cakery`）：

```bash
systemctl status tongsui
journalctl -u tongsui -f                       # 日志；搜 room fault 看房间出错
sudo /opt/tongsui/backup.sh                    # 手动备份
ls -lh /opt/tongsui-backups/
cat /opt/tongsui/client-server.json            # 客户端配置
# 恢复：sudo systemctl stop tongsui && gunzip -c 备份.sql.gz | sudo -u postgres psql -d nakama && sudo systemctl start tongsui
# 控制台：在 Mac 上 ssh -L 7351:127.0.0.1:7351 cakery，浏览器开 http://127.0.0.1:7351（账号密码：sudo grep CONSOLE /opt/tongsui/secrets.env）
```

现在是明文 HTTP（没有域名就拿不到证书）。以后有域名了，可以在 nginx 的 tongsui server 上加证书改成 https，再把 `TONGSUI_SERVER` 改成 `"scheme": "https"` 重新出包。

## 5 分钟上线（一台空的新服务器，Docker + Caddy）

1. **买服务器**：香港轻量应用服务器，2 核 2 GB，Ubuntu 24.04。
   在控制台的**防火墙 / 安全组**里放行 **22、80、443**（TCP；443 再加一条 UDP 给 HTTP/3，可选）。

2. **（可选）加域名解析**：有域名就加一条 A 记录 `tongsui.你的域名` → 服务器公网 IP。
   没有域名可以跳过，脚本会自动用 `<公网IP>.sslip.io`（见下文）。

3. **在你自己的 Mac 上，一条命令部署**（仓库是私有的，所以代码从你电脑经 SSH 传过去，服务器不需要 GitHub 权限）：

   ```bash
   cd ~/tongsui && git pull
   bash deploy/ship.sh root@服务器公网IP                          # 没有域名：自动用 sslip.io
   bash deploy/ship.sh root@服务器公网IP --domain tongsui.你的域名  # 有域名
   ```

   第一次会提示确认服务器指纹、输入 SSH 密码（建议先 `ssh-copy-id root@服务器公网IP` 配好密钥）。
   以后改了服务端代码，**再跑一次同样的命令就是更新**（自动备份 → 重新构建 → 重启 → 健康检查）。

   > 仓库改成公开以后，也可以直接在服务器上跑：
   > `curl -fsSL https://raw.githubusercontent.com/Goudu666/tongsui/main/deploy/install.sh | sudo bash -s -- --domain tongsui.你的域名`

4. **记下打印出来的配置**：跑完会打印一个框，里面有服务器地址、`server_key`，以及一行 JSON：

   ```json
   {"host": "tongsui.你的域名", "port": 443, "scheme": "https", "server_key": "一串随机字符"}
   ```

   这行 JSON 也存在服务器的 `/opt/tongsui/deploy/client-server.json`。
   你的 Mac 上装了 [gh](https://cli.github.com/) 并 `gh auth login` 过的话，`ship.sh` 会自动把它写进仓库变量，第 5 步可以跳过。

5. **把 JSON 填进 GitHub**：打开仓库 **Settings → Secrets and variables → Actions → Variables → New repository variable**，
   名字填 `TONGSUI_SERVER`，值粘贴上面那行 JSON。

6. **重新跑 Actions**：仓库 **Actions → build → Run workflow**，跑完下载 APK，两个人各装一个，就连上你的服务器了。

> 脚本可以放心重复运行：已有的密钥不会被覆盖，只会补缺的、重启服务、再检查一遍。

### 没有域名：sslip.io

`sslip.io` 是一个公共 DNS 服务，`1-2-3-4.sslip.io` 会直接解析成 `1.2.3.4`。所以不买域名也能让 Caddy 申请到正式的 Let's Encrypt 证书，手机端走正常的 HTTPS。

- 不带 `--domain` 运行时，脚本会查本机公网 IPv4，自动用 `<IP 用横线连>.sslip.io`。
- 缺点：换服务器 IP 地址就变了，APK 要重新打；公共服务偶尔会碰到证书频率限制。长期用还是建议买个域名（几十块一年）。
- 想换成自己的域名：加好 A 记录后 `sudo bash /opt/tongsui/deploy/install.sh --domain 新域名`，再把新的 JSON 更新到 `TONGSUI_SERVER`。

### 脚本做了什么

`deploy/install.sh`（可选参数：`--domain`、`--email`、`--module`，`--help` 看全部）：

1. 没有 Docker 就用 get.docker.com 装上；代码放在 `/opt/tongsui`。
2. 第一次运行生成 `deploy/.env`（权限 600）：数据库密码、`server_key`、控制台账号密码，以及 Nakama 的会话 / 刷新令牌 / HTTP / 控制台签名四个密钥（它们的默认值是公开的，不换别人能伪造登录令牌）。
3. 在 `node:22-alpine` 容器里构建服务端模块，服务器上不用装 Node。也可以用 `--module index.js` 直接用 Actions 里的 `server-module` 产物。
4. ufw 只放行 SSH、80、443；装上自动安全更新和 fail2ban（SSH 防爆破）；内存小又没 swap 时加 1 GB swap。
5. `docker compose --profile prod up -d` 启动 PostgreSQL + Nakama + Caddy，等健康检查、确认日志里有 `server module loaded`、访问 `https://域名/healthcheck`。
6. 装每天 04:30 的自动备份，最后打印客户端要用的配置。

> 7350（客户端 API）和 7351（控制台）只绑在 127.0.0.1，公网只有 Caddy 的 80 / 443。
> Docker 映射的端口会绕过 ufw，所以 compose 里不要随手加 `ports`。

## 出 APK：签名、连哪台服务器

### 正式签名（给 TA 装之前做一次）

安卓只允许**同一把钥匙签的包**覆盖安装。换了钥匙只能卸载重装，而卸载会清掉手机里的设备 ID——在同岁里这等于换了一个人，**人生线就找不回来了**。所以正式给 TA 装之前，先配好正式签名：

```bash
bash tools/make_release_keystore.sh        # Mac 没装 Java 也行，会用系统自带的 openssl
bash tools/make_release_keystore.sh --gh   # 装了 gh CLI：生成后直接写进仓库 Secrets
```

钥匙生成在 `~/tongsui-keys/`。不用 `--gh` 的话，去仓库 **Settings → Secrets and variables → Actions → Secrets** 新建 3 个 Secret，值分别是那个文件夹里 3 个 txt 的内容：

| Secret | 内容 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `ANDROID_KEYSTORE_BASE64.txt` |
| `ANDROID_KEYSTORE_PASSWORD` | `ANDROID_KEYSTORE_PASSWORD.txt` |
| `ANDROID_KEY_ALIAS` | `ANDROID_KEY_ALIAS.txt` |

**把 `~/tongsui-keys` 备份到网盘或 U 盘**，永远不要提交到 git。

没配 Secrets 时，CI 用仓库里公开的调试签名（`tools/ci/debug.keystore`），每次出的调试包之间也能互相覆盖安装，自己测试足够；但调试包和正式包之间不能覆盖。

### APK 连哪台服务器

按优先级：

1. 游戏里 **联机 → 服务器设置** 保存的地址（可以「测试连接」；换服务器不用重新打包）
2. 打包时内置的：仓库变量 `TONGSUI_SERVER`（上面第 5 步）
3. 都没有：`127.0.0.1:7350`（本机开发）

桌面调试还可以用命令行：`godot --path client -- --server=https://tongsui.你的域名 --server-key=xxx`。

### 在哪下载

- **最省事：固定下载链接** <https://github.com/Goudu666/tongsui/releases/download/latest/tongsui.apk>
  main 每次 CI 全绿后自动换成最新的包（Releases 页面里叫「同岁 · 最新版」，标成预发布）。
  仓库是私有的，要先在浏览器登录 GitHub；手机上没登录就在电脑上下载，用微信/QQ 文件传输助手发到手机。
- **每次 push / Run workflow**：Actions → 这次运行 → 页面底部 Artifacts → `tongsui-0.1.N.apk`。
  版本号自动递增（versionCode = 运行序号），新包可以直接覆盖安装旧包。
- **发版本**：`git tag v0.2.0 && git push --tags`，CI 会额外发一个 GitHub Release，APK 和服务端模块 `index.js` 都挂在上面。
- **本地出包**（需要 Docker）：`docker run --rm -v "$PWD":/w -w /w barichello/godot-ci:4.7.2 bash tools/ci/build_apk.sh`

### CI 每次都测了什么

| 任务 | 内容 |
| --- | --- |
| 服务端 | 内容生成检查、TypeScript 构建、单测、真 Nakama 加载模块并调用 RPC |
| 端到端 | 真 PostgreSQL + 真 Nakama + **两个真 Godot 客户端进程**：开人生线 → 输配对码加入 → 进房间 → 重抽 → 双方投胎 → 收到实时世界 |
| 部署 | `deploy/ci-smoke.sh`：一键安装（localhost 自签证书）、HTTPS、设备登录、RPC、端口只绑本机、备份恢复、更新 |
| 安卓 | 拉插件、字体裁剪（25.6 MB → 3.4 MB）、无头冒烟测试（主界面 / 联机页 / 服务器设置 / 离线逛逛）、导出、签名校验 |

## 运维

以下命令都在服务器上执行，代码目录是 `/opt/tongsui`。

```bash
cd /opt/tongsui

# 更新服务端（自动备份 → 重新构建模块 → 重启 → 检查）。存档不受影响
# 用 ship.sh 部署的：在你电脑上再跑一次 bash deploy/ship.sh root@服务器IP 就是更新
# 用 git clone 部署的（仓库公开时）：在服务器上 update.sh 会先 git pull
sudo bash deploy/update.sh
sudo bash deploy/update.sh --module /root/index.js   # 用 Actions 下载的 server-module 产物
sudo bash deploy/update.sh --no-pull                 # 改了 deploy/.env 之后让它生效

# 手动备份（每天 04:30 也会自动备份，保留 14 天）
sudo bash deploy/backup.sh
ls -lh /opt/tongsui-backups/

# 恢复（会先自动备份当前数据，再让你输入 yes 确认）
sudo bash deploy/restore.sh /opt/tongsui-backups/tongsui-20260101-043000.sql.gz

# 看日志 / 状态
docker compose -f deploy/docker-compose.yml --profile prod ps
docker compose -f deploy/docker-compose.yml --profile prod logs -f --tail 100 nakama
cat /var/log/tongsui-backup.log
```

**管理控制台**只在服务器本机监听，用 SSH 隧道访问：

```bash
ssh -L 7351:127.0.0.1:7351 root@服务器公网IP
# 然后在自己电脑浏览器打开 http://127.0.0.1:7351
# 账号密码：服务器上 sudo grep CONSOLE /opt/tongsui/deploy/.env
```

**备份别只放在本机**。机器没了备份也没了，建议定期拉到自己电脑或网盘：

```bash
scp 'root@服务器公网IP:/opt/tongsui-backups/tongsui-*.sql.gz' ./   # 在自己电脑上执行
# 或在服务器上装 rclone，同步到 OSS / COS / 网盘：rclone copy /opt/tongsui-backups 远端:tongsui-backups
```

**搬家 / 换服务器**：旧机 `backup.sh` → 拷备份文件到新机 → 新机跑一键脚本 → `restore.sh 备份文件`。如果想让旧 APK 继续能连，把旧机的 `deploy/.env` 也拷过去（`server_key` 不变），域名解析改到新 IP。

## 安全清单

- [ ] 云厂商安全组只放行 22 / 80 / 443（脚本管不到安全组，要自己在控制台改）
- [ ] `deploy/.env` 是脚本生成的随机值，没有 `change-me`；不要提交、不要截图发群里
- [ ] SSH 改用密钥登录，确认能用密钥登进去后，在 `/etc/ssh/sshd_config` 设 `PasswordAuthentication no` 再 `systemctl restart ssh`（脚本只提醒，不替你改，免得把你锁在外面）
- [ ] 控制台只通过 `ssh -L` 访问，不要在 compose 里把 7351 映射到公网
- [ ] 定期把 `/opt/tongsui-backups` 拷到别处（一生的存档丢了是真的会心碎的）
- [ ] `server_key` 会被打进 APK，算不上真正的秘密；真正要保密的是 `.env` 里其他几项

## 排错

**证书申请失败 / 手机提示证书无效**

脚本最后提示「本机 443 能通，但正式证书还没拿到」时，按顺序查：

1. **安全组没放行 80 / 443**：最常见。Let's Encrypt 要从公网访问你的 80 端口来验证，安全组（阿里云叫「防火墙」，腾讯云叫「防火墙 / 安全组」）里加上 TCP 80、443。
2. **DNS 还没生效**：刚加的 A 记录要等几分钟。`ping tongsui.你的域名` 看解析出来的是不是服务器 IP；解析到别处（比如 CDN 代理开着）也不行，先关掉代理（小云朵）。
3. 看 Caddy 怎么说：`docker compose -f deploy/docker-compose.yml --profile prod logs caddy | grep -i -E 'error|challenge'`

修好后不用重启，Caddy 会自己重试；想马上看结果就再跑一次 `install.sh`。

**脚本说「本机 443 都不通」**：80/443 被别的程序占了（比如镜像自带的 nginx / 宝塔）。`ss -ltnp | grep -E ':(80|443) '` 找出来停掉。

**Nakama 起不来**：`docker compose -f deploy/docker-compose.yml --profile prod logs --tail 100 nakama`。最常见是改了 `.env` 里的 `POSTGRES_PASSWORD`，但数据库是用旧密码初始化的。这个密码第一次启动后就别改了。

**构建模块失败**（网络问题拉不下依赖）：在 GitHub Actions 的运行记录里下载 `server-module` 产物（里面是 `index.js`），传到服务器后 `sudo bash deploy/install.sh --module /root/index.js`。

**客户端连不上但 healthcheck 正常**：确认 `TONGSUI_SERVER` 里的 `server_key` 和服务器 `deploy/client-server.json` 一致，并且改完变量后重新跑过 Actions、装的是新 APK。

**没查到公网 IP**：有的机器出网受限，用 `--domain` 手动指定（没有域名就写 `你的IP用横线连.sslip.io`）。

## 本地开发与测试

```bash
# 本地开发：不需要 .env，全是默认值（server_key = defaultkey，http://127.0.0.1:7350）
npm ci && npm run server:build
docker compose -f deploy/docker-compose.yml up -d

# 部署冒烟：用 localhost（Caddy 自签证书）把一键脚本、HTTPS、设备登录、备份恢复、更新整个跑一遍，最后清理
bash deploy/ci-smoke.sh
```

`ci-smoke.sh` 不需要 root，用的是单独的 compose 项目名 `tongsui-smoke`，不会动本地开发的数据；但要求本机 80 / 443 / 7350 / 7351 空闲。
