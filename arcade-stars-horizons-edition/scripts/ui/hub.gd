extends Control
## Hub principal: presencia online, lista de parties (salas) y party actual.

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
var _rename_btn: Button
var _rename_input: LineEdit
var _library_view: Control
var _settings_view: Control
var _tab_buttons: Dictionary = {}    # nombre de pestaña -> Button
var _tab := "party"
var _users_panel: Control
var _sidebar_toggle: SidebarToggle

func _ready() -> void:
	theme = AppTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	Lobby.users_changed.connect(_refresh_users)
	Lobby.rooms_changed.connect(_refresh_rooms)
	Net.players_changed.connect(_refresh_room)
	Net.room_changed.connect(_refresh_room)
	Net.connected_to_room.connect(_on_joined_party)
	Net.left_room.connect(_on_left_room)
	Net.server_error.connect(func(m): _set_status(m, true))
	Backend.status_changed.connect(_on_backend_status)
	GameLoader.installed_changed.connect(_on_installed_changed)
	Backend.catalog_changed.connect(_on_catalog_changed)
	_show_view()
	_refresh_users()
	_refresh_rooms()
	_refresh_room()
	_on_backend_status()
	if Engine.has_meta("fade_in_hub"):
		Engine.remove_meta("fade_in_hub")
		modulate.a = 0.0    # lo muestra fade_in() cuando la ventana ya tiene su tamaño final
	if Net.last_leave_reason != "":
		_set_status(Net.last_leave_reason, true)
	Backend.start()

func _load_sidebar_shown() -> bool:
	var cfg := ConfigFile.new()
	return cfg.load("user://ui.cfg") != OK or cfg.get_value("ui", "sidebar_shown", true)

func _on_sidebar_toggled(shown: bool) -> void:
	_users_panel.visible = shown
	var cfg := ConfigFile.new()
	cfg.load("user://ui.cfg")
	cfg.set_value("ui", "sidebar_shown", shown)
	cfg.save("user://ui.cfg")

func fade_in() -> void:
	create_tween().tween_property(self, "modulate:a", 1.0, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# ── Construcción de UI ───────────────────────────────────

func _build() -> void:
	add_child(StarField.new())
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	margin.add_theme_constant_override("margin_top", WindowChrome.HEIGHT + 14)    # deja sitio a la barra de ventana
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	margin.add_child(root)
	root.add_child(_build_nav())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 20)
	root.add_child(body)
	var center := Control.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(center)
	_users_panel = _build_users_panel()    # barra lateral a la derecha
	_users_panel.visible = _load_sidebar_shown()
	body.add_child(_users_panel)
	_lobby_view = _build_lobby_view()
	_room_view = _build_room_view()
	_library_view = LibraryView.new()
	_settings_view = SettingsView.new()
	for v in [_lobby_view, _room_view, _library_view, _settings_view]:
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		center.add_child(v)
	add_child(UpdatePopup.new())    # flotante, encima del contenido

func _build_nav() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var group := ButtonGroup.new()
	for tab in [["party", "Party"], ["library", "Library"], ["settings", "Settings"]]:
		var b := NavLink.new(tab[1])
		b.button_group = group
		b.button_pressed = tab[0] == _tab
		var key: String = tab[0]
		b.pressed.connect(func():
			_tab = key
			_show_view())
		_tab_buttons[key] = b
		h.add_child(b)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	_status = CapsLabel.new()
	_status.theme_type_variation = "MutedLabel"
	h.add_child(_status)
	_sidebar_toggle = SidebarToggle.new(_load_sidebar_shown())    # al final: la barra lateral está a la derecha
	_sidebar_toggle.toggled.connect(_on_sidebar_toggled)
	h.add_child(_sidebar_toggle)
	return h

