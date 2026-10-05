extends Node3D

class_name PlayerController

const SPEED := 5.0
const JUMP_VELOCITY := 9.0
const REMOTE_INTERPOLATION_TIME := 50.0
const INPUT_COMMAND_SIZE := 7
const MAX_SYNCED_INPUT_COMMANDS := 96

@export var player_id: int

@export var tick_sync_server: int = 0
@export var linear_velocity_sync_server: Vector3
@export var is_on_floor_sync_server: bool
@export var input_buffer_sync := PackedByteArray()

var tick_sync: int = 0
var input_history := PackedByteArray()
var physics_tick_duration: float
var player_body_is_on_floor: bool

func _is_local_player() -> bool:
	return player_id == multiplayer.get_unique_id()

var interpolation_prev_timestamp: int = Time.get_ticks_msec()

func _ready() -> void:
	physics_tick_duration = 1.0 / Engine.physics_ticks_per_second
	player_body_is_on_floor = $PlayerBody.is_on_floor()
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

func _append_input_command(tick: int, direction: Vector2, jump_pressed: bool) -> Vector2:
	var command_offset := input_history.size()
	var command := _encode_input_command(tick, direction, jump_pressed)
	input_history.append_array(command)
	if input_buffer_sync.size() < MAX_SYNCED_INPUT_COMMANDS * INPUT_COMMAND_SIZE:
		input_buffer_sync.append_array(command)
	return _read_input_direction(input_history, command_offset)

func _encode_input_command(tick: int, direction: Vector2, jump_pressed: bool) -> PackedByteArray:
	var command := PackedByteArray()
	command.append(tick & 0xff)
	command.append((tick >> 8) & 0xff)
	command.append((tick >> 16) & 0xff)
	command.append((tick >> 24) & 0xff)
	command.append(roundi(direction.x * 127.0) & 0xff)
	command.append(roundi(direction.y * 127.0) & 0xff)
	command.append(1 if jump_pressed else 0)
	return command

func _read_input_tick(buffer: PackedByteArray, offset: int) -> int:
	var tick := buffer[offset]
	tick += buffer[offset + 1] << 8
	tick += buffer[offset + 2] << 16
	tick += buffer[offset + 3] << 24
	return tick

func _read_input_direction(buffer: PackedByteArray, offset: int) -> Vector2:
	var x := buffer[offset + 4]
	var y := buffer[offset + 5]
	if x >= 128:
		x -= 256
	if y >= 128:
		y -= 256
	return Vector2(x / 127.0, y / 127.0)

func _discard_acknowledged_inputs(buffer: PackedByteArray, acknowledged_tick: int) -> PackedByteArray:
	var first_unacknowledged_offset := 0
	while first_unacknowledged_offset + INPUT_COMMAND_SIZE <= buffer.size():
		if _read_input_tick(buffer, first_unacknowledged_offset) > acknowledged_tick:
			break
		first_unacknowledged_offset += INPUT_COMMAND_SIZE

	var remaining := PackedByteArray()
	for offset in range(first_unacknowledged_offset, buffer.size()):
		remaining.append(buffer[offset])
	return remaining

func _fill_input_window(acknowledged_tick: int) -> void:
	var last_queued_tick := acknowledged_tick
	if not input_buffer_sync.is_empty():
		last_queued_tick = _read_input_tick(input_buffer_sync, input_buffer_sync.size() - INPUT_COMMAND_SIZE)

	var queued_count := input_buffer_sync.size() / INPUT_COMMAND_SIZE
	for offset in range(0, input_history.size(), INPUT_COMMAND_SIZE):
		var tick := _read_input_tick(input_history, offset)
		if tick <= last_queued_tick:
			continue
		if queued_count >= MAX_SYNCED_INPUT_COMMANDS:
			break
		for byte_index in INPUT_COMMAND_SIZE:
			input_buffer_sync.append(input_history[offset + byte_index])
		queued_count += 1
		last_queued_tick = tick

