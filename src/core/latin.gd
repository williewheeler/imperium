class_name Latin
extends RefCounted
## Roman inscription lettering: capitals only, and V stands for both U and V
## (the Latin alphabet had no separate U), so "Imperium" is written IMPERIVM.

const FONT: Font = preload("res://assets/fonts/Cinzel.ttf")


static func t(s: String) -> String:
	return s.to_upper().replace("U", "V")
