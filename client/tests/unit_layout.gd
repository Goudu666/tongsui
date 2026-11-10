extends SceneTree
## 横屏版面的单测（不开窗口，只算矩形）：
##   - 工程设置是横屏 1920×1080，方向锁在横着
##   - HUD 顶上那条横带：日历牌、关口纸带、两个圆、对门的牌，在各种屏幕宽度和刘海下都不叠在一起
##   - 关口纸带够宽，放得下两个人的数
##   - 并排选项的列数、弹窗宽度的规矩
## 跑：godot --headless --path client -s res://tests/unit_layout.gd

const Hud := preload("res://scripts/ui/hud.gd")
const Kit := preload("res://scripts/ui/kit.gd")

var _failed := 0


func _init() -> void:
	_project()
	_hud()
	_options()
	if _failed == 0:
		print("✓ unit_layout：横屏设置、HUD 分区、并排选项")
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("✗ ", what)


func _project() -> void:
	var w := int(ProjectSettings.get_setting("display/window/size/viewport_width"))
	var h := int(ProjectSettings.get_setting("display/window/size/viewport_height"))
	_check(Vector2(w, h) == Kit.BASE, "设计稿应是 %s，project.godot 里是 %d×%d" % [Kit.BASE, w, h])
	_check(w > h, "设计稿应是横的")
	# 4 = sensor_landscape：横着拿，左右哪边朝上都行，不会转成竖屏
	_check(int(ProjectSettings.get_setting("display/window/handheld/orientation")) == DisplayServer.SCREEN_SENSOR_LANDSCAPE, "方向应锁在横屏（sensor_landscape）")
	_check(str(ProjectSettings.get_setting("display/window/stretch/aspect")) == "expand", "stretch aspect 应是 expand（长屏手机往宽里长）")


func _hud() -> void:
	# 16:9、18:9、20:9、21:9 的手机，4:3 的平板；有没有刘海（左右各 110）
	for size in [Vector2(1920, 1080), Vector2(2160, 1080), Vector2(2400, 1080), Vector2(2520, 1080), Vector2(1920, 1440)]:
		for notch in [0.0, 110.0]:
			var hud := Hud.new()
			hud.size = size
			hud.inset = Vector2(notch, notch)
			var tag := "%s 刘海 %d" % [size, int(notch)]
			var cal := Rect2(Vector2(hud.left(), Hud.TOP), Hud.CARD)
			var strip := hud.strip_rect()
			var bond := Rect2(hud.right() - Hud.CARD.x - Hud.GAP - Hud.BOND_W, Hud.TOP, Hud.BOND_W, Hud.CARD.y)
			var partner := Rect2(Vector2(hud.right() - Hud.CARD.x, Hud.TOP), Hud.CARD)
			_check(cal.position.x >= notch and partner.end.x <= size.x - notch, "%s：左右的牌要让开刘海" % tag)
			_check(strip.position.x >= cal.end.x, "%s：关口纸带压住了日历牌" % tag)
			_check(strip.end.x <= bond.position.x, "%s：关口纸带压住了两个圆" % tag)
			_check(bond.end.x <= partner.position.x, "%s：两个圆压住了对门的牌" % tag)
			# 色条 232 + 两头各 196 + 中间至少 170：两个人的数都写得下
			_check(strip.size.x >= 232.0 + 196.0 * 2.0 + 170.0, "%s：关口纸带只有 %d 宽，放不下两个人的数" % [tag, int(strip.size.x)])
			_check(strip.size.x <= Hud.STRIP_MAX, "%s：关口纸带超过了最宽" % tag)
			_check(hud.right_slot_top() >= partner.end.y, "%s：音量按钮的位置压住了对门的牌" % tag)
			hud.free()


func _options() -> void:
	var main: Script = load("res://scripts/main.gd")
	var m: Node = main.new()
	var box := VBoxContainer.new()
	for case in [[1, 1], [2, 2], [3, 3], [4, 2], [5, 3], [6, 3]]:
		var grid: GridContainer = m._options(box, case[0])
		_check(grid.columns == case[1], "%d 个选项应排 %d 列，实际 %d" % [case[0], case[1], grid.columns])
	_check(m._options_width(3) <= m.MODAL_WIDE and m._options_width(1) == m.MODAL_WIDTH, "弹窗宽度的规矩变了")
	_check(m.MODAL_WIDE <= Kit.BASE.x - 96.0, "宽弹窗在 1920 宽的屏幕上放不下")
	box.free()
	m.free()
