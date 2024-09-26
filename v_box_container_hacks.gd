extends VBoxContainer


func _ready() -> void:
	$CheckButtonSpeedHack.toggled.connect(_on_toggle_speed_hack)
	$CheckButtonJumpHack.toggled.connect(_on_toggle_jump_hack)

func _on_toggle_speed_hack(is_speed_hack_on: bool) -> void:
	HacksManager.is_speed_hacking = is_speed_hack_on
	
func _on_toggle_jump_hack(is_jump_hack_on: bool) -> void:
	HacksManager.is_jump_hacking = is_jump_hack_on
