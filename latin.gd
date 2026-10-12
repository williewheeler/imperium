class_name Latin
extends RefCounted
## Roman inscription lettering: capitals only, and V stands for both U and V
## (the Latin alphabet had no separate U), so "Imperium" is written IMPERIVM.

const FONT: Font = preload("res://assets/fonts/Cinzel.ttf")


## English meaning of each Latin sentence the game shows, for hover tooltips.
const GLOSS := {
	"Elige colonos et aedifica forum.": "Select villagers and build a Town Center.",
	"Terra incognita.": "Unknown land: you can't build on unexplored ground.",
	"Locus liber et planus requiritur.": "A clear, level site is required (open grassland).",
	"Coloni impediunt.": "Villagers are in the way.",
	"Copiae non sufficiunt.": "Not enough resources.",
	"Iter nullum est.": "There is no route there.",
	"Elige colonos et iube eos laborare.": "Select villagers and order them to work: right-click a tree, berry bush or mine.",
	"Domus plures requiruntur.": "Population limit reached: build more Houses.",
	"Aedifica forum vel horreum.": "Build a Town Center or Storehouse to drop off resources.",
}


static func gloss(s: String) -> String:
	return GLOSS.get(s, "")


static func t(s: String) -> String:
	return s.to_upper().replace("U", "V")
