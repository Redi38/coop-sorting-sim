class_name ItemCatalog
extends RefCounted
## res://data/item_catalog.gd
##
## Single source of truth for the sorting puzzle (DESIGN.md, "Matching by
## type"): which types exist, what each looks like, what its shelf sign
## says, and the pools that item names and descriptions are built from.
##
## Colour is decoration, never the answer: items get a random tint from
## TINT_PALETTE that has nothing to do with their type. What tells you the
## type is
##   * shape  — each type has its own model family (some have several:
##              a crystal can be an orb *or* a cluster), and
##   * words  — the name, and a description that always carries a hint
##              of what the object is ("rolled", "bound", "a sip").
## The shelf sign shows the type's name, a one-line rule, and small brass
## statuettes of each of its shapes.


class Variant:
	var model_path: String   # model scene, pivot at the base (assets/models/)
	var size: Vector3        # collision box resting on the base, before per-item scale

	func _init(p_model_path: String, p_size: Vector3) -> void:
		model_path = p_model_path
		size = p_size


class Category:
	var id: String
	var display_name: String
	var sign_text: String
	var variants: Array[Variant]

	func _init(p_id: String, p_display_name: String, p_sign_text: String, p_variants: Array[Variant]) -> void:
		id = p_id
		display_name = p_display_name
		sign_text = p_sign_text
		variants = p_variants


const M := "res://assets/models/"

static var _categories: Array[Category] = [
	Category.new("potion", "Potions", "brews and draughts, meant to be drunk", [
		Variant.new(M + "potion_flask.tscn", Vector3(0.21, 0.31, 0.21)),
		Variant.new(M + "potion_vial.tscn", Vector3(0.09, 0.29, 0.09)),
	]),
	Category.new("tome", "Tomes", "bound books of every kind", [
		Variant.new(M + "tome.tscn", Vector3(0.27, 0.08, 0.2)),
	]),
	Category.new("scroll", "Scrolls", "rolled writings, sealed or tied", [
		Variant.new(M + "scroll.tscn", Vector3(0.32, 0.09, 0.1)),
	]),
	Category.new("crystal", "Crystals", "gems, orbs and grown stone", [
		Variant.new(M + "crystal_orb.tscn", Vector3(0.22, 0.26, 0.22)),
		Variant.new(M + "crystal_cluster.tscn", Vector3(0.19, 0.21, 0.19)),
	]),
	Category.new("key", "Keys", "for locks, real or imagined", [
		Variant.new(M + "key.tscn", Vector3(0.24, 0.03, 0.12)),
	]),
	Category.new("candle", "Candles", "wax and wick, lit or waiting", [
		Variant.new(M + "candle.tscn", Vector3(0.17, 0.23, 0.15)),
	]),
]

## Jewel tones for item tints. Deliberately shared by every type.
const TINT_PALETTE: Array[Color] = [
	Color(0.3, 0.62, 0.95),   # sapphire
	Color(0.86, 0.6, 0.2),    # amber
	Color(0.68, 0.36, 0.85),  # amethyst
	Color(0.3, 0.72, 0.52),   # jade
	Color(0.86, 0.34, 0.36),  # garnet
	Color(0.93, 0.8, 0.45),   # citrine
	Color(0.38, 0.78, 0.82),  # aquamarine
	Color(0.9, 0.55, 0.7),    # rose quartz
]

