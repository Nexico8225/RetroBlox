extends SceneTree
## REMOVED — this probe used to CREATE A THROWAWAY ACCOUNT on the live
## site on every run (bot accounts are banned). Do not reintroduce it.
## For sign-in flow testing use tests/probe_auth_flow.gd: it drives the
## real login path OFFLINE (no network, no accounts) and checks that the
## world actually starts and the player spawns.

func _initialize() -> void:
	print("probe_login.gd was removed (it created bot accounts). Use tests/probe_auth_flow.gd instead.")
	quit(1)
