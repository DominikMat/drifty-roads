extends Node2D

@export var patterns_ahead_to_generate: int = 1
@export var car_next_tile_seperation_distance_px: int = 2000
@export var road_patterns: Array[PackedScene] 

@onready var map_start_point: Marker2D = $MapStartPoint
var next_pattern_connection_point := Vector2.ZERO

func _ready() -> void:
	if map_start_point:
		next_pattern_connection_point = map_start_point.position
	generate_map()


func generate_map():
	if road_patterns.size() == 0: return

	for i in range(patterns_ahead_to_generate):
		generate_new_pattern()

func generate_new_pattern():
	var random_pattern_idx = randi_range(0,road_patterns.size()-1)
	var pattern_scene = road_patterns[random_pattern_idx]	
	var created_pattern_node: Node2D = pattern_scene.instantiate() as Node2D
	
	if created_pattern_node:
		add_child( created_pattern_node )
		var entry_point: Vector2 = (created_pattern_node.get_node("RoadEntry") as Marker2D).global_position
		created_pattern_node.global_position = next_pattern_connection_point - entry_point
		next_pattern_connection_point = (created_pattern_node.get_node("RoadExit") as Marker2D).global_position


func _on_car_car_vertical_distance_traveled(car_position_y: float) -> void:
	if abs(next_pattern_connection_point.y - car_position_y) < car_next_tile_seperation_distance_px:
		generate_new_pattern()
		print("Created new map tile ahead of car postion")
