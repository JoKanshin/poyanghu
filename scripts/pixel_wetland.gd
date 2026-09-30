extends Control
## North-up terrain map, with read-only projections of the live ecology state.
## All decorative placement is deterministic; never consume gameplay RNG.
const LANDSCAPE := preload("res://assets/art/poyang-terrain-base.png")
const LAND_COLOR := Color("829666")
const MAP_ZOOM := 1.58
const CREEPER_ART := preload("res://assets/creeper.png")
const CREEPER_ANCHOR := Vector2(0.22, 0.27)
const HOUSE_ART := [
	preload("res://assets/houses/house1.png"),
	preload("res://assets/houses/house2.png"),
	preload("res://assets/houses/house3.png"),
	preload("res://assets/houses/house4.png"),
]
const SPRITES := preload("res://assets/art/wetland-sprites.png")
const BIRDS := preload("res://assets/art/wetland-birds.png")
const BIRD_ACTIONS := preload("res://assets/art/bird-actions.png")
const FLOATING_ISLAND := preload("res://assets/art/floating-island.png")
const SHORE_TREE := preload("res://assets/art/shore-tree.png")
const SPECIES_ART := {"baihe": 0, "dongfangbaihuan": 1, "xiaotiane": 2, "baizhenhe": 3, "yanlei": 4}
# Fixed habitat anchors sampled against the terrain palette; no gameplay RNG.
const WATER_ANCHORS: Array[Vector2] = [
	Vector2(0.36, 0.50), Vector2(0.40, 0.50), Vector2(0.43, 0.51),
	Vector2(0.36, 0.55), Vector2(0.40, 0.55), Vector2(0.44, 0.55),
	Vector2(0.36, 0.60), Vector2(0.40, 0.60), Vector2(0.42, 0.63),
	Vector2(0.37, 0.66), Vector2(0.35, 0.70), Vector2(0.37, 0.73),
]
const ISLAND_ANCHORS: Array[Vector2] = [
	Vector2(0.38, 0.54), Vector2(0.40, 0.59), Vector2(0.39, 0.64),
	Vector2(0.38, 0.68), Vector2(0.35, 0.73), Vector2(0.41, 0.54),
]
const SHORE_ANCHORS: Array[Vector2] = [
	Vector2(0.304688, 0.500000), Vector2(0.301758, 0.549805),
	Vector2(0.309570, 0.599609), Vector2(0.320312, 0.650391),
	Vector2(0.309570, 0.700195), Vector2(0.291992, 0.750000),
	Vector2(0.268555, 0.790039), Vector2(0.351563, 0.792969),
	Vector2(0.408204, 0.732422), Vector2(0.451172, 0.650391),
	Vector2(0.450195, 0.596680), Vector2(0.495117, 0.621094),
	Vector2(0.545898, 0.634766), Vector2(0.628907, 0.611329),
	Vector2(0.629883, 0.660156), Vector2(0.691407, 0.700195),
	Vector2(0.636719, 0.761719), Vector2(0.528320, 0.783203),
	Vector2(0.480469, 0.860352), Vector2(0.472656, 0.900391),
]
const HOUSE_RING_TARGETS: Array[Vector2] = [
	Vector2(0.35, 0.25), Vector2(0.43, 0.31), Vector2(0.51, 0.36),
	Vector2(0.60, 0.41), Vector2(0.71, 0.45), Vector2(0.78, 0.51),
	Vector2(0.79, 0.60), Vector2(0.73, 0.69), Vector2(0.65, 0.77),
	Vector2(0.55, 0.79), Vector2(0.44, 0.80), Vector2(0.35, 0.77),
	Vector2(0.29, 0.70), Vector2(0.28, 0.60), Vector2(0.28, 0.49),
	Vector2(0.30, 0.38),
]
const EDGE_TREE_TARGETS: Array[Vector2] = [
	Vector2(0.15, 0.22), Vector2(0.19, 0.67), Vector2(0.24, 0.79),
	Vector2(0.71, 0.25), Vector2(0.81, 0.34), Vector2(0.87, 0.72),
	Vector2(0.75, 0.79), Vector2(0.59, 0.18),
]
const BOAT_ANCHOR := Vector2(0.40, 0.57)
var bird_sprites: Array[AtlasTexture] = []
var sprites: Array[AtlasTexture] = []
var metrics: Dictionary = {}
var populations: Dictionary = {}
var plants: Dictionary = {}
var islands := 0
var settlement := 50.0
var season := 0
var elapsed := 0.0
var clock_accum := 0.0
var backdrop: TextureRect
var creeper_rect: TextureRect
var water_material: ShaderMaterial
var reduced_motion := false
var terrain_image: Image
var visual_rng := RandomNumberGenerator.new()
var easter_rng := RandomNumberGenerator.new()
var visual_seed := -1
var plant_sites: Dictionary = {}
var bird_agents: Array[Dictionary] = []
var house_sites: Array[Vector2] = []
var house_progress: Array[float] = []
var house_target_count := 0

