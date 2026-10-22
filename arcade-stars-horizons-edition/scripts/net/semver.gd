class_name Semver
## Comparación de versiones "major.minor.patch".

const PATTERN := "^\\d{1,4}\\.\\d{1,4}\\.\\d{1,4}$"

static func is_valid(v: String) -> bool:
	return RegEx.create_from_string(PATTERN).search(v) != null

## -1 si a < b, 0 si iguales, 1 si a > b. Una versión inválida cuenta como 0.0.0.
static func compare(a: String, b: String) -> int:
	var pa := _parts(a)
	var pb := _parts(b)
	for i in 3:
		if pa[i] != pb[i]:
			return -1 if pa[i] < pb[i] else 1
	return 0

static func _parts(v: String) -> Array[int]:
	var out: Array[int] = [0, 0, 0]
	if is_valid(v):
		var s := v.split(".")
		for i in 3:
			out[i] = int(s[i])
	return out
