extends SceneTree
## 内容仓库的单测（不需要服务器）：godot --headless --path client -s res://tests/unit_content.gd

const ContentStore := preload("res://scripts/net/content_store.gd")
const Op := preload("res://scripts/net/protocol.gd")

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("✗ ", what)


func _init() -> void:
	# 安装包里带的那份：完整、有版本
	var bundled := ContentStore.load_bundled()
	check(not bundled.is_empty(), "读得到 res://data/content.json")
	var v := ContentStore.version_of(bundled)
	check(v.length() == 12, "内容带 12 位指纹")
	check(bundled.events.size() > 0 and bundled.map.has("zones"), "有事件和地图")

	# 校验：不是内容的东西一律不收
	check(ContentStore.parse("").is_empty(), "空串")
	check(ContentStore.parse("[1, 2]").is_empty(), "不是对象")
	check(ContentStore.parse("{\"version\": \"x\", \"events\": []}").is_empty(), "缺字段（下载到一半）")
	check(ContentStore.parse("{\"version\": \"x\", \"events\": {}, \"families\": [], \"talents\": [], \"map\": {}}").is_empty(), "字段类型不对")
	var text := JSON.stringify(bundled)
	check(not ContentStore.parse(text, v).is_empty(), "版本对得上")
	check(ContentStore.parse(text, "000000000000").is_empty(), "版本对不上不收")
	check(ContentStore.parse(text.substr(0, text.length() / 2), v).is_empty(), "截断的 JSON 不收")

	# 缓存：存下去，按版本取回来；要别的版本时取不到
	var path := "user://content_cache_test.json"
	check(ContentStore.load_cached(v, "user://no_such_file.json").is_empty(), "没有缓存")
	check(ContentStore.save_cache(text, path), "写缓存")
	var cached := ContentStore.load_cached(v, path)
	check(ContentStore.version_of(cached) == v and cached.events.size() == bundled.events.size(), "按版本取回缓存")
	check(ContentStore.load_cached("000000000000", path).is_empty(), "缓存是别的版本时不用")
	check(ContentStore.load_cached("", path).is_empty(), "没说要哪个版本时不用缓存")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	# 协议版本号自洽
	check(Op.VERSION >= 1 and Op.MIN_SERVER <= Op.VERSION, "协议版本")

	print("✓ 内容仓库：安装包内容 / 校验 / 版本 / 缓存" if fails == 0 else "✗ %d 项失败" % fails)
	quit(1 if fails > 0 else 0)
