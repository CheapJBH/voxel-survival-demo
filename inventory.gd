class_name Inventory
## 极简背包：固定 8 格，同 id 自动堆叠

const SLOT_COUNT := 8
const MAX_STACK := 99

var slots: Array = []   # 每格: {"id": String, "count": int} 或 {}
var selected := 0


func _init() -> void:
	slots.resize(SLOT_COUNT)
	for i in range(SLOT_COUNT):
		slots[i] = {}


func add(item_id: String, amount: int) -> int:
	if amount <= 0 or item_id == "":
		return amount
	var left := amount
	# 先合并已有堆
	for i in range(SLOT_COUNT):
		var s: Dictionary = slots[i]
		if s.is_empty() or s["id"] != item_id:
			continue
		if s["count"] >= MAX_STACK:
			continue
		var can := mini(MAX_STACK - int(s["count"]), left)
		s["count"] = int(s["count"]) + can
		left -= can
		if left <= 0:
			return 0
	# 再放空格
	for i in range(SLOT_COUNT):
		if not slots[i].is_empty():
			continue
		var put := mini(MAX_STACK, left)
		slots[i] = {"id": item_id, "count": put}
		left -= put
		if left <= 0:
			return 0
	return left


func count_of(item_id: String) -> int:
	var total := 0
	for s in slots:
		if not s.is_empty() and s["id"] == item_id:
			total += int(s["count"])
	return total


func remove(item_id: String, amount: int) -> bool:
	if count_of(item_id) < amount:
		return false
	var left := amount
	for i in range(SLOT_COUNT):
		var s: Dictionary = slots[i]
		if s.is_empty() or s["id"] != item_id:
			continue
		var take := mini(int(s["count"]), left)
		s["count"] = int(s["count"]) - take
		left -= take
		if int(s["count"]) <= 0:
			slots[i] = {}
		if left <= 0:
			break
	return true


func selected_item() -> Dictionary:
	return slots[selected]


func selected_id() -> String:
	var s: Dictionary = slots[selected]
	return "" if s.is_empty() else String(s["id"])


func cycle_selected() -> void:
	selected = (selected + 1) % SLOT_COUNT


func to_dict() -> Dictionary:
	return {"slots": slots.duplicate(true), "selected": selected}


func from_dict(d: Dictionary) -> void:
	var arr = d.get("slots", [])
	for i in range(SLOT_COUNT):
		if i < arr.size() and arr[i] is Dictionary:
			slots[i] = arr[i]
		else:
			slots[i] = {}
	selected = int(d.get("selected", 0)) % SLOT_COUNT
