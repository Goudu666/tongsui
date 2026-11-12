extends Node3D
## 实时 3D 的小人：两个主角（和街坊）是一节一节的手办——头、身子、上臂、小臂、手、大腿、小腿、鞋，
## 关节是一串 Node3D（骨骼），每帧按「在干什么」算出各关节的角度（程序动画），和 2D 精灵表的那几套动作一一对上：
##   走（按走过的距离推步子，脚底不打滑）、站着喘气眨眼、坐、睡、招手、高兴、泄气、击掌、不好意思，
##   和 actor.gd ACT_LOOP 的二十一套专属动作（写字、看书、吃饭、颠球、对踢、修车、做饭、钓鱼……）。
## 脸是 face.gdshader 画在头上的（眨眼、笑、张嘴都是参数）；头发是贴着头的发壳，一缕一缕起伏。
## 人朝 +Z（对着镜头）是 0；侧着走时转到七十度（脸还看得见），停下来转回三分之一。
## 不带任何模型文件：长相、衣服、身高都在 LOOKS / _spec 里，改数就变。

const Kit := preload("res://scripts/world3d/kit3d.gd")
const FACE := preload("res://shaders/3d/face.gdshader")
const CLOTH := preload("res://shaders/3d/cloth.gdshader")
const P := preload("res://scripts/ui/palette.gd")
const FACE_TEX := preload("res://shaders/3d/face_tex.gdshader")

## 两个主角用微缩模型线程做的造型甲（art3d/figures/<role>_<stage>.glb，tools/art/realtime3d/slim_glb.py 瘦身过）；
## 没有这个文件、或者是街坊（自带 look），就用下面程序搭的小人。
const GLB_DIR := "res://art3d/figures/"
const GLB_STAGE := {"childhood": "child", "teen": "teen", "young": "young", "middle": "middle", "old": "old"}
static var _face_spots := {}  ## 脸贴图 → 眼睛、嘴在哪（读一次）

## 身高（米）：和 actor.gd 的 HEIGHT 一样（世界像素 ÷ 100）
const HEIGHT := {"childhood": 1.12, "teen": 1.52, "young": 1.72, "middle": 1.70, "old": 1.60}
## 头多大（半径，米）：小孩头大、显得可爱；大人收一点
const HEAD := {"childhood": 0.15, "teen": 0.142, "young": 0.137, "middle": 0.137, "old": 0.133}
const SKIN := Color(0.96, 0.79, 0.67)
const HAIR_DARK := Color(0.13, 0.095, 0.08)
const HAIR_GREY := Color(0.72, 0.7, 0.68)

## 衣服：每个人每个岁数段一套。top 上衣（stripe 横条纹颜色、band 领口袖口的颜色、sleeve 0 无袖 / 0.5 短袖 / 1 长袖）、
## bottom 下装（legs 0.35 短裤 / 1 长裤；dress 连衣裙长到哪：大腿的几分之几）、shoes、socks
const LOOKS := {
	"qing": {
		"childhood": {"top": "#F3EFE6", "stripe": "#2E8B7A", "sleeve": 0.5, "bottom": "#2F3B57", "legs": 0.42, "socks": "#F5F2EA", "shoes": "#E9E6E0", "shoe2": "#2E8B7A", "hair": "boy"},
		"teen": {"top": "#2E8B7A", "band": "#F3EFE6", "sleeve": 1.0, "bottom": "#26304A", "legs": 1.0, "shoes": "#ECE8E0", "shoe2": "#2B2A33", "hair": "boy_long"},
		"young": {"top": "#3A8F80", "band": "#EDE8DD", "sleeve": 1.0, "bottom": "#3D5579", "legs": 1.0, "shoes": "#EFEBE4", "shoe2": "#8E3B33", "hair": "boy_side"},
		"middle": {"top": "#4C7B73", "band": "#D9D2C2", "sleeve": 1.0, "bottom": "#7D6E55", "legs": 1.0, "shoes": "#4A3328", "shoe2": "#2E221C", "hair": "boy_short"},
		"old": {"top": "#3F6B63", "band": "#CFC8B8", "sleeve": 1.0, "bottom": "#5E5A55", "legs": 1.0, "shoes": "#2B2724", "shoe2": "#1E1B19", "hair": "boy_old"},
	},
	"mei": {
		"childhood": {"top": "#F7F2E8", "dress": "#D9485F", "dress_len": 0.55, "sleeve": 0.5, "bottom": "#F7F2E8", "legs": 0.0, "socks": "#F8F5EE", "shoes": "#C23A4F", "shoe2": "#7A2030", "hair": "pigtails"},
		"teen": {"top": "#F4F0E7", "band": "#D9485F", "sleeve": 1.0, "bottom": "#26304A", "legs": 1.0, "shoes": "#ECE8E0", "shoe2": "#D9485F", "hair": "ponytail"},
		"young": {"top": "#EDE6D8", "dress": "#D24A5E", "dress_len": 0.66, "sleeve": 1.0, "bottom": "#3A3440", "legs": 1.0, "shoes": "#5B3A2E", "shoe2": "#3A251D", "hair": "bob"},
		"middle": {"top": "#C8475B", "band": "#EFE7D6", "sleeve": 1.0, "bottom": "#3B3A46", "legs": 1.0, "dress": "#3B3A46", "dress_len": 0.8, "shoes": "#4B3229", "shoe2": "#2E1F19", "hair": "bun"},
		"old": {"top": "#B5495A", "band": "#DDD6C6", "sleeve": 1.0, "bottom": "#4A4650", "legs": 1.0, "shoes": "#2B2724", "shoe2": "#1E1B19", "hair": "bun_grey"},
	},
}

var role := "qing"
var stage := "childhood"
var look: Dictionary = {}  ## 街坊用：不用 LOOKS，自己给一套（同样的键）
var height := 1.12
var j: Dictionary = {}     ## 关节名 → Node3D
var face_mat: ShaderMaterial
var props: Dictionary = {} ## 手上的东西：book / bowl / box / rod / ball
var _pose: Dictionary = {} ## 现在各关节的角度（平滑过去）
var _yaw := 0.0
var _t := 0.0
var _blink_t := 2.0
var _blink := 0.0
var _spec: Dictionary = {}
var _hip_y := 0.5
var _bob := 0.0
var _tail: Node3D = null   ## 马尾 / 辫子：跟着走路甩
var _tail_v := 0.0
var _tail_a := 0.0
var _shadow: MeshInstance3D
var from_glb := false      ## 用的是造型甲的模型（不是程序搭的）

## 动画输入（stage3d 每帧从 2D 的 Actor 抄过来）
var walking := false
var phase := 0.0           ## 一整步走到哪儿（0~1）
var dir := 1               ## 1 朝右 -1 朝左
var face_to := 0           ## 0 照走的方向；1 朝右 -1 朝左（搭伴面对面）
var loop := ""             ## ACT_LOOP 里的名字 / sit / wave / busy；"" 没在做事
var loop_t := 0.0
var emote := ""            ## joy / sad / five / shy / wave
var emote_t := 0.0
var asleep := false
var pass_phase := 0.0      ## 对踢：0 = 正好轮到我出脚
var speed := 1.0           ## 走路快慢（街坊慢一点）


func build(p_role: String, p_stage: String, p_look: Dictionary = {}) -> void:
	role = p_role
	stage = p_stage if HEIGHT.has(p_stage) else "childhood"
	look = p_look if not p_look.is_empty() else LOOKS.get(role, LOOKS.qing).get(stage, {})
	for c in get_children():
		c.queue_free()
	j.clear()
	props.clear()
	_pose.clear()
	_tail = null
	height = float(look.get("height", HEIGHT[stage]))
	if role == "mei" and p_look.is_empty():
		height -= 0.06  # 梅比青矮一点（actor.gd：同岁数矮 6 像素）
	_spec = _make_spec()
	from_glb = p_look.is_empty() and _build_glb()
	if not from_glb:
		_build_body()


