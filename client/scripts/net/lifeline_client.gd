extends Node
## 联机封装：设备登录 → 配对 RPC → 加入权威房间 → 收发回合消息。
## 依赖 nakama-godot 插件（运行 tools/fetch_addons.sh 获取），插件以 autoload「Nakama」注册。
## 这里故意不写插件的类型名，插件缺失时这个脚本仍能被解析，只是不能用。

signal status(text: String)
signal failed(text: String)
signal created(code: String, lifeline_id: String)
signal opened(info: Dictionary)
signal snapshot(data: Dictionary)
signal resolved(data: Dictionary)
signal progress(data: Dictionary)

const Config := preload("res://scripts/net/config.gd")
const Op := preload("res://scripts/net/protocol.gd")

var client
var session
var socket
var match_id := ""


static func addon_available() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	return tree != null and tree.root.get_node_or_null("Nakama") != null


func _nakama():
	return get_tree().root.get_node("Nakama")


func _device_id() -> String:
	# 同一台电脑开两个窗口测试时：godot -- --device=b
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--device="):
			return "tongsui-device-" + arg.trim_prefix("--device=")  # Nakama 要求 10~128 个字符
	var path := "user://device_id"
	if FileAccess.file_exists(path):
		return FileAccess.get_file_as_string(path).strip_edges()
	var id := "tongsui-%d-%d" % [Time.get_unix_time_from_system(), randi()]
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(id)
	return id


func connect_server() -> bool:
	status.emit("正在连接服务器……")
	client = _nakama().create_client(Config.SERVER_KEY, Config.HOST, Config.PORT, Config.SCHEME)
	session = await client.authenticate_device_async(_device_id())
	if session.is_exception():
		failed.emit("登录失败：%s" % session.get_exception().message)
		return false
	socket = _nakama().create_socket_from(client)
	var conn = await socket.connect_async(session)
	if conn.is_exception():
		failed.emit("连接失败：%s" % conn.get_exception().message)
		return false
	socket.received_match_state.connect(_on_match_state)
	status.emit("已连接")
	return true


func _rpc(id: String, payload: Dictionary) -> Variant:
	var res = await client.rpc_async(session, id, JSON.stringify(payload))
	if res.is_exception():
		failed.emit(res.get_exception().message)
		return null
	return JSON.parse_string(res.payload)


func create_lifeline(player_name: String) -> void:
	var r = await _rpc("lifeline_create", {"name": player_name})
	if r != null:
		created.emit(r.code, r.lifelineId)


func join_lifeline(code: String, player_name: String) -> void:
	var r = await _rpc("lifeline_join", {"code": code, "name": player_name})
	if r != null:
		await open_lifeline(r.lifelineId)


func open_lifeline(lifeline_id: String) -> void:
	var r = await _rpc("lifeline_open", {"lifelineId": lifeline_id})
	if r == null:
		return
	opened.emit(r)
	if r.get("matchId") == null:
		status.emit("等 TA 输入配对码……")
		return
	var m = await socket.join_match_async(r.matchId)
	if m.is_exception():
		failed.emit("进入房间失败：%s" % m.get_exception().message)
		return
	match_id = r.matchId


func choose(option_id: String) -> void:
	if match_id != "":
		socket.send_match_state_async(match_id, Op.CHOOSE, JSON.stringify({"optionId": option_id}))


func _on_match_state(state) -> void:
	var data: Variant = JSON.parse_string(state.data)
	if not data is Dictionary:
		return
	var op := int(state.op_code)
	if op == Op.SNAPSHOT:
		snapshot.emit(data)
	elif op == Op.RESOLVED:
		resolved.emit(data)
	elif op == Op.PROGRESS:
		progress.emit(data)
	elif op == Op.ERROR:
		failed.emit(str(data.get("message", "")))
