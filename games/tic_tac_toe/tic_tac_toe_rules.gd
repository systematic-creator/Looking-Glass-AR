class_name TicTacToeRules
extends RefCounted
## Pure tic-tac-toe rules (no nodes), so they are unit-tested headless.

enum Mark { NONE, X, O }

const LINES: Array = [
	[0, 1, 2], [3, 4, 5], [6, 7, 8],
	[0, 3, 6], [1, 4, 7], [2, 5, 8],
	[0, 4, 8], [2, 4, 6],
]

var cells: Array[int] = []
var turn: int = Mark.X
var winner: int = Mark.NONE
var winning_line: Array = []


func _init() -> void:
	reset()


func reset() -> void:
	cells.clear()
	cells.resize(9)
	cells.fill(Mark.NONE)
	turn = Mark.X
	winner = Mark.NONE
	winning_line = []


func is_over() -> bool:
	return winner != Mark.NONE or is_draw()


func is_draw() -> bool:
	return winner == Mark.NONE and not cells.has(Mark.NONE)


## Place the current player's mark. Returns false if the move is illegal.
func play(index: int) -> bool:
	if index < 0 or index >= 9 or is_over() or cells[index] != Mark.NONE:
		return false
	cells[index] = turn
	for line: Array in LINES:
		var a: int = cells[int(line[0])]
		if a != Mark.NONE and a == cells[int(line[1])] and a == cells[int(line[2])]:
			winner = a
			winning_line = line
			break
	if not is_over():
		turn = Mark.O if turn == Mark.X else Mark.X
	return true


static func mark_name(mark: int) -> String:
	match mark:
		Mark.X:
			return "X"
		Mark.O:
			return "O"
		_:
			return "-"
