extends Camera3D

const OFFSET := Vector3(0, 3, 5)

@export var node_to_follow: Node3D

func _process(delta: float) -> void:
	if node_to_follow != null:
		global_position = global_position.lerp(node_to_follow.global_position + OFFSET, delta)
