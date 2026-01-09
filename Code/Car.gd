extends Area2D

signal car_vertical_distance_traveled(position_y: float)

# --- CAR SETTINGS ---
@export var engine_power: float = 8000
@export var braking_power: float = 12000
@export var max_turning_raduis: float = 45
@export var cornering_stiffness_front: float = 5
@export var cornering_stiffness_rear: float = 5.2
@export var maximum_tyre_grip: float = 2
@export var drag: float = 5
@export var rolling_resistance_multiplier: float = 6
@export var mass: float = 1500
@export var inertia: float = 2500

# --- DRIFT & TRAIL SETTINGS ---
@export_group("Drift Visuals")
@export var drifting_minimum_slip_angle: float = 15.0
@export var max_drift_angle_for_opacity: float = 45.0
@export var min_trail_opacity: float = 0.2
@export var max_trail_opacity: float = 1.0
@export var trail_width: float = 5.0
@export var trail_lifetime: float = 30.0

@export_group("Debug")
@export var debug_draw: bool = true

var velocity_world: Vector2 = Vector2.ZERO
var velocity_local: Vector2 = Vector2.ZERO
var angular_velocity := 0.0
var steer_angle: float = 0.0

var wheelbase_length: float = 200
var dist_to_front_axle := 100.0
var dist_to_rear_axle := 100.0
var is_drifting: bool = false
var car_movement_paused: bool = true

# Get node references
@onready var wheel_front_left = $"car body/wheel fl"
@onready var wheel_front_right = $"car body/wheel fr"
@onready var wheel_back_left = $"car body/wheel bl"
@onready var wheel_back_right = $"car body/wheel br"
@onready var car_body = $"car body"
@onready var wheels: Array[Sprite2D] = [wheel_front_left, wheel_front_right, wheel_back_left, wheel_back_right]
var active_trails: Array[Line2D] = [null, null, null, null]
var active_trail_alphas: Array[float] = [0.0, 0.0, 0.0, 0.0]
var trail_container: Node2D

var screensize := Vector2.ZERO
const pixeles_per_metre = 50.0
var inital_car_position := Vector2.ZERO
var distance_vertical_traveled := 0.0

# --- Turn Input UI ---
const ui_turn_horizontal_line_width: int = 15
const ui_turn_value_cirlce_radius: int = 40
const ui_turn_horizontal_line_colour: Color = Color.BLACK
const ui_turn_value_cirlce_colour: Color = Color.GRAY
const ui_turn_distance_from_screen_bottom: float = 0.0
var turn_input: float = 0
const turn_input_screen_cover_percent = 0.65

func _ready():
	# wheelbase_length = (wheel_back_left.position - wheel_front_left.position).length()
	dist_to_front_axle = abs(wheel_front_left.position.x) / pixeles_per_metre
	dist_to_rear_axle = abs(wheel_back_left.position.x) / pixeles_per_metre
	wheelbase_length = dist_to_front_axle + dist_to_rear_axle
	
	# Create a container for the trails to keep hierarchy clean
	trail_container = Node2D.new()
	trail_container.name = "Skidmarks"
	trail_container.z_index = -5
	trail_container.position = Vector2.ZERO
	get_parent().call_deferred("add_child", trail_container)

	# set init car pos
	inital_car_position = global_position
	
func _physics_process(delta):
	get_input()
	apply_physics(delta)
	queue_redraw()
	handle_track_drawing()
    
func get_input():
	# get screen and mouse data
	screensize = get_viewport_rect().size
	if screensize.x == 0: pass # div 0 check    
	var is_pressing = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	
	# 1. Check if the user is actually touching or clicking
	if is_pressing: 
		var input_pos = get_viewport().get_mouse_position()
		turn_input = clamp((input_pos.x - screensize.x / 2) / (screensize.x * turn_input_screen_cover_percent / 2), -1.0, 1.0)
	else: turn_input = lerp(turn_input, 0.0, 0.1) # auto centre when screen not touched     
	
	steer_angle = (turn_input * deg_to_rad(max_turning_raduis))
	wheel_front_left.rotation = steer_angle
	wheel_front_right.rotation = steer_angle

func apply_physics(delta):
	if car_movement_paused: return

	# convert velocity to local
	var vel_pixels = velocity_world * pixeles_per_metre
	var local_vel_pixels = vel_pixels.rotated(-rotation)
	velocity_local = local_vel_pixels / pixeles_per_metre

	# calc drift angle for track drawer
	var current_slip_angle_rad = 0.0
	if velocity_local.length() > 2.0: # Only calc slip if moving
		var motion_dir = velocity_local.normalized()
		var heading_dir = Vector2.RIGHT.rotated(steer_angle)
		current_slip_angle_rad = abs(heading_dir.angle_to(motion_dir))

	var current_slip_deg = rad_to_deg(current_slip_angle_rad)
	is_drifting = current_slip_deg > drifting_minimum_slip_angle

	# get side slip angles
	var rot_angle_front = 0.0
	var rot_angle_rear = 0.0
	if abs(velocity_local.x) > 0.1:
		# atan(v_y / v_x) is the sideslip (beta)
		# We add the contribution of angular velocity to the front/rear axles
		rot_angle_front = atan((velocity_local.y + angular_velocity * dist_to_front_axle) / velocity_local.x)
		rot_angle_rear  = atan((velocity_local.y - angular_velocity * dist_to_rear_axle) / velocity_local.x)
	var slip_angle_front = rot_angle_front - steer_angle
	var slip_angle_rear  = rot_angle_rear

	# calculate lateral forces
	var car_weight_per_axle = mass * 9.8 * 0.5
	var lateral_force_front_wheels = -cornering_stiffness_front * slip_angle_front
	var lateral_force_rear_wheels  = -cornering_stiffness_rear * slip_angle_rear
	lateral_force_front_wheels = clamp(lateral_force_front_wheels, -maximum_tyre_grip, maximum_tyre_grip) * car_weight_per_axle
	lateral_force_rear_wheels  = clamp(lateral_force_rear_wheels, -maximum_tyre_grip, maximum_tyre_grip) * car_weight_per_axle

	# calculate traction forces
	var traction_force = engine_power - (braking_power if Input.is_action_pressed("driveReverse") else 0.0)

	# tracktion decrease in sliding	
	#if is_drifting:
