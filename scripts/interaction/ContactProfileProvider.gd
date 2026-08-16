class_name ContactProfileProvider
extends Node
## 给可触碰对象或部件提供触碰属性。
## 查找时从命中节点开始，优先使用最近部件的 provider，再逐级回溯父节点。

const CONTACT_PROFILE_SCRIPT := preload("res://scripts/core/ContactProfile.gd")
const DEFAULT_PROFILE: Resource = preload("res://assets/contact_profiles/default_contact.tres")
const ASPHALT_PROFILE: Resource = preload("res://assets/contact_profiles/asphalt.tres")
const CONCRETE_PROFILE: Resource = preload("res://assets/contact_profiles/concrete.tres")
const GLASS_PROFILE: Resource = preload("res://assets/contact_profiles/glass.tres")
const METAL_PROFILE: Resource = preload("res://assets/contact_profiles/metal_pole.tres")
const PAVEMENT_PROFILE: Resource = preload("res://assets/contact_profiles/pavement.tres")
const PLASTIC_PROFILE: Resource = preload("res://assets/contact_profiles/plastic.tres")
const WOOD_PROFILE: Resource = preload("res://assets/contact_profiles/wood_or_shelf.tres")

@export var profile: Resource:
	set(value):
		profile = value
		if profile and profile.get_script() != CONTACT_PROFILE_SCRIPT:
			push_warning("ContactProfileProvider: profile should use ContactProfile.gd")

static var _warned_missing: Dictionary = {}


static func resolve_profile(collider: Object, source: StringName = &"unknown") -> Resource:
	var node := collider as Node
	while node:
		var provider := _find_provider_on(node)
		if provider and provider.profile:
			return provider.profile
		node = node.get_parent()

	var inferred_profile := _infer_profile(collider)
	if inferred_profile:
		return inferred_profile

	# 脚底显影会持续自动查询地面；缺失属性仍使用默认值，但不为每块地面刷调试日志。
	if GameConfig.DEBUG and source != &"foot":
		var key := _object_path(collider)
		if not _warned_missing.has(key):
			_warned_missing[key] = true
			print("[DEBUG][ContactProfile] missing profile collider=%s using=%s" % [
				key,
				profile_id(DEFAULT_PROFILE),
			])
	return DEFAULT_PROFILE


static func _infer_profile(collider: Object) -> Resource:
	var node := collider as Node
	if not node:
		return null

	var semantic_tokens := [str(node.name).to_lower()]
	var ancestor := node.get_parent()
	while ancestor:
		semantic_tokens.append(str(ancestor.name).to_lower())
		ancestor = ancestor.get_parent()
	var semantic := " ".join(semantic_tokens)

	if _contains_any(semantic, ["tactile", "blindway", "pavement"]):
		return PAVEMENT_PROFILE
	if _contains_any(semantic, ["glass", "window"]):
		return GLASS_PROFILE
	if _contains_any(semantic, ["car", "vehicle", "bike", "motorcycle", "fence", "trafficlight", "hydrant", "manhole", "metal"]):
		return METAL_PROFILE
	if _contains_any(semantic, ["road", "asphalt", "street"]):
		return ASPHALT_PROFILE
	if _contains_any(semantic, ["box", "dumpster", "trash", "clutter", "bush", "plastic"]):
		return PLASTIC_PROFILE
	if _contains_any(semantic, ["door", "wardrobe", "desk", "chair", "table", "bed", "sofa", "shelf", "wood"]):
		return WOOD_PROFILE
	if _contains_any(semantic, ["ground", "floor", "wall", "building", "stair", "concrete", "department", "shop"]):
		return CONCRETE_PROFILE

	# Keep unknown third-party model nodes on the existing default path.
	return null


static func _contains_any(value: String, tokens: Array[String]) -> bool:
	for token in tokens:
		if value.contains(token):
			return true
	return false


static func profile_id(resolved_profile: Resource) -> StringName:
	if not resolved_profile:
		return &"default_contact"
	return resolved_profile.get("id") as StringName


static func reveal_color(resolved_profile: Resource) -> Color:
	if not resolved_profile:
		return Color(0.4, 0.75, 1.0, 1.0)
	return resolved_profile.get("reveal_color") as Color


static func cane_sound_id(resolved_profile: Resource) -> StringName:
	if not resolved_profile:
		return &"cane_tap_default"
	return resolved_profile.get("cane_sound_id") as StringName


static func step_sound_id(resolved_profile: Resource) -> StringName:
	if not resolved_profile:
		return &"step"
	var sid: StringName = resolved_profile.get("step_sound_id") as StringName
	if sid != &"":
		return sid
	return &"step"


static func _find_provider_on(node: Node) -> ContactProfileProvider:
	var found_provider: ContactProfileProvider = null
	for child in node.get_children():
		if child is ContactProfileProvider:
			if found_provider and GameConfig.DEBUG:
				print("[DEBUG][ContactProfile] multiple providers node=%s using=%s ignored=%s" % [
					node.get_path(),
					found_provider.get_path(),
					(child as Node).get_path(),
				])
			if not found_provider:
				found_provider = child as ContactProfileProvider
	return found_provider


static func _object_path(object: Object) -> String:
	if object is Node:
		return str((object as Node).get_path())
	if object:
		return object.get_class()
	return "<none>"
