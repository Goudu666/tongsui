extends Node
## 联机封装：设备登录 → 配对 RPC → 加入权威房间 → 收发消息；另外负责「掉了自己连回来」。
## 依赖 nakama-godot 插件（client/addons/com.heroiclabs.nakama），插件以 autoload「Nakama」注册。
## 这里故意不写插件的类型名，插件缺失时这个脚本仍能被解析，只是不能用。
##
## 连接的一生：
##   connect_server() 登录（会话存在 user://session.cfg，7 天内重开 App 不用重新登录）→ 开 socket
##   open_lifeline(id) 拿 matchId → 进房间（记住 id，断线后自动回到这条人生线）
##   断线（socket closed / 8 秒没收到任何东西 / App 从后台回来发现连接死了）
##     → 退避重连 1s 2s 4s 8s 10s… → 重新 open_lifeline（房间可能已关闭重开）→ 服务器重发快照

signal status(text: String)
signal failed(text: String)
signal created(code: String, lifeline_id: String)
signal opened(info: Dictionary)
signal lifelines(items: Array)
signal partner_joined(lifeline_id: String, partner_name: String)
signal recovered(ok: bool, text: String)  ## 用找回码登录的结果
signal connection_changed(online: bool)  ## false = 断了，正在重连；true = 回来了
signal snapshot(data: Dictionary)
signal roll_state(data: Dictionary)
signal world_state(data: Dictionary)
signal event_started(data: Dictionary)
signal log_entries(data: Dictionary)
signal presence(data: Dictionary)

const Config := preload("res://scripts/net/config.gd")
const Op := preload("res://scripts/net/protocol.gd")
const ServerClock := preload("res://scripts/net/server_clock.gd")

const SESSION_PATH := "user://session.cfg"
const RECOVERY_PATH := "user://recovery.cfg"
const RECOVERY_PREFIX := "tongsui-recover-"
const CODE_ABC := "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"  ## 去掉容易看错的 0/O/1/I，和配对码一样
const SESSION_SCRIPT := "res://addons/com.heroiclabs.nakama/api/NakamaSession.gd"
const LOG_ERROR := 1  ## NakamaLogger.LOG_LEVEL.ERROR；默认 DEBUG 会把每个请求都打出来
const LAST_PATH := "user://lifeline.cfg"
const PING_INTERVAL := 2.0
const WATCHDOG_SECONDS := 8.0     ## 在房间里这么久没收到任何消息（WORLD 是 5Hz），认为连接已死
const RESUME_STALE_SECONDS := 3.0 ## 从后台回来时，超过这么久没消息就直接重连
const BACKOFF := [1.0, 2.0, 4.0, 8.0, 10.0]
const WAIT_POLL_SECONDS := 5.0    ## 等 TA 输配对码时，通知万一丢了，也定时问一下服务器

var client
var session
var socket
var match_id := ""
var lifeline_id := ""        ## 想待在哪条人生线里（断线后要回去的地方）
var waiting_lifeline := ""   ## 正在等 TA 输配对码的人生线
var clock := ServerClock.new()
var rtt_ms := -1.0
var connected := false

var _want_online := false
var _reconnecting := false
var _last_rx := 0.0
var _ping_timer := 0.0
var _wait_timer := 0.0
var _move_seq := 0
var _move_history := {}      ## seq -> Vector2，服务器回 seq 时拿来对照


static func addon_available() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	return tree != null and tree.root.get_node_or_null("Nakama") != null


func _nakama():
	return get_tree().root.get_node("Nakama")


func server_address() -> String:
	return Config.url()


# ======================================================================
# 登录与会话
# ======================================================================

func _device_id() -> String:
	# 同一台电脑开两个窗口测试时：godot -- --device=b
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--device="):
			return "tongsui-device-" + arg.trim_prefix("--device=")  # Nakama 要求 10~128 个字符
	var path := "user://device_id"
	if FileAccess.file_exists(path):
		var saved := FileAccess.get_file_as_string(path).strip_edges()
		if saved.length() >= 10:
			return saved
	# 安卓上 get_unique_id 是 ANDROID_ID：卸载重装也不变，人生线不会丢
	var uid := OS.get_unique_id()
	var id := ("tongsui-" + uid) if uid.length() >= 4 else "tongsui-%d-%d" % [Time.get_unix_time_from_system(), randi()]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(id)
	return id


func _session_key() -> String:
	# 不同服务器、不同测试设备的会话分开存
	return "%s|%s" % [Config.url(), _device_id()]


