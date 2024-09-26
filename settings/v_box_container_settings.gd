extends VBoxContainer


func _ready() -> void:
	$CheckButtonGhost.toggled.connect(_on_toggle_ghost)

func _on_toggle_ghost(is_active: bool) -> void:
	SettingsManager.show_player_ghosts = is_active