func _ready() -> void:
	for i in 8:
		var atlas := AtlasTexture.new()
		atlas.atlas = SPRITES
		atlas.region = Rect2((i % 4) * 384, floori(float(i) / 4.0) * 512, 384, 512)
		atlas.filter_clip = true
		sprites.append(atlas)
	for i in 6:
		var atlas := AtlasTexture.new()
		atlas.atlas = BIRDS
		atlas.region = Rect2((i % 3) * 512, floori(float(i) / 3.0) * 512, 512, 512)
		atlas.filter_clip = true
		bird_sprites.append(atlas)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	terrain_image = LANDSCAPE.get_image()
	_make_house_sites()
	easter_rng.randomize()
	var land_margin := ColorRect.new()
	land_margin.name = "LandMargin"
	land_margin.color = LAND_COLOR
	land_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	land_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(land_margin)
	backdrop = TextureRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	backdrop.texture = LANDSCAPE
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
uniform float quality = 0.65;
uniform float level = 0.5;
uniform float vegetation = 0.5;
uniform vec4 season_tint : source_color = vec4(1.0);
void fragment() {
 // COLOR includes the texture, or the flat ColorRect color for land margins.
 vec4 original = COLOR;
 float water = smoothstep(0.04, 0.18, original.b - original.r) * smoothstep(0.04, 0.16, original.g - original.r);
 vec4 col = original;
 col.rgb = mix(col.rgb, col.rgb * vec3(0.85, 0.89, 0.58), water * (1.0 - quality) * 0.55);
 float shallows = water * smoothstep(0.42, 0.80, original.g);
 col.rgb = mix(col.rgb, vec3(0.69, 0.65, 0.42), shallows * (1.0 - level) * 0.55);
 float foliage = smoothstep(0.03, 0.17, original.g - original.b) * (1.0-water);
 col.rgb = mix(col.rgb, col.rgb * vec3(1.12, 0.88, 0.70), foliage * (1.0-vegetation) * 0.65);
 COLOR = col * season_tint;
}"""
	water_material = ShaderMaterial.new()
	water_material.shader = shader
	# Share the same ecology and season tint across map land and empty margins.
	land_margin.material = water_material
	backdrop.material = water_material
	add_child(backdrop)
	_layout_map()
	creeper_rect = TextureRect.new()
	creeper_rect.texture = CREEPER_ART
	creeper_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	creeper_rect.stretch_mode = TextureRect.STRETCH_SCALE
	creeper_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	creeper_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	creeper_rect.visible = false
	var creeper_shader := Shader.new()
	creeper_shader.code = "shader_type canvas_item; void fragment() { vec4 pixel = texture(TEXTURE, UV); if (pixel.g > 0.63 && pixel.g > pixel.r * 1.08 && pixel.r > 0.48) discard; COLOR = pixel; }"
	var creeper_material := ShaderMaterial.new()
	creeper_material.shader = creeper_shader
	creeper_rect.material = creeper_material
	add_child(creeper_rect)
	_layout_map()
	# Wildlife stays separate from the terrain-only texture.
	var wildlife := Control.new()
	wildlife.name = "Wildlife"
	wildlife.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wildlife.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wildlife.draw.connect(_draw_wildlife.bind(wildlife))
	add_child(wildlife)
	resized.connect(_layout_map)
	resized.connect(func(): wildlife.queue_redraw())
	sync_state()

func _layout_map() -> void:
	var scale := minf(size.x / LANDSCAPE.get_width(), size.y / LANDSCAPE.get_height()) * MAP_ZOOM
	var extent := Vector2(LANDSCAPE.get_size()) * scale
	backdrop.position = ((size - extent) * 0.5).round()
	backdrop.size = extent.round()
	if creeper_rect:
		creeper_rect.size = Vector2(62, 38)
		creeper_rect.position = _point(CREEPER_ANCHOR) - creeper_rect.size * 0.5

func roll_creeper_visibility() -> void:
	if creeper_rect:
		creeper_rect.visible = easter_rng.randf() < 0.1

func sync_state() -> void:
	metrics = GameState.metrics.duplicate()
	populations = GameState.species_pop.duplicate()
	plants = GameState.plant_pop.duplicate()
	islands = GameState.floating_islands
	settlement = GameState.settlement
	season = maxi(0, GameState.SEASONS.find(GameState.current_season()))
	if visual_seed != GameState.run_seed:
		_reset_scenery()
	sync_settlement_targets()
	if water_material:
		water_material.set_shader_parameter("quality", float(metrics.get("water_quality", 65)) / 100.0)
		water_material.set_shader_parameter("vegetation", float(metrics.get("vegetation", 50)) / 100.0)
		water_material.set_shader_parameter("level", float(metrics.get("water_level", 50)) / 100.0)
		var tints := [Color.WHITE, Color(1.03, 1.02, 0.96), Color(1.06, 0.94, 0.80), Color(0.87, 0.95, 1.05)]
		water_material.set_shader_parameter("season_tint", tints[season])

func _process(delta: float) -> void:
	if not reduced_motion:
		elapsed += delta
		_process_birds(delta)
	for i in house_progress.size():
		var target := 1.0 if i < house_target_count else 0.0
		house_progress[i] = target if reduced_motion else move_toward(house_progress[i], target, delta * (1.8 if target > house_progress[i] else 2.2))
	clock_accum += delta
	if clock_accum < 1.0 / 24.0: return
	clock_accum = 0.0
	get_node("Wildlife").queue_redraw()

func _point(uv: Vector2) -> Vector2:
	# Keep habitat markers aligned with the enlarged terrain at every window size.
	return (backdrop.position + uv * backdrop.size).round()

func _terrain_color(uv: Vector2) -> Color:
	var x := clampi(int(uv.x * terrain_image.get_width()), 0, terrain_image.get_width() - 1)
	var y := clampi(int(uv.y * terrain_image.get_height()), 0, terrain_image.get_height() - 1)
	return terrain_image.get_pixel(x, y)

func _is_water(uv: Vector2) -> bool:
	var color := _terrain_color(uv)
	return color.b > color.g and color.g > color.r

func _is_shore(uv: Vector2) -> bool:
	var color := _terrain_color(uv)
	return color.r > 0.7 and color.r > color.g and color.g > color.b

func _is_land(uv: Vector2) -> bool:
	var color := _terrain_color(uv)
	return color.g > color.r and color.r > color.b

func _near_water(uv: Vector2) -> bool:
	for offset in [Vector2(0.025, 0), Vector2(-0.025, 0), Vector2(0, 0.025), Vector2(0, -0.025),
			Vector2(0.038, 0.015), Vector2(-0.038, -0.015)]:
		if _is_water(uv + offset):
			return true
	return false

func _make_house_sites() -> void:
	# Sample land immediately beside water, then pick evenly spaced points all
	# around the actual shoreline. The choice is map-dependent, not RNG-dependent.
	var candidates: Array[Vector2] = []
	for y in range(20, 82):
		for x in range(23, 83):
			var uv := Vector2(float(x) / 100.0, float(y) / 100.0)
			if _is_land(uv) and _near_water(uv) and uv.distance_to(CREEPER_ANCHOR) > 0.11:
				candidates.append(uv)
	house_sites.clear()
	for target in HOUSE_RING_TARGETS:
		var nearest := Vector2(-1, -1)
		var best := INF
		for candidate in candidates:
			if candidate.distance_to(target) >= best:
				continue
			var clear := true
			for existing in house_sites:
				if candidate.distance_to(existing) < 0.053:
					clear = false
					break
			if clear:
				best = candidate.distance_to(target)
				nearest = candidate
		if nearest.x >= 0.0:
			house_sites.append(nearest)
	# Alternate sectors when settlement grows, so the first homes already
	# form a visible ring instead of filling one side of the lake first.
	var clockwise_sites := house_sites.duplicate()
	house_sites.clear()
	for index in [0, 8, 4, 12, 2, 10, 6, 14, 1, 9, 5, 13, 3, 11, 7, 15]:
		if index < clockwise_sites.size():
			house_sites.append(clockwise_sites[index])
	house_progress.resize(house_sites.size())

func sync_settlement_targets() -> void:
	settlement = GameState.settlement
	house_target_count = clampi(roundi(settlement / 100.0 * float(house_sites.size())), 0, house_sites.size())

func _accept_habitat(kind: String, uv: Vector2) -> bool:
	match kind:
		"bird", "submerged", "floating":
			return _is_water(uv)
		"emergent", "marsh":
			return _is_shore(uv) or (_is_land(uv) and _near_water(uv))
		"tree":
			return _is_land(uv) and _near_water(uv)
	return false

func _scatter_site(kind: String, placed: Array[Vector2]) -> Vector2:
	var zone := Rect2(0.27, 0.20, 0.53, 0.63)
	if kind == "bird" or kind == "floating" or kind == "submerged":
		zone = Rect2(0.30, 0.29, 0.47, 0.52)
	var spacing := 0.029 if kind == "tree" else 0.021
	for attempt in 250:
		var uv := zone.position + Vector2(visual_rng.randf(), visual_rng.randf()) * zone.size
		if not _accept_habitat(kind, uv):
			continue
		var clear := true
		for other in placed:
			if uv.distance_to(other) < spacing:
				clear = false
				break
		if clear:
			return uv
	# The fixed anchors are a fallback if a particular map region is crowded.
	if kind == "tree":
		return Vector2(0.80, 0.55 + 0.018 * placed.size())
	if kind == "bird" or kind == "floating" or kind == "submerged":
		return WATER_ANCHORS[placed.size() % WATER_ANCHORS.size()]
	return SHORE_ANCHORS[placed.size() % SHORE_ANCHORS.size()]

func _reset_scenery() -> void:
	visual_seed = GameState.run_seed
	visual_rng.seed = int(GameState.run_seed) ^ 0x5EED5A7
	for i in house_progress.size():
		house_progress[i] = 1.0 if i < roundi(GameState.settlement / 100.0 * float(house_sites.size())) else 0.0
	plant_sites.clear()
	for pid in GameState.PLANTS:
		var kind: String = GameState.PLANTS[pid]["kind"]
		var sites: Array[Vector2] = []
		for i in 14:
			sites.append(_scatter_site(kind, sites))
		plant_sites[pid] = sites
	bird_agents.clear()
	var homes: Array[Vector2] = []
	for sid in GameState.SPECIES:
		for i in 10:
			var home := _scatter_site("bird", homes)
			homes.append(home)
			bird_agents.append({"sid": sid, "slot": i, "home": home, "pos": home,
				"target": home, "state": 0, "timer": 1.0 + float(i % 5) * 0.6, "angle": 0.0})

func _visible_trees() -> Array:
	var sites: Array = plant_sites.get("chishan", [])
	var count := clampi(int(float(plants.get("chishan", 0)) / 7.0), 0, sites.size())
	return sites.slice(0, count)

func _bird_count(sid: String) -> int:
	return clampi(int(float(populations.get(sid, 0)) / 10.0), 0, 10)

func _choose_bird_state(bird: Dictionary) -> void:
	var roll := visual_rng.randf()
	var trees := _visible_trees()
	var perch_chance := 0.12 + float(metrics.get("vegetation", 50)) / 100.0 * 0.25
	if not trees.is_empty() and roll < perch_chance:
		bird["state"] = 3 # Fly to a visible tree and rest there.
		bird["target"] = trees[visual_rng.randi_range(0, trees.size() - 1)]
	elif roll < 0.45:
		bird["state"] = 0 # Stand in shallow water.
		bird["timer"] = visual_rng.randf_range(1.0, 3.5)
	elif roll < 0.78:
		bird["state"] = 1 # Peck at the water.
		bird["timer"] = visual_rng.randf_range(1.2, 2.6)
	else:
		bird["state"] = 2 # Walk to a nearby water pixel.
		bird["timer"] = visual_rng.randf_range(2.0, 4.5)
		var home: Vector2 = bird["home"]
		bird["target"] = home
		for attempt in 20:
			var candidate := home + Vector2(visual_rng.randf_range(-0.045, 0.045), visual_rng.randf_range(-0.045, 0.045))
			if _is_water(candidate) and _is_water((candidate + bird["pos"]) * 0.5):
				bird["target"] = candidate
				break

func _process_birds(delta: float) -> void:
	for bird in bird_agents:
		if int(bird["slot"]) >= _bird_count(str(bird["sid"])):
			continue
		var state: int = bird["state"]
		var pos: Vector2 = bird["pos"]
		var target: Vector2 = bird["target"]
		if state == 3 or state == 5:
			var to_target := target - pos
			var step := 0.14 * delta
			if to_target.length() <= step:
				bird["pos"] = target
				bird["state"] = 4 if state == 3 else 0
				bird["timer"] = visual_rng.randf_range(6.0, 10.0) if state == 3 else 1.0
			else:
				bird["pos"] = pos + to_target.normalized() * step
				bird["angle"] = to_target.angle()
		elif state == 4:
			bird["timer"] = float(bird["timer"]) - delta
			if bird["timer"] <= 0.0 or _visible_trees().is_empty():
				bird["state"] = 5 # Fly back before walking or pecking again.
				bird["target"] = bird["home"]
		else:
			bird["timer"] = float(bird["timer"]) - delta
			if state == 2:
				var to_target := target - pos
				var step := 0.018 * delta
				if to_target.length() <= step:
					bird["pos"] = target
					bird["state"] = 0
					bird["timer"] = visual_rng.randf_range(1.0, 3.0)
				else:
					bird["pos"] = pos + to_target.normalized() * step
					bird["angle"] = to_target.angle()
			if bird["timer"] <= 0.0:
				_choose_bird_state(bird)

func _px(c: Control, p: Vector2, rect: Rect2, color: Color, scale_px: float = 2.0) -> void:
	c.draw_rect(Rect2(p + rect.position * scale_px, rect.size * scale_px), color)

func _draw_wildlife(c: Control) -> void:
	# Frame the playable shore lightly; keep the secret Creeper's clearing open.
	for uv in EDGE_TREE_TARGETS:
		var clear := uv.distance_to(CREEPER_ANCHOR) > 0.13
		for home in house_sites:
			if uv.distance_to(home) < 0.065:
				clear = false
				break
		if clear and _is_land(uv):
			_draw_tree(c, _point(uv), 0.78)
	# Ripples occupy open water, keeping the HUD readable.
	for i in 28:
		var p := _point(WATER_ANCHORS[i % WATER_ANCHORS.size()])
		var alpha := 0.10 + 0.13 * (sin(elapsed * 1.5 + i * 2.0) + 1.0)
		c.draw_rect(Rect2(p, Vector2(8 + i % 4 * 3, 2)), Color(0.77, 0.94, 0.83, alpha))
	for i in clampi(int(metrics.get("fish", 50)) / 9, 0, 12):
		var p := _point(WATER_ANCHORS[i % WATER_ANCHORS.size()])
		p.x += round(sin(elapsed * 0.35 + i) * 4)
		_draw_sprite(c, p, 3, Vector2(15, 24), Color(0.6, 0.85, 0.8, 0.45))
	# The old scene used plant populations / 7. Keep those visual thresholds and
	# scatter each kind only on its matching terrain color.
	for pid in GameState.PLANTS:
		var sites: Array = plant_sites.get(pid, [])
		var count := mini(int(float(plants.get(pid, 0)) / 7.0), sites.size())
		for i in count:
			var p := _point(sites[i])
			match str(pid):
				"lian":
					c.draw_texture_rect(bird_sprites[5], Rect2(p - Vector2(19, 21), Vector2(38, 38)), false)
				"luwei":
					_draw_sprite(c, p, 4, Vector2(36, 48))
				"chishan":
					_draw_tree(c, p)
				"kucao":
					c.draw_line(p + Vector2(-4, 3), p + Vector2(-1, -4), Color("7aa980"), 2, false)
					c.draw_line(p + Vector2(3, 3), p + Vector2(1, -5), Color("89b68c"), 2, false)
				_:
					_draw_marsh(c, p, str(pid))
	for i in islands:
		var p := _point(ISLAND_ANCHORS[i % ISLAND_ANCHORS.size()])
		p.y += round(sin(elapsed + i) * 1.0)
		c.draw_texture_rect(FLOATING_ISLAND, Rect2((p - Vector2(24, 31)).round(), Vector2(48, 48)), false)
	_draw_houses(c)
	for bird in bird_agents:
		if int(bird["slot"]) < _bird_count(str(bird["sid"])):
			_draw_bird_actor(c, bird)
	var boat_pos := _point(BOAT_ANCHOR)
	boat_pos.x += round(sin(elapsed * 0.06) * 4)
	_draw_sprite(c, boat_pos, 7, Vector2(60, 62))

func _draw_houses(c: Control) -> void:
	var lit := roundi(float(metrics.get("community", 50)) / 100.0 * float(house_target_count))
	for i in house_sites.size():
		var p := _point(house_sites[i])
		var phase: float = house_progress[i]
		if phase <= 0.01:
			_draw_sprite(c, p, 4, Vector2(30, 40))
			continue
		var eased := phase * phase * (3.0 - 2.0 * phase)
		if phase < 0.99:
			# Foundation and scaffold make both construction and wetland retreat legible.
			c.draw_rect(Rect2(p + Vector2(-19, -7), Vector2(38, 8)), Color("6f6949"))
			c.draw_rect(Rect2(p + Vector2(-20, -8), Vector2(3, 19)), Color("bca173"))
			c.draw_rect(Rect2(p + Vector2(17, -8), Vector2(3, 19)), Color("bca173"))
			for dust in 4:
				var offset := Vector2(-23 + dust * 13, -12 - int(elapsed * 15.0 + float(i + dust)) % 8)
				c.draw_rect(Rect2((p + offset).round(), Vector2(3, 3)), Color("e4ce9b"))
		var extent := Vector2(76, 76) * maxf(0.12, eased)
		var tint := Color.WHITE if i < lit else Color(0.66, 0.63, 0.56)
		c.draw_texture_rect(HOUSE_ART[i % HOUSE_ART.size()], Rect2((p - extent * Vector2(0.5, 0.86)).round(), extent.round()), false, tint)
		if phase < 0.22 and i >= house_target_count:
			_draw_sprite(c, p + Vector2(7, 0), 4, Vector2(16, 23))

func _draw_tree(c: Control, p: Vector2, scale_factor: float = 1.0) -> void:
	var extent := Vector2(40, 44) * scale_factor
	c.draw_texture_rect(SHORE_TREE, Rect2((p - extent * Vector2(0.5, 0.9)).round(), extent.round()), false)

func _draw_marsh(c: Control, p: Vector2, pid: String) -> void:
	var color := Color("a8b86a") if pid == "lihao" else Color("81a26d")
	c.draw_rect(Rect2(p + Vector2(-5, -2), Vector2(3, 8)), color)
	c.draw_rect(Rect2(p + Vector2(0, -5), Vector2(3, 10)), color)
	c.draw_rect(Rect2(p + Vector2(5, -1), Vector2(3, 7)), color)

func _draw_sprite(c: Control, p: Vector2, index: int, extent: Vector2, tint: Color = Color.WHITE) -> void:
	c.draw_texture_rect(sprites[index], Rect2((p - extent * Vector2(0.5, 0.85)).round(), extent), false, tint)

func _draw_bird_actor(c: Control, bird: Dictionary) -> void:
	var sprite_index: int = SPECIES_ART.get(str(bird["sid"]), 0)
	var state: int = bird["state"]
	var p := _point(bird["pos"])
	var frame := 0
	var tick := int(elapsed * 7.0 + float(bird["slot"]))
	match state:
		1: frame = 3 + tick % 2 # Peck and lift the head.
		2: frame = 1 + tick % 2 # Alternate feet while walking.
		3, 5: frame = 5 + tick % 3 # Full wingbeat in flight.
		4: frame = 8 # Folded wings while perched.
	if state == 3 or state == 5:
		p.y -= 6.0 + round(sin(elapsed * 13.0) * 2.0)
	elif state == 4:
		p.y -= 5.0 + round(sin(elapsed * 4.0) * 1.0)
	var extent := Vector2(34, 34) if sprite_index != 2 else Vector2(39, 39)
	if state == 3 or state == 5:
		extent *= 1.2
	# Each sprite faces right; rotate the actual frame with its travel vector.
	c.draw_set_transform(p, float(bird["angle"]))
	c.draw_texture_rect_region(BIRD_ACTIONS, Rect2(-extent * 0.5, extent), Rect2(frame * 32, sprite_index * 32, 32, 32))
	c.draw_set_transform(Vector2.ZERO)
