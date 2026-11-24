class_name BlockDB
## 方块类型表（MVP：按世界深度决定，暂不写 per-voxel 类型）
## 掉落物 id 就是物品 id，背包里直接用它

const AIR := 0
const GRASS := 1
const DIRT := 2
const STONE := 3
const DEEP := 4

const INFO := {
	GRASS: {"name": "草地", "color": Color(0.42, 0.53, 0.34), "drop": "dirt", "drop_chance": 0.45, "extra": "berry"},
	DIRT: {"name": "泥土", "color": Color(0.44, 0.38, 0.28), "drop": "dirt", "drop_chance": 1.0, "extra": ""},
	STONE: {"name": "石头", "color": Color(0.48, 0.48, 0.46), "drop": "stone", "drop_chance": 1.0, "extra": ""},
	DEEP: {"name": "硬岩", "color": Color(0.36, 0.36, 0.38), "drop": "stone", "drop_chance": 1.0, "extra": ""},
}

## 可放置物品 → 显示颜色
const ITEM_COLOR := {
	"dirt": Color(0.44, 0.38, 0.28),
	"stone": Color(0.48, 0.48, 0.46),
	"berry": Color(0.72, 0.24, 0.30),
	"wood": Color(0.42, 0.30, 0.18),
	"plank": Color(0.64, 0.49, 0.30),
	"torch": Color(0.92, 0.64, 0.28),
	"pickaxe": Color(0.54, 0.54, 0.58),
	"cooked_berry": Color(0.80, 0.44, 0.26),
	"bone": Color(0.88, 0.86, 0.78),
	"sword": Color(0.62, 0.64, 0.70),
}

const ITEM_NAME := {
	"dirt": "泥土",
	"stone": "石头",
	"berry": "浆果",
	"wood": "木头",
	"plank": "木板",
	"torch": "火把",
	"pickaxe": "石镐",
	"cooked_berry": "烤浆果",
	"bone": "骨片",
	"sword": "石剑",
}


static func id_at(world_y: float) -> int:
	if world_y > -6.0:
		return GRASS
	if world_y > -22.0:
		return DIRT
	if world_y > -55.0:
		return STONE
	return DEEP


static func drop_for(world_y: float) -> Dictionary:
	var id := id_at(world_y)
	var info: Dictionary = INFO[id]
	var out := {"id": info["drop"], "count": 1}
	return out


static func color_of_item(item_id: String) -> Color:
	return ITEM_COLOR.get(item_id, Color(0.6, 0.6, 0.6))


static func name_of_item(item_id: String) -> String:
	return ITEM_NAME.get(item_id, item_id)
