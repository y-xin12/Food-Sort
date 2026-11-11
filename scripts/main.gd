## Wires the authored scene to the board and handles mouse and touch drags.
extends Control

## Drag state: {"plate": int, "slot": int, "view": FruitView, "index": int}.
## A mouse drag uses index -1.
var drag: Dictionary = {}
var busy := false
var board: Board
var plates: Array[PlateView] = []

@onready var drag_layer: Control = $DragLayer
@onready var counter_label: Label = $Counter
@onready var completion_label: Label = $Completion
@onready var restart_button: Button = $Restart


func _ready() -> void:
	plates.resize(LevelData.STARTING_CONTENTS.size())
	for plate: PlateView in $Plates.get_children():
		plates[plate.plate_index] = plate
	get_window().focus_exited.connect(_cancel_drag)
	board = Board.new()
	board.load_save()
	_refresh_all()


## Let GUI controls handle presses first. Once a fruit is held, use _input
## so a release over a button or outside the board still ends the drag.
func _unhandled_input(event: InputEvent) -> void:
	if busy or not drag.is_empty():
		return
	if event is InputEventScreenTouch and event.pressed:
		_try_pickup(event.position, event.index)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_try_pickup(event.position, -1)
	if not drag.is_empty():
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if drag.is_empty():
		return
	var index: int = drag["index"]
	if index == -1:
		if event is InputEventMouseMotion:
			_update_drag(event.position)
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_finish_drag(event.position)
		else:
			return
	elif event is InputEventScreenDrag and event.index == index:
		_update_drag(event.position)
	elif event is InputEventScreenTouch and event.index == index and not event.pressed:
		_finish_drag(event.position, event.canceled)
	else:
		return
	get_viewport().set_input_as_handled()


func _cancel_drag() -> void:
	if not drag.is_empty():
		_finish_drag(Vector2.ZERO, true)


## Picks up the single fruit circle nearest to the press point.
func _try_pickup(position: Vector2, touch_index: int) -> void:
	if not drag.is_empty():
		return
	var best_plate := -1
	var best_slot := -1
	var best_distance := INF
	for plate in plates:
		var slot: int = plate.find_fruit_slot_at(position)
		if slot == -1:
			continue
		var distance: float = plate.slot_center_global(slot).distance_to(position)
		if distance < best_distance:
			best_plate = plate.plate_index
			best_slot = slot
			best_distance = distance
	if best_plate == -1:
		return
	var fruit: String = board.contents[best_plate][best_slot]
	var view := FruitView.new(fruit, PlateView.FRUIT_RADIUS)
	view.highlighted = true
	view.scale = Vector2.ONE * 1.1
	drag_layer.add_child(view)
	plates[best_plate].set_slot_hidden(best_slot, true)
	drag = {"plate": best_plate, "slot": best_slot, "view": view, "index": touch_index}
	_update_drag(position)


## The fruit follows the pointer; the nearest valid destination under the
## pointer gets a soft outline.
func _update_drag(position: Vector2) -> void:
	if drag.is_empty():
		return
	drag["view"].position = drag_layer.get_global_transform_with_canvas().affine_inverse() * position \
		- Vector2.ONE * PlateView.FRUIT_RADIUS
	var destination := _find_destination(position)
	var valid := destination != -1 and board.can_drop_on(destination, drag["plate"])
	for plate in plates:
		plate.highlight = valid and plate.plate_index == destination


## Nearest plate whose drop area (20% larger than the visible plate,
## centered on it) contains the point, or -1 when the point is outside all
## drop areas.
func _find_destination(position: Vector2) -> int:
	var best_plate := -1
	var best_distance := INF
	for plate in plates:
		var center: Vector2 = plate.drop_center_global()
		var radii: Vector2 = plate.drop_radii()
		var delta: Vector2 = plate.get_global_transform_with_canvas().affine_inverse() * position - plate.drop_center()
		if (delta.x * delta.x) / (radii.x * radii.x) + (delta.y * delta.y) / (radii.y * radii.y) > 1.0:
			continue
		var distance: float = center.distance_to(position)
		if distance < best_distance:
			best_plate = plate.plate_index
			best_distance = distance
	return best_plate


func _finish_drag(position: Vector2, canceled: bool = false) -> void:
	var view: FruitView = drag["view"]
	var from_plate: int = drag["plate"]
	var from_slot: int = drag["slot"]
	drag.clear()
	for plate in plates:
		plate.highlight = false
	var destination := -1 if canceled else _find_destination(position)
	if destination != -1 and board.can_drop_on(destination, from_plate):
		view.queue_free()
		var events: Array = board.apply_move(from_plate, from_slot, destination)
		board.save()
		_play_events(events)
	else:
		_return_fruit(view, from_plate, from_slot)


## Sends the fruit back to its original slot without changing the board.
func _return_fruit(view: FruitView, plate_index: int, slot: int) -> void:
	var plate: PlateView = plates[plate_index]
	_set_busy(true)
	var target: Vector2 = drag_layer.get_global_transform_with_canvas().affine_inverse() * plate.slot_center_global(slot) \
		- Vector2.ONE * PlateView.FRUIT_RADIUS
	var tween := create_tween()
	tween.tween_property(view, "position", target, 0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(view, "scale", Vector2.ONE, 0.15)
	await tween.finished
	view.queue_free()
	plate.set_slot_hidden(slot, false)
	_set_busy(false)


## Animates the board events of one move in order: the moved fruit lands,
## trios scale-and-fade, preview refills pop in and revealed batches appear.
## Input is blocked while this plays.
func _play_events(events: Array) -> void:
	_set_busy(true)
	for event in events:
		match event["type"]:
			Board.EVENT_MOVED:
				_refresh_plate(event["from"], event)
				_refresh_plate(event["to"], event)
			Board.EVENT_CLEAR:
				await plates[event["plate"]].play_clear_animation()
			Board.EVENT_REFILL:
				_refresh_plate(event["plate"], event)
			Board.EVENT_REVEAL:
				_refresh_plate(event["source"], event)
				_refresh_plate(event["plate"], event)
	_refresh_all()
	_set_busy(false)


## Applies one event snapshot to a plate: contents plus its preview.
func _refresh_plate(plate_index: int, event: Dictionary) -> void:
	var plate: PlateView = plates[plate_index]
	plate.set_contents(event["contents"][plate_index])
	plate.set_preview(event["previews"][plate_index])


## Syncs every plate with the current board state.
func _refresh_all() -> void:
	for i in plates.size():
		plates[i].set_contents(board.contents[i])
		plates[i].set_preview(board.preview_batch(i))
	_update_hud()


func _set_busy(value: bool) -> void:
	busy = value
	restart_button.disabled = value


func _update_hud() -> void:
	counter_label.text = "Trios cleared: %d / %d" % [board.cleared_count(), LevelData.TOTAL_TRIOS]
	completion_label.visible = board.is_complete()


func _on_restart_pressed() -> void:
	if busy:
		return
	if not drag.is_empty():
		drag["view"].queue_free()
		drag.clear()
	for plate in plates:
		plate.highlight = false
	board.reset_to_level()
	board.save()
	_refresh_all()
