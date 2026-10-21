extends Control
## Hub principal: presencia online, lista de salas y sala actual.

const ROOM_NAMES := [
	"Orion Nebula", "Pleiades Cluster", "Vega Horizon", "Sirius Orbit",
	"Kuiper Belt", "Aurora Borealis", "Red Pulsar", "Andromeda",
]
const ROOM_NAME_PATTERN := "^[A-Za-z0-9_\\- ]{3,24}$"
const ERROR_COLOR := Color("#FF7A8A")

var _users_box: VBoxContainer
var _rooms_box: VBoxContainer
var _rooms_empty: Label
var _lobby_view: Control
var _room_view: Control
var _room_title: Label
var _room_players: VBoxContainer
var _game_select: OptionButton
var _settings_box: VBoxContainer
var _start_btn: Button
var _create_btn: Button
var _status: Label
var _room_name_input: LineEdit
var _name_input: LineEdit

func _ready() -> void:
	theme = AppTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	Lobby.users_changed.connect(_refresh_users)
	Lobby.rooms_changed.connect(_refresh_rooms)
	Net.players_changed.connect(_refresh_room)
	Net.room_changed.connect(_refresh_room)
	Net.connected_to_room.connect(_show_view)
	Net.left_room.connect(_on_left_room)
	Net.server_error.connect(func(m): _set_status(m, true))
	Backend.status_changed.connect(_on_backend_status)
	_show_view()
	_refresh_users()
	_refresh_rooms()
	_refresh_room()
	_on_backend_status()
	if Net.last_leave_reason != "":
		_set_status(Net.last_leave_reason, true)
	Backend.start()

# ── Construcción de UI ───────────────────────────────────

func _build() -> void:
	add_child(StarField.new())
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 20)
	margin.add_child(root)
	root.add_child(_build_header())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 20)
	root.add_child(body)
	body.add_child(_build_users_panel())

	var center := Control.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(center)
	_lobby_view = _build_lobby_view()
	_room_view = _build_room_view()
	for v in [_lobby_view, _room_view]:
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		center.add_child(v)

func _build_header() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.add_child(StarIcon.new())
	var title := Label.new()
	title.theme_type_variation = "HeadLabel"
	title.text = "ARCADE STARS"
	h.add_child(title)
	var sub := Label.new()
	sub.text = "Horizons Edition"
	sub.add_theme_color_override("font_color", Palette.ACC_GREEN)
	sub.size_flags_vertical = Control.SIZE_SHRINK_END
	h.add_child(sub)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	_status = Label.new()
	_status.theme_type_variation = "MutedLabel"
	h.add_child(_status)
	_name_input = LineEdit.new()
	_name_input.text = Net.local_name
	_name_input.custom_minimum_size.x = 180
	_name_input.max_length = 16
	_name_input.placeholder_text = "Nickname"
	_name_input.text_submitted.connect(_apply_name)
	_name_input.focus_exited.connect(func(): _apply_name(_name_input.text))
	h.add_child(_name_input)
	return h

func _build_users_panel() -> Control:
	var p := PanelContainer.new()
	p.theme_type_variation = "GlassPanel"
	p.custom_minimum_size.x = 260
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var t := Label.new()
	t.theme_type_variation = "MutedLabel"
	t.text = "ONLINE"
	v.add_child(t)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_users_box = VBoxContainer.new()
	_users_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_users_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_users_box)
	return p

func _build_lobby_view() -> Control:
	var p := PanelContainer.new()
	p.theme_type_variation = "GlassPanel"
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	v.add_child(top)
	var t := Label.new()
	t.theme_type_variation = "HeadLabel"
	t.text = "Rooms"
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(t)
	_room_name_input = LineEdit.new()
	_room_name_input.text = ROOM_NAMES.pick_random()
	_room_name_input.max_length = 24
	_room_name_input.placeholder_text = "Room name"
	_room_name_input.custom_minimum_size.x = 220
	_room_name_input.text_submitted.connect(func(_t): _on_create_pressed())
	top.add_child(_room_name_input)
	_create_btn = Button.new()
	_create_btn.theme_type_variation = "PrimaryButton"
	_create_btn.text = "Create room"
	_create_btn.pressed.connect(_on_create_pressed)
	top.add_child(_create_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)
	_rooms_empty = Label.new()
	_rooms_empty.theme_type_variation = "MutedLabel"
	_rooms_empty.text = "No rooms yet"
	inner.add_child(_rooms_empty)
	_rooms_box = VBoxContainer.new()
	_rooms_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rooms_box.add_theme_constant_override("separation", 8)
	inner.add_child(_rooms_box)
	return p

