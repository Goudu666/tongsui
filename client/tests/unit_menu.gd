extends SceneTree
## 菜单（ui/system_menu.gd）的单测：
##   - 返回键不再直接退出游戏（project.godot quit_on_go_back=false），交给菜单
##   - 标题页右上角有菜单按钮；Esc 开、再 Esc 关；开着的时候河畔里点不动
##   - 三条音量：拖了以后总线的分贝跟着变，拖到底是静音，松手才写盘
##   - 老设置（右上角三档按钮的 level）换算成三条音量
##   - 弹窗出来时按钮让开；河畔里按钮在「对门」那张牌底下，离线逛逛时回到角上
##   - 「回标题」能从河畔里出来
## 跑：godot --headless --path client -s res://tests/unit_menu.gd

const Menu := preload("res://scripts/ui/system_menu.gd")
const Mix := preload("res://scripts/audio/mix_table.gd")
const Director := preload("res://scripts/audio/audio_director.gd")

var _failed := 0
var main: Node


func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("✗ ", what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _texts(n: Node, out: Array = []) -> Array:
	if n is Button:
		out.append(n.text)
	for c in n.get_children():
		_texts(c, out)
	return out


func _find(n: Node, text: String) -> Button:
	if n is Button and n.text == text:
		return n
	for c in n.get_children():
		var b := _find(c, text)
		if b != null:
			return b
	return null


## 动画要真的走完（无头跑的时候一帧很快，数帧数不够）
func _settle() -> void:
	await create_timer(0.6).timeout
	await process_frame


func _esc() -> void:
	var e := InputEventAction.new()
	e.action = "ui_cancel"
	e.pressed = true
	Input.parse_input_event(e)
	var up := InputEventAction.new()
	up.action = "ui_cancel"
	up.pressed = false
	Input.parse_input_event(up)


func _run() -> void:
	_check(ProjectSettings.get_setting("application/config/quit_on_go_back") == false, "返回键应交给菜单（quit_on_go_back=false），不然一按就退出")

	# 老设置换算：先把玩家现在的设置收起来，测完放回去
	var keep := FileAccess.get_file_as_string(Director.SETTINGS) if FileAccess.file_exists(Director.SETTINGS) else ""
	var old := ConfigFile.new()
	old.set_value("audio", "level", 1)
	old.save(Director.SETTINGS)

	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(6)
	var audio: Node = main.get_node("Audio")
	var menu: Menu = main.sysmenu
	_check(menu != null, "main.gd 里没有 sysmenu")
	_check(is_equal_approx(audio.volume.Music, 0.0) and is_equal_approx(audio.volume.Sfx, 1.0), "老设置「只关音乐」应换算成音乐 0、其余 1：%s" % audio.volume)
	_check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "音乐 0 应静音")

	# 标题页：按钮在右上角
	_check(menu.button.visible, "标题页应看得到菜单按钮")
	_check(is_equal_approx(menu.button.offset_top, Menu.BUTTON_TOP_MENU), "标题页按钮应在角上")
	_esc()
	await _frames(3)
	_check(menu.is_open(), "Esc 应打开菜单")
	var texts := _texts(menu)
	_check(not texts.has("回标题") and not texts.has("回大厅"), "标题页的菜单不该有回标题 / 回大厅：%s" % [texts])
	_check(texts.has("退出游戏") and texts.has("回去"), "标题页的菜单应有「回去」「退出游戏」：%s" % [texts])

	# 音量：拖动（没松手）只改分贝，松手写盘
	var sliders: Array = []
	for c in menu._body.get_children():
		if c is Menu.InkSlider:
			sliders.append(c)
	_check(sliders.size() == 3, "应有三条音量，有 %d 条" % sliders.size())
	if sliders.size() == 3:
		var sfx: Menu.InkSlider = sliders[2]
		var t: Rect2 = sfx._track()
		sfx._set_from(t.position.x + t.size.x * 0.5, false)
		_check(is_equal_approx(audio.volume.Sfx, 0.5), "拖到一半应是 0.5：%s" % audio.volume.Sfx)
		var want := float(Mix.BUS_DB.Sfx) + linear_to_db(0.5)
		_check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Sfx")) - want) < 0.05, "动静的分贝应跟着变")
		var saved := ConfigFile.new()
		saved.load(Director.SETTINGS)
		_check(not saved.has_section_key("audio", "sfx"), "还没松手不该写盘")
		sfx._set_from(t.position.x - 50.0, true)
		_check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Sfx")), "拖到底应静音")
		saved = ConfigFile.new()
		saved.load(Director.SETTINGS)
		_check(is_equal_approx(float(saved.get_value("audio", "sfx", -1.0)), 0.0), "松手应写盘")
		_check(not saved.has_section_key("audio", "level"), "写了三条音量以后，老的 level 应删掉：" + FileAccess.get_file_as_string(Director.SETTINGS))
		# 音乐拉回来
		var music: Menu.InkSlider = sliders[0]
		music._set_from(t.end.x + 10.0, true)
		_check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")) and is_equal_approx(audio.volume.Music, 1.0), "音乐拉满应不再静音")

	menu._toggled_at = -1.0  # 两下 Esc 隔得太近会被当成手机返回键的一下（按键 + 通知）
	_esc()
	await _settle()
	_check(not menu.is_open() and not menu._sheet.visible, "再按 Esc 应关上")

	# 离线逛逛：按钮回到角上（右上角没有对门的牌）；菜单开着时河畔里点不动
	main._start_preview()
	await _frames(10)
	_check(main.world != null, "离线逛逛没进河畔里")
	_check(is_equal_approx(menu.button.offset_top, Menu.BUTTON_TOP_MENU), "离线逛逛按钮应在角上")
	menu._toggled_at = -1.0
	menu.toggle()
	await _frames(3)
	_check(main.world.controllable == false, "菜单开着时河畔里不该点得动")
	texts = _texts(menu)
	_check(texts.has("接着过") and texts.has("回标题"), "河畔里的菜单应有「接着过」「回标题」：%s" % [texts])
	_check(not texts.has("回大厅"), "离线逛逛没有人生线，不该有回大厅")
	_find(menu, "接着过").pressed.emit()
	await _settle()
	_check(not menu.is_open(), "「接着过」应关上菜单")
	await _frames(2)
	_check(main.world.controllable, "关上以后河畔里应能点")

	# 联机时按钮在「对门」那张牌底下；弹窗出来时让开
	main.offline_preview = false
	await _frames(2)
	_check(is_equal_approx(menu.button.offset_top, Menu.BUTTON_TOP_WORLD), "河畔里按钮应在对门的牌底下")
	main.modal.visible = true
	await _frames(2)
	_check(not menu.button.visible, "弹窗出来时按钮应让开")
	main.modal.visible = false
	main.offline_preview = true

	# 回标题
	menu._toggled_at = -1.0
	menu.toggle()
	await _frames(3)
	_find(menu, "回标题").pressed.emit()
	await _settle()
	_check(main.world == null and main._page_id == "title", "「回标题」应回到标题页")
	_check(not menu.is_open() and not menu._sheet.visible, "回标题以后菜单应收起来")

	# 把玩家原来的设置放回去
	if keep != "":
		var f := FileAccess.open(Director.SETTINGS, FileAccess.WRITE)
		f.store_string(keep)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Director.SETTINGS))
	if _failed == 0:
		print("✓ unit_menu：返回键、Esc、三条音量、老设置换算、按钮位置、回标题")
	quit(1 if _failed > 0 else 0)
