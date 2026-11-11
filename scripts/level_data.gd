## Editable data for the one prototype level.
## EDIT THIS FILE to change the starting board and the refill batches.
## Fruit IDs: "apple", "orange", "banana" (see fruit_data.gd).
## The level holds exactly 12 trios (36 fruits, 12 of each type); 3 plates
## start empty for sorting, and plate 0 plus plate 3 form an easy opening
## apple match.
class_name LevelData
extends RefCounted

## Number of trios the player must clear to finish the level.
const TOTAL_TRIOS := 12

## Starting fruits per plate (plates 0..8, up to three fruits each).
const STARTING_CONTENTS := [
	["apple", "apple"],
	["orange", "orange"],
	["banana", "banana"],
	["apple"],
	["orange"],
	["banana"],
	[],
	[],
	[],
]

## Refill batches per plate, in queue order. The first pending batch is the
## one previewed below the plate and is loaded onto it after it clears a
## trio. A plate with an empty list stays empty after clearing. Batches hold
## one to three fruits.
const RESERVE_BATCHES := [
	[["banana", "orange", "banana"], ["apple", "apple", "apple"]],
	[["banana", "apple", "banana"], ["orange", "banana", "orange"]],
	[["apple", "orange", "apple"], ["orange", "banana", "banana"]],
	[["orange", "banana", "orange"]],
	[["apple", "banana", "apple"]],
	[["orange", "apple", "orange"]],
	[],
	[],
	[],
]
