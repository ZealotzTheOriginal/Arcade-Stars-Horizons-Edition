extends RefCounted
## Reglas del Buscaminas competitivo por turnos (port de backend/app/games/minesweeper).
## Solo lo instancia el servidor; los clientes reciben `view()`.

const POINTS_PER_CELL := 5
const POINTS_WIN_BONUS := 50
## id -> Vector3i(columnas, filas, minas)
const SIZES := {
	"normal": Vector3i(9, 9, 10),
	"intermediate": Vector3i(16, 16, 40),
	"expert": Vector3i(30, 16, 99),
}

const HIDDEN := -2
const MINE_EXPLODED := -1
const MINE_UNSEEN := -3

var cols: int
var rows: int
var mines: int
var board := PackedInt32Array()      # -1 = mina, 0..8 = vecinas; vacío hasta la 1ª jugada
var revealed := PackedByteArray()
var flags := PackedInt32Array()      # peer_id que puso la bandera, 0 = ninguna
var order: Array[int] = []
var turn_idx := 0
var scores: Dictionary = {}
var over := false
var winner := 0
var exploded_by := 0
var exploded_cell := -1
var reason := ""                     # "mine" | "cleared" | "alone"

func _init(settings: Dictionary, peer_ids: Array) -> void:
	var s: Vector3i = SIZES.get(settings.get("board_size", "normal"), SIZES["normal"])
	cols = s.x
	rows = s.y
	mines = s.z
	revealed.resize(cols * rows)
	flags.resize(cols * rows)
	for id in peer_ids:
		order.append(int(id))
		scores[int(id)] = 0
	order.sort()

## Interfaz común de módulos de juego del servidor.
func handle_action(pid: int, payload: Dictionary) -> bool:
	var row: Variant = payload.get("row")
	var col: Variant = payload.get("col")
	if not (row is int and col is int):
		return false
	return toggle_flag(pid, row, col) if payload.get("flag", false) == true else reveal(pid, row, col)

func is_over() -> bool:
	return over

## Resultado para estadísticas. Vacío si la partida no cuenta (rivales desconectados).
func results() -> Array:
	if reason == "alone":
		return []
	return order.map(func(id): return {"pid": id, "score": scores[id], "is_winner": id == winner})

func current_player() -> int:
	return order[turn_idx % order.size()] if not order.is_empty() else 0

## Devuelve true si el estado cambió.
func reveal(pid: int, row: int, col: int) -> bool:
	if over or pid != current_player() or not _in_bounds(row, col):
		return false
	var i := row * cols + col
	if revealed[i] or flags[i] != 0:
		return false
	if board.is_empty():
		_generate(row, col)
	if board[i] == -1:
		revealed[i] = 1
		exploded_by = pid
		exploded_cell = i
		_finish("mine", _best_other(pid))
		return true
	var gained := _flood(row, col)
	scores[pid] += gained * POINTS_PER_CELL
	if _revealed_safe() >= cols * rows - mines:
		_finish("cleared", _best_score())
	else:
		_next_turn()
	return true

func toggle_flag(pid: int, row: int, col: int) -> bool:
	if over or pid != current_player() or not _in_bounds(row, col):
		return false
	var i := row * cols + col
	if revealed[i]:
		return false
	flags[i] = 0 if flags[i] != 0 else pid
	return true

## Un jugador se desconectó: lo saca del orden y reajusta el turno.
func remove_player(pid: int) -> void:
	var idx := order.find(pid)
	if idx == -1 or over:
		return
	var was_turn := current_player() == pid
	order.remove_at(idx)
	scores.erase(pid)
	if order.size() < 2:
		_finish("alone", order[0] if order.size() == 1 else 0)
		return
	if idx < turn_idx:
		turn_idx -= 1
	if was_turn:
		turn_idx %= order.size()

func view() -> Dictionary:
	var cells := PackedInt32Array()
	cells.resize(cols * rows)
	for i in cells.size():
		if revealed[i]:
			cells[i] = MINE_EXPLODED if board[i] == -1 else board[i]
		elif over and not board.is_empty() and board[i] == -1:
			cells[i] = MINE_UNSEEN
		else:
			cells[i] = HIDDEN
	return {
		"cols": cols, "rows": rows, "mines": mines,
		"cells": cells, "flags": flags,
		"order": order, "turn": current_player(), "scores": scores,
		"over": over, "winner": winner, "exploded_by": exploded_by,
		"exploded_cell": exploded_cell, "reason": reason,
		"flags_left": mines - _count_flags(),
	}

# ── interno ──────────────────────────────────────────────

func _in_bounds(r: int, c: int) -> bool:
	return r >= 0 and r < rows and c >= 0 and c < cols

func _next_turn() -> void:
	turn_idx = (turn_idx + 1) % order.size()

func _finish(why: String, win_id: int) -> void:
	over = true
	reason = why
	winner = win_id
	if scores.has(win_id):
		scores[win_id] += POINTS_WIN_BONUS

func _best_other(pid: int) -> int:
	var best := 0
	var best_score := -1
	for id in order:
		if id != pid and scores[id] > best_score:
			best = id
			best_score = scores[id]
	return best

func _best_score() -> int:
	var best := 0
	var best_score := -1
	for id in order:
		if scores[id] > best_score:
			best = id
			best_score = scores[id]
	return best

func _count_flags() -> int:
	var n := 0
	for f in flags:
		if f != 0:
			n += 1
	return n

func _revealed_safe() -> int:
	var n := 0
	for i in revealed.size():
		if revealed[i] and board[i] != -1:
			n += 1
	return n

func _generate(safe_row: int, safe_col: int) -> void:
	board.resize(cols * rows)
	board.fill(0)
	var candidates: Array[int] = []
	for r in rows:
		for c in cols:
			if absi(r - safe_row) > 1 or absi(c - safe_col) > 1:
				candidates.append(r * cols + c)
	candidates.shuffle()
	for k in mini(mines, candidates.size()):
		board[candidates[k]] = -1
	for r in rows:
		for c in cols:
			var i := r * cols + c
			if board[i] == -1:
				continue
			var n := 0
			for dr in range(-1, 2):
				for dc in range(-1, 2):
					if (dr != 0 or dc != 0) and _in_bounds(r + dr, c + dc) and board[(r + dr) * cols + c + dc] == -1:
						n += 1
			board[i] = n

func _flood(row: int, col: int) -> int:
	var stack: Array[Vector2i] = [Vector2i(col, row)]
	var count := 0
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		if not _in_bounds(p.y, p.x):
			continue
		var i := p.y * cols + p.x
		if revealed[i] or board[i] == -1:
			continue
		revealed[i] = 1
		flags[i] = 0
		count += 1
		if board[i] == 0:
			for dr in range(-1, 2):
				for dc in range(-1, 2):
					if dr != 0 or dc != 0:
						stack.append(Vector2i(p.x + dc, p.y + dr))
	return count