func _load_session():
	var f := ConfigFile.new()
	if f.load(SESSION_PATH) != OK:
		return null
	var key := _session_key()
	var token := str(f.get_value(key, "token", ""))
	if token.is_empty():
		return null
	var refresh := str(f.get_value(key, "refresh", ""))
	var s = load(SESSION_SCRIPT).new(token, false, refresh if refresh != "" else null)
	if s == null or s.is_exception() or not s.is_valid():
		return null
	return s


func _save_session() -> void:
	if session == null or session.is_exception():
		return
	var f := ConfigFile.new()
	f.load(SESSION_PATH)
	f.set_value(_session_key(), "token", session.token)
	f.set_value(_session_key(), "refresh", session.refresh_token)
	f.save(SESSION_PATH)


func _forget_session() -> void:
	session = null
	var f := ConfigFile.new()
	if f.load(SESSION_PATH) == OK and f.has_section(_session_key()):
		f.erase_section(_session_key())
		f.save(SESSION_PATH)


## 保证手里有一个还能用一会儿的会话：先用存下来的，快过期就刷新，刷新不了就重新设备登录
func _ensure_session() -> bool:
	if client == null:
		client = _nakama().create_client(Config.SERVER_KEY, Config.HOST, Config.PORT, Config.SCHEME, 8, LOG_ERROR)
		session = _load_session()
	if session != null and not session.is_exception() and not session.would_expire_in(300):
		return true
	if session != null and not session.is_exception() and session.refresh_token != "" and not session.is_refresh_expired():
		var refreshed = await client.session_refresh_async(session)
		if not refreshed.is_exception():
			session = refreshed
			_save_session()
			return true
	var s
	var rc := _saved_recovery()
	if rc != "":
		# 这台手机用找回码登过：以后都用找回码这个身份
		s = await client.authenticate_custom_async(RECOVERY_PREFIX + rc, null, false)
	else:
		s = await client.authenticate_device_async(_device_id())
	if s.is_exception():
		failed.emit("登录失败：%s" % _err_text(s.get_exception()))
		return false
	session = s
	_save_session()
	return true


func _err_text(ex) -> String:
	var msg := str(ex.message) if ex != null else ""
	if msg.is_empty() or "connect" in msg.to_lower() or "timeout" in msg.to_lower():
		return "连不上服务器（%s）" % Config.url()
	return msg


# ======================================================================
# 找回码：换手机、卸载重装后找回自己的人生线
# 第一次看找回码时生成一个 10 位码，作为 Nakama 的 custom id 绑到当前账号上；
# 新手机上输入它，用 authenticate_custom 登回同一个账号（同一个 user_id，人生线都在）。
# ======================================================================

func _recovery_section() -> String:
	# 按「服务器 + 设备」分开存：同一台电脑用 --device= 开两个窗口测试时互不影响
	return _session_key()


func _saved_recovery() -> String:
	var f := ConfigFile.new()
	if f.load(RECOVERY_PATH) != OK:
		return ""
	return str(f.get_value(_recovery_section(), "code", ""))


func _save_recovery(code: String) -> void:
	var f := ConfigFile.new()
	f.load(RECOVERY_PATH)
	f.set_value(_recovery_section(), "code", code)
	f.save(RECOVERY_PATH)


static func _new_code() -> String:
	var s := ""
	for i in 10:
		s += CODE_ABC[randi() % CODE_ABC.length()]
	return s


## 我的找回码（没有就生成并绑定）。失败返回 ""
func recovery_code() -> String:
	var saved := _saved_recovery()
	if saved != "":
		return saved
	if not await _ensure_session():
		return ""
	var code := _new_code()
	var r = await client.link_custom_async(session, RECOVERY_PREFIX + code)
	if r.is_exception():
		failed.emit("生成找回码失败：%s" % _err_text(r.get_exception()))
		return ""
	_save_recovery(code)
	return code


## 新手机上输入旧手机的找回码
func recover(code: String) -> void:
	var c := code.strip_edges().to_upper().replace(" ", "")
	if c.length() != 10:
		recovered.emit(false, "找回码是 10 位")
		return
	if client == null and not await _ensure_session():
		recovered.emit(false, "连不上服务器")
		return
	var s = await client.authenticate_custom_async(RECOVERY_PREFIX + c, null, false)
	if s.is_exception():
		recovered.emit(false, "找回码不对（%s）" % _err_text(s.get_exception()))
		return
	session = s
	_save_session()
	_save_recovery(c)
	# 换了身份：socket 要用新会话重连
	if _want_online:
		_drop_socket()
		await _open_socket()
	recovered.emit(true, "找回来了")


# ======================================================================
# Socket
# ======================================================================

