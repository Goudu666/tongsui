extends RefCounted
## 估计「服务器现在是第几秒」，给插值缓冲用。
## 服务器每条 WORLD 都带 tick（每秒 TICK_RATE 跳）。收到时 server_time ≈ tick / TICK_RATE + 单程延迟，
## 我们记 offset = server_time - local_time，平滑跟随；网络抖动时偏差大于 1 秒就直接跳过去。

const TICK_RATE := 10.0
const SNAP_THRESHOLD := 1.0
const SMOOTH := 0.1

var _offset := 0.0
var _has := false


static func local_now() -> float:
	return Time.get_ticks_usec() / 1000000.0


func observe(tick: int, now := -1.0) -> void:
	if now < 0.0:
		now = local_now()
	var sample := float(tick) / TICK_RATE - now
	if not _has or absf(sample - _offset) > SNAP_THRESHOLD:
		_offset = sample
		_has = true
	elif sample > _offset:
		# 来得早的包延迟更小，更可信：往上跟得快一点
		_offset = lerpf(_offset, sample, SMOOTH * 3.0)
	else:
		_offset = lerpf(_offset, sample, SMOOTH)


func is_ready() -> bool:
	return _has


func server_now(now := -1.0) -> float:
	if now < 0.0:
		now = local_now()
	return now + _offset


func reset() -> void:
	_has = false
	_offset = 0.0
