extends Control
## 目标面板展开以后的一行：一条线的名字、看什么、两个人各在哪、够没够着（尺的画法在 goal_panel.gd）

const P := preload("res://scripts/ui/palette.gd")
const GoalPanel := preload("res://scripts/ui/goal_panel.gd")
var line: Dictionary = {}
var theirs := -1.0
var mine_color := P.QING
var theirs_color := P.MEI

func _init(p_line: Dictionary, p_theirs: float, p_mine_color: Color, p_theirs_color: Color) -> void:
	line = p_line
	theirs = p_theirs
	mine_color = p_mine_color
	theirs_color = p_theirs_color
	custom_minimum_size = Vector2(0, 104)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var f := P.font()
	var unit := str(line.get("unit", "分"))
	var need := int(line.get("need", 0))
	var ok := bool(line.get("ok", false))
	draw_string(f, Vector2(0, 36), str(line.text), HORIZONTAL_ALIGNMENT_LEFT, size.x - 300.0, 34, P.INK)
	var right := ("%d / %d %s" % [int(line.have), need, unit]) if need > 0 else ("%d" % int(line.have))
	var rw := f.get_string_size(right, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	draw_string(f, Vector2(size.x - rw, 36), right, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, P.INK if ok or need == 0 else P.INK_SOFT)
	if str(line.get("by", "")) != "" and need > 0:
		var by := "看" + str(line.by) + ("  够着了" if ok else "")
		var bw := f.get_string_size(by, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		draw_string(f, Vector2(size.x - rw - bw - 20, 34), by, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, P.INK_SOFT)
	GoalPanel.draw_ruler(self, Vector2(8, 76), size.x - 16.0, line, theirs, mine_color, theirs_color)
