extends Control
## Tienda de gemas (Tab por defecto). La partida sigue mientras está abierta: puedes moverte, pero los
## clics van a la tienda. Cada power-up con su icono, nombre y precio; no se puede comprar lo que no
## alcanza o lo que ya no te serviría (permanentes que ya tienes, vida llena, armadura al máximo).

signal buy_requested(kind: int)
signal clicked

const Style = preload("style.gd")
const Art = preload("res://lurk/render/powerup_art.gd")
const PU = preload("res://lurk/shared/powerups.gd")
const Config = preload("res://lurk/shared/config.gd")
const GEM_COLOR := Color("#5EEAD4")
const TIERS := [
	["Health", [PU.Kind.REPAIR]],
	["Normal", [PU.Kind.VISOR, PU.Kind.RADAR, PU.Kind.SHIELD, PU.Kind.ARMOR, PU.Kind.SPECTRE, PU.Kind.PSIONIC]],
	["Strong", [PU.Kind.REDEEMER, PU.Kind.HEAVY, PU.Kind.EXPLOSIVE]],
	["Reactor", [PU.Kind.OVERLOAD]],
]

var gems := 0
var _useless: Dictionary = {}       # tipo -> true si ya no te serviría
var _buttons: Dictionary = {}       # tipo -> Button
var _gem_label: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = Style.build_theme()
	var anchor := MarginContainer.new()
	anchor.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	anchor.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	anchor.grow_vertical = Control.GROW_DIRECTION_BOTH
	anchor.add_theme_constant_override("margin_right", 26)
	add_child(anchor)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 330
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	anchor.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var title := Label.new()
	title.theme_type_variation = "HeadLabel"
	title.add_theme_font_size_override("font_size", 20)
	title.uppercase = true
	title.text = "Shop"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	_gem_label = Label.new()
	_gem_label.add_theme_color_override("font_color", GEM_COLOR)
	_gem_label.add_theme_font_override("font", Style.font(700))
	top.add_child(_gem_label)
	for tier in TIERS:
		var h := Label.new()
		h.theme_type_variation = "MutedLabel"
		h.uppercase = true
		h.text = tier[0]
		v.add_child(h)
		for kind in tier[1]:
			v.add_child(_row(kind))
	refresh()

func _row(kind: int) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(30, 30)
	icon.draw.connect(func(): Art.icon(icon, kind, icon.size / 2.0, 12.0))
	h.add_child(icon)
	var name := Label.new()
	name.uppercase = true
	name.text = PU.NAMES[kind]
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.add_theme_font_size_override("font_size", 13)
	h.add_child(name)
	var b := Button.new()
	b.custom_minimum_size = Vector2(64, 30)
	b.text = str(Config.SHOP_PRICES[kind])
	b.add_theme_color_override("font_color", GEM_COLOR)
	b.pressed.connect(func():
		clicked.emit()
		buy_requested.emit(kind))
	h.add_child(b)
	_buttons[kind] = b
	return h

## `useless`: tipos que ahora mismo no te servirían.
func set_state(gem_count: int, useless: Dictionary) -> void:
	if gem_count == gems and useless == _useless:
		return
	gems = gem_count
	_useless = useless
	refresh()

func refresh() -> void:
	if _gem_label == null:
		return
	_gem_label.text = "%d GEMS" % gems
	for kind in _buttons:
		var b: Button = _buttons[kind]
		b.disabled = gems < Config.SHOP_PRICES[kind] or _useless.has(kind)
		b.modulate.a = 0.45 if b.disabled else 1.0