## 按身高和头的大小推出各段的长度（米）
func _make_spec() -> Dictionary:
	var hgt := height
	var hr: float = float(look.get("head", HEAD.get(stage, 0.124)))
	var kid := stage == "childhood"
	var girl := role == "mei" or bool(look.get("girl", false))
	var s := {}
	s.hr = hr
	s.head_c = hgt - hr * 1.08
	s.neck = (0.035 if kid else 0.06) * (1.0 if not girl else 0.95)
	s.shoulder_y = s.head_c - hr * 0.93 - s.neck
	s.hip_y = hgt * (0.415 if kid else (0.45 if stage == "teen" else 0.47))
	s.torso = s.shoulder_y - s.hip_y
	s.ankle = hgt * 0.045
	s.thigh = (s.hip_y - s.ankle) * 0.52
	s.shin = (s.hip_y - s.ankle) * 0.48
	var broad := 0.0 if girl else 1.0
	s.sh_half = hgt * (0.112 if kid else lerpf(0.104, 0.118, broad)) * float(look.get("build", 1.0))
	s.hip_half = hgt * (0.075 if kid else lerpf(0.083, 0.072, broad)) * float(look.get("build", 1.0))
	s.waist = hgt * (0.078 if kid else lerpf(0.066, 0.076, broad)) * float(look.get("build", 1.0)) * (1.12 if stage == "middle" or stage == "old" else 1.0)
	s.depth = 0.72 if kid else 0.6
	s.upper = hgt * 0.17
	s.fore = hgt * 0.15
	s.arm_r = hgt * (0.033 if kid else 0.026)
	s.leg_r = hgt * (0.05 if kid else 0.042)
	s.hand = hgt * (0.04 if kid else 0.03)
	s.foot = hgt * (0.12 if kid else 0.135)
	return s


func _cloth(c: Variant, stripe: Variant = null, band: Variant = null, rough := 0.85) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = CLOTH
	m.set_shader_parameter("base", Color(str(c)))
	m.set_shader_parameter("stripe_col", Color(str(stripe)) if stripe != null else Color(str(c)))
	m.set_shader_parameter("stripes", 1.0 if stripe != null else 0.0)
	m.set_shader_parameter("roughness", rough)
	return m