func _on_check_reconcile() -> void:
	var acknowledged_tick := mini(tick_sync_server, tick_sync)
	
	$PlayerBody.global_position = $PlayerGhost.global_position
	$PlayerBody.global_rotation = $PlayerGhost.global_rotation
	$PlayerBody.velocity = linear_velocity_sync_server
	player_body_is_on_floor = is_on_floor_sync_server
	
	input_history = _discard_acknowledged_inputs(input_history, acknowledged_tick)
	input_buffer_sync = _discard_acknowledged_inputs(input_buffer_sync, acknowledged_tick)
	_fill_input_window(acknowledged_tick)

	for offset in range(0, input_history.size(), INPUT_COMMAND_SIZE):
		var direction := _read_input_direction(input_history, offset)
		var jump_pressed := input_history[offset + 6] != 0
		player_body_is_on_floor = _move_player($PlayerBody, physics_tick_duration, jump_pressed, direction, player_body_is_on_floor)

func _interpolate_other() -> void:
	interpolation_prev_timestamp = Time.get_ticks_msec()

func _physics_process(delta: float) -> void:
	$PlayerGhost.visible = SettingsManager.show_player_ghosts
	
	if _is_local_player():
		tick_sync += 1
		var input_dir := Input.get_vector("move_left", "move_right", "move_backward", "move_forward")
		var jump_pressed := Input.is_action_just_pressed("jump")
		input_dir = _append_input_command(tick_sync, input_dir, jump_pressed)
		player_body_is_on_floor = _move_player($PlayerBody, physics_tick_duration, jump_pressed, input_dir, player_body_is_on_floor)
	else:
		var elapsed_since_sync := Time.get_ticks_msec() - interpolation_prev_timestamp
		var weight := minf(1.0, elapsed_since_sync / REMOTE_INTERPOLATION_TIME)
		$PlayerBody.global_position = $PlayerBody.global_position.lerp($PlayerGhost.global_position, weight)
		$PlayerBody.global_rotation = $PlayerBody.global_rotation.lerp($PlayerGhost.global_rotation, weight)
		
	
	if multiplayer.is_server():
		var next_tick := tick_sync_server + 1
		for offset in range(0, input_buffer_sync.size(), INPUT_COMMAND_SIZE):
			if _read_input_tick(input_buffer_sync, offset) != next_tick:
				continue
			var direction := _read_input_direction(input_buffer_sync, offset)
			var jump_pressed := input_buffer_sync[offset + 6] != 0
			is_on_floor_sync_server = _move_player($PlayerGhost, physics_tick_duration, jump_pressed, direction, $PlayerGhost.is_on_floor())
			tick_sync_server = next_tick
			linear_velocity_sync_server = $PlayerGhost.velocity
			break

func _move_player(body: CharacterBody3D, delta: float, is_jumping: bool, input_dir: Vector2, is_on_floor: bool) -> bool:
	# Add the gravity.
	if not is_on_floor:
		body.velocity += body.get_gravity() * delta

	# Handle jump.
	if is_jumping:
		if is_on_floor or (_is_local_player() and CheatsManager.is_active_cheat_jump):
			var jump_velocity = JUMP_VELOCITY
			if _is_local_player() and CheatsManager.is_active_cheat_jump:
				jump_velocity *= 2.0
			body.velocity.y = jump_velocity
	
	var speed = SPEED
	
	# SIMULATE CHEATING
	if _is_local_player() and CheatsManager.is_active_cheat_speed:
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
	
	var flat_velocity = Vector3(body.velocity.x, 0.0, body.velocity.z)
	if flat_velocity.length() > 0:
		_look_at_target_interpolated(body, body.global_position + flat_velocity, 0.1)
	
	# Find the current quaternion from the current transform. 
	#var current_quat = body.transform.basis.get_rotation_quaternion()
	#var desired_quat: Quaternion
	#if body.velocity.length() > 0:
#
		## Find the quaternion you want to interpolate towards based on the current velocity 
		## and the maximum lean angle (say PI / 6 radians). 
		#desired_quat = Quaternion(body.velocity.cross(Vector3(0,-1,0)).normalized(), PI / 20)
	#else:
		#desired_quat = Quaternion(Vector3(0,1,0), PI / 6)
		#
	## Calculate an interpolated quaternion (using so-called spherical linear interpolation). 
	#var next_quat = current_quat.slerp(desired_quat, 0.5)
#
	## Make the character lean by updating the character's transform. 
	#body.transform.basis = Basis(next_quat)

	body.move_and_slide()
	return body.is_on_floor()

func _look_at_target_interpolated(body: Node3D, look_target: Vector3, weight: float) -> void:
	var target_transform := body.transform.looking_at(look_target, Vector3.UP)
	body.transform = body.transform.interpolate_with(target_transform, weight)
