class_name TicTacToeRules
extends RefCounted
## Pure tic-tac-toe rules (no nodes), so they are unit-tested headless.
## Board sizes 3x3, 4x4 and 5x5; a line of `win_length` marks in a row,
## column or diagonal wins (3 on 3x3, 4 on 4x4, 4 on 5x5: see
## win_length_for()).

enum Mark { NONE, X, O }

const SIZES: Array[int] = [3, 4, 5]
## The classic 3x3 lines (kept for reference / older callers).
const LINES: Array = [
	[0, 1, 2], [3, 4, 5], [6, 7, 8],
	[0, 3, 6], [1, 4, 7], [2, 5, 8],
	[0, 4, 8], [2, 4, 6],
]

var size: int = 3
var win_length: int = 3
## Every winning line for this size / win length (arrays of cell indices,
## in order along the line).
var lines: Array = []
var cells: Array[int] = []
var turn: int = Mark.X
var winner: int = Mark.NONE
var winning_line: Array = []


func _init(p_size: int = 3, p_win_length: int = -1) -> void:
	configure(p_size, p_win_length)


## Win length used for a board size: the whole row on 3x3 and 4x4; four in
## a row on 5x5 (five in a row on 5x5 is almost always a draw between two
## careful players, three in a row on 4x4 / 5x5 is a quick first-player win).
static func win_length_for(p_size: int) -> int:
	return 3 if p_size <= 3 else 4


## Change the board size (and win length; -1 = win_length_for(size)) and
## start a fresh round.
func configure(p_size: int, p_win_length: int = -1) -> void:
	size = clampi(p_size, 3, 5)
	win_length = clampi(p_win_length if p_win_length > 0 else win_length_for(size), 3, size)
	lines = all_lines(size, win_length)
	reset()


## All runs of `length` cells in rows, columns and both diagonals.
static func all_lines(p_size: int, length: int) -> Array:
	var out: Array = []
	var steps: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1)]
	for step: Vector2i in steps:
		for row: int in p_size:
			for col: int in p_size:
				var end_col: int = col + step.x * (length - 1)
				var end_row: int = row + step.y * (length - 1)
				if end_col < 0 or end_col >= p_size or end_row < 0 or end_row >= p_size:
					continue
				var line: Array = []
				for k: int in length:
					line.append((row + step.y * k) * p_size + col + step.x * k)
				out.append(line)
	return out


func cell_count() -> int:
	return size * size


func reset() -> void:
	cells.clear()
	cells.resize(size * size)
	cells.fill(Mark.NONE)
	turn = Mark.X
	winner = Mark.NONE
	winning_line = []


func is_empty() -> bool:
	return not cells.has(Mark.X) and not cells.has(Mark.O)


func is_over() -> bool:
	return winner != Mark.NONE or is_draw()


func is_draw() -> bool:
	return winner == Mark.NONE and not cells.has(Mark.NONE)


## Place the current player's mark. Returns false if the move is illegal.
func play(index: int) -> bool:
	if index < 0 or index >= cells.size() or is_over() or cells[index] != Mark.NONE:
		return false
	cells[index] = turn
	for line: Array in lines:
		if not line.has(index):
			continue
		var complete: bool = true
		for cell: Variant in line:
			if cells[int(cell)] != turn:
				complete = false
				break
		if complete:
			winner = turn
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