func _build_users_panel() -> Control:
	var p := PanelContainer.new()
	p.theme_type_variation = "GlassPanel"
	p.custom_minimum_size.x = 230
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var t := CapsLabel.new()
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
	var t := CapsLabel.new()
	t.theme_type_variation = "HeadLabel"
	t.text = "Party"
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(t)
	_create_btn = AccentButton.new("CREATE PARTY")
	_create_btn.pressed.connect(_on_create_pressed)
	top.add_child(_create_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)
	_rooms_empty = CapsLabel.new()
	_rooms_empty.theme_type_variation = "MutedLabel"
	_rooms_empty.text = "No parties yet"
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
	top.add_theme_constant_override("separation", 10)
	v.add_child(top)
	_room_title = CapsLabel.new()
	_room_title.theme_type_variation = "HeadLabel"
	_room_title.clip_text = true
	_room_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_room_title)
	# Renombrar (solo anfitrión): el título pasa a ser un campo; Enter aplica, Esc o clic fuera cancela.
	_rename_input = LineEdit.new()
	_rename_input.max_length = 24
	_rename_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rename_input.visible = false
	_rename_input.text_submitted.connect(func(_t): _apply_rename())
	_rename_input.focus_exited.connect(_end_rename)
	_rename_input.gui_input.connect(func(e):
		if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
			_end_rename()
			_rename_input.accept_event())
	top.add_child(_rename_input)
	_rename_btn = Button.new()
	_rename_btn.theme_type_variation = "CompactButton"
	_rename_btn.text = "RENAME"
	_rename_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rename_btn.pressed.connect(_begin_rename)
	top.add_child(_rename_btn)
	var leave := Button.new()
	leave.text = "LEAVE PARTY"
	leave.pressed.connect(func(): Net.leave())
	top.add_child(leave)

	var gl := CapsLabel.new()
	gl.theme_type_variation = "MutedLabel"
	gl.text = "GAME"
	v.add_child(gl)
	_game_select = OptionButton.new()
	_fill_game_select()
	_game_select.item_selected.connect(func(i): Net.set_room_game(_game_select.get_item_metadata(i)))
	v.add_child(_game_select)

	_settings_box = VBoxContainer.new()
	_settings_box.add_theme_constant_override("separation", 6)
	v.add_child(_settings_box)

	var pl := CapsLabel.new()
	pl.theme_type_variation = "MutedLabel"
	pl.text = "PLAYERS"
	v.add_child(pl)
	_room_players = VBoxContainer.new()
	_room_players.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_room_players.add_theme_constant_override("separation", 8)
	v.add_child(_room_players)

	_start_btn = AccentButton.new("START GAME")
	_start_btn.pressed.connect(func(): Net.start_game())
	v.add_child(_start_btn)
	return p

# ── Refrescos ────────────────────────────────────────────

func _fill_game_select() -> void:
	_game_select.clear()
	for id in GameRegistry.games:
		var suffix := "" if GameLoader.is_installed(id) else " (not installed)"
		_game_select.add_item((GameRegistry.game_name(id) + suffix).to_upper())
		_game_select.set_item_metadata(_game_select.item_count - 1, id)

## La pestaña PARTY muestra la lista de parties o, si estás en una, esa party. Library y Settings
## siguen disponibles dentro de una party (al empezar la partida se entra al juego igualmente).
func _show_view() -> void:
	_lobby_view.visible = _tab == "party" and not Net.in_room
	_room_view.visible = _tab == "party" and Net.in_room
	_library_view.visible = _tab == "library"
	_settings_view.visible = _tab == "settings"
	_refresh_room()

## Al crear o unirse a una party se muestra su pestaña.
func _on_joined_party() -> void:
	_select_tab("party")

func _select_tab(key: String) -> void:
	_tab = key
	_tab_buttons[key].button_pressed = true
	_show_view()

func _on_backend_status() -> void:
	var online := Backend.is_online()
	_create_btn.disabled = not online or GameRegistry.games.is_empty()
	_set_status("" if online else Backend.status_text, not online and Backend.state == Backend.State.OFFLINE and Backend.status_text != "")
	_refresh_rooms()
	_refresh_users()

func _refresh_users() -> void:
	for c in _users_box.get_children():
		c.queue_free()
	for id in Lobby.users:
		var u: Dictionary = Lobby.users[id]
		var is_me: bool = id == Net.my_id()
		_users_box.add_child(_user_row(u["name"] + (" (you)" if is_me else ""), Palette.ACC_GREEN if is_me else Palette.ACC_BLUE))

