extends VBoxContainer
## 「服务器设置」面板：改联机服务器地址和 server key，测试连通性。
## 用法：var p := ServerSettings.new(); p.done.connect(...); body.add_child(p)
## 保存到 user://server.json，优先于打包时内置的地址（见 scripts/net/config.gd）。

signal done(changed: bool)

const Config := preload("res://scripts/net/config.gd")
const P := preload("res://scripts/ui/palette.gd")

var _addr: LineEdit
var _key: LineEdit
var _status: Label
var _http: HTTPRequest


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 24)

	_text("服务器设置", 72)
	_text("现在连的是：%s\n来源：%s" % [Config.url(), _source_name()], 30, P.INK_SOFT)

	_text("地址", 32)
	_addr = LineEdit.new()
	_addr.placeholder_text = "tongsui.example.com 或 https://1-2-3-4.sslip.io"
	_addr.text = Config.url()
	_addr.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_URL
	add_child(_addr)

	_text("Server key（部署脚本最后打印的那串）", 32)
	_key = LineEdit.new()
	_key.text = Config.SERVER_KEY
	_key.secret = true
	add_child(_key)

	_status = _text("", 30, P.INK_SOFT)

	_http = HTTPRequest.new()
	_http.timeout = 8.0
	_http.request_completed.connect(_on_health)
	add_child(_http)

	_btn("测试连接", _test)
	_btn("保存", _save)
	_btn("恢复打包时的地址", _reset)
	_btn("返回", func(): done.emit(false))


func _source_name() -> String:
	match Config.SOURCE:
		"cmdline":
			return "命令行参数"
		"user":
			return "你在这里保存的"
		"built_in":
			return "打包时内置"
	return "本机开发默认"


func _parsed() -> Dictionary:
	var cfg := Config.parse_address(_addr.text)
	if cfg.is_empty():
		_status.text = "地址看不懂，试试 tongsui.example.com"
		_status.add_theme_color_override("font_color", P.MEI)
		return {}
	cfg["server_key"] = _key.text.strip_edges()
	return cfg


func _test() -> void:
	var cfg := _parsed()
	if cfg.is_empty():
		return
	_http.cancel_request()
	var u := "%s://%s:%d/healthcheck" % [cfg.scheme, cfg.host, cfg.port]
	_status.text = "正在连 %s ……" % u
	_status.add_theme_color_override("font_color", P.INK_SOFT)
	var err := _http.request(u)
	if err != OK:
		_status.text = "发不出请求（错误 %d）" % err
		_status.add_theme_color_override("font_color", P.MEI)


func _on_health(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		_status.text = "通了 ✓ 服务器在线"
		_status.add_theme_color_override("font_color", P.QING)
	elif result == HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
		_status.text = "HTTPS 证书不对：服务器的证书可能还没申请下来"
		_status.add_theme_color_override("font_color", P.MEI)
	elif result == HTTPRequest.RESULT_CANT_RESOLVE:
		_status.text = "找不到这个域名：检查拼写，或者 DNS 还没生效"
		_status.add_theme_color_override("font_color", P.MEI)
	elif result == HTTPRequest.RESULT_SUCCESS:
		_status.text = "连上了，但返回 %d：地址可能不是同岁服务器" % code
		_status.add_theme_color_override("font_color", P.MEI)
	else:
		_status.text = "连不上（%d）：服务器没开、端口被安全组拦了，或者网络不通" % result
		_status.add_theme_color_override("font_color", P.MEI)


func _save() -> void:
	var cfg := _parsed()
	if cfg.is_empty():
		return
	Config.save_user(cfg)
	done.emit(true)


func _reset() -> void:
	Config.clear_user()
	done.emit(true)


func _text(t: String, font_size: int, color := P.INK) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(l)
	return l


func _btn(t: String, on_press: Callable) -> void:
	var b := Button.new()
	b.text = t
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(on_press)
	add_child(b)
