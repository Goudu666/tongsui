extends Node2D
## 人头顶的字和气泡单独画一层：盖在夜版（z 65）、光与空气（z 68）、近景（z 69）和互动点（z 70）上面，
## 白天不被调色压灰，晚上也看得清。挂在人底下跟着走；画什么由 paint(canvas) 说了算。
const Z := 71

var paint: Callable


func _init(p: Callable) -> void:
	paint = p
	z_as_relative = false
	z_index = Z


func _draw() -> void:
	if paint.is_valid():
		paint.call(self)
