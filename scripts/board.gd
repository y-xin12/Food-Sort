## Pure board rules: plate contents, reserve batches, move validation, trio
## clearing, refills, stuck-batch reveals and the cleared-trio history.
## No input handling and no drawing here; main.gd owns input, plate.gd draws
## the state, level_data.gd holds the editable level data.
class_name Board
extends RefCounted

const PLATE_COUNT := 9
const CAPACITY := 3
const SAVE_PATH := "user://food_sort_save.json"

## Event types returned by apply_move() for the caller to animate, in order.
const EVENT_MOVED := "moved"
const EVENT_CLEAR := "clear"
const EVENT_REFILL := "refill"
const EVENT_REVEAL := "reveal"

## Fruits on each plate (array of fruit ID arrays).
var contents: Array = []
## Pending refill batches per plate (array of batch arrays). The first
## pending batch of a plate is the batch previewed below it.
var reserve: Array = []
## One fruit ID per cleared trio, in clear order, e.g. ["apple", "banana"].
var cleared_trios: Array = []


func _init(level_contents: Array = [], level_reserve: Array = []) -> void:
	if level_contents.is_empty() and level_reserve.is_empty():
		reset_to_level()
	else:
		contents = _deep_copy(level_contents)
		reserve = _deep_copy(level_reserve)
		cleared_trios = []


func reset_to_level() -> void:
	contents = _deep_copy(LevelData.STARTING_CONTENTS)
	reserve = _deep_copy(LevelData.RESERVE_BATCHES)
	cleared_trios = []


func cleared_count() -> int:
	return cleared_trios.size()


func is_complete() -> bool:
	return cleared_trios.size() >= LevelData.TOTAL_TRIOS


func preview_batch(plate: int) -> Array:
	if reserve[plate].is_empty():
		return []
	return reserve[plate][0]


func can_pickup(plate: int, slot: int) -> bool:
	return _valid_plate(plate) and slot >= 0 and slot < contents[plate].size()


## A drop needs free space and must move to another plate. The board stays
## unchanged for invalid drops; the caller returns the fruit to its slot.
func can_drop_on(plate: int, source_plate: int) -> bool:
	return _valid_plate(plate) and plate != source_plate \
		and contents[plate].size() < CAPACITY


## Applies one fruit move and resolves trio clears, preview refills and
## stuck-batch reveals. Returns ordered events; each event carries a
## "contents"/"previews" snapshot of the full board after that event so the
## caller can animate the sequence step by step.
func apply_move(from_plate: int, from_slot: int, to_plate: int) -> Array:
	var events: Array = []
	if not can_pickup(from_plate, from_slot) or not can_drop_on(to_plate, from_plate):
		return events
	var fruit: String = contents[from_plate][from_slot]
	contents[from_plate].remove_at(from_slot)
	contents[to_plate].append(fruit)
	_emit(events, {"type": EVENT_MOVED, "from": from_plate, "to": to_plate, "fruit": fruit})
	events.append_array(_resolve())
	return events


## Clears trios, refills from previews and reveals pending batches until the
## board is stable.
func _resolve() -> Array:
	var events: Array = []
	while true:
		var plate := _find_trio_plate()
		if plate != -1:
			events.append_array(_clear_plate(plate))
			continue
		if _needs_rescue():
			var reveal := _reveal_batch()
			if reveal.is_empty():
				break
			_emit(events, reveal)
			continue
		break
	return events


func _find_trio_plate() -> int:
	for i in PLATE_COUNT:
		if _is_trio(contents[i]):
			return i
	return -1


func _is_trio(fruits: Array) -> bool:
	if fruits.size() != CAPACITY:
		return false
	for i in range(1, CAPACITY):
		if fruits[i] != fruits[0]:
			return false
	return true



## Removes the trio, records the history entry and loads the plate's next
## preview batch, if any.
func _clear_plate(plate: int) -> Array:
	var events: Array = []
	var fruits: Array = contents[plate]
	cleared_trios.append(fruits[0])
	_emit(events, {"type": EVENT_CLEAR, "plate": plate, "fruits": fruits.duplicate()})
	contents[plate] = []
	if not reserve[plate].is_empty():
		var batch: Array = reserve[plate].pop_front()
		contents[plate] = batch.duplicate()
		_emit(events, {"type": EVENT_REFILL, "plate": plate, "fruits": contents[plate].duplicate()})
	return events


## The player is stuck when no fruit type has three copies on the board
## (no trio can be assembled) while pending batches remain.
func _needs_rescue() -> bool:
	var has_reserve := false
	for i in PLATE_COUNT:
		if not reserve[i].is_empty():
			has_reserve = true
			break
	if not has_reserve:
		return false
	return _max_type_count() < CAPACITY


