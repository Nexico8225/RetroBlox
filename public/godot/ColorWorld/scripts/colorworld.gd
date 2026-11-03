extends Node3D
## ==================================================================
##  COLORWORLD — main controller. The whole game is 5 small files:
## ==================================================================
##
##    scripts/colorworld.gd   <- YOU ARE HERE: menu <-> world switching
##    scripts/cw_menu.gd        the front door (built-ins + community + login)
##    scripts/cw_world.gd       the paint world (brush, HUD, hints, win)
##    scripts/cw_maps.gd        the built-in maps — ADD YOURS HERE
##    scripts/cw_glb.gd         community .glb maps -> white paintable world
##    scripts/cw_api.gd         the RetroBlox SDK HTTP door (autoload CwApi)
##
##  Made with the RetroBlox SDK — https://retro-blox.vercel.app
##  Everything here is meant to be edited: by you, or by pasting it into
##  ChatGPT and asking for what you want next. Have fun!
## ==================================================================

## Fill these in after you publish the game on RetroBlox (they make the
## play counter tick and your Player ID show up):
const GAME_ID := ""            # the game's page id (cmv... — from its URL)
const GAME_SEQ := 0            # the game's short human Game ID (#1, #2 ...)

const HINTS_PER_MAP := 10      # the rule: 10 hints per map

var _menu: CanvasLayer
var _world: Node3D

func _ready() -> void:
        # tell the platform someone is playing (only counts when signed in)
        if GAME_ID != "":
                CwApi.play_ping(GAME_ID)
        _open_menu()

## ---------------------------------------------------------------- menu

func _open_menu() -> void:
        if _world != null:
                _world.queue_free()
                _world = null
        _menu = preload("res://scripts/cw_menu.gd").new()
        _menu.map_chosen.connect(_on_map_chosen)
        add_child(_menu)

func _close_menu() -> void:
        if _menu != null:
                _menu.queue_free()
                _menu = null

## ---------------------------------------------------------------- play

func _on_map_chosen(map_def: Dictionary) -> void:
        _close_menu()
        _world = preload("res://scripts/cw_world.gd").new()
        add_child(_world)
        _world.setup(map_def)                       # world is in the tree first!
        _world.request_menu.connect(_open_menu)
        if _world.has_signal("world_complete"):
                _world.world_complete.connect(_on_complete)

func _on_complete() -> void:
        # Hook your celebration here: sounds, confetti, saving the paint...
        print("[ColorWorld] World complete! %s painted everything." % CwApi.display_tag())
