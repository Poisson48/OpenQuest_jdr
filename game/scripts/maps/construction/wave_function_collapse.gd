extends RefCounted
class_name WaveFunctionCollapse

## Wave Function Collapse — Even Simpler Tiled Model (ESTM).
##
## Chaque case possède un masque de tuiles encore possibles. On collapse la
## case de plus faible entropie (Shannon, pondérée par la fréquence des tuiles),
## puis on propage les contraintes aux 4 voisins jusqu'à stabilité. En cas de
## contradiction, on relance avec une nouvelle graine.
##
## API volontairement simple :
##   var wfc := WaveFunctionCollapse.new()
##   wfc.configure(weights, adjacency, seed)
##   var grid := wfc.generate(width, height, fixed_cells)

const DIRECTIONS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var _weights: Array[float] = []
var _neighbor_masks: Array = [] # [4][tile] -> masque de voisins autorisés
var _rng := RandomNumberGenerator.new()
var _width: int = 0
var _height: int = 0
var _allowed: Array[int] = []
var _fixed: Dictionary = {}
var _seed: int = 1
var last_attempts: int = 0

## `adjacency[direction][tile]` = liste des tuiles autorisées dans cette direction.
func configure(weights: Array, adjacency: Array, seed: int = 1) -> void:
	_weights.clear()
	for w in weights:
		_weights.append(maxf(0.0001, float(w)))
	_seed = seed
	_rng.seed = seed
	_neighbor_masks.clear()
	for d in range(DIRECTIONS.size()):
		var dir_masks: Array[int] = []
		dir_masks.resize(_weights.size())
		var dir_rules: Array = adjacency[d] if d < adjacency.size() else []
		for t in range(_weights.size()):
			var mask := 0
			var allowed: Array = dir_rules[t] if t < dir_rules.size() else []
			for n in allowed:
				var ni := int(n)
				if ni >= 0 and ni < _weights.size():
					mask |= (1 << ni)
			dir_masks[t] = mask
		_neighbor_masks.append(dir_masks)

func generate(width: int, height: int, fixed_cells: Dictionary = {},
		max_attempts: int = 12) -> Array:
	last_attempts = 0
	if _weights.is_empty() or width <= 0 or height <= 0:
		return []
	for attempt in range(max_attempts):
		last_attempts = attempt + 1
		_rng.seed = _seed + attempt * 104729
		_width = width
		_height = height
		_fixed = fixed_cells
		if _init_wave():
			if _solve():
				return _result_grid()
	return []

func _init_wave() -> bool:
	var full_mask := (1 << _weights.size()) - 1
	_allowed.resize(_width * _height)
	_allowed.fill(full_mask)
	for key in _fixed.keys():
		var idx := int(key)
		if idx < 0 or idx >= _allowed.size():
			continue
		var tile := int(_fixed[key])
		if tile < 0 or tile >= _weights.size():
			return false
		var bit := 1 << tile
		if (_allowed[idx] & bit) == 0:
			return false
		_allowed[idx] = bit
		if not _propagate(idx):
			return false
	return true

func _solve() -> bool:
	while true:
		var idx := _lowest_entropy_cell()
		if idx < 0:
			return true
		var mask := _allowed[idx]
		if mask == 0:
			return false
		if _popcount(mask) <= 1:
			# Déjà résolu (le choix de plus faible entropie évite ce cas).
			continue
		var tile := _weighted_tile(mask)
		_allowed[idx] = 1 << tile
		if not _propagate(idx):
			return false
	return false

func _lowest_entropy_cell() -> int:
	var best: Array[int] = []
	var best_entropy := INF
	for idx in range(_allowed.size()):
		var mask := _allowed[idx]
		var count := _popcount(mask)
		if count <= 1:
			continue
		var entropy := _entropy(mask)
		if entropy < best_entropy - 0.0001:
			best_entropy = entropy
			best.clear()
			best.append(idx)
		elif absf(entropy - best_entropy) <= 0.0001:
			best.append(idx)
	if best.is_empty():
		return -1
	return best[_rng.randi() % best.size()]

func _entropy(mask: int) -> float:
	var sum_w := 0.0
	var sum_w_log_w := 0.0
	for t in range(_weights.size()):
		if mask & (1 << t):
			var w := _weights[t]
			sum_w += w
			sum_w_log_w += w * log(w)
	if sum_w <= 0.0:
		return INF
	return log(sum_w) - sum_w_log_w / sum_w

func _weighted_tile(mask: int) -> int:
	var total := 0.0
	for t in range(_weights.size()):
		if mask & (1 << t):
			total += _weights[t]
	var pick := _rng.randf() * total
	for t in range(_weights.size()):
		if mask & (1 << t):
			pick -= _weights[t]
			if pick <= 0.0:
				return t
	return 0

func _propagate(start_idx: int) -> bool:
	var queue: Array[int] = [start_idx]
	while not queue.is_empty():
		var idx: int = queue.pop_back()
		var x := idx % _width
		var y := int(idx / _width)
		for d in range(DIRECTIONS.size()):
			var dir: Vector2i = DIRECTIONS[d]
			var nx := x + dir.x
			var ny := y + dir.y
			if nx < 0 or ny < 0 or nx >= _width or ny >= _height:
				continue
			var nidx := ny * _width + nx
			var allowed_neighbor := _neighbor_mask_for(_allowed[idx], d)
			var next_mask := _allowed[nidx] & allowed_neighbor
			if next_mask == 0:
				return false
			if next_mask != _allowed[nidx]:
				_allowed[nidx] = next_mask
				queue.append(nidx)
	return true

func _neighbor_mask_for(mask: int, direction: int) -> int:
	var out := 0
	var dir_masks: Array = _neighbor_masks[direction]
	for t in range(_weights.size()):
		if mask & (1 << t):
			out |= int(dir_masks[t])
	return out

func _result_grid() -> Array:
	var grid: Array = []
	grid.resize(_width * _height)
	for idx in range(_allowed.size()):
		var mask := _allowed[idx]
		grid[idx] = _lowest_bit_index(mask)
	return grid

static func _popcount(value: int) -> int:
	var v := value
	var count := 0
	while v != 0:
		v &= v - 1
		count += 1
	return count

static func _lowest_bit_index(value: int) -> int:
	if value == 0:
		return -1
	var i := 0
	while (value & (1 << i)) == 0:
		i += 1
	return i
