@tool
## Draws a plate and its refill preview. In the editor, show the starting
## layout directly from LevelData without running the board or loading a save.
class_name PlateView
extends Control

const PLATE_CENTER := Vector2(112.0, 96.0)
const PLATE_RADII := Vector2(100.0, 58.0)
## Drop areas are 20% larger than the visible plate, centered on it.
const DROP_SCALE := 1.2

const PLATE_EDGE_COLOR := Color(0.87, 0.82, 0.73)
const PLATE_COLOR := Color(0.96, 0.94, 0.90)
const HIGHLIGHT_COLOR := Color(1.0, 0.99, 0.92, 0.9)
const HIGHLIGHT_GLOW_COLOR := Color(1.0, 0.99, 0.92, 0.3)

const FRUIT_RADIUS := 26.0
const SLOT_POSITIONS := [
	Vector2(56.0, 96.0),
	Vector2(112.0, 96.0),
	Vector2(168.0, 96.0),
]
const PREVIEW_RADIUS := 13.0
const PREVIEW_SPACING := 30.0
const PREVIEW_Y := 186.0
const PREVIEW_ALPHA := 0.85

@export_range(-1, 8) var plate_index := -1:
	set(value):
		plate_index = value
		queue_redraw()

var highlight := false:
	set(value):
		if highlight != value:
			highlight = value
			queue_redraw()

var _fruits: Array = []
var _preview_fruits: Array = []
var _fruit_views: Array[FruitView] = []


## Rebuilds the fruit circles. Slots whose fruit changed (new or moved) get
## a small pop-in so refills and dropped fruits read clearly.
func set_contents(fruits: Array) -> void:
	var old_fruits := _fruits
	_fruits = fruits.duplicate()
	_clear_fruit_views()
	for i in _fruits.size():
		var fruit: String = _fruits[i]
		var view := FruitView.new(fruit, FRUIT_RADIUS)
		view.position = SLOT_POSITIONS[i] - Vector2.ONE * FRUIT_RADIUS
		add_child(view)
		_fruit_views.append(view)
		if i >= old_fruits.size() or old_fruits[i] != fruit:
			view.scale = Vector2.ONE * 0.3
			var tween := view.create_tween()
			tween.tween_property(view, "scale", Vector2.ONE, 0.16) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	queue_redraw()


func set_preview(batch: Array) -> void:
	_preview_fruits = batch.duplicate()
	queue_redraw()


## Hides the fruit circle of a slot while that fruit is being dragged, so
## its original slot stays visible as the return position.
func set_slot_hidden(slot: int, hidden: bool) -> void:
	if slot >= 0 and slot < _fruit_views.size():
		var view: FruitView = _fruit_views[slot]
		if not hidden:
			view.scale = Vector2.ONE
			view.modulate.a = 1.0
		view.visible = not hidden


## Short scale-and-fade animation for a cleared trio. Await this before
## applying the next event snapshot.
func play_clear_animation() -> void:
	if _fruit_views.is_empty():
		return
	var tween := create_tween().set_parallel()
	for view in _fruit_views:
		tween.tween_property(view, "scale", Vector2.ONE * 1.3, 0.12)
		tween.tween_property(view, "modulate:a", 0.0, 0.22).set_delay(0.06)
	await tween.finished
	_clear_fruit_views()
	_fruits = []
	queue_redraw()


func _clear_fruit_views() -> void:
	for view in _fruit_views:
		view.hide()
		view.queue_free()
	_fruit_views.clear()


func _draw() -> void:
	_draw_plate_ellipse(PLATE_CENTER, PLATE_RADII, PLATE_EDGE_COLOR)
	_draw_plate_ellipse(PLATE_CENTER, PLATE_RADII * 0.94, PLATE_COLOR)
	if highlight:
		_draw_plate_ellipse_outline(PLATE_CENTER, PLATE_RADII * 1.04, HIGHLIGHT_GLOW_COLOR, 9.0)
		_draw_plate_ellipse_outline(PLATE_CENTER, PLATE_RADII * 1.04, HIGHLIGHT_COLOR, 3.5)
	var preview := _preview_fruits
	if Engine.is_editor_hint() and plate_index >= 0:
		var fruits: Array = LevelData.STARTING_CONTENTS[plate_index]
		for i in fruits.size():
			FruitView.draw_fruit(self, SLOT_POSITIONS[i], FRUIT_RADIUS, fruits[i])
		var batches: Array = LevelData.RESERVE_BATCHES[plate_index]
		preview = [] if batches.is_empty() else batches[0]
	for i in preview.size():
		var offset := (i - 1.0) * PREVIEW_SPACING
		var center := Vector2(PLATE_CENTER.x + offset, PREVIEW_Y)
		var color := FruitData.color_of(preview[i])
		color.a = PREVIEW_ALPHA
		draw_circle(center, PREVIEW_RADIUS, color)


## Draws a filled ellipse via a non-uniform transform. Renamed with an
## underscore so it does not clash with CanvasItem.draw_ellipse().
func _draw_plate_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	draw_set_transform(center, 0.0, radii)
	draw_circle(Vector2.ZERO, 1.0, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_plate_ellipse_outline(center: Vector2, radii: Vector2, color: Color, width: float) -> void:
	draw_set_transform(center, 0.0, radii)
	draw_arc(Vector2.ZERO, 1.0, 0.0, TAU, 48, color, width / radii.x, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Center of the plate's drop ellipse in this control's coordinate space.
func drop_center() -> Vector2:
	return PLATE_CENTER


## Radii of the drop ellipse (20% larger than the visible plate).
func drop_radii() -> Vector2:
	return PLATE_RADII * DROP_SCALE


## Global center of the plate's drop ellipse.
func drop_center_global() -> Vector2:
	return get_global_transform_with_canvas() * drop_center()


## Global center of a fruit slot (used for pickup hit tests and returns).
func slot_center_global(slot: int) -> Vector2:
	return get_global_transform_with_canvas() * SLOT_POSITIONS[slot]


## Slot of the nearest fruit circle to a global point within the pickup
## radius, or -1.
func find_fruit_slot_at(global_point: Vector2, slop: float = 22.0) -> int:
	var best_slot := -1
	var local_point := get_global_transform_with_canvas().affine_inverse() * global_point
	var best_distance := FRUIT_RADIUS + slop
	for i in _fruit_views.size():
		var view: FruitView = _fruit_views[i]
		if not view.visible:
			continue
		var distance := local_point.distance_to(SLOT_POSITIONS[i])
		if distance <= best_distance:
			best_slot = i
			best_distance = distance
	return best_slot
