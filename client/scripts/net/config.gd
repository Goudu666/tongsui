extends RefCounted
## 联机服务器地址。部署到香港/东京后改成你的域名（见 docs/DEPLOY.md）

const HOST := "127.0.0.1"
const PORT := 7350
const SCHEME := "http"          ## 上线后用 Caddy 反代：HOST="tongsui.example.com", PORT=443, SCHEME="https"
const SERVER_KEY := "defaultkey" ## 必须与 deploy/.env 里的 NAKAMA_SERVER_KEY 一致
