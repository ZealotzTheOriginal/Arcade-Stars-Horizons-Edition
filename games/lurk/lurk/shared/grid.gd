extends RefCounted
## Rejilla espacial (hash por celdas) para no comparar todo con todo: cada elemento se inserta en la
## celda de su centro; `query` devuelve los de las 3×3 celdas vecinas. El tamaño de celda debe ser
## mayor que el diámetro de interacción más grande.

var cell: float
var _cells: Dictionary = {}    # Vector2i -> PackedInt32Array de índices

func _init(cell_size: float) -> void:
	cell = cell_size

func clear() -> void:
	_cells.clear()

func key(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / cell), floori(pos.y / cell))

func insert(pos: Vector2, index: int) -> void:
	var k := key(pos)
	if not _cells.has(k):
		_cells[k] = PackedInt32Array()
	_cells[k].append(index)

func query(pos: Vector2) -> PackedInt32Array:
	var k := key(pos)
	var out := PackedInt32Array()
	for y in range(k.y - 1, k.y + 2):
		for x in range(k.x - 1, k.x + 2):
			var c: Variant = _cells.get(Vector2i(x, y))
			if c != null:
				out.append_array(c)
	return out

## Índices en las celdas que toca el círculo (pos, radius); radios grandes recorren más celdas.
func query_radius(pos: Vector2, radius: float) -> PackedInt32Array:
	var a := key(pos - Vector2(radius, radius))
	var b := key(pos + Vector2(radius, radius))
	var out := PackedInt32Array()
	for y in range(a.y, b.y + 1):
		for x in range(a.x, b.x + 1):
			var c: Variant = _cells.get(Vector2i(x, y))
			if c != null:
				out.append_array(c)
	return out
