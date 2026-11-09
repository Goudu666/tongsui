extends RefCounted
## 《同岁》配色：孔版套色（Risograph）的两种专色 + 墨 + 纸

const PAPER := Color("#F4EEE1")
const PAPER_DARK := Color("#E8E0CF")
const INK := Color("#2B2A33")
const INK_SOFT := Color("#8A8578")
const QING := Color("#2E8B7A")  ## 玩家 A 的颜色
const MEI := Color("#D9485F")   ## 玩家 B 的颜色
const OVERLAP := Color("#4A3546")  ## 两色叠印

const ROLE_NAME := {"qing": "青", "mei": "梅"}
const WEALTH_NAME := ["清贫", "小康", "殷实"]
const STAT_NAME := {"body": "体魄", "mind": "心智", "charm": "魅力", "luck": "运气"}
const NEED_NAME := {"hunger": "饱腹", "energy": "精力", "mood": "心情", "clean": "清洁"}

const FONT_PATH := "res://fonts/LXGWWenKai-Regular.ttf"


static func role_color(role: String) -> Color:
	return QING if role == "qing" else MEI


static func font() -> Font:
	if ResourceLoader.exists(FONT_PATH):
		return load(FONT_PATH)
	return ThemeDB.fallback_font


static func clock(minute: float) -> String:
	var m := int(minute)
	return "%02d:%02d" % [m / 60, m % 60]
