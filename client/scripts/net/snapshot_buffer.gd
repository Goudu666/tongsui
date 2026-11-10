extends RefCounted
## 对方角色的插值缓冲：存最近一串（服务器时间, 位置），画面落后服务器 DELAY 秒播放，
## 在两帧之间线性插值，走起来是匀速的，不会像直接 lerp 那样一顿一顿地「追」。
## - 包来晚了：用最后的速度往前外推一小段（最多 MAX_EXTRAPOLATE 秒），然后停住
## - 两帧之间跳得太远（换了一天回到家门口、被事件叫过去）：不插值，直接到位

const DELAY := 0.25           ## 世界广播 5Hz，落后 0.25 秒保证手里总有两帧
const MAX_EXTRAPOLATE := 0.25
const TELEPORT_DIST := 500.0
const KEEP := 24

var _t: PackedFloat64Array = []
var _p: PackedVector2Array = []


func push(t: float, pos: Vector2) -> void:
	var n := _t.size()
	if n > 0 and t <= _t[n - 1]:
		if is_equal_approx(t, _t[n - 1]):
			_p[n - 1] = pos
		return  # 乱序的旧帧不要
	_t.append(t)
	_p.append(pos)
	if _t.size() > KEEP:
		_t.remove_at(0)
		_p.remove_at(0)


func clear() -> void:
	_t.clear()
	_p.clear()


func is_empty() -> bool:
	return _t.is_empty()


func latest() -> Vector2:
	return _p[_p.size() - 1] if not _p.is_empty() else Vector2.ZERO


## render_time = 服务器时间 - DELAY
func sample(render_time: float) -> Vector2:
	var n := _t.size()
	if n == 0:
		return Vector2.ZERO
	if n == 1 or render_time <= _t[0]:
		return _p[0] if render_time <= _t[0] else _p[n - 1]
	if render_time >= _t[n - 1]:
		var a := _p[n - 2]
		var b := _p[n - 1]
		var span := _t[n - 1] - _t[n - 2]
		if span <= 0.0 or a.distance_to(b) > TELEPORT_DIST:
			return b
		var ahead := minf(render_time - _t[n - 1], MAX_EXTRAPOLATE)
		return b + (b - a) / span * ahead
	# 二分找到 render_time 所在的区间
	var lo := 0
	var hi := n - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if _t[mid] <= render_time:
			lo = mid
		else:
			hi = mid
	var pa := _p[lo]
	var pb := _p[hi]
	if pa.distance_to(pb) > TELEPORT_DIST:
		return pb
	var k := (render_time - _t[lo]) / (_t[hi] - _t[lo])
	return pa.lerp(pb, k)
