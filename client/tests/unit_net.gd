extends SceneTree
## 联机小零件的单测（不需要服务器）：godot --headless --path client -s res://tests/unit_net.gd

const SnapshotBuffer := preload("res://scripts/net/snapshot_buffer.gd")
const ServerClock := preload("res://scripts/net/server_clock.gd")
const Config := preload("res://scripts/net/config.gd")

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("✗ ", what)


func _init() -> void:
	# 插值：两帧之间匀速
	var b = SnapshotBuffer.new()
	b.push(1.0, Vector2(0, 0))
	b.push(1.2, Vector2(60, 0))
	b.push(1.4, Vector2(120, 0))
	check(b.sample(1.1).is_equal_approx(Vector2(30, 0)), "两帧中间取中点")
	check(b.sample(1.3).is_equal_approx(Vector2(90, 0)), "第二段中点")
	check(b.sample(0.5).is_equal_approx(Vector2(0, 0)), "早于第一帧取第一帧")
	# 外推最多 0.25 秒
	check(b.sample(1.5).is_equal_approx(Vector2(150, 0)), "晚到时按速度外推")
	check(b.sample(9.0).is_equal_approx(Vector2(195, 0)), "外推有上限")
	# 乱序旧帧丢掉
	b.push(1.3, Vector2(999, 0))
	check(b.sample(1.3).is_equal_approx(Vector2(90, 0)), "乱序帧不进缓冲")
	# 瞬移不插值
	b.push(1.6, Vector2(2000, 0))
	check(b.sample(1.5).is_equal_approx(Vector2(2000, 0)), "跳太远直接到位")

	# 时钟：跟随 tick，抖动不跳
	var c = ServerClock.new()
	c.observe(100, 50.0)            # 服务器 10 秒，本地 50 秒
	check(absf(c.server_now(50.0) - 10.0) < 0.001, "第一次直接对齐")
	c.observe(102, 50.25)           # 晚到 0.05 秒的包
	check(absf(c.server_now(50.25) - 10.25) < 0.05, "小抖动平滑")
	c.observe(500, 51.0)            # 服务器重启之类的大跳
	check(absf(c.server_now(51.0) - 50.0) < 0.001, "大偏差直接跳")

	# 服务器地址解析
	var d: Dictionary = Config.parse_address("192.168.1.5")
	check(d.host == "192.168.1.5" and d.port == 7350 and d.scheme == "http", "只填 IP")
	d = Config.parse_address("https://tongsui.example.com/")
	check(d.port == 443 and d.scheme == "https", "填域名")
	check(Config.parse_address("10.0.0.2:9000").port == 9000, "IP:端口")

	print("✓ 联机零件单测通过" if fails == 0 else "✗ %d 项失败" % fails)
	quit(1 if fails > 0 else 0)
