extends Control
## 人生关口选路时，每张路票底下的一把小尺（和 HUD 关口纸带上的同一把，goal_panel.draw_ruler）：
## 实心点是我、空心点是对门、小旗是线。够不够得着一眼看出来，不用读「心智 60 分，线是 64 分」再心算。

const P := preload("res://scripts/ui/palette.gd")
const GoalPanel := preload("res://scripts/ui/goal_panel.gd")

var line: Dictionary = {}
var theirs := -1.0
var mine_color := P.QING
var theirs_color := P.MEI


## dim：这条路锁着，尺子淡一半
func _init(p_line: Dictionary, p_theirs: float, p_mine: Color, p_theirs_color: Color, dim := false) -> void:
	line = p_line
	theirs = p_theirs
	mine_color = p_mine
	theirs_color = p_theirs_color
	modulate.a = 0.55 if dim else 1.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	GoalPanel.draw_ruler(self, Vector2(0, size.y - 12.0), size.x, line, theirs, mine_color, theirs_color)
