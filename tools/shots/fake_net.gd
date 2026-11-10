extends "res://scripts/net/lifeline_client.gd"
## 截图用的假联机：不连服务器，大厅列表和找回码直接给假数据。


func connect_server() -> bool:
	return true


func list_lifelines() -> void:
	lifelines.emit([
		{"lifelineId": "a", "role": "qing", "names": {"qing": "小满", "mei": "阿蘅"}, "paired": true, "phase": "life", "label": "7 岁 · 立夏", "code": "482913"},
		{"lifelineId": "b", "role": "mei", "names": {"qing": "老顾", "mei": "小满"}, "paired": true, "phase": "ended", "label": "", "code": "117204"},
		{"lifelineId": "c", "role": "qing", "names": {"qing": "小满"}, "paired": false, "phase": "roll", "label": "", "code": "905516"},
	])


func last_lifeline() -> String:
	return "a"


func recovery_code() -> String:
	return "K7M2QX94TB"


func go_offline() -> void:
	pass
