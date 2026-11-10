extends RefCounted
## 剧情内容从哪来。
##   安装包里带一份（res://data/content.json，npm run content 生成）。
##   服务器更新了内容时，lifeline_open 会报出新的内容指纹；客户端发现和手里的不一样，
##   就用 content_get 分块下载服务器那一份，缓存到 user://content_cache.json，下次直接用。
## 所以改剧情只要更新服务器，两台手机不用重装；没联网（先逛逛）时用安装包里那份。

const BUNDLED_PATH := "res://data/content.json"
const CACHE_PATH := "user://content_cache.json"
const REQUIRED := ["version", "events", "families", "talents", "map"]


## 安装包里带的那份。读不到返回空字典
static func load_bundled() -> Dictionary:
	if not FileAccess.file_exists(BUNDLED_PATH):
		return {}
	return parse(FileAccess.get_file_as_string(BUNDLED_PATH))


## 缓存里是不是正好有这个版本。没有或版本不对返回空字典
static func load_cached(want_version: String, path := CACHE_PATH) -> Dictionary:
	if want_version.is_empty() or not FileAccess.file_exists(path):
		return {}
	return parse(FileAccess.get_file_as_string(path), want_version)


## 下载完整后存起来（只留最新的一份）
static func save_cache(text: String, path := CACHE_PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	return true


## 解析并检查：必须是完整的内容；给了 want_version 时版本要对得上。不合格返回空字典
static func parse(text: String, want_version := "") -> Dictionary:
	var json := JSON.new()  # 不用 JSON.parse_string：下载到一半的内容是意料之中的，不往日志里刷报错
	if json.parse(text) != OK or not json.data is Dictionary:
		return {}
	var parsed: Dictionary = json.data
	for k in REQUIRED:
		if not parsed.has(k):
			return {}
	if not (parsed.events is Array and parsed.families is Array and parsed.talents is Array and parsed.map is Dictionary):
		return {}
	if want_version != "" and str(parsed.version) != want_version:
		return {}
	return parsed


static func version_of(content: Dictionary) -> String:
	return str(content.get("version", ""))