func _max_type_count() -> int:
	var counts := {}
	for plate_fruits in contents:
		for fruit in plate_fruits:
			counts[fruit] = counts.get(fruit, 0) + 1
	var max_count := 0
	for count in counts.values():
		max_count = max(max_count, int(count))
	return max_count


## Loads the first pending batch (in plate order) onto the first empty plate
## so play can continue. An empty plate is always available when a rescue is
## needed: a board with no empty plate holds at least nine fruits, so some
## type already has three copies.
func _reveal_batch() -> Dictionary:
	var source := -1
	for i in PLATE_COUNT:
		if not reserve[i].is_empty():
			source = i
			break
	var destination := -1
	for i in PLATE_COUNT:
		if contents[i].is_empty():
			destination = i
			break
	if source == -1 or destination == -1:
		return {}
	var batch: Array = reserve[source].pop_front()
	contents[destination] = batch.duplicate()
	return {"type": EVENT_REVEAL, "plate": destination, "source": source,
		"fruits": contents[destination].duplicate()}



func _emit(events: Array, event: Dictionary) -> void:
	event["contents"] = _deep_copy(contents)
	var previews: Array = []
	for i in PLATE_COUNT:
		previews.append(preview_batch(i).duplicate())
	event["previews"] = previews
	events.append(event)


func _valid_plate(plate: int) -> bool:
	return plate >= 0 and plate < PLATE_COUNT


func _deep_copy(value):
	match typeof(value):
		TYPE_ARRAY:
			var copy: Array = []
			for item in value:
				copy.append(_deep_copy(item))
			return copy
		_:
			return value


## Saves the plate contents, remaining batches and cleared-trio history to
## user://. Returns true on success.
func save() -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	var data := {
		"contents": _deep_copy(contents),
		"reserve": _deep_copy(reserve),
		"cleared_trios": cleared_trios.duplicate(),
	}
	file.store_string(JSON.stringify(data))
	return true


func has_save_file() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## Restores a saved game. Returns false (and leaves the level start state)
## when there is no save or the save is invalid.
func load_save() -> bool:
	if not has_save_file():
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	if not is_valid_state(parsed):
		return false
	contents = _deep_copy(parsed["contents"])
	reserve = _deep_copy(parsed["reserve"])
	cleared_trios = parsed["cleared_trios"].duplicate()
	return true


## Structural validation for data loaded from disk: shapes, fruit IDs and
## per-type counts must match what the level can still hold.
static func is_valid_state(state) -> bool:
	if typeof(state) != TYPE_DICTIONARY:
		return false
	if not state.has_all(["contents", "reserve", "cleared_trios"]):
		return false
	var contents: Array = state["contents"]
	var reserve: Array = state["reserve"]
	var trios: Array = state["cleared_trios"]
	if contents.size() != PLATE_COUNT or reserve.size() != PLATE_COUNT:
		return false
	if trios.size() > LevelData.TOTAL_TRIOS:
		return false
	for plate_fruits in contents:
		if plate_fruits.size() > CAPACITY:
			return false
		for fruit in plate_fruits:
			if not FruitData.is_valid(fruit):
				return false
	for plate_batches in reserve:
		for batch in plate_batches:
			if batch.is_empty() or batch.size() > CAPACITY:
				return false
			for fruit in batch:
				if not FruitData.is_valid(fruit):
					return false
	for fruit in trios:
		if not FruitData.is_valid(fruit):
			return false
	var cleared_counts := {}
	for fruit in trios:
		cleared_counts[fruit] = cleared_counts.get(fruit, 0) + 1
	var state_counts := {}
	for i in PLATE_COUNT:
		for fruit in contents[i]:
			state_counts[fruit] = state_counts.get(fruit, 0) + 1
		for batch in reserve[i]:
			for fruit in batch:
				state_counts[fruit] = state_counts.get(fruit, 0) + 1
	for fruit in FruitData.ALL:
		var expected := _level_total_of(fruit) - 3 * int(cleared_counts.get(fruit, 0))
		if int(state_counts.get(fruit, 0)) != expected:
			return false
	return true


static func _level_total_of(fruit: String) -> int:
	var total := 0
	for plate_fruits in LevelData.STARTING_CONTENTS:
		for item in plate_fruits:
			if item == fruit:
				total += 1
	for plate_batches in LevelData.RESERVE_BATCHES:
		for batch in plate_batches:
			for item in batch:
				if item == fruit:
					total += 1
	return total
