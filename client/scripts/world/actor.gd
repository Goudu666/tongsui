extends Node2D
## 河畔里的一个孩子。本地玩家按点击走动；对方按服务器广播插值。
## 画法：墨线简笔 + 专色填充，像孔版印刷一样略微错位。

const P := preload("res://scripts/ui/palette.gd")
const WALK_SPEED := 330.0  ## 略低于服务器限速

var role := "qing"
var display_name := ""
var is_local := false
var walk_target := Vector2.ZERO  ## 本地：要走去的地方
var net_target := Vector2.ZERO   ## 远端：服务器给的位置
var action_label := ""
var asleep := false
var walking := false
var _t := 0.0


func setup(p_role: String, p_name: String, p_local: bool, pos: Vector2) -> void:
	role = p_role
	display_name = p_name
	is_local = p_local
	position = pos
	walk_target = pos
	net_target = pos


func _process(delta: float) -> void:
	_t += delta
	if is_local:
		var to := walk_target - position
		walking = to.length() > 4.0 and action_label == "" and not asleep
		if walking:
			position += to.limit_length(WALK_SPEED * delta)
	else:
		var before := position
		position = position.lerp(net_target, 1.0 - exp(-8.0 * delta))
		walking = before.distance_to(position) > 0.5
	queue_redraw()


func _draw() -> void:
	var c := P.role_color(role)
	var bob := sin(_t * 12.0) * 4.0 if walking else 0.0
	# 影子
	draw_set_transform(Vector2(0, 34), 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, 30.0, Color(P.INK, 0.12))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if asleep:
		draw_circle(Vector2(0, 10), 26.0, Color(c, 0.85))
		draw_arc(Vector2(0, 10), 26.0, 0, TAU, 32, P.INK, 3.0)
		_text("z z", Vector2(30, -30 + sin(_t * 2.0) * 6.0), 30, P.INK_SOFT)
		return
	# 身体（专色，略微错位）+ 墨线
	var body := Rect2(Vector2(-20, -6 + bob), Vector2(40, 44))
	draw_rect(Rect2(body.position + Vector2(3, 2), body.size), Color(c, 0.9))
	draw_rect(body, P.INK, false, 3.0)
	# 头
	draw_circle(Vector2(3, -30 + bob), 22.0, Color(c, 0.9))
	draw_arc(Vector2(0, -32 + bob), 22.0, 0, TAU, 32, P.INK, 3.0)
	draw_circle(Vector2(-7, -34 + bob), 2.5, P.INK)
	draw_circle(Vector2(7, -34 + bob), 2.5, P.INK)
	_text(display_name, Vector2(0, 70), 28, c)
	if action_label != "":
		_text(action_label + "中…", Vector2(0, -70 + sin(_t * 3.0) * 3.0), 26, P.INK_SOFT)


func _text(s: String, at: Vector2, size: int, color: Color) -> void:
	var f := P.font()
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(f, at - Vector2(w / 2.0, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