func _joint(name: String, parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = name
	n.position = pos
	parent.add_child(n)
	j[name] = n
	return n


func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _build_body() -> void:
	var s := _spec
	var lk := look
	var kid := stage == "childhood"
	var skin := Kit.mat(Color(str(lk.get("skin", SKIN.to_html()))), 0.6, 0.0, 0.25)
	var top := _cloth(lk.get("top", "#ffffff"), lk.get("stripe"))
	var bottom := _cloth(lk.get("bottom", "#333344"))
	var band: Variant = lk.get("band")
	var band_m := _cloth(band) if band != null else top
	var shoe_m := Kit.mat(Color(str(lk.get("shoes", "#eeeeee"))), 0.45, 0.0)
	var sole_m := Kit.mat(Color(str(lk.get("shoe2", "#333333"))), 0.6)
	var sock_m := _cloth(lk.get("socks", lk.get("bottom", "#333344")))
	var root := _joint("root", self, Vector3.ZERO)
	_shadow = Kit.blob_shadow(s.sh_half * 4.2, s.sh_half * 2.6, 0.5)
	add_child(_shadow)
	var hips := _joint("hips", root, Vector3(0, s.hip_y, 0))
	_hip_y = s.hip_y
	var T: float = s.torso
	var hh: float = s.hip_half
	var d: float = s.depth
	# 胯：裤腰到裆
	var pelvis_rings := [
		[-0.09 * T, hh * 0.55, hh * 0.5 * d / 0.6],
		[-0.04 * T, hh * 1.0, hh * 0.78 * d / 0.6],
		[0.05 * T, hh * 1.08, hh * 0.85 * d / 0.6],
		[0.3 * T, s.waist * 0.9, s.waist * 0.7 * d / 0.6],
	]
	var dress: Variant = lk.get("dress")
	var pants_on_hips: Material = bottom
	if dress != null and float(lk.get("legs", 1.0)) <= 0.0:
		pants_on_hips = _cloth(dress)
	_mesh(hips, Kit.loft(pelvis_rings, 16), pants_on_hips)
	# 裙子：从腰往下撑开，长到大腿的几分之几（腿在里头摆）
	if dress != null:
		var L: float = (s.thigh + s.shin) * float(lk.get("dress_len", 0.6))
		var flare: float = hh * (1.9 if kid else 1.55)
		var sk := [
			[-L, flare, flare * 0.92],
			[-L * 0.6, flare * 0.86, flare * 0.8],
			[-L * 0.15, hh * 1.18, hh * 1.0],
			[0.2 * T, s.waist * 0.93, s.waist * 0.74],
		]
		var skirt := _mesh(hips, Kit.loft(sk, 20, false, false), _cloth(dress))
		skirt.material_override.set_shader_parameter("double", 1.0)
		j["skirt"] = skirt
	# 上身
	var spine := _joint("spine", hips, Vector3(0, 0.26 * T, 0))
	var sh: float = s.sh_half
	var tuck := 0.92 if dress != null else 1.06
	var chest_rings := [
		[-0.06 * T, s.waist * tuck, s.waist * 0.8 * tuck * d / 0.6],
		[0.18 * T, s.waist * 1.05, s.waist * 0.85 * d / 0.6],
		[0.42 * T, sh * 0.86, sh * 0.6 * d / 0.6],
		[0.62 * T, sh * 0.95, sh * 0.6 * d / 0.6],
		[0.7 * T, sh * 0.9, sh * 0.52 * d / 0.6],
		[0.76 * T, sh * 0.55, sh * 0.42 * d / 0.6],
		[0.78 * T, s.hr * 0.4, s.hr * 0.36],
	]
	var chest_m: Material = top
	if dress != null and kid:
		chest_m = _cloth(dress)  # 背带裙：前襟也是裙子的颜色，袖子是里头的白衬衣
	_mesh(spine, Kit.loft(chest_rings, 18), chest_m)
	if kid and dress != null:
		# 白领子
		var collar := Kit.loft([[0.7 * T, sh * 0.62, sh * 0.5], [0.775 * T, s.hr * 0.5, s.hr * 0.46]], 16, false, false)
		_mesh(spine, collar, _cloth(lk.get("top")))
	elif band != null:
		var collar2 := Kit.loft([[0.72 * T, sh * 0.6, sh * 0.47], [0.79 * T, s.hr * 0.46, s.hr * 0.42]], 16, false, false)
		_mesh(spine, collar2, band_m)
	# 脖子、头
	var neck := _joint("neck", spine, Vector3(0, 0.76 * T, 0))
	_mesh(neck, Kit.limb(s.neck + 0.02, s.hr * 0.3, s.hr * 0.3, 10), skin, Vector3(0, s.neck + 0.01, 0))
	var head := _joint("head", neck, Vector3(0, s.neck, 0))
	var hr: float = s.hr
	var hrv := Vector3(hr * 0.94, hr, hr * 0.96)
	face_mat = ShaderMaterial.new()
	face_mat.shader = FACE
	face_mat.set_shader_parameter("skin", Color(str(lk.get("skin", SKIN.to_html()))))
	var girl := role == "mei" or bool(lk.get("girl", false))
	face_mat.set_shader_parameter("lash", 1.0 if girl else 0.0)
	face_mat.set_shader_parameter("age", {"childhood": 0.0, "teen": 0.15, "young": 0.3, "middle": 0.55, "old": 0.9}.get(stage, 0.3))
	face_mat.set_shader_parameter("blush", 0.7 if kid else (0.45 if girl else 0.25))
	face_mat.set_shader_parameter("eye_tall", 0.17 if kid else (0.15 if stage == "teen" else 0.13))
	face_mat.set_shader_parameter("eye_w", 0.115 if kid else (0.1 if stage == "teen" else 0.088))
	face_mat.set_shader_parameter("eye_gap", 0.36 if kid else 0.33)
	face_mat.set_shader_parameter("eye_h", -0.16 if kid else -0.1)
	var head_c := Vector3(0, hr * 0.92, 0)
	_mesh(head, Kit.ellipsoid(hrv, 28, 18), face_mat, head_c)
	# 耳朵
	for sgn in [-1.0, 1.0]:
		_mesh(head, Kit.ellipsoid(Vector3(hr * 0.12, hr * 0.2, hr * 0.14), 10, 8), skin, head_c + Vector3(sgn * hr * 0.92, -hr * 0.08, -hr * 0.05))
	_build_hair(head, head_c, hrv, str(lk.get("hair", "boy")), lk)
	# 胳膊
	var sleeve := float(lk.get("sleeve", 1.0))
	var sleeve_m: Material = top if not (kid and dress != null) else _cloth(lk.get("top"))
	for side in [["l", 1.0], ["r", -1.0]]:
		var n: String = side[0]
		var sg: float = side[1]
		var shj := _joint("sh_" + n, spine, Vector3(sg * sh * 0.86, 0.66 * T, 0))
		var ar: float = s.arm_r
		var up_m: Material = skin if sleeve < 1.0 else sleeve_m
		_mesh(shj, Kit.limb(s.upper, ar * 1.1, ar * 0.95, 10), up_m)
		if sleeve > 0.0 and sleeve < 1.0:
			# 短袖：袖筒套在上臂上半截，口大一点
			_mesh(shj, Kit.limb(s.upper * sleeve, ar * 1.45, ar * 1.38, 12), sleeve_m)
		var el := _joint("el_" + n, shj, Vector3(0, -s.upper, 0))
		_mesh(el, Kit.limb(s.fore, ar * 0.95, ar * 0.8, 10), skin if sleeve < 1.0 else sleeve_m)
		if sleeve >= 1.0 and band != null:
			_mesh(el, Kit.limb(0.03, ar * 1.02, ar * 1.0, 10), band_m, Vector3(0, -s.fore + 0.02, 0))
		var hand := _joint("hand_" + n, el, Vector3(0, -s.fore, 0))
		_mesh(hand, Kit.ellipsoid(Vector3(s.hand * 0.75, s.hand, s.hand * 0.6), 12, 8), skin, Vector3(0, -s.hand * 0.7, 0))
	# 腿
	var legs := float(lk.get("legs", 1.0))
	for side in [["l", 1.0], ["r", -1.0]]:
		var n: String = side[0]
		var sg: float = side[1]
		var th := _joint("th_" + n, hips, Vector3(sg * hh * 0.52, 0, 0))
		var lr: float = s.leg_r
		var thigh_m: Material = bottom if legs >= 0.5 else skin
		_mesh(th, Kit.limb(s.thigh, lr * 1.05, lr * 0.86, 12), thigh_m)
		if legs > 0.0 and legs < 0.5:
			# 短裤腿
			_mesh(th, Kit.limb(s.thigh * legs * 1.6, lr * 1.32, lr * 1.22, 12), bottom)
		var kn := _joint("kn_" + n, th, Vector3(0, -s.thigh, 0))
		var shin_m: Material = bottom if legs >= 1.0 else (sock_m if lk.has("socks") else skin)
		if legs < 1.0 and lk.has("socks"):
			# 小腿露着，袜子到小腿肚
			_mesh(kn, Kit.limb(s.shin, lr * 0.88, lr * 0.66, 12), skin)
			_mesh(kn, Kit.limb(s.shin * 0.42, lr * 0.78, lr * 0.7, 12), sock_m, Vector3(0, -s.shin * 0.58, 0))
		else:
			_mesh(kn, Kit.limb(s.shin, lr * 0.9, lr * 0.7, 12), shin_m)
		var an := _joint("an_" + n, kn, Vector3(0, -s.shin, 0))
		var fl: float = s.foot
		var fw: float = lr * 0.95
		var shoe := Kit.loft([
			[-s.ankle * 0.98, fw * 0.92, fl * 0.5, 0.0, fl * 0.2],
			[-s.ankle * 0.5, fw * 1.0, fl * 0.52, 0.0, fl * 0.2],
			[s.ankle * 0.2, fw * 0.75, fl * 0.32, 0.0, fl * 0.1],
		], 14)
		_mesh(an, shoe, shoe_m)
		_mesh(an, Kit.loft([[-s.ankle * 1.0, fw * 0.95, fl * 0.53, 0.0, fl * 0.2], [-s.ankle * 0.78, fw * 1.02, fl * 0.55, 0.0, fl * 0.2]], 14), sole_m)
	_build_props()


## 造型甲：读 glb，把一节节部件挂到和程序小人同名的关节上（hips/spine/neck/head/sh/el/hand/th/kn/an），动画就通用了。
## glb 的休息姿势是 A 字（胳膊往外张 35°）：胳膊那几节整体先转回竖直，关节的「0」就和程序小人一样是垂手站着。
func _build_glb() -> bool:
	var path := GLB_DIR + "%s_%s.glb" % [role, GLB_STAGE.get(stage, "child")]
	if not ResourceLoader.exists(path):
		return false
	var ps := load(path) as PackedScene
	if ps == null:
		return false
	var src := ps.instantiate()
	var parts := {}
	for n in ["pelvis", "torso", "head", "hair", "upper_arm_L", "lower_arm_L", "hand_L", "upper_arm_R", "lower_arm_R", "hand_R", "thigh_L", "shin_L", "shoe_L", "thigh_R", "shin_R", "shoe_R"]:
		var mi := src.find_child(n, true, false) as MeshInstance3D
		if mi == null:
			src.free()
			return false
		parts[n] = mi
	var mats := {}
	var s := _spec
	var root := _joint("root", self, Vector3.ZERO)
	var pel: MeshInstance3D = parts.pelvis
	var hips := _joint("hips", root, pel.position)
	_hip_y = hips.position.y
	_part(hips, pel, mats)
	var torso: MeshInstance3D = parts.torso
	var spine := _joint("spine", hips, torso.position)
	_part(spine, torso, mats)
	var hd: MeshInstance3D = parts.head
	var neck := _joint("neck", spine, hd.position)
	var head := _joint("head", neck, Vector3.ZERO)
	_part(head, hd, mats)
	_part(head, parts.hair, mats)
	var hbox := hd.mesh.get_aabb()
	s.hr = hbox.size.y * 0.5
	for side in [["l", "L"], ["r", "R"]]:
		var n: String = side[0]
		var S: String = side[1]
		var up: MeshInstance3D = parts["upper_arm_" + S]
		var lo: MeshInstance3D = parts["lower_arm_" + S]
		var ha: MeshInstance3D = parts["hand_" + S]
		var ang := atan2(lo.position.x, -lo.position.y)
		var R := Basis(Vector3(0, 0, 1), -ang)
		var shj := _joint("sh_" + n, spine, up.position)
		_part(shj, up, mats, R)
		var el := _joint("el_" + n, shj, R * lo.position)
		_part(el, lo, mats, R)
		var hand := _joint("hand_" + n, el, R * ha.position)
		_part(hand, ha, mats, R)
		s.upper = lo.position.length()
		s.fore = ha.position.length()
		s.hand = ha.mesh.get_aabb().size.y * 0.5
		s.sh_half = absf(up.position.x)
		var th: MeshInstance3D = parts["thigh_" + S]
		var sh: MeshInstance3D = parts["shin_" + S]
		var so: MeshInstance3D = parts["shoe_" + S]
		var thj := _joint("th_" + n, hips, th.position)
		_part(thj, th, mats)
		var kn := _joint("kn_" + n, thj, sh.position)
		_part(kn, sh, mats)
		var an := _joint("an_" + n, kn, so.position)
		_part(an, so, mats)
		s.thigh = -sh.position.y
		s.shin = -so.position.y
	src.free()
	_shadow = Kit.blob_shadow(s.sh_half * 4.4, s.sh_half * 2.8, 0.5)
	add_child(_shadow)
	_build_props()
	return true


## 一节部件：同一个网格新建一个 MeshInstance3D 挂到关节下（rot：A 字转回竖直），材质换成游戏里的（布、皮肤、头发、能眨眼的脸）
func _part(joint: Node3D, src: MeshInstance3D, mats: Dictionary, rot := Basis.IDENTITY) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = src.mesh
	mi.basis = rot
	joint.add_child(mi)
	for i in src.mesh.get_surface_count():
		var m := src.get_active_material(i)
		if m == null:
			continue
		if not mats.has(m):
			mats[m] = _game_mat(m)
		mi.set_surface_override_material(i, mats[m])
	return mi


func _game_mat(m: Material) -> Material:
	var bm := m as BaseMaterial3D
	if bm == null:
		return m
	var nm := bm.resource_name.to_lower()
	var c := bm.albedo_color
	if bm.albedo_texture != null or nm == "face":
		face_mat = ShaderMaterial.new()
		face_mat.shader = FACE_TEX
		face_mat.set_shader_parameter("tex", bm.albedo_texture)
		var spots := _find_face(bm.albedo_texture)
		for k in spots:
			face_mat.set_shader_parameter(k, spots[k])
		return face_mat
	if nm.begins_with("fabric"):
		return _cloth(c.to_html(false), null, null, 0.9)
	if nm == "skin":
		return Kit.mat(c, 0.6, 0.0, 0.25)
	if nm == "hair":
		var hm := Kit.mat(c, 0.55, 0.0, 0.12)
		hm.metallic_specular = 0.35
		return hm
	var other := bm.duplicate() as BaseMaterial3D
	other.normal_enabled = false
	return other


## 读脸的贴图找眼睛和嘴：深色的连成片，两边最大的两块是眼睛，正中间的是嘴（同一张贴图只找一次）
static func _find_face(tex: Texture2D) -> Dictionary:
	if tex == null:
		return {}
	var key := tex.resource_path if tex.resource_path != "" else str(tex.get_instance_id())
	if _face_spots.has(key):
		return _face_spots[key]
	var out := {}
	var img := tex.get_image()
	if img == null or img.is_empty():
		_face_spots[key] = out
		return out
	if img.is_compressed():
		img.decompress()
	var N := 256
	img = img.duplicate()
	img.resize(N, N, Image.INTERPOLATE_BILINEAR)
	var x0 := int(N * 0.3)
	var x1 := int(N * 0.7)
	var y0 := int(N * 0.15)
	var y1 := int(N * 0.75)
	var seen := {}
	var comps := []
	for y in range(y0, y1):
		for x in range(x0, x1):
			var k := y * N + x
			if seen.has(k) or img.get_pixel(x, y).get_luminance() > 0.3:
				continue
			# 连成片
			var stack := [k]
			seen[k] = true
			var bb := Rect2i(x, y, 1, 1)
			var area := 0
			while not stack.is_empty():
				var q: int = stack.pop_back()
				var qx := q % N
				var qy := q / N
				area += 1
				bb = bb.expand(Vector2i(qx, qy))
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx: int = qx + d.x
					var ny: int = qy + d.y
					if nx < x0 or nx >= x1 or ny < y0 or ny >= y1:
						continue
					var nk := ny * N + nx
					if seen.has(nk) or img.get_pixel(nx, ny).get_luminance() > 0.3:
						continue
					seen[nk] = true
					stack.append(nk)
			comps.append({"area": area, "bb": Rect2(Vector2(bb.position) / N, Vector2(bb.size + Vector2i.ONE) / N)})
	var left: Dictionary = {}
	var right: Dictionary = {}
	var mid: Dictionary = {}
	for c in comps:
		var r: Rect2 = c.bb
		var cx := r.get_center().x
		if absf(cx - 0.5) < 0.03:
			if mid.is_empty() or c.area > mid.area:
				mid = c
		elif cx < 0.5:
			if left.is_empty() or c.area > left.area:
				left = c
		elif right.is_empty() or c.area > right.area:
			right = c
	if left.is_empty() or right.is_empty():
		_face_spots[key] = out
		return out
	for e in [["eye_l", left], ["eye_r", right]]:
		var r: Rect2 = e[1].bb
		out[e[0]] = Vector4(r.get_center().x, r.get_center().y, r.size.x * 0.5, r.size.y * 0.5)
	var eye_y := ((left.bb as Rect2).get_center().y + (right.bb as Rect2).get_center().y) * 0.5
	if not mid.is_empty():
		var mr: Rect2 = mid.bb
		out["mouth"] = Vector4(mr.get_center().x, mr.get_center().y, maxf(mr.size.x * 0.5, 0.006), maxf(mr.size.y * 0.5, 0.004))
		out["down"] = signf(mr.get_center().y - eye_y)
	# 皮肤色：两眼中间偏上一点的那个像素
	out["skin"] = img.get_pixel(N / 2, int(eye_y * N))
	_face_spots[key] = out
	return out


## 头发：发壳 + 各人的样子（翘起的一撮、两个小辫、马尾、发髻）
func _build_hair(head: Node3D, c: Vector3, r: Vector3, kind: String, lk: Dictionary) -> void:
	var grey := kind.ends_with("_grey") or kind == "boy_old"
	var hc: Color = Color(str(lk.get("hair_col"))) if lk.has("hair_col") else (HAIR_GREY if grey else HAIR_DARK)
	var hm := Kit.mat(hc, 0.58, 0.0, 0.2)
	hm.cull_mode = BaseMaterial3D.CULL_DISABLED
	hm.metallic_specular = 0.6
	var line: Callable
	var lift := 0.09
	var clump := 0.04
	var strands := 10.0
	match kind:
		"boy", "boy_long", "boy_side", "boy_short":
			var front := 1.3 if kind == "boy" else (1.38 if kind == "boy_long" else 1.2)
			var side_drop := 1.72 if kind != "boy_short" else 1.6
			line = func(phi: float) -> float:
				var a := absf(phi)
				var saw := 0.12 * absf(fmod(phi * 4.5 + 10.0, 1.0) - 0.5) * 2.0 * (1.0 - smoothstep(0.6, 1.2, a))
				var side_part := 0.0
				if kind == "boy_side":
					side_part = -0.1 * smoothstep(0.0, 0.5, phi) * (1.0 - smoothstep(0.5, 1.0, phi))
				return lerpf(front, side_drop, smoothstep(0.35, 1.5, a)) + (2.15 - side_drop) * smoothstep(1.9, 3.0, a) + saw + side_part
			lift = 0.075 if kind == "boy" else 0.065
			clump = 0.05 if kind == "boy" else 0.035
			strands = 11.0
		"boy_old":
			line = func(phi: float) -> float:
				var a := absf(phi)
				return lerpf(0.78, 1.55, smoothstep(0.3, 1.5, a)) + 0.5 * smoothstep(1.9, 3.0, a)
			lift = 0.05
			clump = 0.02
			strands = 14.0
		"pigtails", "ponytail", "bob", "bun", "bun_grey":
			var bangs := 1.42 if kind != "bun" and kind != "bun_grey" else 1.0
			var side_drop := 2.3 if kind == "bob" else 1.95
			var back := 2.3 if kind == "bob" else 2.05
			line = func(phi: float) -> float:
				var a := absf(phi)
				# 齐刘海：正面平的，两边往下
				var fringe := 0.035 * absf(fmod(phi * 6.0 + 10.0, 1.0) - 0.5) * (1.0 - smoothstep(0.6, 1.1, a))
				return lerpf(bangs, side_drop, smoothstep(0.55, 1.45, a)) + (back - side_drop) * smoothstep(1.8, 3.0, a) + fringe
			lift = 0.08 if kind == "bob" else 0.06
			clump = 0.03
			strands = 13.0
		_:
			line = func(_p: float) -> float: return 1.6
	var shell := _mesh(head, Kit.hair_shell(r, line, lift, clump, strands, 44, 16), hm, c)
	shell.name = "hair"
	if kind == "boy":
		# 头顶翘起的一撮
		var pts := PackedVector3Array([Vector3(0, r.y * 1.06, -r.z * 0.1), Vector3(0.0, r.y * 1.22, r.z * 0.02), Vector3(0.0, r.y * 1.3, r.z * 0.2), Vector3(0.0, r.y * 1.24, r.z * 0.32)])
		_mesh(head, Kit.tube(pts, r.x * 0.07, 6, r.x * 0.015), hm, c)
	if kind == "pigtails":
		# 两个小辫：耳朵后面扎起来、往下垂，红头绳
		var tie := Kit.mat(P.MEI.darkened(0.05), 0.5)
		for sgn in [-1.0, 1.0]:
			var tail := Node3D.new()
			tail.position = c + Vector3(sgn * r.x * 0.88, r.y * 0.02, -r.z * 0.4)
			tail.rotation.z = sgn * 0.55
			tail.set_meta("base_z", sgn * 0.55)
			head.add_child(tail)
			_mesh(tail, Kit.loft([[-r.y * 0.85, r.x * 0.04, r.x * 0.04], [-r.y * 0.62, r.x * 0.2, r.x * 0.17], [-r.y * 0.3, r.x * 0.25, r.x * 0.21], [-r.y * 0.05, r.x * 0.13, r.x * 0.12]], 12), hm, Vector3(sgn * r.x * 0.08, 0, 0))
			_mesh(tail, Kit.ellipsoid(Vector3(r.x * 0.13, r.x * 0.08, r.x * 0.13), 12, 6), tie, Vector3(sgn * r.x * 0.03, -r.y * 0.02, 0))
			if _tail == null:
				_tail = tail
			else:
				tail.set_meta("twin", true)
				_tail.set_meta("twin_node", tail)
	elif kind == "ponytail":
		var tail := Node3D.new()
		tail.position = c + Vector3(0, r.y * 0.1, -r.z * 1.0)
		head.add_child(tail)
		_mesh(tail, Kit.loft([[-r.y * 1.25, r.x * 0.05, r.x * 0.05], [-r.y * 0.9, r.x * 0.2, r.x * 0.15], [-r.y * 0.4, r.x * 0.24, r.x * 0.2], [-r.y * 0.05, r.x * 0.15, r.x * 0.13]], 12), hm, Vector3(0, 0, -r.z * 0.12))
		_mesh(tail, Kit.ellipsoid(Vector3(r.x * 0.14, r.x * 0.08, r.x * 0.14), 12, 6), Kit.mat(P.MEI, 0.5), Vector3(0, -r.y * 0.04, -r.z * 0.05))
		_tail = tail
	elif kind == "bun" or kind == "bun_grey":
		_mesh(head, Kit.ellipsoid(Vector3(r.x * 0.36, r.x * 0.32, r.x * 0.3), 16, 10), hm, c + Vector3(0, r.y * 0.45, -r.z * 0.95))


func _build_props() -> void:
	var s := _spec
	var hand: Node3D = j.hand_r
	var hl: Node3D = j.hand_l
	var book := Node3D.new()
	hl.add_child(book)
	var cover := Kit.mat(Color("#C9563F"), 0.6)
	var paper := Kit.mat(Color("#F2EBDC"), 0.9)
	_mesh(book, Kit.box(Vector3(0.12, 0.16, 0.022) * (s.hr / 0.13)), cover, Vector3(-0.04, -s.hand * 1.4, 0.03))
	_mesh(book, Kit.box(Vector3(0.11, 0.15, 0.024) * (s.hr / 0.13)), paper, Vector3(-0.035, -s.hand * 1.4, 0.03))
	props.book = book
	var bowl := Node3D.new()
	hl.add_child(bowl)
	_mesh(bowl, Kit.loft([[0.0, 0.035, 0.035], [0.02, 0.055, 0.055], [0.05, 0.068, 0.068]], 16, true, false), Kit.mat(Color("#EDEBE4"), 0.25), Vector3(0, -s.hand * 1.6, 0.02))
	_mesh(bowl, Kit.loft([[0.04, 0.062, 0.062], [0.042, 0.0, 0.0]], 16, false, false), Kit.mat(Color("#E3C68E"), 0.8), Vector3(0, -s.hand * 1.6, 0.02))
	props.bowl = bowl
	var box := Node3D.new()
	add_child(box)
	_mesh(box, Kit.box(Vector3(0.36, 0.24, 0.26) * (height / 1.6)), Kit.mat(Color("#B48A5A"), 0.9))
	props.box = box
	var rod := Node3D.new()
	hand.add_child(rod)
	var rp := PackedVector3Array([Vector3(0, -s.hand, 0), Vector3(0, -s.hand + 0.4, 0.5), Vector3(0, -s.hand + 0.75, 1.1)])
	_mesh(rod, Kit.tube(rp, 0.012, 5, 0.004), Kit.mat(Color("#6B4A2B"), 0.5))
	props.rod = rod
	var ball := Node3D.new()
	add_child(ball)
	var br := 0.11 * height / 1.6 + 0.02
	_mesh(ball, Kit.ellipsoid(Vector3.ONE * br, 16, 10), Kit.mat(Color("#F6F3EC"), 0.35), Vector3(0, br, 0))
	_mesh(ball, Kit.ellipsoid(Vector3.ONE * br * 1.01, 6, 4), Kit.mat(Color("#2B2A33"), 0.4), Vector3(0, br, 0)).scale = Vector3(0.45, 0.45, 1.0)
	ball.set_meta("r", br)
	props.ball = ball
	for k in props:
		props[k].visible = false


# ======================================================================
# 动画
# ======================================================================

func _process(delta: float) -> void:
	animate(delta)


func animate(delta: float) -> void:
	if j.is_empty():
		return
	_t += delta
	loop_t += delta
	if emote != "":
		emote_t += delta
	var target := _target_pose()
	var k := 1.0 - exp(-delta * (18.0 if walking else 10.0))
	for name in target:
		var v: Variant = target[name]
		if v is Vector3:
			var cur: Vector3 = _pose.get(name, Vector3.ZERO)
			cur = cur.lerp(v, k)
			_pose[name] = cur
			if j.has(name):
				(j[name] as Node3D).rotation = cur
		elif v is float:
			_pose[name] = lerpf(float(_pose.get(name, v)), v, k)
	# 没写到的关节回到 0
	for name in _pose.keys():
		if not target.has(name) and _pose[name] is Vector3:
			var cur: Vector3 = (_pose[name] as Vector3).lerp(Vector3.ZERO, k)
			_pose[name] = cur
			if j.has(name):
				(j[name] as Node3D).rotation = cur
	var h: Node3D = j.hips
	h.position = Vector3(float(_pose.get("x", 0.0)), _hip_y + float(_pose.get("y", 0.0)), float(_pose.get("z", 0.0)))
	# 朝向：走着侧过去七十度，站着转回来一点；搭伴面对面
	var want := float(target.get("yaw", 0.0))
	_yaw = lerp_angle(_yaw, want, 1.0 - exp(-delta * 9.0))
	(j.root as Node3D).rotation.y = _yaw
	_face(delta, target)
	_swing_tail(delta)
	_place_props(target)
	if _shadow != null:
		_shadow.position.x = float(_pose.get("x", 0.0))
	if j.has("skirt"):
		# 裙摆跟着腿撑开：两条腿前后分得越开，裙子前后越鼓
		var spread := absf(((j.th_l as Node3D).rotation.x - (j.th_r as Node3D).rotation.x))
		var lift := maxf(0.0, -minf((j.th_l as Node3D).rotation.x, (j.th_r as Node3D).rotation.x))
		(j.skirt as Node3D).scale = Vector3(1.0 + lift * 0.25, 1.0 - lift * 0.08, 1.0 + spread * 0.55 + lift * 0.5)


func _face(delta: float, target: Dictionary) -> void:
	_blink_t -= delta
	if _blink_t <= 0.0:
		_blink_t = randf_range(2.2, 5.0)
		_blink = 1.0
	_blink = maxf(0.0, _blink - delta * 7.0)
	var b := 1.0 if _blink > 0.5 else 0.0
	if target.has("blink"):
		b = float(target.blink)
	face_mat.set_shader_parameter("blink", b)
	face_mat.set_shader_parameter("smile", float(target.get("smile", 0.55)))
	face_mat.set_shader_parameter("open", float(target.get("open", 0.0)))


func _swing_tail(delta: float) -> void:
	if _tail == null:
		return
	# 辫子：一个阻尼弹簧，跟着身子的晃动甩
	var drive := float(_pose.get("y", 0.0)) * 30.0 + (sin(phase * TAU * 2.0) * 0.25 if walking else 0.0)
	_tail_v += (drive - _tail_a) * 60.0 * delta - _tail_v * 6.0 * delta
	_tail_a += _tail_v * delta
	var rot := Vector3(-0.15 + _tail_a * 0.5, 0, 0)
	_tail.rotation = rot + Vector3(0, 0, float(_tail.get_meta("base_z", 0.0)))
	if _tail.has_meta("twin_node"):
		var tw: Node3D = _tail.get_meta("twin_node")
		tw.rotation = rot + Vector3(0, 0, float(tw.get_meta("base_z", 0.0)))


func _place_props(target: Dictionary) -> void:
	var want: String = str(target.get("prop", ""))
	for k in props:
		props[k].visible = k == want
	if want == "box":
		var b: Node3D = props.box
		# 两只手中间
		var hl: Vector3 = _local_of(j.hand_l)
		var hr: Vector3 = _local_of(j.hand_r)
		b.position = (hl + hr) / 2.0 + Vector3(0, -0.04, 0)
		b.rotation.y = _yaw
	elif want == "ball":
		var bl: Node3D = props.ball
		bl.position = target.get("ball", Vector3.ZERO)
		bl.rotation.z = -float(target.get("ball_spin", 0.0))


## 关节在小人自己坐标里的位置（一级级乘上去；不在场景树里也算得出）
func _local_of(n: Node3D) -> Vector3:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != self:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf.origin


## 这一刻各关节该在哪（弧度）。键：关节名 → Vector3；x/y/z 胯的位移；yaw 朝向；smile/open/blink 脸；prop 手上拿什么
func _target_pose() -> Dictionary:
	var s := _spec
	var p := {}
	var face_dir := face_to if face_to != 0 and not walking else dir
	var kid := stage == "childhood"
	var old := stage == "old"
	# 站着的底子：胳膊微微张开，手肘略弯；老人背有点驼
	p.sh_l = Vector3(0.05, 0, 0.09)
	p.sh_r = Vector3(0.05, 0, -0.09)
	p.el_l = Vector3(-0.18, 0, 0)
	p.el_r = Vector3(-0.18, 0, 0)
	p.spine = Vector3(0.12 if old else 0.0, 0, 0)
	p.neck = Vector3(0.1 if old else 0.0, 0, 0)
	p.yaw = face_dir * deg_to_rad(28.0)
	p.smile = 0.55
	var breath := sin(_t * 2.1)
	p.spine = (p.spine as Vector3) + Vector3(breath * 0.012, 0, 0)
	p.y = breath * 0.003
	if asleep:
		_pose_sleep(p)
		return p
	if walking:
		_pose_walk(p, face_dir)
		return p
	if loop != "":
		p.yaw = face_dir * deg_to_rad(32.0)
		_pose_loop(p, loop, face_dir)
		return p
	if emote != "":
		p.yaw = face_dir * deg_to_rad(40.0)
		_pose_emote(p, emote)
		return p
	# 站着：重心慢慢左右换，头偶尔转一下
	var sway := sin(_t * 0.6 + float(role.length()))
	p.z = 0.0
	p.x = sway * 0.008
	p.hips = Vector3(0, 0, sway * 0.025)
	p.spine = (p.spine as Vector3) + Vector3(0, 0, -sway * 0.03)
	p.neck = (p.neck as Vector3) + Vector3(0.0, sin(_t * 0.37) * 0.25 - face_dir * 0.2, sway * 0.04)
	p.th_l = Vector3(0, 0, sway * 0.03 + 0.02)
	p.th_r = Vector3(0, 0, sway * 0.03 - 0.02)
	if kid:
		# 小孩站不住：脚尖点一点
		p.an_r = Vector3(-0.2 * maxf(0.0, sin(_t * 1.3)), 0, 0)
	return p


func _pose_walk(p: Dictionary, face_dir: int) -> void:
	var a := phase * TAU
	var sn := sin(a)
	var cs := cos(a)
	var kid := stage == "childhood"
	var old := stage == "old"
	var amp := 0.5 if not old else 0.32
	p.yaw = face_dir * deg_to_rad(60.0)
	p.th_l = Vector3(-amp * sn, 0, 0.02)
	p.th_r = Vector3(amp * sn, 0, -0.02)
	p.kn_l = Vector3(0.1 + 0.85 * maxf(0.0, cs) * amp, 0, 0)
	p.kn_r = Vector3(0.1 + 0.85 * maxf(0.0, -cs) * amp, 0, 0)
	p.an_l = Vector3(-0.25 * maxf(0.0, -sn) + 0.2 * maxf(0.0, cs) * 0.5, 0, 0)
	p.an_r = Vector3(-0.25 * maxf(0.0, sn) + 0.2 * maxf(0.0, -cs) * 0.5, 0, 0)
	var arm := (0.55 if kid else 0.42) * (0.6 if old else 1.0)
	p.sh_l = Vector3(arm * sn, 0, 0.1)
	p.sh_r = Vector3(-arm * sn, 0, -0.1)
	p.el_l = Vector3(-0.35 - 0.25 * maxf(0.0, -sn), 0, 0)
	p.el_r = Vector3(-0.35 - 0.25 * maxf(0.0, sn), 0, 0)
	p.y = -absf(sn) * 0.028 * height / 1.4 + (0.012 if kid else 0.0) * absf(cs)
	p.hips = Vector3(0, 0.1 * sn, 0)
	p.spine = Vector3(0.06 + (0.14 if old else 0.0), -0.16 * sn, 0)
	# 头往镜头这边转一点：侧着走也看得见脸
	p.neck = Vector3(-0.02 + (0.1 if old else 0.0), -face_dir * 0.45, 0)
	if j.has("skirt") or (from_glb and look.has("dress")):
		# 裙子里的腿别迈出来：步子小一点
		for k2 in ["th_l", "th_r"]:
			p[k2] = (p[k2] as Vector3) * Vector3(0.6, 1, 1)


func _pose_sleep(p: Dictionary) -> void:
	# 坐着打盹：头歪下来，胳膊搭着
	_pose_sit(p)
	p.neck = Vector3(0.55, 0.0, 0.25)
	p.spine = Vector3(0.25, 0, 0)
	p.blink = 1.0
	p.smile = 0.2
	p.yaw = deg_to_rad(10.0) * dir


func _pose_sit(p: Dictionary) -> void:
	var s := _spec
	p.y = -s.thigh * 0.92
	p.z = -s.thigh * 0.15
	p.th_l = Vector3(-1.45, 0, 0.08)
	p.th_r = Vector3(-1.45, 0, -0.08)
	p.kn_l = Vector3(1.4, 0, 0)
	p.kn_r = Vector3(1.4, 0, 0)
	p.sh_l = Vector3(-0.35, 0, 0.12)
	p.sh_r = Vector3(-0.35, 0, -0.12)
	p.el_l = Vector3(-0.6, 0, 0)
	p.el_r = Vector3(-0.6, 0, 0)


func _crouch(p: Dictionary, depth := 1.0) -> void:
	var s := _spec
	p.y = -s.thigh * 0.55 * depth
	p.th_l = Vector3(-1.2 * depth, 0, 0.18)
	p.th_r = Vector3(-1.0 * depth, 0, -0.18)
	p.kn_l = Vector3(2.0 * depth, 0, 0)
	p.kn_r = Vector3(1.9 * depth, 0, 0)
	p.an_l = Vector3(-0.7 * depth, 0, 0)
	p.an_r = Vector3(-0.8 * depth, 0, 0)
	p.spine = Vector3(0.45 * depth, 0, 0)


func _pose_emote(p: Dictionary, e: String) -> void:
	var t := emote_t
	match e:
		"wave":
			var w := sin(t * 11.0)
			p.sh_r = Vector3(-0.3, 0, -2.5 + w * 0.12)
			p.el_r = Vector3(-0.25, 0, -0.35 - w * 0.35)
			p.neck = Vector3(-0.05, 0, 0.12)
			p.smile = 0.9
			p.open = 0.3
		"joy":
			var hop := maxf(0.0, sin(t * 9.0)) * (1.0 if t < 1.0 else 0.0)
			p.y = hop * 0.12 * height / 1.4
			p.sh_l = Vector3(-0.2, 0, 2.5)
			p.sh_r = Vector3(-0.2, 0, -2.5)
			p.el_l = Vector3(-0.3, 0, 0)
			p.el_r = Vector3(-0.3, 0, 0)
			p.kn_l = Vector3(hop * 0.9, 0, 0)
			p.kn_r = Vector3(hop * 0.9, 0, 0)
			p.th_l = Vector3(-hop * 0.4, 0, 0)
			p.th_r = Vector3(-hop * 0.4, 0, 0)
			p.smile = 1.0
			p.open = 0.6
			p.blink = 1.0
		"sad":
			p.neck = Vector3(0.45, 0, 0)
			p.spine = Vector3(0.22, 0, 0)
			p.sh_l = Vector3(0.1, 0, 0.04)
			p.sh_r = Vector3(0.1, 0, -0.04)
			p.smile = -0.8
			p.y = -0.01
		"five":
			p.sh_r = Vector3(-2.7, 0, -0.25)
			p.el_r = Vector3(-0.2, 0, 0)
			p.yaw = (face_to if face_to != 0 else dir) * deg_to_rad(70.0)
			p.smile = 1.0
			p.open = 0.4
		"shy":
			p.sh_r = Vector3(-2.3, 0, -0.75)
			p.el_r = Vector3(-2.3, 0, 0)
			p.neck = Vector3(0.12, 0.2, 0.18)
			p.smile = 0.7
			p.th_l = Vector3(0, 0, -0.06)
			p.kn_l = Vector3(0.2, 0, 0)


func _pose_loop(p: Dictionary, lp: String, face_dir: int) -> void:
	var t := loop_t
	var s := _spec
	match lp:
		"sit":
			_pose_sit(p)
			p.neck = Vector3(0.05, sin(t * 0.5) * 0.2, 0)
		"wave":
			_pose_emote(p, "wave")
		"write", "chalk":
			if lp == "chalk":
				p.sh_r = Vector3(-2.0 + sin(t * 3.0) * 0.1, 0, -0.2 + sin(t * 5.0) * 0.15)
				p.el_r = Vector3(-0.5, 0, 0)
				p.neck = Vector3(-0.15, 0, 0)
				p.yaw = face_dir * deg_to_rad(60.0)
			else:
				p.neck = Vector3(0.4, 0, 0)
				p.spine = Vector3(0.12, 0, 0)
				p.sh_l = Vector3(-0.6, 0, 0.15)
				p.el_l = Vector3(-1.4, 0, 0)
				p.sh_r = Vector3(-0.55 + sin(t * 6.0) * 0.05, 0, -0.2 + cos(t * 6.0) * 0.06)
				p.el_r = Vector3(-1.3, 0, 0)
				p.prop = "book"
		"read":
			p.neck = Vector3(0.35, 0, 0)
			p.sh_l = Vector3(-0.75, 0, 0.12)
			p.el_l = Vector3(-1.25, 0, 0)
			p.sh_r = Vector3(-0.75, 0, -0.12)
			p.el_r = Vector3(-1.25, 0, 0)
			if fmod(t, 6.0) > 5.4:
				p.sh_r = Vector3(-0.9, 0, -0.35)
			p.prop = "book"
		"eat":
			var bite := smoothstep(0.0, 0.3, fmod(t, 1.6)) * (1.0 - smoothstep(0.7, 1.0, fmod(t, 1.6)))
			p.sh_l = Vector3(-0.55, 0, 0.18)
			p.el_l = Vector3(-1.35, 0, 0)
			p.sh_r = Vector3(-0.4 - bite * 0.55, 0, -0.15)
			p.el_r = Vector3(-1.2 - bite * 1.1, 0, 0)
			p.neck = Vector3(0.15 - bite * 0.1, 0, 0)
			p.open = bite * 0.6
			p.smile = 0.8
			p.prop = "bowl"
		"type", "piano", "busy", "wash":
			var f := 10.0 if lp != "wash" else 5.0
			p.sh_l = Vector3(-0.55, 0, 0.1)
			p.sh_r = Vector3(-0.55, 0, -0.1)
			p.el_l = Vector3(-1.0 + sin(t * f) * 0.12, 0, 0)
			p.el_r = Vector3(-1.0 + sin(t * f + 1.7) * 0.12, 0, 0)
			p.neck = Vector3(0.3, 0, 0)
			if lp == "piano":
				_pose_sit(p)
				p.sh_l = Vector3(-0.8, 0, 0.15)
				p.sh_r = Vector3(-0.8, 0, -0.15)
				p.el_l = Vector3(-0.6 + sin(t * f) * 0.15, 0, 0)
				p.el_r = Vector3(-0.6 + sin(t * f + 1.7) * 0.15, 0, 0)
			if lp == "wash":
				p.el_l = Vector3(-1.3, 0, sin(t * f) * 0.3)
				p.el_r = Vector3(-1.3, 0, -sin(t * f) * 0.3)
				p.spine = Vector3(0.2, 0, 0)
		"kick":
			# 颠球：右脚一下一下往上踢，球在脚面上方跳
			var period := 0.72
			var u := fmod(t, period) / period
			var kick := smoothstep(0.0, 0.18, u) * (1.0 - smoothstep(0.25, 0.55, u))
			p.th_r = Vector3(-0.9 * kick, 0, 0)
			p.kn_r = Vector3(0.5 + 0.4 * kick, 0, 0)
			p.an_r = Vector3(-0.3 * kick, 0, 0)
			p.sh_l = Vector3(-0.3, 0, 0.6)
			p.sh_r = Vector3(-0.2, 0, -0.55)
			p.neck = Vector3(0.35, 0, 0)
			var hball := 0.08 + absf(sin(u * PI)) * 0.42 * height / 1.4
			p.ball = _forward(0.18) + Vector3(0, hball, 0)
			p.ball_spin = t * 6.0
			p.prop = "ball"
		"pass":
			# 对着踢：球滚到脚边那一下出脚
			var ph := pass_phase
			var kick2 := 1.0 - smoothstep(0.0, 0.16, ph) if ph < 0.5 else smoothstep(0.82, 1.0, ph) * 0.5
			p.th_r = Vector3(-0.85 * kick2 + 0.25 * smoothstep(0.82, 0.95, ph), 0, 0)
			p.kn_r = Vector3(0.3 + 0.3 * kick2, 0, 0)
			p.sh_l = Vector3(-0.3, 0, 0.45)
			p.sh_r = Vector3(0.2, 0, -0.4)
			p.neck = Vector3(0.25, 0, 0)
			p.yaw = face_dir * deg_to_rad(75.0)
		"hop":
			var u2 := fmod(t, 0.62) / 0.62
			var up := sin(u2 * PI)
			p.y = up * 0.1 * height / 1.4
			p.th_l = Vector3(-0.5 * up, 0, 0)
			p.kn_l = Vector3(1.3 * up, 0, 0)
			p.th_r = Vector3(0.1 * up, 0, 0)
			p.kn_r = Vector3(0.3 * up, 0, 0)
			p.sh_l = Vector3(-0.3, 0, 0.7)
			p.sh_r = Vector3(-0.3, 0, -0.7)
			p.smile = 1.0
			p.open = 0.3 * up
		"fix":
			_crouch(p, 1.0)
			p.sh_l = Vector3(-1.0, 0, 0.2)
			p.sh_r = Vector3(-1.1 + sin(t * 4.0) * 0.15, 0, -0.2)
			p.el_l = Vector3(-0.6, 0, 0)
			p.el_r = Vector3(-0.7 + sin(t * 8.0) * 0.2, 0, 0)
			p.neck = Vector3(0.25, 0, 0)
			p.yaw = face_dir * deg_to_rad(55.0)
		"carry":
			p.sh_l = Vector3(-0.85, 0, 0.2)
			p.sh_r = Vector3(-0.85, 0, -0.2)
			p.el_l = Vector3(-1.0, 0, -0.3)
			p.el_r = Vector3(-1.0, 0, 0.3)
			p.spine = Vector3(-0.08, 0, 0)
			p.y = -absf(sin(t * 4.0)) * 0.01
			p.prop = "box"
		"cook":
			p.sh_l = Vector3(-0.6, 0, 0.15)
			p.el_l = Vector3(-1.0, 0, 0)
			p.sh_r = Vector3(-0.7 + sin(t * 4.5) * 0.18, 0, -0.25 + cos(t * 4.5) * 0.18)
			p.el_r = Vector3(-0.9, 0, 0)
			p.neck = Vector3(0.3, 0, 0)
			p.spine = Vector3(0.1, 0, 0)
			p.yaw = face_dir * deg_to_rad(15.0)
		"fish":
			p.sh_r = Vector3(-0.9 + sin(t * 1.3) * 0.05, 0, -0.1)
			p.el_r = Vector3(-0.6, 0, 0)
			p.sh_l = Vector3(-0.7, 0, 0.3)
			p.el_l = Vector3(-1.0, 0, 0)
			p.neck = Vector3(0.1, 0, 0)
			p.yaw = face_dir * deg_to_rad(65.0)
			p.prop = "rod"
		"chess":
			_pose_sit(p)
			var reach := smoothstep(0.0, 0.3, fmod(t, 4.0)) * (1.0 - smoothstep(0.6, 1.0, fmod(t, 4.0)))
			p.sh_r = Vector3(-0.7 - reach * 0.4, 0, -0.1)
			p.el_r = Vector3(-0.8 + reach * 0.5, 0, 0)
			p.sh_l = Vector3(-0.5, 0, 0.3)
			p.el_l = Vector3(-1.6, 0, 0.0)
			p.neck = Vector3(0.35, 0, 0)
			p.yaw = face_dir * deg_to_rad(70.0)
		"talk":
			var g := sin(t * 2.3)
			p.sh_r = Vector3(-0.5 - maxf(0.0, g) * 0.4, 0, -0.25 - maxf(0.0, g) * 0.3)
			p.el_r = Vector3(-1.1, 0, 0)
			p.sh_l = Vector3(-0.1, 0, 0.12)
			p.neck = Vector3(sin(t * 3.1) * 0.08, 0, sin(t * 1.7) * 0.06)
			p.open = maxf(0.0, sin(t * 11.0)) * 0.45 * (0.5 + 0.5 * maxf(0.0, sin(t * 1.3)))
			p.smile = 0.7
			p.yaw = face_dir * deg_to_rad(62.0)
		"sing":
			p.sh_r = Vector3(-1.2, 0, -0.6 + sin(t * 1.8) * 0.15)
			p.el_r = Vector3(-0.3, 0, 0)
			p.sh_l = Vector3(-0.5, 0, 0.15)
			p.el_l = Vector3(-1.4, 0, 0)
			p.neck = Vector3(-0.2, 0, sin(t * 1.8) * 0.1)
			p.open = 0.55 + sin(t * 4.0) * 0.25
			p.blink = 1.0 if fmod(t, 5.0) < 2.0 else 0.0
			p.smile = 0.6
		"kite":
			var tug := sin(t * 1.7)
			p.sh_r = Vector3(-2.2 + tug * 0.15, 0, -0.2)
			p.el_r = Vector3(-0.2, 0, 0)
			p.sh_l = Vector3(-0.8, 0, 0.2)
			p.el_l = Vector3(-0.9, 0, 0)
			p.neck = Vector3(-0.55, 0, 0)
			p.smile = 0.9
			p.open = 0.2
		"gaze":
			p.sh_l = Vector3(0.45, 0, 0.12)
			p.sh_r = Vector3(0.45, 0, -0.12)
			p.el_l = Vector3(-0.9, 0, 0)
			p.el_r = Vector3(-0.9, 0, 0)
			p.neck = Vector3(-0.15, sin(t * 0.4) * 0.3, 0)
			p.spine = Vector3(-0.05, 0, 0)
			p.smile = 0.4
			p.yaw = face_dir * deg_to_rad(50.0)
		"exercise":
			var u3 := sin(t * 2.6)
			p.sh_l = Vector3(-0.2, 0, 1.4 + u3 * 1.2)
			p.sh_r = Vector3(-0.2, 0, -1.4 - u3 * 1.2)
			p.el_l = Vector3(-0.1, 0, 0)
			p.el_r = Vector3(-0.1, 0, 0)
			p.y = -maxf(0.0, -u3) * 0.05
			p.kn_l = Vector3(maxf(0.0, -u3) * 0.3, 0, 0)
			p.kn_r = Vector3(maxf(0.0, -u3) * 0.3, 0, 0)
			p.th_l = Vector3(-maxf(0.0, -u3) * 0.15, 0, 0.08)
			p.th_r = Vector3(-maxf(0.0, -u3) * 0.15, 0, -0.08)
		"brush":
			# 蹲着在地上写（老人拿水笔写地书 / 小孩堆沙子）
			_crouch(p, 0.8)
			p.sh_r = Vector3(-1.0 + sin(t * 2.0) * 0.2, 0, -0.3 + cos(t * 2.0) * 0.2)
			p.el_r = Vector3(-0.3, 0, 0)
			p.sh_l = Vector3(-0.6, 0, 0.3)
			p.el_l = Vector3(-1.2, 0, 0)
			p.neck = Vector3(0.4, 0, 0)
		_:
			p.sh_l = Vector3(-0.5, 0, 0.1)
			p.sh_r = Vector3(-0.5 + sin(t * 5.0) * 0.1, 0, -0.1)
			p.el_l = Vector3(-1.0, 0, 0)
			p.el_r = Vector3(-1.1, 0, 0)
			p.neck = Vector3(0.3, 0, 0)


## 人前面多远的一点（人自己的坐标里，按朝向）
func _forward(dist: float) -> Vector3:
	return Vector3(sin(_yaw) * dist, 0, cos(_yaw) * dist)


## 头顶在哪（世界坐标）：气泡、名字牌对齐用
func head_top() -> Vector3:
	return global_position + Vector3(0, height, 0)
