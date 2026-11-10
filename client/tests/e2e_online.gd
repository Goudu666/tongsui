extends Node
## 端到端联机测试：两个真客户端（两个进程）连同一台 Nakama，
## 开线 → 配对 → 进房间 → 收到快照、看到对方在线 → 重抽一次 → 双方确认投胎 → 收到实时世界状态。
## 用法（CI 里同时起两个进程，共享一个目录交换配对码）：
##   godot --headless --path client res://tests/e2e_online.tscn -- --device=e2e-a --e2e=host --e2e-dir=/tmp/e2e --server=http://127.0.0.1:7350
##   godot --headless --path client res://tests/e2e_online.tscn -- --device=e2e-b --e2e=join --e2e-dir=/tmp/e2e --server=http://127.0.0.1:7350

const NetClient := preload("res://scripts/net/lifeline_client.gd")
const TIMEOUT_SEC := 60.0

var role := ""
var dir := "/tmp/e2e"
var net: NetClient
var got_snapshot := false
var got_roll := false
var got_world := false
var both_online := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--e2e="):
			role = arg.trim_prefix("--e2e=")
		elif arg.begins_with("--e2e-dir="):
			dir = arg.trim_prefix("--e2e-dir=")
	get_tree().create_timer(TIMEOUT_SEC).timeout.connect(func(): _done(false, "超时"))
	if not NetClient.addon_available():
		_done(false, "没有 nakama-godot 插件（先跑 tools/fetch_addons.sh）")
		return
	net = NetClient.new()
	add_child(net)
	net.status.connect(func(t): print("[e2e %s] %s" % [role, t]))
	net.failed.connect(func(t): _done(false, "服务器报错：%s" % t))
	net.snapshot.connect(func(_d): got_snapshot = true)
	net.world_state.connect(func(_d): got_world = true)
	net.roll_state.connect(func(_d): got_roll = true)
	net.presence.connect(func(d): both_online = d.get("online", {}).values().all(func(v): return v == true) and d.get("online", {}).size() == 2)
	if not await net.connect_server():
		_done(false, "连不上服务器")
		return
	DirAccess.make_dir_recursive_absolute(dir)
	if role == "host":
		await _host()
	else:
		await _join()


func _host() -> void:
	net.create_lifeline("青")
	var created: Array = await net.created
	var code: String = created[0]
	print("[e2e host] 配对码 %s" % code)
	_write(dir + "/code", code)
	await _wait_file(dir + "/joined")
	await net.open_lifeline(created[1])
	await _wait_messages()


func _join() -> void:
	var code := await _wait_file(dir + "/code")
	net.join_lifeline(code, "梅")
	var info: Dictionary = await net.opened
	print("[e2e join] 进入人生线 %s，角色 %s" % [info.get("lifelineId"), info.get("role")])
	_write(dir + "/joined", "1")
	await _wait_messages()


func _wait_messages() -> void:
	await _until(func(): return got_snapshot and both_online)
	print("[e2e %s] 进了房间 %s，收到快照，两个人都在线" % [role, net.match_id])
	net.reroll()
	await _until(func(): return got_roll)
	print("[e2e %s] 重抽成功" % role)
	net.confirm_roll()
	await _until(func(): return got_world)
	_done(true, "双方确认投胎，收到实时世界状态")


func _until(cond: Callable) -> void:
	while not cond.call():
		await get_tree().create_timer(0.2).timeout


func _wait_file(path: String) -> String:
	while not FileAccess.file_exists(path):
		await get_tree().create_timer(0.2).timeout
	return FileAccess.get_file_as_string(path).strip_edges()


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _done(ok: bool, why: String) -> void:
	if ok:
		print("[e2e %s] 通过：%s" % [role, why])
	else:
		printerr("[e2e %s] 失败：%s" % [role, why])
	get_tree().quit(0 if ok else 1)