func _build_room_view() -> Control:
	var p := PanelContainer.new()
	p.theme_type_variation = "GlassPanel"
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)

	var top := HBoxContainer.new()
	v.add_child(top)
	_room_title = Label.new()
	_room_title.theme_type_variation = "HeadLabel"
	_room_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_room_title)
	var leave := Button.new()
	leave.text = "Leave room"
	leave.pressed.connect(func(): Net.leave())
	top.add_child(leave)

	var gl := Label.new()
	gl.theme_type_variation = "MutedLabel"
	gl.text = "GAME"
	v.add_child(gl)
	_game_select = OptionButton.new()
	for id in GameRegistry.GAMES:
		_game_select.add_item(GameRegistry.game_name(id))
		_game_select.set_item_metadata(_game_select.item_count - 1, id)
	_game_select.item_selected.connect(func(i): Net.set_room_game(_game_select.get_item_metadata(i)))
	v.add_child(_game_select)

	_settings_box = VBoxContainer.new()
	_settings_box.add_theme_constant_override("separation", 6)
	v.add_child(_settings_box)

	var pl := Label.new()
	pl.theme_type_variation = "MutedLabel"
	pl.text = "PLAYERS"
	v.add_child(pl)
	_room_players = VBoxContainer.new()
	_room_players.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_room_players.add_theme_constant_override("separation", 8)
	v.add_child(_room_players)

	_start_btn = Button.new()
	_start_btn.theme_type_variation = "PrimaryButton"
	_start_btn.text = "Start game"
	_start_btn.pressed.connect(func(): Net.start_game())
	v.add_child(_start_btn)
	return p

# ── Refrescos ────────────────────────────────────────────

func _show_view() -> void:
	_lobby_view.visible = not Net.in_room
	_room_view.visible = Net.in_room
	_refresh_room()

func _on_backend_status() -> void:
	var online := Backend.is_online()
	_create_btn.disabled = not online
	_set_status("" if online else Backend.status_text, not online and Backend.state == Backend.State.OFFLINE and Backend.status_text != "")
	_name_input.text = Net.local_name
	_refresh_rooms()
	_refresh_users()

func _refresh_users() -> void:
	for c in _users_box.get_children():
		c.queue_free()
	for id in Lobby.users:
		var u: Dictionary = Lobby.users[id]
		var is_me: bool = id == Net.my_id()
		_users_box.add_child(_user_row(u["name"] + (" (you)" if is_me else ""), Palette.ACC_GREEN if is_me else Palette.ACC_BLUE, u["room_name"]))

