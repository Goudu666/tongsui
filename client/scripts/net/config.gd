extends RefCounted
## 联机服务器地址。按优先级取第一个找到的：
##   1. 命令行：godot --path client -- --server=https://tongsui.example.com --server-key=xxx （桌面调试）
##   2. user://server.json：游戏里「联机 → 服务器设置」保存的（玩家自己改，换服务器不用重新打包）
##   3. res://data/server.json：CI 按 GitHub 仓库变量 TONGSUI_SERVER 打进 APK（见 docs/DEPLOY.md）
##   4. 下面的 DEFAULT：本机开发，连 docker compose 起的 Nakama
## server.json 格式：{"host": "tongsui.example.com", "port": 443, "scheme": "https", "server_key": "..."}
## 其他脚本照旧读 Config.HOST / PORT / SCHEME / SERVER_KEY。

const DEFAULT := {"host": "127.0.0.1", "port": 7350, "scheme": "http", "server_key": "defaultkey"}
const BUILT_IN_PATH := "res://data/server.json"
const USER_PATH := "user://server.json"

static var HOST: String = DEFAULT.host
static var PORT: int = DEFAULT.port
static var SCHEME: String = DEFAULT.scheme
static var SERVER_KEY: String = DEFAULT.server_key
## 当前配置来自哪里：cmdline / user / built_in / default
static var SOURCE := "default"


static func _static_init() -> void:
	reload()


static func reload() -> void:
	var picked := {}
	SOURCE = "default"
	var cli := _from_cmdline()
	var user := _read_json(USER_PATH)
	var built_in := _read_json(BUILT_IN_PATH)
	if not cli.is_empty():
		picked = cli
		SOURCE = "cmdline"
	elif not user.is_empty():
		picked = user
		SOURCE = "user"
	elif not built_in.is_empty():
		picked = built_in
		SOURCE = "built_in"
	_apply(picked)


## 内置（打包时）的配置，「恢复默认」时用
static func built_in() -> Dictionary:
	var d := _read_json(BUILT_IN_PATH)
	return _normalize(d if not d.is_empty() else DEFAULT)


static func current() -> Dictionary:
	return {"host": HOST, "port": PORT, "scheme": SCHEME, "server_key": SERVER_KEY}


static func url() -> String:
	var default_port := (SCHEME == "https" and PORT == 443) or (SCHEME == "http" and PORT == 80)
	return "%s://%s%s" % [SCHEME, HOST, "" if default_port else ":%d" % PORT]


static func save_user(cfg: Dictionary) -> void:
	var f := FileAccess.open(USER_PATH, FileAccess.WRITE)
	if f == null:
		push_error("写不了 %s" % USER_PATH)
		return
	f.store_string(JSON.stringify(_normalize(cfg), "  "))
	f.close()
	reload()


static func clear_user() -> void:
	if FileAccess.file_exists(USER_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(USER_PATH))
	reload()


## 把玩家随手输入的地址解析成配置：
##   "tongsui.example.com"          → https://tongsui.example.com:443
##   "https://1-2-3-4.sslip.io"     → https://1-2-3-4.sslip.io:443
##   "http://192.168.1.5:7350"      → http://192.168.1.5:7350
##   "192.168.1.5"（纯 IP）         → http://192.168.1.5:7350（局域网直连 Nakama）
static func parse_address(text: String) -> Dictionary:
	var s := text.strip_edges()
	if s.is_empty():
		return {}
	var scheme := ""
	if s.begins_with("https://"):
		scheme = "https"
		s = s.trim_prefix("https://")
	elif s.begins_with("http://"):
		scheme = "http"
		s = s.trim_prefix("http://")
	s = s.get_slice("/", 0)
	var host := s
	var port := 0
	var colon := s.rfind(":")
	if colon > 0 and s.substr(colon + 1).is_valid_int():
		host = s.substr(0, colon)
		port = s.substr(colon + 1).to_int()
	if host.is_empty():
		return {}
	if scheme.is_empty():
		scheme = "http" if (host.is_valid_ip_address() or host == "localhost") else "https"
	if port == 0:
		if scheme == "https":
			port = 443
		elif host.is_valid_ip_address() or host == "localhost":
			port = 7350
		else:
			port = 80
	return {"host": host, "port": port, "scheme": scheme}


static func _apply(d: Dictionary) -> void:
	var n := _normalize(d)
	HOST = n.host
	PORT = n.port
	SCHEME = n.scheme
	SERVER_KEY = n.server_key


static func _normalize(d: Dictionary) -> Dictionary:
	var scheme := str(d.get("scheme", DEFAULT.scheme))
	if scheme != "https":
		scheme = "http"
	var host := str(d.get("host", DEFAULT.host)).strip_edges()
	var port := int(d.get("port", 443 if scheme == "https" else DEFAULT.port))
	var key := str(d.get("server_key", DEFAULT.server_key)).strip_edges()
	return {
		"host": host if not host.is_empty() else DEFAULT.host,
		"port": port if port > 0 and port < 65536 else DEFAULT.port,
		"scheme": scheme,
		"server_key": key if not key.is_empty() else DEFAULT.server_key,
	}


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary and str(parsed.get("host", "")) != "":
		return parsed
	return {}


static func _from_cmdline() -> Dictionary:
	var d := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--server="):
			d = parse_address(arg.trim_prefix("--server="))
	if d.is_empty():
		return {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--server-key="):
			d["server_key"] = arg.trim_prefix("--server-key=")
	return d