#		lateral_force_front_wheels *= 0.5
#		lateral_force_rear_wheels *= 0.5
		# traction_force *= 0.5

	# sum forces
	var resistance = Vector2.ZERO
	resistance.x = -(rolling_resistance_multiplier*drag * velocity_local.x + drag * velocity_local.x * abs(velocity_local.x))
	resistance.y = -(rolling_resistance_multiplier*drag * velocity_local.y + drag * velocity_local.y * abs(velocity_local.y))

	var force = Vector2.ZERO
	force.x = traction_force + resistance.x - lateral_force_front_wheels * sin(steer_angle)
	force.y = lateral_force_front_wheels * cos(steer_angle) + lateral_force_rear_wheels + resistance.y

	var torque = (lateral_force_front_wheels * cos(steer_angle) * dist_to_front_axle) - (lateral_force_rear_wheels * dist_to_rear_axle)

	# integration 
	var acceleration = force / mass
	var angular_acceleration = torque / inertia

	velocity_local += acceleration * delta
	angular_velocity += angular_acceleration * delta
	velocity_world = velocity_local.rotated(rotation)
	position += (velocity_world*pixeles_per_metre) * delta
	rotation += angular_velocity * delta

func _draw():
	# ui turn input display
	var offset_y = screensize.y/scale.y * (0.5-ui_turn_distance_from_screen_bottom)
	var offset_x = screensize.x/scale.x * turn_input_screen_cover_percent/2
	draw_line(Vector2(-offset_x,offset_y).rotated(-rotation), Vector2(offset_x,offset_y).rotated(-rotation), ui_turn_horizontal_line_colour, ui_turn_horizontal_line_width)
	var position_circle_x = screensize.x/scale.x * turn_input_screen_cover_percent/2 * turn_input
	draw_circle(Vector2(position_circle_x, offset_y).rotated(-rotation), ui_turn_value_cirlce_radius, ui_turn_value_cirlce_colour)

	# debug lines
	if debug_draw:
		draw_line(Vector2.ZERO, velocity_local, Color.DARK_BLUE)
		draw_line(Vector2.ZERO, Vector2.RIGHT.rotated(steer_angle) * 100, Color.GREEN)

func handle_track_drawing():
	# Calculate opacity based on current slip angle
	# Remap(value, input_min, input_max, output_min, output_max)
	var current_slip_deg = rad_to_deg(abs(velocity_local.angle_to(Vector2.RIGHT.rotated(steer_angle))))

	# Clean up angle calculation (ensure it's 0-90 range approximately)
	if current_slip_deg > 180: current_slip_deg = 360 - current_slip_deg

	var alpha_val = remap(current_slip_deg, drifting_minimum_slip_angle, max_drift_angle_for_opacity, min_trail_opacity, max_trail_opacity)
	alpha_val = clamp(alpha_val, 0.0, 1.0)	
	if is_drifting:
		for i in range(4):
			# delete current new line segment if opacity changed significantly
			if active_trails[i] != null:
				if abs(active_trail_alphas[i] - alpha_val) > 0.1:
					active_trails[i] = null
					
			# Create new line segment if needed
			if active_trails[i] == null: 
				active_trails[i] = create_new_trail(alpha_val)
				active_trail_alphas[i] = alpha_val
			
			active_trails[i].add_point(wheels[i].global_transform.origin)
	else: 
		for i in range(4): active_trails[i] = null

func create_new_trail(alpha_val: float) -> Line2D:
	var l = Line2D.new()
	l.top_level = true
	l.z_index = -5
	l.width = trail_width
	l.default_color = Color(0, 0, 0, alpha_val)
	l.texture_mode = Line2D.LINE_TEXTURE_NONE
	l.begin_cap_mode = Line2D.LINE_CAP_ROUND
	l.end_cap_mode = Line2D.LINE_CAP_ROUND
	l.global_position = Vector2.ZERO
	trail_container.add_child(l)

	# auto delete tracks after time exprired
	var tween = l.create_tween()
	tween.tween_interval(trail_lifetime) # Wait
	tween.tween_property(l, "modulate:a", 0.0, 1.0) # Fade out over 1 sec
	tween.tween_callback(l.queue_free) # Delete

	return l

func _process(_delta: float) -> void:
	const signal_distance_threshold = 500
	var current_distance_vert_traveled = abs(global_position.y - inital_car_position.y)
	if current_distance_vert_traveled > distance_vertical_traveled + signal_distance_threshold:
		distance_vertical_traveled = current_distance_vert_traveled
		car_vertical_distance_traveled.emit(global_position.y)

func _on_game_started() -> void:
	car_movement_paused = false
