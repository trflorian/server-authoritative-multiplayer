extends VBoxContainer


func _ready() -> void:
	$CheckButtonGhost.toggled.connect(_on_toggle_ghost)
	$CheckButtonGhost.button_pressed = SettingsManager.show_player_ghosts

func _on_toggle_ghost(is_active: bool) -> void:
	SettingsManager.show_player_ghosts = is_active
