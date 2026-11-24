class_name Recipes
## 合成配方表（第三期）

const LIST := [
	{
		"id": "plank",
		"name": "木板",
		"need": {"wood": 2},
		"give": {"plank": 4},
	},
	{
		"id": "torch",
		"name": "火把",
		"need": {"plank": 1, "stone": 1},
		"give": {"torch": 2},
	},
	{
		"id": "pickaxe",
		"name": "石镐",
		"need": {"plank": 2, "stone": 3},
		"give": {"pickaxe": 1},
	},
	{
		"id": "sword",
		"name": "石剑",
		"need": {"bone": 2, "stone": 2},
		"give": {"sword": 1},
	},
	{
		"id": "cooked_berry",
		"name": "烤浆果",
		"need": {"berry": 2, "plank": 1},
		"give": {"cooked_berry": 2},
	},
]


static func can_craft(recipe: Dictionary, inv: Inventory) -> bool:
	var need: Dictionary = recipe["need"]
	for k in need.keys():
		if inv.count_of(String(k)) < int(need[k]):
			return false
	return true


static func craft(recipe: Dictionary, inv: Inventory) -> bool:
	if not can_craft(recipe, inv):
		return false
	var need: Dictionary = recipe["need"]
	for k in need.keys():
		inv.remove(String(k), int(need[k]))
	var give: Dictionary = recipe["give"]
	for k in give.keys():
		inv.add(String(k), int(give[k]))
	return true


static func need_text(recipe: Dictionary) -> String:
	var parts: Array = []
	var need: Dictionary = recipe["need"]
	for k in need.keys():
		parts.append("%s×%d" % [BlockDB.name_of_item(String(k)), int(need[k])])
	return "  ".join(parts)
