extends Control
## 目标面板展开以后的一行：一条线的名字、看什么、两个人各在哪、够没够着（尺的画法在 goal_panel.gd）

const P := preload("res://scripts/ui/palette.gd")
const GoalPanel := preload("res://scripts/ui/goal_panel.gd")
var line: Dictionary = {}
var theirs := -1.0
var mine_color := P.QING
var theirs_color := P.MEI
var compact := false  ## 小一号（投胎页上「头一道关」那几行）

func _init(p_line: Dictionary, p_theirs: float, p_mine_color: Color, p_theirs_color: Color, p_compact := false) -> void:
	line = p_line
	theirs = p_theirs
	mine_color = p_mine_color
	theirs_color = p_theirs_color
	compact = p_compact
	custom_minimum_size = Vector2(0, 74 if compact else 104)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var f := P.font()
	var unit := str(line.get("unit", "分"))
	var need := int(line.get("need", 0))
	var ok := bool(line.get("ok", false))
	var ft := 28 if compact else 34
	var fr := 26 if compact else 30
	var fb := 22 if compact else 22
	var ty := 28.0 if compact else 36.0
	var right := ("%d / %d %s" % [int(line.have), need, unit]) if need > 0 else ("%d" % int(line.have))
	var rw := f.get_string_size(right, HORIZONTAL_ALIGNMENT_LEFT, -1, fr).x
	var by := ("看" + str(line.by) + ("  够着了" if ok else "")) if str(line.get("by", "")) != "" and need > 0 else ""
	var bw := f.get_string_size(by, HORIZONTAL_ALIGNMENT_LEFT, -1, fb).x if by != "" else 0.0
	draw_string(f, Vector2(0, ty), str(line.text), HORIZONTAL_ALIGNMENT_LEFT, maxf(60.0, size.x - rw - bw - 40.0), ft, P.INK)
	draw_string(f, Vector2(size.x - rw, ty), right, HORIZONTAL_ALIGNMENT_LEFT, -1, fr, P.INK if ok or need == 0 else P.INK_SOFT)
	if by != "":
		draw_string(f, Vector2(size.x - rw - bw - 20, ty - 2.0), by, HORIZONTAL_ALIGNMENT_LEFT, -1, fb, P.MEI if ok and compact else P.INK_SOFT)
	GoalPanel.draw_ruler(self, Vector2(8, 54.0 if compact else 76.0), size.x - 16.0, line, theirs, mine_color, theirs_color)
