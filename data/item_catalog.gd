class_name ItemCatalog
extends RefCounted
## res://data/item_catalog.gd
##
## Single source of truth for the sorting clue data: what categories exist,
## what color/label represents each one (the "visual clue"), and the pool
## of item name/description templates (the "textual clue") players read to
## figure out where something belongs.
##
## World.gd spawns items by pulling from get_item_templates(); Item.gd and
## ShelfSlot.gd both call get_category() so the color a player sees on an
## item always matches the color on the slot it belongs in.

class Category:
	var id: String
	var display_name: String
	var color: Color

	func _init(p_id: String, p_display_name: String, p_color: Color) -> void:
		id = p_id
		display_name = p_display_name
		color = p_color


static var _categories: Array[Category] = [
	Category.new("potion", "Potion", Color(0.25, 0.55, 0.95)),
	Category.new("tome", "Tome", Color(0.85, 0.65, 0.15)),
	Category.new("artifact", "Artifact", Color(0.6, 0.25, 0.75)),
]

# Hand-authored clue templates — real display names + short descriptions,
# grouped by category. This is the part to keep growing toward the spec's
# 150-300 items; get_item_templates() below cycles + numbers these to reach
# whatever target count World.gd asks for, so the pool doesn't need 300
# hand-written entries to test the loop at scale.
static var _templates := {
	"potion": [
		{"name": "Shimmering Elixir", "desc": "Glows faintly blue when shaken."},
		{"name": "Murky Draught", "desc": "Smells of damp cellar stone."},
		{"name": "Sunpetal Tonic", "desc": "Warm to the touch, faint citrus scent."},
		{"name": "Frostbite Brew", "desc": "Cold enough to fog the glass."},
		{"name": "Whispering Tincture", "desc": "Hums a low note when uncorked."},
		{"name": "Ashwood Serum", "desc": "Tinted the color of burnt oak."},
		{"name": "Nightbloom Potion", "desc": "Only glows after dark."},
		{"name": "Ember Flask", "desc": "Faint warmth radiates from the cork."},
	],
	"tome": [
		{"name": "Tome of Embers", "desc": "Pages edged with soot."},
		{"name": "Waterlogged Journal", "desc": "Ink bled into faint blue rings."},
		{"name": "Cracked Grimoire", "desc": "Spine held together with twine."},
		{"name": "Star-Chart Codex", "desc": "Cover etched with constellations."},
		{"name": "Moth-Eaten Ledger", "desc": "Half the pages are missing."},
		{"name": "Silverleaf Almanac", "desc": "Smells faintly of pressed flowers."},
		{"name": "Iron-Bound Folio", "desc": "Clasped shut with a rusted lock."},
		{"name": "Whispering Primer", "desc": "Margins full of cramped handwriting."},
	],
	"artifact": [
		{"name": "Cracked Orb", "desc": "A hairline fracture runs through its core."},
		{"name": "Tarnished Compass", "desc": "Needle spins without settling."},
		{"name": "Woven Talisman", "desc": "Threads knotted in an old pattern."},
		{"name": "Chipped Hourglass", "desc": "Sand trickles slower than it should."},
		{"name": "Rusted Key", "desc": "No lock in the archive seems to fit it."},
		{"name": "Carved Bone Charm", "desc": "Etched with symbols worn smooth."},
		{"name": "Dented Medallion", "desc": "Bears a crest no one recognizes."},
		{"name": "Faded Seal-Stone", "desc": "Once stamped official archive documents."},
	],
}


static func get_categories() -> Array[Category]:
	return _categories


static func get_category(id: String) -> Category:
	for c in _categories:
		if c.id == id:
			return c
	return null


## Returns `count` item definitions (id/category/name/description),
## spread evenly across categories, cycling each category's templates and
## numbering repeats ("Shimmering Elixir (Batch 2)") once `count` exceeds
## the hand-authored pool. Deterministic pass order, but World.gd is free
## to scatter/shuffle spawn positions itself.
static func get_item_templates(count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var per_category := int(ceil(float(count) / _categories.size()))
	for category in _categories:
		var pool: Array = _templates[category.id]
		for i in per_category:
			if result.size() >= count:
				break
			var template: Dictionary = pool[i % pool.size()]
			var batch := (i / pool.size()) + 1
			var suffix := "" if batch == 1 else " (Batch %d)" % batch
			result.append({
				"id": "%s_%02d" % [category.id, i],
				"category": category.id,
				"name": template["name"] + suffix,
				"description": template["desc"],
			})
	return result
