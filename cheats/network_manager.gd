extends Node

const IP_ADDRESS := "172.104.235.79"
#const IP_ADDRESS := "localhost"
const PORT := 8765
const MAX_CLIENTS := 4

@export var network_type_label: Label
@export var cheats_ui: Control

@export var player_prefab: PackedScene
@export var players_parent: Node3D

func _ready() -> void:
	var args = Array(OS.get_cmdline_args())
	if OS.has_feature("dedicated_server") or args.has("server"):
		network_type_label.text = "Server - " + IP_ADDRESS + ":" + str(PORT)
		cheats_ui.visible = false
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		_create_server()
		SettingsManager.show_player_ghosts = true
	else:
		network_type_label.text = "Client - " + IP_ADDRESS + ":" + str(PORT)
		cheats_ui.visible = true
		_create_client()

func _create_client() -> void:
	print("Starting client...")
	var peer = WebSocketMultiplayerPeer.new()
	peer.create_client("ws://%s:%d" % [IP_ADDRESS, PORT])
	multiplayer.multiplayer_peer = peer
	await multiplayer.connected_to_server
	print("Client is connected to server!")

func _create_server() -> void:
	print("Starting server...")
	var peer = WebSocketMultiplayerPeer.new()
	peer.create_server(PORT, "*") # TODO: add TLS options according to https://www.reddit.com/r/godot/comments/17ltxjp/comment/l1uz70s/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button
	multiplayer.multiplayer_peer = peer

func _on_peer_connected(peer: int) -> void:
	var new_player_inst = player_prefab.instantiate() as PlayerController
	new_player_inst.name = str(peer)
	new_player_inst.player_id = peer
	players_parent.add_child(new_player_inst)
	new_player_inst.spawn_randomly()

func _on_peer_disconnected(peer: int) -> void:
	players_parent.get_node(str(peer)).queue_free()
