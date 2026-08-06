extends Node
## Persistent meta-progression: scrap currency, lifetime stats, and
## permanent "starting loadout" upgrades that carry over between runs.
##
## Saved to `user://meta_progress.json`. Loaded on _ready, saved on
## every meaningful change.

signal currency_changed(new_amount: int)
signal purchased_changed(id: String, now_owned: bool)
signal stats_changed                          # kills/boss_kills/best_time

# Permanent upgrades purchasable with currency. Each entry's `apply`
# is called once at run start (game.gd reads it).
class ShopItem:
	var id: String
	var name: String
	var description: String
	var cost: int
	var apply: Callable   # 启动时调用，对 GameState 设置一个永久偏置

	func _init(p_id: String, p_name: String, p_desc: String,
			p_cost: int, p_apply: Callable) -> void:
		id = p_id
		name = p_name
		description = p_desc
		cost = p_cost
		apply = p_apply

# --- Persisted state ---
var currency: int = 0
var total_kills: int = 0
var total_boss_kills: int = 0
var best_time: float = 0.0
var purchased: Dictionary = {}   # id -> true

# --- Run-scope stat (NOT persisted) ---
var run_kills: int = 0
var run_boss_kills: int = 0

const SAVE_PATH: String = "user://meta_progress.json"

# Shop catalogue. Bump cost in multiples of 50/80/120.
var _shop: Array = []

func _ready() -> void:
	add_to_group("meta_progress")
	_build_shop()
	_load()

func _build_shop() -> void:
	_shop.clear()
	_shop.append(ShopItem.new(
		"magnet_lv1", "磁力回收 · 模块",
		"开局拾取半径 +25%", 50,
		func(): GameState.pickup_radius_mult *= 1.25
	))
	_shop.append(ShopItem.new(
		"iron_skin_lv1", "钛合金外骨骼 · 模块",
		"开局最大生命 +25", 50,
		func(): GameState.max_hp_bonus += 25.0
	))
	_shop.append(ShopItem.new(
		"tactical_lens_lv1", "战术瞄准镜 · 模块",
		"开局暴击率 +5%", 80,
		func(): GameState.crit_rate = minf(1.0, GameState.crit_rate + 0.05)
	))
	_shop.append(ShopItem.new(
		"vambrace_lv1", "机动伺服 · 模块",
		"开局移速 +5%", 80,
		func(): GameState.move_speed_mult *= 1.05
	))
	_shop.append(ShopItem.new(
		"overcharge_lv1", "过载电容 · 模块",
		"开局伤害 +10%", 120,
		func(): GameState.damage_mult *= 1.10
	))

# --- Shop ---

func get_shop_items() -> Array:
	return _shop.duplicate()

func has(id: String) -> bool:
	return purchased.get(id, false)

func can_afford(id: String) -> bool:
	for s in _shop:
		if s.id == id:
			return currency >= s.cost and not purchased.get(id, false)
	return false

## Try to buy. Returns true on success.
func buy(id: String) -> bool:
	for s in _shop:
		if s.id == id and not purchased.get(id, false) and currency >= s.cost:
			currency -= s.cost
			purchased[id] = true
			purchased_changed.emit(id, true)
			_save()
			currency_changed.emit(currency)
			return true
	return false

## Apply all owned meta upgrades to GameState. Called at run start.
func apply_owned_upgrades() -> void:
	for s in _shop:
		if purchased.get(s.id, false):
			s.apply.call()

# --- Run lifecycle ---

func start_run() -> void:
	run_kills = 0
	run_boss_kills = 0
	apply_owned_upgrades()

func record_kill() -> void:
	total_kills += 1
	run_kills += 1
	stats_changed.emit()

func record_boss_kill() -> void:
	total_boss_kills += 1
	run_boss_kills += 1
	currency += 50
	currency_changed.emit(currency)
	stats_changed.emit()
	_save()

## End-of-run reward: 1 currency per second survived, plus 1 per 10 kills.
func finish_run(time_alive: float) -> int:
	var reward: int = int(time_alive) + (run_kills / 10)
	currency += reward
	if time_alive > best_time:
		best_time = time_alive
		stats_changed.emit()
	currency_changed.emit(currency)
	_save()
	return reward

## 从头开始：清空整个元进度存档（废金属、累计统计、已购模块），然后立即落盘。
## 这是玩家主动的"开新档"，不可撤销 —— 只在结算界面的"从头开始"按钮触发。
func wipe() -> void:
	currency = 0
	total_kills = 0
	total_boss_kills = 0
	best_time = 0.0
	run_kills = 0
	run_boss_kills = 0
	purchased.clear()
	for s in _shop:
		purchased_changed.emit(s.id, false)
	currency_changed.emit(currency)
	stats_changed.emit()
	_save()
	print("[MetaProgress] save wiped — fresh start")

# --- Persistence ---

func _save() -> void:
	var data: Dictionary = {
		"currency": currency,
		"total_kills": total_kills,
		"total_boss_kills": total_boss_kills,
		"best_time": best_time,
		"purchased": purchased,
	}
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[MetaProgress] cannot write %s" % SAVE_PATH)
		return
	f.store_string(JSON.stringify(data))
	f.close()

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var data: Dictionary = parsed
	currency = int(data.get("currency", 0))
	total_kills = int(data.get("total_kills", 0))
	total_boss_kills = int(data.get("total_boss_kills", 0))
	best_time = float(data.get("best_time", 0.0))
	var p: Variant = data.get("purchased", {})
	if typeof(p) == TYPE_DICTIONARY:
		purchased = p
	currency_changed.emit(currency)
	stats_changed.emit()
	print("[MetaProgress] loaded: %d currency, %d kills, %d bosses, best %.0fs" %
		[currency, total_kills, total_boss_kills, best_time])