func connect_server() -> bool:
	_want_online = true
	status.emit("正在连接服务器……")
	var ok := await _open_socket()
	if ok:
		status.emit("已连接")
	return ok


func _open_socket() -> bool:
	if not await _ensure_session():
		return false
	_drop_socket()
	socket = _nakama().create_socket_from(client)
	socket.received_match_state.connect(_on_match_state)
	socket.received_notification.connect(_on_notification)
	socket.closed.connect(_on_socket_closed)
	var conn = await socket.connect_async(session)
	if conn.is_exception():
		failed.emit("连接失败：%s" % _err_text(conn.get_exception()))
		_drop_socket()
		return false
	connected = true
	_last_rx = ServerClock.local_now()
	return true


func _drop_socket() -> void:
	connected = false
	match_id = ""
	if socket == null:
		return
	var old = socket
	socket = null
	for pair in [["received_match_state", _on_match_state], ["received_notification", _on_notification], ["closed", _on_socket_closed]]:
		if old.is_connected(pair[0], pair[1]):
			old.disconnect(pair[0], pair[1])
	old.close()


func _on_socket_closed() -> void:
	connected = false
	match_id = ""
	if _want_online:
		_reconnect()


func is_online() -> bool:
	return connected and socket != null and socket.is_connected_to_host()


## 断线重连：退避重试，直到连上或者玩家退出联机
func _reconnect() -> void:
	if _reconnecting or not _want_online:
		return
	_reconnecting = true
	connection_changed.emit(false)
	var attempt := 0
	while _want_online:
		var wait: float = BACKOFF[mini(attempt, BACKOFF.size() - 1)]
		attempt += 1
		await get_tree().create_timer(wait).timeout
		if not _want_online:
			break
		if await _open_socket():
			var back := true
			if lifeline_id != "":
				back = await open_lifeline(lifeline_id, true)
			if back:
				_reconnecting = false
				connection_changed.emit(true)
				return
	_reconnecting = false


## 退出联机（回到标题）：不再重连
func go_offline() -> void:
	_want_online = false
	lifeline_id = ""
	waiting_lifeline = ""
	_drop_socket()


func _process(delta: float) -> void:
	if not _want_online or _reconnecting:
		return
	if match_id != "" and connected:
		_ping_timer += delta
		if _ping_timer >= PING_INTERVAL:
			_ping_timer = 0.0
			_send(Op.PING, {"t": Time.get_ticks_msec()})
		if ServerClock.local_now() - _last_rx > WATCHDOG_SECONDS:
			# 手机切网络、进电梯时 socket 不一定会报 closed，看门狗兜底
			_drop_socket()
			_reconnect()
			return
	if waiting_lifeline != "" and match_id == "" and connected:
		_wait_timer += delta
		if _wait_timer >= WAIT_POLL_SECONDS:
			_wait_timer = 0.0
			_poll_waiting()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if not _want_online or _reconnecting or socket == null:
			return
		var stale := match_id != "" and ServerClock.local_now() - _last_rx > RESUME_STALE_SECONDS
		if stale or not socket.is_connected_to_host():
			_drop_socket()
			_reconnect()


# ======================================================================
# RPC：配对、打开、列表
# ======================================================================

func _rpc(id: String, payload: Dictionary) -> Variant:
	if not await _ensure_session():
		return null
	var res = await client.rpc_async(session, id, JSON.stringify(payload))
	if res.is_exception():
		failed.emit(_err_text(res.get_exception()))
		return null
	return JSON.parse_string(res.payload)


func create_lifeline(player_name: String) -> void:
	var r = await _rpc("lifeline_create", {"name": player_name})
	if r != null:
		waiting_lifeline = str(r.lifelineId)
		_remember(waiting_lifeline)
		created.emit(r.code, r.lifelineId)


func join_lifeline(code: String, player_name: String) -> void:
	if code.length() != 6:
		failed.emit("配对码是 6 位")
		return
	var r = await _rpc("lifeline_join", {"code": code.to_upper(), "name": player_name})
	if r != null:
		await open_lifeline(r.lifelineId)


func list_lifelines() -> void:
	var r = await _rpc("lifeline_list", {})
	if r != null:
		lifelines.emit(r.get("lifelines", []))


