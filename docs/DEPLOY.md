# 部署：香港 / 东京

## 选哪里

| | 香港 | 东京 |
| --- | --- | --- |
| 到大陆延迟 | 低（华南尤其明显），选 CN2 / 优化线路更稳 | 稍高，晚高峰波动更大 |
| 备案 | 不需要 | 不需要 |
| 适合 | 两个人都在大陆 | 有人在日本/海外，或者想顺便做日服 |
| 可选厂商 | 阿里云 / 腾讯云 轻量应用服务器（香港） | 腾讯云东京、AWS Lightsail 东京、Vultr 东京 |

**建议：两个人都在国内就选香港。** 回合制游戏对延迟不敏感，但连接稳定性（晚高峰丢包）会直接影响"对方已选好"这类提示的体验。

配置：**2 核 2 GB 起步就够**（Nakama + PostgreSQL 空载约 300 MB 内存）。想留余量做测试服就选 2 核 4 GB。系统选 Ubuntu 24.04 或 Debian 12。

## 步骤

### 1. 服务器准备

```bash
# 安装 Docker（官方脚本）
curl -fsSL https://get.docker.com | sh
# 防火墙只开 22 / 80 / 443。7350/7351 只绑在 127.0.0.1，不对外。
```

在云厂商控制台的安全组里同样只放行 22、80、443。

### 2. 域名

买一个域名（任意注册商），加一条 A 记录：`tongsui.你的域名` → 服务器公网 IP。
Caddy 会自动申请 Let's Encrypt 证书，客户端走 `https/wss` 443 端口。

> 没有域名也能先用 IP + http 测试，但 Android 9 以上默认限制明文 HTTP，正式给对方装之前请用 HTTPS。

### 3. 部署

```bash
git clone https://github.com/Goudu666/tongsui.git && cd tongsui
cp deploy/.env.example deploy/.env && nano deploy/.env    # 改掉所有 change-me，填 DOMAIN

# 构建服务端模块（服务器上装 Node 22，或者直接从 GitHub Actions 下载 server-module 产物放到 server/build/）
npm ci && npm run server:build

docker compose -f deploy/docker-compose.yml --env-file deploy/.env --profile prod up -d
docker compose -f deploy/docker-compose.yml logs -f nakama   # 看到「同岁 server module loaded」即成功
```

### 4. 客户端指向服务器

修改 `client/scripts/net/config.gd`：

```gdscript
const HOST := "tongsui.你的域名"
const PORT := 443
const SCHEME := "https"
const SERVER_KEY := "与 deploy/.env 中 NAKAMA_SERVER_KEY 相同"
```

重新导出 APK，两个人各装一个。

### 5. 运维

```bash
# 管理控制台（只在本机监听，用 SSH 隧道访问）
ssh -L 7351:127.0.0.1:7351 你的服务器   # 然后浏览器打开 http://127.0.0.1:7351

# 备份存档（人生线都在 PostgreSQL 里）
docker compose -f deploy/docker-compose.yml exec postgres pg_dump -U postgres nakama | gzip > backup-$(date +%F).sql.gz

# 更新服务端逻辑：重新 build 后重启 nakama 即可，存档不受影响
npm run server:build && docker compose -f deploy/docker-compose.yml restart nakama
```

## 安全清单

- [ ] `.env` 里的四个密码/密钥都换成随机值
- [ ] 安全组只放行 22 / 80 / 443
- [ ] SSH 用密钥登录，关闭密码登录
- [ ] 定期 `pg_dump` 备份（一生的存档丢了是真的会心碎的）
