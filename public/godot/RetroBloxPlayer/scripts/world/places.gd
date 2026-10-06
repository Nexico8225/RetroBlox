class_name Places
extends RefCounted
## The built-in places the new player ships with. Part format:
##   { p=[x,y,z], s=[sx,sy,sz], c="RRGGBB", g="spawn|kill|ladder|goal|checkpoint|bounce", m="plastic|metal|neon|wood" }
## Jumps are tuned to the classic physics (WalkSpeed 16 / JumpPower 50):
## a full flat jump clears ~12 studs; kill bricks and gaps stay 6-10 apart.


static func all() -> Array:
	return [baseplate(), obby(), skylands()]


static func by_id(id: String) -> Dictionary:
	for def in all():
		if def["id"] == id:
			return def
	return baseplate()


## ---------------------------------------------------------------- Baseplate
## The classic gray baseplate: bricks to climb, a stairs fort, a truss tower,
## a trampoline and a metal shed. Pure sandbox.

static func baseplate() -> Dictionary:
	return {
		"id": "baseplate",
		"name": "Happy Baseplate",
		"desc": "The classic sandbox. Climb the fort, ride the trampoline, hang out.",
		"tile": "8f8f8f",
		"sky_top": "3d8fd1",
		"sky_horizon": "bfe0f5",
		"void_y": -40.0,
		"parts": [
			{ "p": [0, -0.5, 0], "s": [140, 1, 140], "c": "8f8f8f" },
			# spawn pads
			{ "p": [0, 0.5, 0], "s": [5, 1, 5], "c": "cfd4da", "g": "spawn" },
			{ "p": [10, 0.5, 0], "s": [5, 1, 5], "c": "cfd4da", "g": "spawn" },
			{ "p": [-10, 0.5, 0], "s": [5, 1, 5], "c": "cfd4da", "g": "spawn" },
			{ "p": [0, 0.5, 10], "s": [5, 1, 5], "c": "cfd4da", "g": "spawn" },
			# the classic brick pile
			{ "p": [14, 1, 6], "s": [4, 2, 2], "c": "c0392b" },
			{ "p": [18, 1.5, 6], "s": [3, 3, 3], "c": "e2b23a" },
			{ "p": [16, 4.5, 6], "s": [2.4, 3, 2.4], "c": "1b6fae" },
			# stairs fort (2-stud risers walk right up)
			{ "p": [-18, 1, 0], "s": [6, 2, 6], "c": "a3a2a5" },
			{ "p": [-18, 3, 6], "s": [6, 2, 6], "c": "a3a2a5" },
			{ "p": [-18, 5, 12], "s": [6, 2, 6], "c": "a3a2a5" },
			{ "p": [-18, 7, 18], "s": [6, 2, 6], "c": "a3a2a5" },
			{ "p": [-18, 7.5, 30], "s": [10, 1, 14], "c": "98a1a8" },
			# truss tower
			{ "p": [24, 9.5, 10], "s": [8, 1, 8], "c": "98a1a8" },
			{ "p": [24, 5, 14.3], "s": [1.5, 10, 0.6], "c": "6b6f74", "g": "ladder" },
			# trampoline
			{ "p": [-8, 0.5, -14], "s": [6, 1, 6], "c": "2f9e44", "m": "neon", "g": "bounce" },
			# metal shed (shiny!)
			{ "p": [8, 2, -20], "s": [6, 4, 6], "c": "aab4bd", "m": "metal" },
			{ "p": [8, 4.6, -20], "s": [7, 0.6, 7], "c": "8fa0ac", "m": "metal" },
		],
	}


## ---------------------------------------------------------------- Classic Obby
## Jumps, kill bricks, a narrow plank, a truss climb and a trampoline launch
## to the gold goal. Checkpoints keep it friendly.

