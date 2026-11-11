@tool
## One fruit placeholder visual: a solid colored circle drawn per fruit ID.
## Swap the drawing here for sprites later; the rules only use fruit IDs.
class_name FruitView
extends Control

var fruit_id: String
var radius: float
var highlighted := false:
	set(value):
		if highlighted != value:
			highlighted = value
			queue_redraw()


func _init(fruit_id_value: String = "", radius_value: float = 26.0) -> void:
	fruit_id = fruit_id_value
	radius = radius_value
	custom_minimum_size = Vector2.ONE * (radius * 2.0)
	size = custom_minimum_size
	pivot_offset = Vector2.ONE * radius
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var center := Vector2.ONE * radius
	if highlighted:
		draw_circle(center, radius + 6.0, Color(1.0, 1.0, 0.95, 0.35))
	draw_fruit(self, center, radius, fruit_id)
	if highlighted:
		draw_arc(center, radius + 2.5, 0.0, TAU, 40, Color(1.0, 1.0, 0.95, 0.9), 2.5, true)


## Shares the fruit artwork between the editor preview and the game.
static func draw_fruit(canvas: CanvasItem, center: Vector2, fruit_radius: float, id: String) -> void:
	canvas.draw_circle(center, fruit_radius, FruitData.color_of(id))
	canvas.draw_arc(center, fruit_radius, 0.0, TAU, 40, FruitData.outline_color_of(id), 2.5, true)
