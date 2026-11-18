extends "res://scripts/world3d/set3d.gd"
## （临时占位，正在搭）content/maps/primary.yaml 的实时 3D。


func build(sc: Dictionary, p_look: String, season: String) -> void:
	_rng.seed = 20261118
	var w := float(sc.get("width", 2800)) / 100.0
	_begin()
	bx("pavers", -2.0, w + 2.0, -0.2, 0.0, -3.0, 2.0)
	var i := 0
	for key in ["brick", "plaster", "concrete", "curb", "wood", "metal", "glass", "paint", "stone", "tiles", "iron"]:
		bx(key, i * 2.5, i * 2.5 + 2.4, 0.0, 3.0, -4.0, -3.0)
		i += 1
	_commit(self)
	_add_lamp(Vector3(w / 2.0, 3.0, -1.0), Color(1.0, 0.85, 0.6), 6.0, 1.2)
	super.build(sc, p_look, season)
