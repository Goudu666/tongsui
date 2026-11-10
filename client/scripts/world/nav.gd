extends RefCounted
## 河畔里的可走区域与寻路。
## walk.png 由 tools/art/build_map.py 生成：10 世界像素一格，白 = 能走。
## 点哪儿走哪儿：目标落在墙里、家具上时，吸附到最近的能走的格子；路径再拉直一遍，走起来不会一格一格地拐。

const WALK_PATH := "res://art/map/walk.png"
const CELL := 10.0

var grid: AStarGrid2D
var size := Vector2i.ZERO
var _walk: PackedByteArray  ## 1 = 能走


func load_mask() -> bool:
	if not ResourceLoader.exists(WALK_PATH):
		return false
	var tex: Texture2D = load(WALK_PATH)
	var img := tex.get_image()
	if img == null:
		return false
	if img.is_compressed():
		img.decompress()
	size = img.get_size()
	_walk.resize(size.x * size.y)
	grid = AStarGrid2D.new()
	grid.region = Rect2i(Vector2i.ZERO, size)
	grid.cell_size = Vector2(CELL, CELL)
	grid.offset = Vector2(CELL, CELL) * 0.5
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	for y in size.y:
		for x in size.x:
			var ok := img.get_pixel(x, y).r > 0.5
			_walk[y * size.x + x] = 1 if ok else 0
			if not ok:
				grid.set_point_solid(Vector2i(x, y), true)
	return true


func ready() -> bool:
	return grid != null


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(p.x / CELL), 0, size.x - 1), clampi(int(p.y / CELL), 0, size.y - 1))


func walkable(p: Vector2) -> bool:
	if grid == null:
		return true
	var c := cell_of(p)
	return _walk[c.y * size.x + c.x] == 1


## 最近的能走的格子（螺旋向外找）
func snap(p: Vector2, max_r := 40) -> Vector2:
	if walkable(p):
		return p
	var c := cell_of(p)
	for r in range(1, max_r):
		var best := Vector2.INF
		var best_d := INF
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var q := c + Vector2i(dx, dy)
				if q.x < 0 or q.y < 0 or q.x >= size.x or q.y >= size.y:
					continue
				if _walk[q.y * size.x + q.x] == 1:
					var w := (Vector2(q) + Vector2(0.5, 0.5)) * CELL
					var d := w.distance_squared_to(p)
					if d < best_d:
						best_d = d
						best = w
		if best != Vector2.INF:
			return best
	return p


## 从 a 走到 b 的路径点（不含起点）。走不到时返回空。
func path(a: Vector2, b: Vector2) -> PackedVector2Array:
	if grid == null:
		return PackedVector2Array([b])
	var start := snap(a)
	var goal := snap(b)
	if _clear_line(start, goal):
		return PackedVector2Array([goal])
	var raw := grid.get_point_path(cell_of(start), cell_of(goal), true)
	if raw.is_empty():
		return PackedVector2Array()
	raw[raw.size() - 1] = goal
	# 拉直：能直接看见的点就跳过中间的
	var out := PackedVector2Array()
	var from := start
	var i := 0
	while i < raw.size():
		var j := raw.size() - 1
		while j > i and not _clear_line(from, raw[j]):
			j -= 1
		out.append(raw[j])
		from = raw[j]
		i = j + 1
	return out


func _clear_line(a: Vector2, b: Vector2) -> bool:
	var d := a.distance_to(b)
	var n := int(ceil(d / (CELL * 0.5)))
	for k in range(1, n + 1):
		var p := a.lerp(b, float(k) / n)
		# 身体有点宽：左右各探一点
		if not walkable(p):
			return false
	return true