static func obby() -> Dictionary:
	return {
		"id": "obby",
		"name": "Classic Obby",
		"desc": "Jumps, kill bricks, ladders and a trampoline finish. Reach the gold!",
		"tile": "e2574c",
		"sky_top": "2f7fbf",
		"sky_horizon": "a8d4f0",
		"void_y": -30.0,
		"parts": [
			# start
			{ "p": [0, 0, 0], "s": [14, 2, 14], "c": "a3a2a5", "g": "spawn" },
			# hops (tops 2 -> 3 -> 4)
			{ "p": [0, 1, 16], "s": [6, 2, 6], "c": "e2b23a" },
			{ "p": [3, 2, 30], "s": [6, 2, 6], "c": "e2b23a" },
			{ "p": [-3, 3, 44], "s": [6, 2, 6], "c": "e2b23a" },
			# kill-brick bridge (hop the reds)
			{ "p": [0, 3, 60], "s": [6, 2, 24], "c": "a3a2a5" },
			{ "p": [0, 4.5, 54], "s": [2, 1, 2], "c": "c0392b", "g": "kill" },
			{ "p": [0, 4.5, 60], "s": [2, 1, 2], "c": "c0392b", "g": "kill" },
			{ "p": [0, 4.5, 66], "s": [2, 1, 2], "c": "c0392b", "g": "kill" },
			# checkpoint one
			{ "p": [0, 3, 80], "s": [10, 2, 10], "c": "98a1a8" },
			{ "p": [0, 4.5, 80], "s": [4, 1, 4], "c": "e2b23a", "g": "checkpoint" },
			# narrow plank
			{ "p": [0, 3, 93], "s": [2, 2, 20], "c": "a3a2a5" },
			# truss climb (from plank top 4 up to platform top 7)
			{ "p": [0, 6, 116], "s": [12, 2, 12], "c": "98a1a8" },
			{ "p": [0, 3.5, 109.8], "s": [1.5, 7, 0.6], "c": "6b6f74", "g": "ladder" },
			# checkpoint two
			{ "p": [-3, 7.5, 113], "s": [4, 1, 4], "c": "e2b23a", "g": "checkpoint" },
			# trampoline launch to the goal island
			{ "p": [3, 7.5, 120], "s": [5, 1, 5], "c": "2f9e44", "m": "neon", "g": "bounce" },
			{ "p": [0, 16, 130], "s": [10, 2, 10], "c": "98a1a8" },
			# THE GOLD GOAL
			{ "p": [0, 17.5, 130], "s": [5, 1, 5], "c": "ffd700", "m": "metal", "g": "goal" },
		],
	}


## ---------------------------------------------------------------- Skylands
## Floating islands over the void. Bridges, a trampoline launch between
## islands and a kill-plank finale.

static func skylands() -> Dictionary:
	return {
		"id": "skylands",
		"name": "Skylands",
		"desc": "Islands in the sky. Do not look down — the void is real.",
		"tile": "4caf50",
		"sky_top": "2a6fb8",
		"sky_horizon": "cfe6f7",
		"void_y": -40.0,
		"parts": [
			# island one (spawn)
			{ "p": [0, 0, 0], "s": [20, 1, 20], "c": "4caf50" },
			{ "p": [0, -2, 0], "s": [16, 3, 16], "c": "795548" },
			{ "p": [0, 0.5, 0], "s": [5, 1, 5], "c": "cfd4da", "g": "spawn" },
			# wood bridge
			{ "p": [0, 0, 20], "s": [3, 1, 16], "c": "a1665e", "m": "wood" },
			# island two + checkpoint + trampoline up
			{ "p": [0, 0, 40], "s": [18, 1, 18], "c": "4caf50" },
			{ "p": [0, -2, 40], "s": [14, 3, 14], "c": "795548" },
			{ "p": [-4, 0.5, 40], "s": [4, 1, 4], "c": "e2b23a", "g": "checkpoint" },
			{ "p": [4, 0.5, 44], "s": [5, 1, 5], "c": "2f9e44", "m": "neon", "g": "bounce" },
			# island three (metal landing)
			{ "p": [0, 11, 56], "s": [12, 1, 12], "c": "98a1a8" },
			{ "p": [0, 9, 56], "s": [9, 2, 9], "c": "757575", "m": "metal" },
			{ "p": [0, 11.5, 54], "s": [4, 1, 4], "c": "e2b23a", "g": "checkpoint" },
			# kill plank
			{ "p": [0, 11, 68], "s": [2, 1, 10], "c": "a1665e", "m": "wood" },
			{ "p": [1.7, 11.6, 68], "s": [0.8, 0.5, 10], "c": "c0392b", "g": "kill" },
			{ "p": [-1.7, 11.6, 68], "s": [0.8, 0.5, 10], "c": "c0392b", "g": "kill" },
			# island four — THE GOLD
			{ "p": [0, 11, 82], "s": [12, 1, 12], "c": "4caf50" },
			{ "p": [0, 9, 82], "s": [9, 2, 9], "c": "795548" },
			{ "p": [0, 11.5, 82], "s": [5, 1, 5], "c": "ffd700", "m": "metal", "g": "goal" },
		],
	}
