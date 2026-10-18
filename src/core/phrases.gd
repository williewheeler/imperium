class_name Phrases
extends RefCounted
## The game's messages, each with a key and both its Latin and its English: `[latin, english]`. Code names a
## message by key (`"err.no_route"`); a client turns the key into text for the person looking. The
## simulation only ever returns keys, so nothing there depends on a language.
##
## Latin is shown in Roman capitals (see `Latin.t`), the English small beneath or on hover. Names of
## buildings, units, resources and eras are data in `Defs`, not here; so are one-word labels. See
## docs/LATIN.md for the vocabulary and its conventions.
##
## Keys: `err.` a refusal of a command, `msg.` something the game says, `lobby.` the multiplayer hall.

const TABLE := {
	# --- why a command was refused
	"err.unknown_player": ["Lusor ignotus.", "No such player."],
	"err.unknown_command": ["Imperium ignotum.", "No such command."],
	"err.not_allowed": ["Non licet.", "Not allowed."],
	"err.not_yet": ["Nondum licet.", "Not yet allowed: it unlocks in a later era."],
	"err.no_route": ["Iter nullum est.", "There is no route there."],
	"err.unexplored": ["Terra incognita.", "Unknown land: you can't build on unexplored ground."],
	"err.need_level": ["Locus liber et planus requiritur.", "A clear, level site is required (open grassland)."],
	"err.spot_taken": ["Locus occupatus.", "That spot is already taken."],
	"err.villagers_in_way": ["Coloni impediunt.", "Villagers are in the way."],
	"err.cant_afford": ["Copiae non sufficiunt.", "Not enough resources."],
	"err.need_houses": ["Domus plures requiruntur.", "Population limit reached: build more Houses."],
	"err.soldiers_cant_work": ["Milites laborare non possunt.", "Fighting men can't work: only villagers gather and build. They just walk to the spot."],
	"err.need_depot": ["Aedifica forum vel horreum.", "Build a Town Center or Storehouse to drop off resources."],
	# --- what the game says
	"msg.welcome": ["Elige colonos et iube eos laborare.", "Select villagers and order them to work: right-click a tree, berry bush or mine."],
	"msg.marsh_drained": ["Palus siccatur.", "The marsh around the city is drained (the Cloaca Maxima)."],
	"msg.advancing": ["Progredimur.", "Advancing to the next era..."],
	"msg.attack_move": ["Quo oppugnamus? Sinistra.", "Attack-move: left click where the fighters should go, fighting whatever they meet. (Esc cancels)"],
	"msg.nothing_to_explore": ["Nihil ultra explorandum.", "Nothing reachable is left to explore."],
	"msg.quit_again": ["Iterum preme, ut exeas.", "Click Exi again to leave the game."],
	"msg.map_open": ["Tota terra patet.", "The whole map is shown."],
	"msg.map_closed": ["Terra iterum celatur.", "The fog returns."],
	"msg.rain": ["Pluit.", "It begins to rain."],
	"msg.storm": ["Tonat.", "A storm breaks: thunder and heavy rain."],
	"msg.fog": ["Nebula oritur.", "Fog is rolling in."],
	"msg.sun": ["Sol lucet.", "The sun shines."],
	"msg.clouds": ["Caelum nubilum est.", "The sky clouds over."],
	# --- the multiplayer hall
	"lobby.host_left": ["Hospes abest.", "The host has left."],
	"lobby.waiting": ["Exspectamus lusores.", "Waiting for players to join."],
	"lobby.in_hall": ["In atrio sumus.", "You are in the host's lobby. Press Paratus when you are ready."],
	"lobby.all_ready": ["Omnes parati sunt.", "Everyone is ready. Press Incipe to begin."],
}


## The Latin of `key`; `args` fill any `%` in it.
static func latin(key: String, args: Array = []) -> String:
	return _text(key, 0, args)


## The English of `key`; `args` fill any `%` in it.
static func english(key: String, args: Array = []) -> String:
	return _text(key, 1, args)


static func _text(key: String, which: int, args: Array) -> String:
	if not TABLE.has(key):
		push_error("Phrases: no such key '%s'" % key)
		return key
	var s: String = TABLE[key][which]
	return s % args if not args.is_empty() else s
