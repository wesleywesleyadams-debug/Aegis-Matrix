extends RefCounted
class_name GripPoses
## Per-category finger-curl overrides, applied every frame on top of
## whatever animation is currently playing (see Unit._apply_grip_pose()) --
## a runtime layer, not something baked into each animation clip.
##
## Why this exists: the alternative is baking a correct hand-curl into
## every single animation that could ever play while a weapon's equipped
## (Idle, Idle_TwoHanded, Walk, Walk_TwoHanded, Attack, Attack_TwoHanded,
## ...), in Blender, by hand, per weapon category -- which is exactly the
## multi-hour-per-animation process this project spent this whole session
## on for just ONE animation. Applying the curl procedurally at runtime
## means any current or future animation gets a correct grip for free,
## and a new weapon *category* (not even a new weapon -- existing
## categories cover every new sword/axe/mace of the same hand-type) needs
## zero Blender work at all.
##
## Keyed by the same slot-kind strings ItemDefs.get_slot_kind() returns
## ("one_hand", "two_hand", "hybrid_hand") plus "unarmed" for an empty
## hand. Add a new key here (and wire a new ItemDefs "slot" kind to it,
## e.g. "bow") when a weapon category needs a genuinely different grip
## shape -- a new sword/axe/mace of an EXISTING category needs no new
## entry, it just reuses one of these by category.
##
## Curl degrees are rotation around each finger segment's local X axis
## (closing it toward the palm), tapering from the base segment (1, curls
## most) out to the tip (4, curls least) -- same convention and same
## values as the ones this session hand-tuned in Blender for the
## Idle_TwoHanded bake (see rebuild_vertical_idle.py's FINGER_CURL_DEG/
## THUMB_CURL_DEG), just moved here so they apply everywhere instead of
## to one baked clip.
const CURL_DEG: Dictionary = {
	"two_hand": {
		"fingers": {1: 55.0, 2: 45.0, 3: 35.0, 4: 20.0},
		"thumb": {1: 25.0, 2: 30.0, 3: 20.0, 4: 10.0},
	},
	"hybrid_hand": {
		"fingers": {1: 55.0, 2: 45.0, 3: 35.0, 4: 20.0},
		"thumb": {1: 25.0, 2: 30.0, 3: 20.0, 4: 10.0},
	},
	"one_hand": {
		"fingers": {1: 50.0, 2: 40.0, 3: 30.0, 4: 15.0},
		"thumb": {1: 20.0, 2: 25.0, 3: 15.0, 4: 8.0},
	},
	# No "unarmed" entry -- an empty hand applies no override at all (see
	# Unit._apply_grip_pose), leaving whatever the animation itself set.
}

## The curl table for `slot_kind` ("one_hand"/"two_hand"/"hybrid_hand"),
## or null if this category has no override defined (e.g. "unarmed", or
## a future "armor"/"accessory" slot that was never meant to touch
## fingers -- Unit._apply_grip_pose treats null as "leave the hand alone").
static func get_curl(slot_kind: String) -> Dictionary:
	return CURL_DEG.get(slot_kind, {})