# Name pools. An item's name is a qualifier applied to a noun ("%s" is the
# noun), and its description is the noun's line + the qualifier's line.
# The noun line always hints at the type; the qualifier line is flavour.
# Each noun also picks which shape variant the item uses.
# 6 nouns x 6 qualifiers = 36 unique items per type.
static var _pools := {
	"potion": {
		"nouns": [
			["Draught", 0, "A round flask that sloshes when tilted."],
			["Tonic", 1, "A slim vial of something drinkable."],
			["Elixir", 0, "A stoppered flask; the label says \"one sip\"."],
			["Philter", 1, "A thin vial, sealed with red wax."],
			["Brew", 0, "Still faintly warm, like fresh tea."],
			["Tincture", 1, "A few drops go in your tea, apparently."],
		],
		"qualifiers": [
			["Shimmering %s", "Glows softly when shaken."],
			["Murky %s", "Smells of damp cellar stone."],
			["Sunpetal %s", "A faint citrus scent."],
			["%s of Frost", "Cold enough to fog the glass."],
			["Nightbloom %s", "Only glows after dark."],
			["Whispering %s", "Hums a low note when uncorked."],
		],
	},
	"tome": {
		"nouns": [
			["Grimoire", 0, "Heavy covers and a stitched spine."],
			["Almanac", 0, "Bound pages of seasons and tides."],
			["Ledger", 0, "A bound record in tiny columns."],
			["Codex", 0, "Leather-bound, with a brass clasp."],
			["Journal", 0, "Someone's bound diary, well thumbed."],
			["Primer", 0, "A small bound book for beginners."],
		],
		"qualifiers": [
			["%s of Embers", "The page edges are sooty."],
			["Waterlogged %s", "The ink has bled into blue rings."],
			["Star-Chart %s", "Its cover is etched with constellations."],
			["Moth-Eaten %s", "Half the pages are missing."],
			["Silverleaf %s", "Pressed flowers hide between the pages."],
			["Iron-Bound %s", "Clasped shut with a rusted lock."],
		],
	},
	"scroll": {
		"nouns": [
			["Scroll", 0, "Rolled parchment, tied with a ribbon."],
			["Decree", 0, "A rolled proclamation with a wax seal."],
			["Map", 0, "Rolled tight; a coastline peeks out."],
			["Letter", 0, "A rolled note, sealed and never opened."],
			["Chart", 0, "A long roll of careful diagrams."],
			["Recipe", 0, "Rolled up and tied; smells of spices."],
		],
		"qualifiers": [
			["Ancient %s", "The parchment crackles."],
			["Royal %s", "The seal shows a crowned owl."],
			["Faded %s", "The ink has gone pale brown."],
			["Secret %s", "Tied twice, as if to keep it closed."],
			["%s of the Tides", "Smells faintly of the sea."],
			["Scorched %s", "One end is singed."],
		],
	},
	"crystal": {
		"nouns": [
			["Orb", 0, "A polished sphere on a brass stand."],
			["Geode", 1, "Crystals grown out of a lump of rock."],
			["Seer-Stone", 0, "A crystal ball, clear as water."],
			["Shard", 1, "Sharp points of grown crystal."],
			["Glowglobe", 0, "A crystal ball holding a soft light."],
			["Druse", 1, "A crust of tiny crystals on stone."],
		],
		"qualifiers": [
			["Cracked %s", "A hairline fracture runs through it."],
			["Singing %s", "Rings like a bell when tapped."],
			["Cloudy %s", "Mist swirls slowly inside."],
			["Dawn %s", "Warmest in morning light."],
			["%s of Echoes", "Hold it close and you hear footsteps."],
			["Dreaming %s", "Feels warmer when you're sleepy."],
		],
	},
	"key": {
		"nouns": [
			["Key", 0, "An old key with a looped bow."],
			["Skeleton Key", 0, "Long shaft, simple teeth; opens many locks."],
			["Latchkey", 0, "A small key for a front door."],
			["Vault Key", 0, "Heavy, with deep-cut teeth."],
			["Chest Key", 0, "Sized for a traveller's trunk lock."],
			["Gate Key", 0, "Made for a lock you'd need both hands for."],
		],
		"qualifiers": [
			["Rusted %s", "No lock in the archive seems to fit it."],
			["Silver %s", "Polished bright by many pockets."],
			["Lost %s", "A tag reads: \"if found, return to the archive\"."],
			["Whistling %s", "Blow through the bow and it whistles."],
			["%s of Nine Doors", "Nine notches are filed into the shaft."],
			["Dreamer's %s", "Only opens doors you imagine."],
		],
	},
	"candle": {
		"nouns": [
			["Candle", 0, "Wax and wick in a brass dish."],
			["Taper", 0, "A tall wax candle, barely burned."],
			["Nightlight", 0, "A stubby candle for a bedside table."],
			["Vigil Candle", 0, "Burns steady through the night."],
			["Chamberstick", 0, "A candle in a brass holder with a ring."],
			["Rushlight", 0, "A simple candle of rolled wax."],
		],
		"qualifiers": [
			["Honey %s", "Smells of beeswax and summer."],
			["Everburning %s", "It has never once gone out."],
			["Lavender %s", "Scented to help you sleep."],
			["Midnight %s", "Its flame leans toward the moon."],
			["%s of Remembering", "Lighting it brings back a memory."],
			["Crooked %s", "Bent, but it still stands."],
		],
	},
}


static func get_categories() -> Array[Category]:
	return _categories


static func get_category(id: String) -> Category:
	for c in _categories:
		if c.id == id:
			return c
	return null


static func get_variant(category_id: String, variant_index: int) -> Variant:
	var cat := get_category(category_id)
	if cat == null or cat.variants.is_empty():
		return null
	return cat.variants[clampi(variant_index, 0, cat.variants.size() - 1)]


## Returns `count` item definitions (id/category/name/description/variant),
## spread evenly across types. Names are unique within a round and shuffled
## differently every round (host only calls this; clients receive the
## results through the item's spawn sync). If `count` exceeds a type's
## unique combinations, names repeat with a roman numeral ("… II").
static func get_item_templates(count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var per_category := int(ceil(float(count) / _categories.size()))
	for category in _categories:
		var pool: Dictionary = _pools[category.id]
		# Deal combos round-robin across nouns (each noun's qualifiers
		# shuffled, noun order shuffled) so even a small solo archive gets
		# every noun — and therefore every shape — of each type.
		var by_noun: Array = []
		for noun in pool["nouns"]:
			var group: Array = []
			for qual in pool["qualifiers"]:
				group.append([noun, qual])
			group.shuffle()
			by_noun.append(group)
		by_noun.shuffle()
		var combos: Array = []
		for k in pool["qualifiers"].size():
			for group in by_noun:
				combos.append(group[k])
		for i in per_category:
			if result.size() >= count:
				break
			var combo: Array = combos[i % combos.size()]
			var noun: Array = combo[0]
			var qual: Array = combo[1]
			var repeat := i / combos.size()
			var suffix: String = "" if repeat == 0 else " " + ["II", "III", "IV", "V"][mini(repeat - 1, 3)]
			result.append({
				"id": "%s_%02d" % [category.id, i],
				"category": category.id,
				"name": (qual[0] % noun[0]) + suffix,
				"description": noun[2] + " " + qual[1],
				"variant": noun[1],
			})
	return result


## Deterministic per-item look from a seed, so every peer draws the same
## tint and size from one synced int.
static func look_for_seed(look_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = look_seed
	var tint: Color = TINT_PALETTE[rng.randi() % TINT_PALETTE.size()]
	tint = tint.lightened(rng.randf_range(-0.08, 0.1))
	return {"tint": tint, "scale": rng.randf_range(0.9, 1.12)}
