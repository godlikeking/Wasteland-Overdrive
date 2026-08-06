extends CanvasLayer
## Meta-progression shop. Lists all purchasable permanent upgrades,
## shows the player's currency, and lets the player buy an item.
## Lives on the GameOver screen — paused while open.

signal closed
signal purchased(id: String)

@onready var title_label: Label = $CenterContainer/Panel/MarginContainer/VBox/TitleLabel
@onready var currency_label: Label = $CenterContainer/Panel/MarginContainer/VBox/CurrencyLabel
@onready var card_row: HBoxContainer = $CenterContainer/Panel/MarginContainer/VBox/CardRow
@onready var close_btn: Button = $CenterContainer/Panel/MarginContainer/VBox/CloseButton

var _cards: Array = []   # Array[Button]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	close_btn.pressed.connect(_on_close)
	MetaProgress.currency_changed.connect(_refresh)
	MetaProgress.purchased_changed.connect(_on_purchased_changed)
	MetaProgress.stats_changed.connect(_refresh)

func open() -> void:
	visible = true
	get_tree().paused = true
	_build_cards()
	_refresh()

func _on_close() -> void:
	# NOTE: don't touch `get_tree().paused` here — the host screen
	# (GameOver) decides whether the game stays paused. We just hide.
	visible = false
	closed.emit()

func _build_cards() -> void:
	# Remove old cards (if any).
	for c in _cards:
		if is_instance_valid(c):
			c.queue_free()
	_cards.clear()
	var items: Array = MetaProgress.get_shop_items()
	for item in items:
		var btn: Button = Button.new()
		btn.custom_minimum_size = Vector2(180, 220)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		btn.disabled = true
		btn.focus_mode = Control.FOCUS_NONE
		# Disable the autofit text shrinking so the description stays readable.
		btn.clip_text = true
		btn.text = "%s\n\n%s\n\n%d 废金属" % [item.name, item.description, item.cost]
		# Use a simple monospace-ish alignment.
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# Tag the card with item id via metadata.
		btn.set_meta("item_id", item.id)
		btn.pressed.connect(_on_card_pressed.bind(item.id))
		card_row.add_child(btn)
		_cards.append(btn)

## 挂在 MetaProgress.currency_changed（带 1 个参数）上，自己用不到那个参数。
func _refresh(_amount: int = 0) -> void:
	if not is_inside_tree():
		return
	currency_label.text = "废金属: %d" % MetaProgress.currency
	title_label.text = "模块商店"
	for btn in _cards:
		if not is_instance_valid(btn):
			continue
		var id: String = btn.get_meta("item_id", "")
		var owned: bool = MetaProgress.has(id)
		btn.disabled = owned or not MetaProgress.can_afford(id)
		if owned:
			btn.text = btn.text.split("\n\n")[0] + "\n\n已拥有\n\n— 废金属 —"
		else:
			var items: Array = MetaProgress.get_shop_items()
			for it in items:
				if it.id == id:
					btn.text = "%s\n\n%s\n\n%d 废金属" % [it.name, it.description, it.cost]
					break

func _on_purchased_changed(_id: String, _now: bool) -> void:
	_refresh()

func _on_card_pressed(id: String) -> void:
	if MetaProgress.buy(id):
		purchased.emit(id)
		_refresh()
