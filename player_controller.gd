extends Node3D

class_name PlayerController

const SPEED = 5.0
const JUMP_VELOCITY = 6.0

@export var player_id: int

@export var tick_sync: int = 0
@export var tick_sync_server: int = 0
@export var input_dir_sync: Vector2
@export var is_jumping_sync: bool
@export var linear_velocity_sync_server: Vector3

var input_buffer_dir: Array[Vector2]
var input_buffer_jumping: Array[bool]

func _is_local_player() -> bool:
	return player_id == multiplayer.get_unique_id()

const INTERPOLATION_FRAMES := 2
var interpolation_prev_timestamp: int = Time.get_ticks_msec()
var interpolation_pos_buffer: Array[Vector3]
var interpolation_rot_buffer: Array[Vector3]

func _ready() -> void:
	if multiplayer.is_server():
		$PlayerBody.visible = false
	else:
		if _is_local_player():
			$PlayerGhost/GhostSync.synchronized.connect(_on_check_reconcile)
		else:
			$PlayerGhost/GhostSync.synchronized.connect(_interpolate_other)
			
	

func _enter_tree() -> void:
	$InputSync.set_multiplayer_authority(int(str(name)))

func spawn_randomly() -> void:
	$PlayerGhost.global_position = Vector3(
		randf_range(-5.0, 5.0),
		0.0,
		randf_range(-5.0, 5.0),
	)

func _on_check_reconcile() -> void:
	var delta_ticks = tick_sync - tick_sync_server
	
	$PlayerBody.global_position = $PlayerGhost.global_position
	$PlayerBody.velocity = linear_velocity_sync_server
	
	while len(input_buffer_dir) > delta_ticks:
		input_buffer_dir.pop_front()
		input_buffer_jumping.pop_front()
	
	if is_jumping_sync and input_buffer_jumping[0]:
		is_jumping_sync = false
	
	while len(input_buffer_dir) > 0:
		var input_dir = input_buffer_dir.pop_front()
		var is_jumping = input_buffer_jumping.pop_front()
		_move_player($PlayerBody, 1/60.0, is_jumping, input_dir)

func _interpolate_other() -> void:
	interpolation_pos_buffer.append($PlayerGhost.global_position)
	interpolation_rot_buffer.append($PlayerGhost.global_rotation)
	
	while len(interpolation_pos_buffer) > INTERPOLATION_FRAMES:
		interpolation_pos_buffer.pop_front()
		interpolation_rot_buffer.pop_front()
	
	interpolation_prev_timestamp = Time.get_ticks_msec()

func _physics_process(delta: float) -> void:
	
	if _is_local_player():
		tick_sync += 1
		if Input.is_action_just_pressed("jump"):
			is_jumping_sync = true
		input_dir_sync = Input.get_vector("move_left", "move_right", "move_backward", "move_forward")
		input_buffer_dir.append(input_dir_sync)
		input_buffer_jumping.append(is_jumping_sync)
		_move_player($PlayerBody, delta, is_jumping_sync, input_dir_sync)
	else:
		var dt = Time.get_ticks_msec() - interpolation_prev_timestamp
		$PlayerBody.global_position = $PlayerBody.global_position.lerp($PlayerGhost.global_position, min(1, dt/200.0))
	
	if multiplayer.is_server():
		tick_sync_server = tick_sync
		_move_player($PlayerGhost, delta, is_jumping_sync, input_dir_sync)
		linear_velocity_sync_server = $PlayerGhost.velocity

func _move_player(body: CharacterBody3D, delta: float, is_jumping: bool, input_dir: Vector2) -> void:
	# Add the gravity.
	if not body.is_on_floor():
		body.velocity += body.get_gravity() * delta

	# Handle jump.
	if is_jumping:
		if body.is_on_floor() or (_is_local_player() and HacksManager.is_jump_hacking):
			var jump_velocity = JUMP_VELOCITY
			if _is_local_player() and HacksManager.is_jump_hacking:
				jump_velocity *= 2.0
			body.velocity.y = jump_velocity
	
	var speed = SPEED
	
	# SIMULATE CHEATING
	if _is_local_player() and HacksManager.is_speed_hacking:
		speed *= 2.0

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var direction := (transform.basis * Vector3(input_dir.x, 0, -input_dir.y)).normalized()
	if direction:
		body.velocity.x = direction.x * speed
		body.velocity.z = direction.z * speed
	else:
		body.velocity.x = move_toward(body.velocity.x, 0, speed)
		body.velocity.z = move_toward(body.velocity.z, 0, speed)

	body.move_and_slide()
