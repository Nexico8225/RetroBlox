@tool
class_name GamePassData
extends Resource
## Reusable GamePass definition (.tres) stored in res://gamepasses/
## Customize the Icon, Title, Description, and Tix Cost in the Godot Inspector!

@export var pass_id: String = "vip"
@export var title: String = "VIP"
@export_multiline var description: String = "Unlock special VIP status in this game!"
@export var cost_tix: int = 75
@export var icon: Texture2D
@export var creator_username: String = ""
