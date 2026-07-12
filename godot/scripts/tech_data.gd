class_name TechData
extends RefCounted
## Loader for the shared world data: data/tech_tree.json (the full DAG) and
## data/era1_content.json (resources, recipes, foods, needs tuning).
## Godot executes recipes; Cortex decides which to run. Same files, two readers.

var nodes := {}       # tech id -> node dict
var recipes := {}     # recipe id -> {tech, inputs, tools, outputs, seconds, verb, label}
var resources := {}   # resource type -> {label, yields, gather_seconds, respawns, ...}
var items := {}       # item id -> {label, food?, tool?}
var needs_cfg := {}
var stations := {}    # station id -> {fuel_start, warmth_radius, ...}
var buildables := {}  # structure id -> {label, warmth_radius, model_height, ...}
var predators := {}   # predator id -> {count, threat_radius, bite_damage, ...}
var time_cfg := {}    # {day_seconds_default, night_fraction, days_per_season, seasons}
var lifecycle := {}   # {years_per_day, adult_age, lifespan_mean, birth_chance_per_dawn, ...}
var storage_cfg := {} # {vermin_raid_chance_per_dawn, vermin_loss_fraction, withdraw_amount}
var ok := false


static func load_data() -> TechData:
	var td := TechData.new()
	var root := ProjectSettings.globalize_path("res://")
	var tree: Variant = _read_json(root.path_join("../data/tech_tree.json"))
	var content: Variant = _read_json(root.path_join("../data/era1_content.json"))
	if tree == null or content == null:
		push_error("[TechData] missing data/tech_tree.json or data/era1_content.json")
		return td
	for n in tree.get("nodes", []):
		td.nodes[n["id"]] = n
	td.recipes = content.get("recipes", {})
	td.resources = content.get("resources", {})
	td.items = content.get("items", {})
	td.needs_cfg = content.get("needs", {})
	td.stations = content.get("stations", {})
	td.buildables = content.get("buildables", {})
	td.predators = content.get("predators", {})
	td.time_cfg = content.get("time", {})
	td.lifecycle = content.get("lifecycle", {})
	td.storage_cfg = content.get("storage", {})
	for rid in td.recipes:
		var tech_id: String = td.recipes[rid].get("tech", "")
		if tech_id != "" and not td.nodes.has(tech_id):
			push_error("[TechData] recipe %s references unknown tech %s" % [rid, tech_id])
			return td
	td.ok = true
	return td


static func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


func item_label(item: String) -> String:
	return items.get(item, {}).get("label", item)


func is_food(item: String) -> bool:
	return items.get(item, {}).has("food")


func food_hunger_value(item: String) -> float:
	return float(items.get(item, {}).get("food", {}).get("hunger", 0))


func recipe_status(recipe: Dictionary, inventory: Dictionary) -> Dictionary:
	## What is missing to run this recipe with the given inventory.
	var missing := {}
	var inputs: Dictionary = recipe.get("inputs", {})
	for item in inputs:
		var short: int = int(inputs[item]) - int(inventory.get(item, 0))
		if short > 0:
			missing[item] = short
	for tool in recipe.get("tools", []):
		if int(inventory.get(tool, 0)) < 1:
			missing[tool] = 1
	return {"ready": missing.is_empty(), "missing": missing}


func apply_recipe(recipe: Dictionary, inventory: Dictionary) -> void:
	## Consume inputs, add outputs. Caller must have checked recipe_status.
	var inputs: Dictionary = recipe.get("inputs", {})
	for item in inputs:
		inventory[item] = int(inventory.get(item, 0)) - int(inputs[item])
		if inventory[item] <= 0:
			inventory.erase(item)
	var outputs: Dictionary = recipe.get("outputs", {})
	for item in outputs:
		inventory[item] = int(inventory.get(item, 0)) + int(outputs[item])


func resource_yielding(item: String) -> String:
	for rtype in resources:
		if resources[rtype].get("yields", {}).has(item):
			return rtype
	return ""