func _user_row(uname: String, dot: Color, room_name: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var d := ColorRect.new()
	d.color = dot
	d.custom_minimum_size = Vector2(8, 8)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(d)
	var l := Label.new()
	l.text = uname
	l.clip_text = true
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	if room_name != "":
		var r := Label.new()
		r.theme_type_variation = "MutedLabel"
		r.text = "● " + room_name
		r.clip_text = true
		r.custom_minimum_size.x = 100
		row.add_child(r)
	return row

func _refresh_rooms() -> void:
	for c in _rooms_box.get_children():
		c.queue_free()
	_rooms_empty.visible = Lobby.rooms.is_empty()
	for r in Lobby.rooms:
		_rooms_box.add_child(_room_card(r))

func _room_card(r: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = "CardPanel"
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	card.add_child(h)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(info)
	var n := Label.new()
	n.theme_type_variation = "HeadLabel"
	n.add_theme_font_size_override("font_size", 20)
	n.text = r["name"]
	info.add_child(n)
	var d := Label.new()
	d.theme_type_variation = "MutedLabel"
	d.text = "%s · host %s · %d/%d%s" % [GameRegistry.game_name(r["game_id"]), r["host_name"], r["players"], r["max"], " · in game" if r["in_game"] else ""]
	info.add_child(d)
	var b := Button.new()
	b.text = "Join"
	b.disabled = r["in_game"] or r["players"] >= r["max"] or not Backend.is_online()
	b.pressed.connect(func(): Net.join_room(r["id"]))
	h.add_child(b)
	return card

func _refresh_room() -> void:
	if not Net.in_room:
		return
	_room_title.text = Net.room.get("name", "Room")
	var idx := 0
	for i in _game_select.item_count:
		if _game_select.get_item_metadata(i) == Net.room.get("game_id"):
			idx = i
	_game_select.select(idx)
	_game_select.disabled = not Net.is_host()
	_refresh_settings()
	for c in _room_players.get_children():
		c.queue_free()
	for id in Net.players:
		_room_players.add_child(_player_card(id))
	var info: Dictionary = GameRegistry.GAMES.get(Net.room.get("game_id", ""), {})
	_start_btn.visible = Net.is_host()
	_start_btn.disabled = Net.players.size() < info.get("min_players", 1)

func _refresh_settings() -> void:
	for c in _settings_box.get_children():
		c.queue_free()
	var schema: Array = GameRegistry.GAMES.get(Net.room.get("game_id", ""), {}).get("settings", [])
	var current: Dictionary = Net.room.get("settings", {})
	for s in schema:
		var l := Label.new()
		l.theme_type_variation = "MutedLabel"
		l.text = s["label"]
		_settings_box.add_child(l)
		var ob := OptionButton.new()
		var selected := 0
		for i in s["options"].size():
			ob.add_item(s["options"][i][1])
			ob.set_item_metadata(i, s["options"][i][0])
			if s["options"][i][0] == current.get(s["key"], s["default"]):
				selected = i
		ob.select(selected)
		ob.disabled = not Net.is_host()
		var key: String = s["key"]
		ob.item_selected.connect(func(i): Net.set_room_setting(key, ob.get_item_metadata(i)))
		_settings_box.add_child(ob)

func _player_card(id: int) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = "CardPanel"
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	card.add_child(h)
	var dot := ColorRect.new()
	dot.color = Net.player_color(id)
	dot.custom_minimum_size = Vector2(12, 12)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(dot)
	var l := Label.new()
	l.text = Net.player_name(id) + ("  (you)" if id == Net.my_id() else "")
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	if id == Net.room.get("host_id"):
		var tag := Label.new()
		tag.theme_type_variation = "MutedLabel"
		tag.text = "HOST"
		h.add_child(tag)
	return card

# ── Acciones ─────────────────────────────────────────────

func _apply_name(new_name: String) -> void:
	new_name = new_name.strip_edges()
	if new_name == Net.local_name or Net.in_room:
		_name_input.text = Net.local_name
		return
	if not Net.is_valid_nickname(new_name):
		_set_status("Nickname: 3-16 letters, numbers, spaces, - or _", true)
		_name_input.text = Net.local_name
		return
	Net.local_name = new_name
	if Backend.is_online():
		Net.set_nickname(new_name)

func _on_create_pressed() -> void:
	var rname := _room_name_input.text.strip_edges()
	if RegEx.create_from_string(ROOM_NAME_PATTERN).search(rname) == null:
		_set_status("Room name: 3-24 letters, numbers, spaces, - or _", true)
		return
	_set_status("")
	Net.create_room(rname, GameRegistry.GAMES.keys()[0])

func _on_left_room(reason: String) -> void:
	_set_status(reason, reason != "")
	_room_name_input.text = ROOM_NAMES.pick_random()
	_show_view()

func _set_status(text: String, error: bool = false) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", ERROR_COLOR if error else Palette.fade(Palette.FG_200, 0.55))