func _user_row(uname: String, dot: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var d := ColorRect.new()
	d.color = dot
	d.custom_minimum_size = Vector2(8, 8)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(d)
	var l := CapsLabel.new()
	l.text = uname
	l.clip_text = true
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
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
	var n := CapsLabel.new()
	n.theme_type_variation = "HeadLabel"
	n.add_theme_font_size_override("font_size", 20)
	n.text = r["name"]
	info.add_child(n)
	var d := CapsLabel.new()
	d.theme_type_variation = "MutedLabel"
	d.text = "%s · host %s · %d/%d%s%s" % [GameRegistry.game_name(r["game_id"]), r["host_name"], r["players"], r["max"],
			" · in game" if r["in_game"] else "", "" if GameLoader.is_installed(r["game_id"]) else " · not installed"]
	info.add_child(d)
	var b := Button.new()
	b.text = "JOIN"
	var joinable_in_game: bool = GameRegistry.allows_join_in_progress(r["game_id"]) and GameLoader.is_installed(r["game_id"])
	b.disabled = (r["in_game"] and not joinable_in_game) or r["players"] >= r["max"] or not Backend.is_online()
	b.pressed.connect(func(): Net.join_room(r["id"]))
	h.add_child(b)
	return card

func _refresh_room() -> void:
	if not Net.in_room:
		return
	_room_title.text = Net.room.get("name", "Party")
	_rename_btn.visible = Net.is_host() and not _rename_input.visible
	var idx := 0
	for i in _game_select.item_count:
		if _game_select.get_item_metadata(i) == Net.room.get("game_id"):
			idx = i
	_fill_game_select()
	_game_select.select(idx)
	_game_select.disabled = not Net.is_host()
	_refresh_settings()
	for c in _room_players.get_children():
		c.queue_free()
	for id in Net.players:
		_room_players.add_child(_player_card(id))
	var info: Dictionary = GameRegistry.games.get(Net.room.get("game_id", ""), {})
	_start_btn.visible = Net.is_host()
	var all_ready: bool = Net.players.values().all(func(p): return p.get("ready", false))
	_start_btn.disabled = Net.players.size() < info.get("min_players", 1) or not all_ready

func _refresh_settings() -> void:
	for c in _settings_box.get_children():
		c.queue_free()
	var schema: Array = GameRegistry.games.get(Net.room.get("game_id", ""), {}).get("settings", [])
	var current: Dictionary = Net.room.get("settings", {})
	for s in schema:
		var l := CapsLabel.new()
		l.theme_type_variation = "MutedLabel"
		l.text = s["label"]
		_settings_box.add_child(l)
		var ob := OptionButton.new()
		var selected := 0
		for i in s["options"].size():
			ob.add_item((s["options"][i][1]).to_upper())
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
	var l := CapsLabel.new()
	l.text = Net.player_name(id) + ("  (you)" if id == Net.my_id() else "")
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	if not Net.players[id].get("ready", false):
		var missing := CapsLabel.new()
		missing.theme_type_variation = "MutedLabel"
		missing.text = "MISSING GAME"
		missing.add_theme_color_override("font_color", ERROR_COLOR)
		h.add_child(missing)
	if id == Net.room.get("host_id"):
		var tag := CapsLabel.new()
		tag.theme_type_variation = "MutedLabel"
		tag.text = "HOST"
		h.add_child(tag)
	return card

# ── Acciones ─────────────────────────────────────────────

func _notification(what: int) -> void:
	# Al volver a la ventana se detectan .pck recién copiados a la carpeta de juegos.
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		GameLoader.scan()

func _on_catalog_changed() -> void:
	_create_btn.disabled = not Backend.is_online() or GameRegistry.games.is_empty()
	_fill_game_select()
	_refresh_rooms()
	_refresh_room()

func _on_installed_changed() -> void:
	if Backend.is_online():
		Net.send_installed_games()
	_fill_game_select()
	_refresh_rooms()
	_refresh_room()

func _default_game_id() -> String:
	for id in GameRegistry.games:
		if GameLoader.is_installed(id):
			return id
	return GameRegistry.games.keys()[0]

func _on_create_pressed() -> void:
	if GameRegistry.games.is_empty():
		return
	_set_status("")
	Net.create_party(_default_game_id())

func _begin_rename() -> void:
	_rename_input.text = _room_title.text
	_room_title.visible = false
	_rename_btn.visible = false
	_rename_input.visible = true
	_rename_input.grab_focus()
	_rename_input.select_all()

func _apply_rename() -> void:
	var rname := _rename_input.text.strip_edges()
	if not Net.is_valid_party_name(rname):
		_set_status("Party name: 3-24 letters, numbers, spaces, - or _", true)
		return
	_set_status("")
	if rname != Net.room.get("name", ""):
		Net.rename_room(rname)
	_end_rename()

func _end_rename() -> void:
	if not _rename_input.visible:
		return
	_rename_input.visible = false
	_room_title.visible = true
	_rename_btn.visible = Net.is_host()

func _on_left_room(reason: String) -> void:
	_set_status(reason, reason != "")
	_show_view()

func _set_status(text: String, error: bool = false) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", ERROR_COLOR if error else Palette.fade(Palette.FG_200, 0.55))
