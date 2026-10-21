class_name Palette
## Paleta de Clustark (frontend/clustark/src/styles/_colors.scss).

const VOID := Color("#03030E")
const BLACK := Color("#000000")

const BG_100 := Color("#0E0E1E")
const BG_200 := Color("#131324")
const BG_300 := Color("#191A2D")
const BG_400 := Color("#202237")

const ACC_GREEN := Color("#86F730")   # --acc-100
const ACC_BLUE := Color("#A6C8FF")    # --acc-200
const ACC_PINK := Color("#ECB2FF")    # --acc-300

const FG_100 := Color("#FFFFFF")
const FG_200 := Color("#E1E0FB")

## Equivalente a color-mix(in srgb, c, transparent N%).
static func fade(c: Color, alpha: float) -> Color:
	return Color(c.r, c.g, c.b, alpha)
