extends StyleBox
## 自绘的"孔版"框：纸色底 + 墨线（四角出头，和地图里建筑草图的画法一样）
## + 一块没套准的专色（往右下错开几个像素，像第二块版印歪了）。
## 按钮、卡片、弹窗、提示条都用它，界面和地图才是同一张印刷品。

const P := preload("res://scripts/ui/palette.gd")

# 都要 @export：Resource.duplicate() 只拷导出的属性，不然复制出来的框会丢掉填色和按下的位移
@export var fill := P.PAPER
@export var ink := P.INK
@export var line := 3.0
@export var block := P.QING              ## 错位的色块；透明 = 不印
@export var block_offset := Vector2(8, 8)
@export var hatch := false               ## 色块印成排线而不是实地
@export var overshoot := 7.0             ## 线头伸出去多少
@export var shift := Vector2.ZERO        ## 整体挪动（按下时压到色块上）


static func make(p_block: Color, p_offset := 8.0, margin := 40.0) -> StyleBox:
	var b := new()
	b.block = p_block
	b.block_offset = Vector2(p_offset, p_offset)
	b.set_content_margin_all(margin)
	return b


func _draw(ci: RID, rect: Rect2) -> void:
	var r := Rect2(rect.position + shift, rect.size)
	if block.a > 0.0 and block_offset != Vector2.ZERO:
		var b := Rect2(rect.position + block_offset, rect.size)
		if hatch:
			_hatch(ci, b)
		else:
			RenderingServer.canvas_item_add_rect(ci, b, block)
	if fill.a > 0.0:
		RenderingServer.canvas_item_add_rect(ci, r, fill)
	if line <= 0.0 or ink.a <= 0.0:
		return
	# 四条边各自出头，而且不完全平行：手拿尺子画的
	var e := overshoot
	var k := fmod(rect.size.x * 0.37 + rect.size.y * 0.11, 1.0) * 2.0 - 1.0  # 每个框固定的一点歪
	var a := r.position
	var c := r.end
	_line(ci, Vector2(a.x - e, a.y + k), Vector2(c.x + e * 0.6, a.y - k * 0.5))
	_line(ci, Vector2(a.x - e * 0.5, c.y - k * 0.5), Vector2(c.x + e, c.y + k))
	_line(ci, Vector2(a.x + k * 0.5, a.y - e), Vector2(a.x - k * 0.5, c.y + e * 0.6))
	_line(ci, Vector2(c.x - k, a.y - e * 0.6), Vector2(c.x + k * 0.5, c.y + e))


func _line(ci: RID, from: Vector2, to: Vector2) -> void:
	RenderingServer.canvas_item_add_line(ci, from, to, ink, line, true)


func _hatch(ci: RID, b: Rect2) -> void:
	var step := 9.0
	var w := b.size.x
	var h := b.size.y
	var k := -h
	while k < w:
		var p0 := Vector2(k, h)
		var p1 := Vector2(k + h, 0.0)
		if p0.x < 0.0:
			p0 = Vector2(0.0, h + k)
		if p1.x > w:
			p1 = Vector2(w, k + h - w)
		RenderingServer.canvas_item_add_line(ci, b.position + p0, b.position + p1, block, 2.5, true)
		k += step


func _get_draw_rect(rect: Rect2) -> Rect2:
	return rect.grow(overshoot + line).expand(rect.end + block_offset + Vector2(2, 2))
