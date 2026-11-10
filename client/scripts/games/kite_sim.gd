extends RefCounted
## 放风筝的本地试玩：不联网时自己跟一个「陪练」放一局，用来试手感和调画面。
## 物理照抄 server/src/games.ts 的 kiteTick（那边才算数，改规则先改那边，再同步这里）。
## 出的每一帧和服务器 OP.GAME 的 game 字段同一个形状，kite.gd 分不出来。

const SECONDS := 30.0
const NEED := 0.75
const LEAD_IN := 3.0

var t := -LEAD_IN
var d := {}
var me := "qing"


func start(my_role: String, i_hold: bool, rng_seed: int) -> void:
	me = my_role
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var ph: Array = []
	for i in 8:
		ph.append(rng.randf() * TAU)
	var other := "mei" if my_role == "qing" else "qing"
	d = {
		"holder": my_role if i_hold else other, "dur": SECONDS,
		"kx": 0.5, "kh": 0.06, "rx": 0.5, "line": 0.05, "tx": 0.5, "tl": 0.05,
		"wx": 0.5, "wh": 0.6, "wr": 0.14, "prog": 0.0, "inside": false, "snag": 0.0, "ph": ph,
	}
	var w0 := _sweet(0.0)
	d.wx = w0.x
	d.wh = w0.y
	t = -LEAD_IN


func _sweet(at: float) -> Vector2:
	var ph: Array = d.ph
	return Vector2(
		0.5 + 0.3 * sin(0.5 * at + ph[0]) + 0.1 * sin(1.13 * at + ph[1]),
		0.6 + 0.2 * sin(0.41 * at + ph[2]) + 0.08 * sin(0.97 * at + ph[3]))


func input(body: Dictionary) -> void:
	if t < 0.0:
		return
	if body.get("k") == "line" and d.holder == me:
		d.tl = clampf(float(body.get("v", d.tl)), 0.0, 1.0)
	elif body.get("k") == "run" and d.holder != me:
		d.tx = clampf(float(body.get("v", d.tx)), 0.0, 1.0)


## 往前走一步。打完了返回得分（0~100），否则返回 -1
func tick(dt: float) -> float:
	t += dt
	if t < 0.0:
		return -1.0
	var sw := _sweet(t)
	d.wx = sw.x
	d.wh = sw.y
	d.wr = 0.14 - 0.04 * clampf(t / SECONDS, 0.0, 1.0)
	# 陪练：盯着半秒前的风口，手有点晃
	var seen := _sweet(t - 0.5)
	var wob := 0.07 * sin(0.83 * t + float(d.ph[6]))
	if d.holder == me:
		d.tx = clampf(seen.x + wob, 0.0, 1.0)
	else:
		d.tl = clampf((seen.y - 0.06) / 0.9 + wob, 0.0, 1.0)
	d.rx = move_toward(float(d.rx), float(d.tx), 0.5 * dt)
	d.line = move_toward(float(d.line), float(d.tl), 0.45 * dt)
	if float(d.snag) > 0.0:
		d.snag = float(d.snag) - dt
		if float(d.snag) <= 0.0:
			d.kh = 0.24
			d.line = maxf(float(d.line), 0.22)
			d.tl = maxf(float(d.tl), 0.22)
	else:
		var sway := 0.05 * sin(1.7 * t + float(d.ph[4])) * (0.3 + float(d.line))
		var bob := 0.03 * sin(2.3 * t + float(d.ph[5]))
		d.kx = float(d.kx) + (float(d.rx) + sway - float(d.kx)) * (1.0 - exp(-dt / 0.45))
		d.kh = float(d.kh) + (0.06 + 0.9 * float(d.line) + bob - float(d.kh)) * (1.0 - exp(-dt / 0.35))
		if t > 4.0 and float(d.kx) < 0.3 and float(d.kh) < 0.16:
			d.snag = 1.6
			d.prog = maxf(0.0, float(d.prog) - 0.06)
	var dx := (float(d.kx) - float(d.wx)) * 0.6
	var dh := float(d.kh) - float(d.wh)
	d.inside = float(d.snag) <= 0.0 and sqrt(dx * dx + dh * dh) < float(d.wr)
	if d.inside:
		d.prog = minf(1.0, float(d.prog) + dt / (SECONDS * NEED))
	if t >= SECONDS or float(d.prog) >= 1.0:
		return float(d.prog) * 100.0
	return -1.0


func view() -> Dictionary:
	var out := d.duplicate()
	out.snag = float(d.snag) > 0.0
	return {"gameId": "kite", "phase": "play", "t": t, "d": out}
