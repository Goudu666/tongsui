extends RefCounted
## 《同岁》配色：孔版套色（Risograph）的两种专色 + 墨 + 纸

const PAPER := Color("#F4EEE1")
const INK := Color("#2B2A33")
const INK_SOFT := Color("#8A8578")
const QING := Color("#2E8B7A")  ## 玩家 A 的颜色
const MEI := Color("#D9485F")   ## 玩家 B 的颜色
const OVERLAP := Color("#4A3546")  ## 两色叠印

const ROLE_NAME := {"qing": "青", "mei": "梅"}


static func role_color(role: String) -> Color:
	return QING if role == "qing" else MEI
