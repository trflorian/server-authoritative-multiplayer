extends Camera3D

const OFFSET := Vector3(0, 3, 5)

@export var node_to_follow: Node3D

func _process(delta: float) -> void:
	if node_to_follow != null:
		global_position = global_position.lerp(node_to_follow.global_position + OFFSET, delta)
	elif not multiplayer.is_server():
		var all_players = get_tree().get_nodes_in_group("player")
		for player in all_players:
			print(int(str(player.name)), multiplayer.get_unique_id())
			if int(str(player.name)) == multiplayer.get_unique_id():
				node_to_follow = player.get_node("PlayerBody")
