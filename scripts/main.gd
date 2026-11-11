## Main scene: warm-brown background, the 3x3 plate grid, HUD, restart
## button and the mouse/touch drag-and-drop controller. Board rules live in
## board.gd, the level data in level_data.gd and the plate visuals in
## plate.gd / plate.tscn (instanced nine times).
extends Control

const GRID_ORIGIN := Vector2(24.0, 130.0)
const CELL_SIZE := Vector2(224.0, 320.0)
const GRID_COLUMNS := 3
const GRID_ROWS := 3
const PLATE_SCENE := preload("res://scenes/plate.tscn")

const BACKGROUND_COLOR := Color(0.545, 0.36, 0.22)
const HUD_TEXT_COLOR := Color(0.97, 0.95, 0.9)
const COMPLETION_COLOR := Color(0.99, 0.93, 0.6)

## Drag state: {"plate": int, "slot": int, "view": FruitView, "index": int}.
var drag: Dictionary = {}
## True while clear/refill events are animating; input is ignored then.
var busy := false

var board: Board
var plates: Array = []
var drag_layer: Control
var counter_label: Label
var completion_label: Label
var restart_button: Button


func _ready() -> void:
	_build_hud()
	_build_plates()
	drag_layer = Control.new()
	drag_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	drag_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(drag_layer)
	board = Board.new()
	board.load_save()
	_refresh_all()
	_update_hud()


func _build_hud() -> void:
	var background := ColorRect.new()
	background.color = BACKGROUND_COLOR
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(background)

	var title_label := _add_centered_label("Food Sort", 40, 16, HUD_TEXT_COLOR)
	add_child(title_label)
	counter_label = _add_centered_label("", 26, 68, HUD_TEXT_COLOR)
	add_child(counter_label)
	completion_label = _add_centered_label("Level complete!", 36, 1100, COMPLETION_COLOR)
	completion_label.visible = false
	add_child(completion_label)

	restart_button = Button.new()
	restart_button.text = "Restart"
	restart_button.add_theme_font_size_override("font_size", 30)
	restart_button.custom_minimum_size = Vector2(220.0, 72.0)
	restart_button.position = Vector2(250.0, 1172.0)
	restart_button.pressed.connect(_on_restart_pressed)
	add_child(restart_button)


func _add_centered_label(text: String, font_size: int, y: float, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	label.offset_top = y
	return label


func _build_plates() -> void:
	var plate_scene: PackedScene = PLATE_SCENE
	for row in GRID_ROWS:
		for column in GRID_COLUMNS:
			var plate: PlateView = plate_scene.instantiate()
			plate.setup(row * GRID_COLUMNS + column)
			plate.position = GRID_ORIGIN + Vector2(column, row) * CELL_SIZE
			plate.size = CELL_SIZE
			add_child(plate)
			plates.append(plate)



## Unified mouse and touch input. With touch-from-mouse emulation enabled,
## duplicate events are harmless: pickup only starts when nothing is held
## and release only acts while something is held.
func _unhandled_input(event: InputEvent) -> void:
	if busy:
		return
	if event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		if event.pressed:
			_try_pickup(event.position, -1)
		elif not drag.is_empty():
			_finish_drag(event.position)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_try_pickup(event.position, event.index)
		elif not drag.is_empty() and drag["index"] == event.index:
			_finish_drag(event.position)
	elif not drag.is_empty() and event is InputEventScreenDrag and event.index == drag["index"]:
		_update_drag(event.position)
	elif not drag.is_empty() and event is InputEventMouseMotion:
		_update_drag(event.position)


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
	view.position = position - Vector2.ONE * PlateView.FRUIT_RADIUS
	drag_layer.add_child(view)
	plates[best_plate].set_slot_hidden(best_slot, true)
	drag = {"plate": best_plate, "slot": best_slot, "view": view, "index": touch_index}
	_update_drag(position)


## The fruit follows the pointer; the nearest valid destination under the
## pointer gets a soft outline.
func _update_drag(position: Vector2) -> void:
	if drag.is_empty():
		return
	drag["view"].position = position - Vector2.ONE * PlateView.FRUIT_RADIUS
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
		var delta: Vector2 = position - center
		if (delta.x * delta.x) / (radii.x * radii.x) + (delta.y * delta.y) / (radii.y * radii.y) > 1.0:
			continue
		var distance: float = center.distance_to(position)
		if distance < best_distance:
			best_plate = plate.plate_index
			best_distance = distance
	return best_plate


func _finish_drag(position: Vector2) -> void:
	var view: FruitView = drag["view"]
	var from_plate: int = drag["plate"]
	var from_slot: int = drag["slot"]
	drag = {}
	var destination := _find_destination(position)
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
	var target: Vector2 = plate.slot_center_global(slot) - Vector2.ONE * PlateView.FRUIT_RADIUS
	var tween := create_tween()
	tween.tween_property(view, "position", target, 0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(view, "scale", Vector2.ONE, 0.15)
	await tween.finished
	view.queue_free()
	plate.set_slot_hidden(slot, false)


## Animates the board events of one move in order: the moved fruit lands,
## trios scale-and-fade, preview refills pop in and revealed batches appear.
## Input is blocked while this plays.
func _play_events(events: Array) -> void:
	busy = true
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
	_update_hud()
	busy = false


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


func _update_hud() -> void:
	counter_label.text = "Trios cleared: %d / %d" % [board.cleared_count(), LevelData.TOTAL_TRIOS]
	completion_label.visible = board.is_complete()


func _on_restart_pressed() -> void:
	if not drag.is_empty():
		drag["view"].queue_free()
		drag = {}
	board.reset_to_level()
	board.save()
	_refresh_all()