## 打开一条人生线并进入它的房间。quiet = 重连时用，不发 opened（界面不用跳）
func open_lifeline(id: String, quiet := false) -> bool:
	var r = await _rpc("lifeline_open", {"lifelineId": id})
	if r == null:
		return false
	_remember(id)
	if r.get("matchId") == null:
		waiting_lifeline = id
		_wait_timer = 0.0
		if not quiet:
			opened.emit(r)
		status.emit("等 TA 输入配对码……")
		return true
	waiting_lifeline = ""
	if not quiet:
		opened.emit(r)
	if socket == null:
		return false
	# 先把房间记下来再进：服务器的进房快照可能比 join 的回执先到，
	# 界面收到快照马上要发消息（比如确认投胎），这时 match_id 必须已经有了
	lifeline_id = id
	match_id = str(r.matchId)
	_last_rx = ServerClock.local_now()
	_ping_timer = PING_INTERVAL  # 进房立刻测一次延迟
	_move_seq = 0
	_move_history.clear()
	clock.reset()
	var m = await socket.join_match_async(r.matchId)
	if m.is_exception():
		match_id = ""
		failed.emit("进入房间失败：%s" % _err_text(m.get_exception()))
		return false
	return true


func _poll_waiting() -> void:
	var id := waiting_lifeline
	var r = await _rpc("lifeline_open", {"lifelineId": id})
	if r != null and r.get("matchId") != null and waiting_lifeline == id:
		partner_joined.emit(id, "")
		await open_lifeline(id)


func _on_notification(n) -> void:
	var content: Variant = JSON.parse_string(str(n.content))
	if not content is Dictionary:
		return
	var id := str(content.get("lifelineId", ""))
	if int(n.code) == Op.NOTIFY_PARTNER_JOINED and id == waiting_lifeline and match_id == "":
		# TA 输入了配对码：直接进房间开始投胎
		partner_joined.emit(id, str(content.get("name", "")))
		await open_lifeline(id)


func _remember(id: String) -> void:
	var f := ConfigFile.new()
	f.load(LAST_PATH)
	f.set_value(_session_key(), "last", id)
	f.save(LAST_PATH)


## 上次玩的人生线（大厅里放在最上面）
func last_lifeline() -> String:
	var f := ConfigFile.new()
	if f.load(LAST_PATH) != OK:
		return ""
	return str(f.get_value(_session_key(), "last", ""))


# ======================================================================
# 房间消息
# ======================================================================

func _send(op: int, body: Dictionary) -> void:
	if match_id != "" and socket != null and connected:
		socket.send_match_state_async(match_id, op, JSON.stringify(body))


func reroll() -> void:
	_send(Op.ROLL, {"reroll": true})


func confirm_roll() -> void:
	_send(Op.ROLL, {"confirm": true})


## 上报自己的位置，带递增序号；服务器在 WORLD 里回「处理到第几条」，用来校正
func move(pos: Vector2) -> void:
	if match_id == "" or not connected:
		return
	_move_seq += 1
	var p := Vector2(snappedf(pos.x, 1.0), snappedf(pos.y, 1.0))
	_move_history[_move_seq] = p
	if _move_history.size() > 64:
		var drop := []
		for k in _move_history:
			if int(k) <= _move_seq - 64:
				drop.append(k)
		for k in drop:
			_move_history.erase(k)
	_send(Op.MOVE, {"x": p.x, "y": p.y, "seq": _move_seq})


func last_move_seq() -> int:
	return _move_seq


## 服务器处理第 seq 条 MOVE 时，我本地上报的位置（没有就返回 null）
func sent_position(seq: int) -> Variant:
	var p: Variant = _move_history.get(seq)
	for k in _move_history.keys():
		if int(k) < seq:
			_move_history.erase(k)
	return p


func act(spot_id: String) -> void:
	_send(Op.ACT, {"spot": spot_id})


func choose(option_id: String) -> void:
	_send(Op.CHOOSE, {"optionId": option_id})


func _on_match_state(state) -> void:
	_last_rx = ServerClock.local_now()
	var data: Variant = JSON.parse_string(state.data)
	if not data is Dictionary:
		return
	var op := int(state.op_code)
	if op == Op.WORLD:
		if data.has("tick"):
			clock.observe(int(data.tick))
		world_state.emit(data)
	elif op == Op.PONG:
		rtt_ms = float(Time.get_ticks_msec() - int(data.get("t", 0)))
		if data.has("tick"):
			clock.observe(int(data.tick))
	elif op == Op.SNAPSHOT:
		if data.has("tick"):
			clock.observe(int(data.tick))
		snapshot.emit(data)
	elif op == Op.ROLL_STATE:
		roll_state.emit(data)
	elif op == Op.EVENT:
		event_started.emit(data)
	elif op == Op.LOG:
		log_entries.emit(data)
	elif op == Op.PRESENCE:
		presence.emit(data)
	elif op == Op.ERROR:
		failed.emit(str(data.get("message", "")))
