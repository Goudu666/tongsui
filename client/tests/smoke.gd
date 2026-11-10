extends Node
## 无头冒烟：解析配置 → 跑主场景 → 进联机页 / 服务器设置 / 离线逛逛，各停几帧。
## CI 里跑：godot --headless --path client res://tests/smoke.tscn
## 失败时退出码非 0；另外 CI 会在输出里找 SCRIPT ERROR。

const Config := preload("res://scripts/net/config.gd")

var _failures := 0


func _ready() -> void:
	_check_config()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(10)
	main._show_online()
	await _frames(10)
	main._show_server_settings()
	await _frames(10)
	main._show_title()
	await _frames(5)
	main._start_preview()
	await _frames(30)
	print("[smoke] 主场景、联机页、服务器设置、离线逛逛都跑过了")
	print("[smoke] %s" % ("通过" if _failures == 0 else "失败 %d 项" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _check_config() -> void:
	_eq(Config.parse_address("tongsui.example.com"), {"host": "tongsui.example.com", "port": 443, "scheme": "https"})
	_eq(Config.parse_address(" https://1-2-3-4.sslip.io/ "), {"host": "1-2-3-4.sslip.io", "port": 443, "scheme": "https"})
	_eq(Config.parse_address("http://192.168.1.5:7350"), {"host": "192.168.1.5", "port": 7350, "scheme": "http"})
	_eq(Config.parse_address("192.168.1.5"), {"host": "192.168.1.5", "port": 7350, "scheme": "http"})
	_eq(Config.parse_address("example.com:8443"), {"host": "example.com", "port": 8443, "scheme": "https"})
	_eq(Config.parse_address(""), {})
	print("[smoke] 当前服务器 %s（来源 %s）" % [Config.url(), Config.SOURCE])


func _eq(got: Variant, want: Variant) -> void:
	if got != want:
		_failures += 1
		printerr("[smoke] 期望 %s，实际 %s" % [want, got])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
