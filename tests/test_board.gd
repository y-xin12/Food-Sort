## Headless verification of the board rules, drop geometry and level design.
## Run with:
##   Godot --headless --path <project> res://tests/test.tscn
extends Node

const SAVE_PATH := "user://food_sort_save.json"

var failures: Array = []
## Cleared during the level solver runs; counts trio clears without a
## following preview refill.
var no_preview_clears := 0


func _ready() -> void:
	_remove_save()
	_test_level_data()
	await _test_drop_geometry()
	await _test_scene_input()
	_test_opening_match_and_refill()
	_test_invalid_drops()
	_test_mixed_plate_stays()
	_test_cascade_clear()
	_test_rescue_reveal()
	_test_complete_level("level completes with normal gathering", false)
	_test_complete_level("level completes when trios clear on plates without previews", true)
	_test_save_and_restore()
	_remove_save()
	_print_summary()
	get_tree().quit(1 if not failures.is_empty() else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  " + label)
	else:
		failures.append(label)
		print("FAIL  " + label)


func _fail(label: String) -> void:
	failures.append(label)
	print("FAIL  " + label)


func _remove_save() -> void:
	var directory := DirAccess.open("user://")
	if directory != null and directory.file_exists("food_sort_save.json"):
		directory.remove("food_sort_save.json")


func _print_summary() -> void:
	print("")
	if failures.is_empty():
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED:" % failures.size())
		for failure in failures:
			print("  - " + failure)


func _event_types(events: Array) -> Array:
	var types: Array = []
	for event in events:
		types.append(event["type"])
	return types


func _test_level_data() -> void:
	var board := Board.new()
	_check(board.contents.size() == 9 and board.reserve.size() == 9, "level has 9 plates")
	var counts := {}
	for plate_fruits in board.contents:
		for fruit in plate_fruits:
			counts[fruit] = counts.get(fruit, 0) + 1
	for plate_batches in board.reserve:
		for batch in plate_batches:
			for fruit in batch:
				counts[fruit] = counts.get(fruit, 0) + 1
	_check(int(counts.get("apple", 0)) == 12 and int(counts.get("orange", 0)) == 12 \
		and int(counts.get("banana", 0)) == 12, "level holds 12 trios: 12 of each fruit")
	var empty_plates := 0
	for plate_fruits in board.contents:
		if plate_fruits.is_empty():
			empty_plates += 1
	_check(empty_plates == 3, "level starts with empty sorting plates")
	_check(board.contents[0] == ["apple", "apple"] and board.contents[3] == ["apple"],
		"level has an easy opening apple match")


func _test_drop_geometry() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var center: Vector2 = main.plates[0].drop_center_global()
	_check(main._find_destination(center + Vector2(109, 0)) == 0,
		"a drop just outside the right rim lands on plate 0")
	_check(main._find_destination(center + Vector2(0, 64)) == 0,
		"a drop just below the rim lands on plate 0")
	_check(main._find_destination(center + Vector2(0, 74)) == -1,
		"a pointer outside all drop areas has no destination")
	_check(main._find_destination(main.plates[4].drop_center_global()) == 4,
		"a drop on a plate center targets that plate")
	_check(main.plates[4].find_fruit_slot_at(main.plates[4].slot_center_global(0)) == 0,
		"pressing on a fruit picks up its slot")
	remove_child(main)
	main.free()


func _test_scene_input() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	var viewport := get_viewport()
	var source: Vector2 = main.plates[3].slot_center_global(0)
	var destination: Vector2 = main.plates[0].drop_center_global()
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = source
	mouse.pressed = true
	viewport.push_input(mouse, true)
	_check(not main.drag.is_empty(), "mouse can pick up fruit through the authored scene")

	var motion := InputEventMouseMotion.new()
	motion.position = destination
	viewport.push_input(motion, true)
	_check(main.plates[0].highlight, "mouse movement highlights the valid destination")
	var mouse_release := InputEventMouseButton.new()
	mouse_release.button_index = MOUSE_BUTTON_LEFT
	mouse_release.position = destination
	viewport.push_input(mouse_release, true)
	await get_tree().create_timer(0.5).timeout
	_check(main.drag.is_empty() and not main.busy and not main.plates[0].highlight,
		"mouse release finishes the clear animation and clears highlighting")
	_check(main.board.cleared_trios == ["apple"] and main.board.contents[0] == ["banana", "orange", "banana"],
		"mouse drag clears the opening trio and refills from its preview")

	source = main.plates[4].slot_center_global(0)
	var touch := InputEventScreenTouch.new()
	touch.index = 1
	touch.position = source
	touch.pressed = true
	viewport.push_input(touch, true)
	_check(not main.drag.is_empty(), "touch can pick up fruit through the authored scene")
	var touch_motion := InputEventScreenDrag.new()
	touch_motion.index = 1
	touch_motion.position = main.plates[6].drop_center_global()
	viewport.push_input(touch_motion, true)
	_check(main.plates[6].highlight, "touch movement highlights the valid destination")
	var touch_cancel := InputEventScreenTouch.new()
	touch_cancel.index = 1
	touch_cancel.position = touch_motion.position
	touch_cancel.canceled = true
	viewport.push_input(touch_cancel, true)
	await get_tree().create_timer(0.25).timeout
	_check(main.drag.is_empty() and not main.plates[6].highlight and main.board.contents[6].is_empty()
		and main.plates[4].find_fruit_slot_at(source) == 0, "canceled touch returns fruit without moving it")

	mouse.position = source
	viewport.push_input(mouse, true)
	mouse_release.position = main.restart_button.get_global_rect().get_center()
	viewport.push_input(mouse_release, true)
	await get_tree().create_timer(0.25).timeout
	_check(main.drag.is_empty() and main.board.cleared_count() == 1
		and main.plates[4].find_fruit_slot_at(source) == 0, "release over Restart returns fruit without restarting")
	remove_child(main)
	main.free()
	_remove_save()


func _test_opening_match_and_refill() -> void:
	var board := Board.new()
	var events: Array = board.apply_move(3, 0, 0)
	_check(_event_types(events) == ["moved", "clear", "refill"],
		"opening match produces move, clear and refill events")
	_check(board.cleared_trios == ["apple"], "opening match records one apple trio")
	_check(board.contents[0] == ["banana", "orange", "banana"],
		"cleared plate refills with its previewed batch")
	_check(board.preview_batch(0) == ["apple", "apple", "apple"],
		"preview advances to the next batch after the refill")
	_check(board.contents[3].is_empty(), "source plate gap closes after the move")


func _test_invalid_drops() -> void:
	var board := Board.new()
	board.apply_move(3, 0, 0)
	var snapshot: Array = board.contents.duplicate(true)
	_check(not board.can_drop_on(0, 5), "full plate rejects drops")
	_check(board.apply_move(5, 0, 0).is_empty(), "move onto a full plate does nothing")
	_check(not board.can_drop_on(2, 2), "source plate rejects drops")
	_check(board.apply_move(2, 0, 2).is_empty(), "move onto the source plate does nothing")
	_check(board.contents == snapshot, "board is unchanged after rejected drops")


func _test_mixed_plate_stays() -> void:
	var board := Board.new()
	board.apply_move(0, 0, 6)
	board.apply_move(4, 0, 6)
	var events: Array = board.apply_move(5, 0, 6)
	_check(board.contents[6] == ["apple", "orange", "banana"], "mixed plate stays as it is")
	_check(board.cleared_trios.is_empty(), "mixed plate does not clear")
	_check(_event_types(events) == ["moved"], "mixed drop only emits a move event")


func _test_cascade_clear() -> void:
	var board := Board.new([["apple", "apple"], [], [], ["apple"], [], [], [], [], []],
		[[["apple", "apple", "apple"]], [], [], [], [], [], [], [], []])
	var events: Array = board.apply_move(3, 0, 0)
	_check(_event_types(events) == ["moved", "clear", "refill", "clear"],
		"a pure refill batch clears again as a cascade")
	_check(board.cleared_trios == ["apple", "apple"], "cascade records both trios in order")
	_check(board.contents[0].is_empty(), "plate with no batch left stays empty")


func _test_rescue_reveal() -> void:
	var board := Board.new([["apple"], ["orange"], ["banana"], [], [], [], [], [], []],
		[[], [], [], [], [], [["banana", "orange", "banana"]], [], [], []])
	var events: Array = board.apply_move(0, 0, 6)
	_check(_event_types(events) == ["moved", "reveal"],
		"a stuck board reveals a pending batch")
	_check(board.contents[0] == ["banana", "orange", "banana"],
		"revealed batch loads onto the first empty plate")
	_check(board.reserve[5].is_empty(), "revealed batch leaves its source plate")
	var reveal_event: Dictionary = events[1]
	_check(reveal_event["source"] == 5 and reveal_event["plate"] == 0,
		"reveal event records source and destination plates")


## Plays the level to the end with a simple gather strategy. With
## prefer_empty the solver sticks to one empty plate while assembling a
## trio, so trios get cleared on plates that have no preview batches and
## progress depends on the rescue reveals.
func _test_complete_level(label: String, prefer_empty: bool) -> void:
	var board := Board.new()
	var moves := 0
	var sticky := -1
	no_preview_clears = 0
	while not board.is_complete():
		moves += 1
		if moves > 600:
			_fail(label + " (solver exceeded the move cap)")
			print("DEBUG contents=", board.contents, " reserve=", board.reserve)
			return
		if sticky != -1 and board.contents[sticky].is_empty():
			sticky = -1
		var fruit := _most_common_type(board)
		if fruit == "":
			_fail(label + " (no fruit type has three copies while incomplete)")
			return
		var target: int = sticky
		if target == -1:
			target = _gather_plate(board, fruit, prefer_empty)
			sticky = target
		if board.contents[target].size() == Board.CAPACITY:
			var spill := _first_plate_with_space(board, target)
			if spill == -1:
				_fail(label + " (no space to make room on the target plate)")
				return
			var slot := 0
			for i in Board.CAPACITY:
				if board.contents[target][i] != fruit:
					slot = i
					break
			_count_no_preview_clears(board.apply_move(target, slot, spill))
			continue
		var events: Array = _move_one_fruit_of_type(board, fruit, target)
		if events.is_empty():
			_fail(label + " (no movable fruit of the gathered type)")
			return
		_count_no_preview_clears(events)
	var type_counts := {}
	for fruit in board.cleared_trios:
		type_counts[fruit] = type_counts.get(fruit, 0) + 1
	var board_empty := true
	for i in 9:
		if not board.contents[i].is_empty() or not board.reserve[i].is_empty():
			board_empty = false
	_check(board.cleared_trios.size() == 12 and board_empty, label)
	_check(int(type_counts.get("apple", 0)) == 4 and int(type_counts.get("orange", 0)) == 4 \
		and int(type_counts.get("banana", 0)) == 4, label + " (four trios per fruit)")
	if prefer_empty:
		_check(no_preview_clears > 0, label + " (trios cleared on plates without previews)")
	print("      solver finished in %d moves, %d clears without a preview" % [moves, no_preview_clears])



## Counts trio clears that were not followed by a preview refill, i.e. trios
## cleared on plates that had no batch left.
func _count_no_preview_clears(events: Array) -> void:
	for i in events.size():
		if events[i]["type"] != Board.EVENT_CLEAR:
			continue
		var followed_by_refill: bool = i + 1 < events.size() \
			and events[i + 1]["type"] == Board.EVENT_REFILL \
			and events[i + 1]["plate"] == events[i]["plate"]
		if not followed_by_refill:
			no_preview_clears += 1


## Fruit type with the most copies on the board, or "" when no type reaches
## three. Ties break in the fixed FruitData.ALL order on purpose: iterating
## a counts dictionary instead would order its keys by first insertion,
## which changes as plates empty and refill. With tied types the gathered
## fruit could then flip every move, ping-ponging spilled fruits back onto
## the target plate and stalling the solver forever.
func _most_common_type(board: Board) -> String:
	var best := ""
	var best_count := 0
	for fruit in FruitData.ALL:
		var count := 0
		for plate_fruits in board.contents:
			for item in plate_fruits:
				if item == fruit:
					count += 1
		if count > best_count:
			best = fruit
			best_count = count
	if best_count < 3:
		return ""
	return best


func _gather_plate(board: Board, fruit: String, prefer_empty: bool) -> int:
	if prefer_empty:
		for i in 9:
			if board.contents[i].is_empty():
				return i
	var best := -1
	var best_count := -1
	for i in 9:
		var count := 0
		for item in board.contents[i]:
			if item == fruit:
				count += 1
		if count > best_count:
			best = i
			best_count = count
	return best


func _first_plate_with_space(board: Board, exclude: int) -> int:
	for i in 9:
		if i != exclude and board.contents[i].size() < Board.CAPACITY:
			return i
	return -1


## Moves one fruit of the given type onto the target plate and returns the
## board events, or an empty array when no such fruit is movable.
func _move_one_fruit_of_type(board: Board, fruit: String, target: int) -> Array:
	for i in 9:
		if i == target:
			continue
		var fruits: Array = board.contents[i]
		for slot in fruits.size():
			if fruits[slot] == fruit:
				return board.apply_move(i, slot, target)
	return []


func _test_save_and_restore() -> void:
	var board := Board.new()
	board.apply_move(3, 0, 0)
	board.apply_move(4, 0, 1)
	_check(board.save(), "progress saves to user://")
	var restored := Board.new()
	_check(restored.load_save(), "saved game restores on launch")
	_check(restored.contents == board.contents and restored.reserve == board.reserve \
		and restored.cleared_trios == board.cleared_trios, "restored state matches the saved state")
	var corrupt := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	corrupt.store_string("{not json")
	corrupt = null
	var board_two := Board.new()
	_check(not board_two.load_save(), "corrupt save is rejected")
	_check(board_two.contents[0] == ["apple", "apple"], "rejected save falls back to the level start")
	var invalid := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	invalid.store_string('{"contents": [], "reserve": [], "cleared_trios": ["apple"]}')
	invalid = null
	_check(not Board.new().load_save(), "structurally invalid save is rejected")


