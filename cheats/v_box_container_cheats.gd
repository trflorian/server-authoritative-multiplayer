extends VBoxContainer


func _ready() -> void:
	$CheckButtonSpeedCheat.toggled.connect(_on_toggle_speed_cheat)
	$CheckButtonJumpCheat.toggled.connect(_on_toggle_jump_cheat)

func _on_toggle_speed_cheat(is_active: bool) -> void:
	CheatsManager.is_active_cheat_speed = is_active
	
func _on_toggle_jump_cheat(is_active: bool) -> void:
	CheatsManager.is_active_cheat_jump = is_active
