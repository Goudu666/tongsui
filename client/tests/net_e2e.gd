extends Node
## 无头联机机器人：用游戏里真正的 lifeline_client.gd + world_view.gd 连真 Nakama，两个进程扮演两台手机。
##   青：godot --headless --path client res://tests/net_e2e.tscn -- --device=e2e-q --bot=qing --codefile=/tmp/code
##   梅：godot --headless --path client res://tests/net_e2e.tscn -- --device=e2e-m --bot=mei  --codefile=/tmp/code
## 一般用 tools/net_e2e.sh 一起启动。流程：
##   青开线写配对码 → 梅读码加入 → 青收到通知自动进屋 → 两人投胎 → 同框，各自走到地图上的一个点
##   → 梅中途把 socket 硬断（模拟切网络），靠自动重连回来 → 两人互相看到对方停在对的位置
##   → 统计对方角色在画面上的移动是否平滑（插值缓冲）

const NetClient := preload("res://scripts/net/lifeline_client.gd")
const WorldView := preload("res://scripts/world/world_view.gd")

var bot := "qing"
var codefile := ""
var net
var world
var content: Dictionary = {}
var phase := "start"
var reconnects := 0
var lost := 0
var t0 := 0.0
var remote_trace: Array = []  ## 对方在我画面上的位置（每帧）


func _arg(name: String, fallback := "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.trim_prefix("--%s=" % name)
	return fallback


func _log(s: String) -> void:
	print("[%s %5.1fs] %s" % [bot, Time.get_ticks_msec() / 1000.0 - t0, s])


func _fail(s: String) -> void:
	_log("FAIL " + s)
	get_tree().quit(1)


func _ready() -> void:
	t0 = Time.get_ticks_msec() / 1000.0
	bot = _arg("bot", "qing")
	codefile = _arg("codefile", "/tmp/tongsui-e2e-code")
	content = JSON.parse_string(FileAccess.get_file_as_string("res://data/content.json"))
	get_tree().create_timer(90.0).timeout.connect(func(): _fail("超时，停在阶段 " + phase))
	net = NetClient.new()
	add_child(net)
	net.failed.connect(func(t): _log("net failed: " + t))
	net.snapshot.connect(_on_snapshot)
	net.world_state.connect(_on_world)
	net.partner_joined.connect(func(_id, n): _log("收到通知：%s 来了" % n))
	net.connection_changed.connect(_on_conn)
	if not await net.connect_server():
		_fail("连不上服务器 " + net.server_address())
		return
	_log("已连接 " + net.server_address())
	if bot == "qing":
		net.created.connect(func(code, _id):
			var f := FileAccess.open(codefile, FileAccess.WRITE)
			f.store_string(code)
			f.close()
			_log("开线，配对码 " + code))
		phase = "waiting"
		net.create_lifeline("机器人青")
	else:
		phase = "reading code"
		var code := ""
		for i in 200:
			if FileAccess.file_exists(codefile):
				code = FileAccess.get_file_as_string(codefile).strip_edges()
				if code.length() == 6:
					break
			await get_tree().create_timer(0.1).timeout
		_log("读到配对码 " + code)
		DirAccess.remove_absolute(codefile)
		net.join_lifeline(code, "机器人梅")


func _on_conn(online: bool) -> void:
	if online:
		reconnects += 1
		_log("自动重连成功")
	else:
		lost += 1
		_log("连接断了，开始重连")


func _on_snapshot(d: Dictionary) -> void:
	var ph := str(d.life.phase)
	_log("快照 phase=%s you=%s online=%s" % [ph, d.you, d.online])
	if ph == "roll":
		phase = "roll"
		net.confirm_roll()
	elif ph == "life":
		if world == null:
			world = WorldView.new()
			add_child(world)
			world.setup(content, str(d.you), d.names)
			world.net = net
			world.move_report.connect(func(p): net.move(p))
			phase = "life"
			_play()
		world.apply_snapshot_actors(d.life.world.actors)
		world.me().walk_target = _target()  # 重连快照会把人放回服务器位置，接着走


func _on_world(d: Dictionary) -> void:
	if world != null:
		world.apply_world(d)


func _target() -> Vector2:
	# 两人在楼下街上碰头，各站一边
	return Vector2(1500, 470) if bot == "qing" else Vector2(1720, 470)


func _other() -> String:
	return "mei" if bot == "qing" else "qing"


func _play() -> void:
	world.me().walk_target = _target()
	_log("走向 %s" % _target())
	if bot == "mei":
		await get_tree().create_timer(2.0).timeout
		_log("硬断 socket（模拟切网络）")
		net.socket.close()  # 不走 go_offline：要靠 closed 信号自己连回来
	await get_tree().create_timer(14.0).timeout
	_check()


func _process(_delta: float) -> void:
	if world != null and phase == "life":
		var o = world.actors[_other()]
		remote_trace.append(o.position)


func _check() -> void:
	var me = world.me()
	var other = world.actors[_other()]
	var other_target := Vector2(1720, 470) if bot == "qing" else Vector2(1500, 470)
	_log("我在 %s（目标 %s），画面里 TA 在 %s（TA 的目标 %s）" % [me.position.round(), _target(), other.position.round(), other_target])
	if me.position.distance_to(_target()) > 12.0:
		return _fail("自己没走到")
	if other.position.distance_to(other_target) > 30.0:
		return _fail("看到的 TA 不在 TA 该在的地方")
	if bot == "mei" and (lost < 1 or reconnects < 1):
		return _fail("应该断过一次并自动连回来")
	# 平滑度：对方走动时每帧位移的抖动（帧间位移的标准差 / 均值），越小越匀速
	var steps: Array = []
	for i in range(1, remote_trace.size()):
		var d: float = remote_trace[i].distance_to(remote_trace[i - 1])
		if d > 0.05 and d < 100.0:
			steps.append(d)
	var mean := 0.0
	for s in steps:
		mean += s
	mean /= maxf(steps.size(), 1)
	var v := 0.0
	for s in steps:
		v += (s - mean) * (s - mean)
	var cv := sqrt(v / maxf(steps.size(), 1)) / maxf(mean, 0.001)
	_log("对方移动 %d 帧，平均每帧 %.2f px，抖动系数 %.2f；RTT %d ms；断线 %d 次，重连 %d 次" % [steps.size(), mean, cv, int(net.rtt_ms), lost, reconnects])
	_log("PASS")
	# 等对方也检查完再走，别让自己下线影响 TA 的检查
	await get_tree().create_timer(3.0).timeout
	net.go_offline()
	get_tree().quit(0)
