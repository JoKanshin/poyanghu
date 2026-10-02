extends Control
## Orthographic 45-degree wetland view, with upright scenery and wildlife.
## All decorative placement is deterministic; never consume gameplay RNG.
const LANDSCAPE := preload("res://assets/art/poyang-terrain-base.png")
const LAND_COLOR := Color("829666")
const MAP_ZOOM := 1.58
const VIEW_AZIMUTH := PI / 4.0
const VIEW_PITCH := PI / 4.0
const GROUND_SIZE := 100.0
const BIRD_DISPLAY_SCALE := 0.65
const RiverRoutes := preload("res://scripts/wetland_rivers.gd")
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
const BIRD_ACTIONS := [
	preload("res://assets/art/bird-baihe-v2.png"),
	preload("res://assets/art/bird-dongfangbaihuan-v2.png"),
	preload("res://assets/art/bird-xiaotiane-v2.png"),
	preload("res://assets/art/bird-baizhenhe-v2.png"),
	preload("res://assets/art/bird-yanlei-v2.png"),
]
const BIRD_ATLAS_GRID := Vector2(4, 4)
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
var terrain_viewport: SubViewport
var map_camera: Camera3D
var creeper_mesh: MeshInstance3D
var camera_zoom_factor := 1.0
var camera_tween: Tween
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
var yangtze_route: Array[Vector2] = []
var gan_route: Array[Vector2] = []
var scenery_props: Array[Dictionary] = []
var prop_textures: Array[ImageTexture] = []

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
	_build_river_routes()
	_make_house_sites()
	_build_meadow_scenery()
	easter_rng.randomize()
	var land_margin := ColorRect.new()
	land_margin.name = "LandMargin"
	land_margin.color = LAND_COLOR
	land_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	land_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(land_margin)
	backdrop = TextureRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
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
	_build_terrain_viewport()
	backdrop.texture = terrain_viewport.get_texture()
	add_child(backdrop)
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

func _build_terrain_viewport() -> void:
	terrain_viewport = SubViewport.new()
	terrain_viewport.name = "TerrainViewport"
	terrain_viewport.own_world_3d = true
	terrain_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(terrain_viewport)
	var world := Node3D.new()
	terrain_viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = LAND_COLOR
	world.add_child(environment)
	var ground := MeshInstance3D.new()
	ground.name = "WetlandGround"
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * GROUND_SIZE
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.albedo_texture = LANDSCAPE
	ground.material_override = material
	world.add_child(ground)
	_build_river_mesh(world, yangtze_route, 0.017)
	_build_river_mesh(world, gan_route, 0.010)
	map_camera = Camera3D.new()
	map_camera.name = "WetlandCamera"
	map_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	map_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	map_camera.position = Vector3(sin(VIEW_AZIMUTH) * cos(VIEW_PITCH),
		sin(VIEW_PITCH), cos(VIEW_AZIMUTH) * cos(VIEW_PITCH)) * 150.0
	world.add_child(map_camera)
	map_camera.look_at(Vector3.ZERO, Vector3.UP)
	map_camera.current = true
	# Keep the original face as a ground decal, viewed by the same 3D camera.
	creeper_mesh = MeshInstance3D.new()
	creeper_mesh.name = "CreeperEasterEgg"
	var creeper_plane := PlaneMesh.new()
	creeper_plane.size = Vector2(8.0, 8.0 * CREEPER_ART.get_height() / CREEPER_ART.get_width())
	creeper_mesh.mesh = creeper_plane
	creeper_mesh.position = _ground_position(CREEPER_ANCHOR) + Vector3(0, 0.03, 0)
	var creeper_shader := Shader.new()
	creeper_shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D face_texture : source_color, filter_nearest;
void fragment() {
 vec4 pixel = texture(face_texture, UV);
 if (pixel.a < 0.5 || (pixel.g > 0.63 && pixel.g > pixel.r * 1.08 && pixel.r > 0.48)) discard;
 ALBEDO = pixel.rgb;
}"""
	var creeper_material := ShaderMaterial.new()
	creeper_material.shader = creeper_shader
	creeper_material.set_shader_parameter("face_texture", CREEPER_ART)
	creeper_mesh.material_override = creeper_material
	creeper_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	creeper_mesh.visible = false
	world.add_child(creeper_mesh)

func _layout_map() -> void:
	var viewport_size := Vector2i(maxi(1, roundi(size.x)), maxi(1, roundi(size.y)))
	terrain_viewport.size = viewport_size
	var aspect := float(viewport_size.x) / float(viewport_size.y)
	var ground_width := GROUND_SIZE * (sin(VIEW_AZIMUTH) + cos(VIEW_AZIMUTH))
	var ground_height := ground_width * sin(VIEW_PITCH)
	map_camera.size = maxf(ground_height, ground_width / aspect) / MAP_ZOOM * camera_zoom_factor
	backdrop.position = Vector2.ZERO
	backdrop.size = Vector2(viewport_size)
	var wildlife := get_node_or_null("Wildlife") as Control
	if wildlife:
		wildlife.scale = Vector2.ONE / camera_zoom_factor
		wildlife.position = size * 0.5 * (1.0 - 1.0 / camera_zoom_factor)
		wildlife.queue_redraw()

func set_menu_camera(far: bool, menu_zoom: float = 1.3) -> void:
	if camera_tween and camera_tween.is_valid(): camera_tween.kill()
	if far: _set_camera_zoom(1.0)
	camera_tween = create_tween()
	camera_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	camera_tween.tween_method(_set_camera_zoom, camera_zoom_factor, menu_zoom if far else 1.0, 1.2 if far else 0.8)

func _set_camera_zoom(value: float) -> void:
	camera_zoom_factor = value
	_layout_map()

func roll_creeper_visibility() -> void:
	if creeper_mesh:
		creeper_mesh.visible = easter_rng.randf() < 0.1

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
	# Camera projection keeps upright screen sprites attached to the 3D ground.
	return map_camera.unproject_position(_ground_position(uv)).round()

func _wildlife_point(uv: Vector2) -> Vector2:
	# Undo the overlay's camera zoom for local coordinates; its scale then makes
	# every sprite and ripple zoom in sync with the ground and Creeper decal.
	var wildlife := get_node("Wildlife") as Control
	return (wildlife.get_transform().affine_inverse() * _point(uv)).round()

func _ground_position(uv: Vector2) -> Vector3:
	return Vector3((uv.x - 0.5) * GROUND_SIZE, 0.0, (uv.y - 0.5) * GROUND_SIZE)

func _bird_facing(bird: Dictionary) -> float:
	# Heading is stored in map coordinates; facing must follow screen motion.
	var direction := Vector2.from_angle(float(bird["angle"]))
	var center := Vector2(0.5, 0.5)
	var screen_direction := map_camera.unproject_position(_ground_position(center + direction * 0.01)) - map_camera.unproject_position(_ground_position(center))
	return -1.0 if screen_direction.x < -0.0001 else 1.0

func _terrain_color(uv: Vector2) -> Color:
	var x := clampi(int(uv.x * terrain_image.get_width()), 0, terrain_image.get_width() - 1)
	var y := clampi(int(uv.y * terrain_image.get_height()), 0, terrain_image.get_height() - 1)
	return terrain_image.get_pixel(x, y)

func _is_water(uv: Vector2) -> bool:
	if _in_river_corridor(uv, 0.012): return true
	var color := _terrain_color(uv)
	return color.b > color.g and color.g > color.r

func _is_shore(uv: Vector2) -> bool:
	var color := _terrain_color(uv)
	return color.r > 0.7 and color.r > color.g and color.g > color.b

func _is_land(uv: Vector2) -> bool:
	if _in_river_corridor(uv, 0.025): return false
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
	# Preserve the old settlement-to-village rule; the extra art anchors stay reeds.
	house_target_count = clampi(roundi(settlement / 100.0 * 7.0), 0, mini(7, house_sites.size()))

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
		var animation_state := int(bird.get("animation_state", 0))
		if animation_state != int(bird["state"]):
			bird["animation_previous_state"] = animation_state
			bird["animation_state"] = int(bird["state"])
			bird["animation_age"] = 0.0
		else:
			bird["animation_age"] = float(bird.get("animation_age", 0.0)) + delta

func _px(c: Control, p: Vector2, rect: Rect2, color: Color, scale_px: float = 2.0) -> void:
	c.draw_rect(Rect2(p + rect.position * scale_px, rect.size * scale_px), color)

func _build_river_routes() -> void:
	yangtze_route.assign(RiverRoutes.YANGTZE)
	gan_route.assign(RiverRoutes.GAN)
	# Carry the boundary tangents well past every supported window's view.
	var west := (yangtze_route[0] - yangtze_route[4]).normalized()
	var east := (yangtze_route[-1] - yangtze_route[-4]).normalized()
	yangtze_route.push_front(yangtze_route[0] + west * 2.5)
	yangtze_route.append(yangtze_route[-1] + east * 2.5)
	var south := (gan_route[0] - gan_route[5]).normalized()
	gan_route.push_front(gan_route[0] + south * 2.5)

func _in_river_corridor(uv: Vector2, radius: float) -> bool:
	for route in [yangtze_route, gan_route]:
		for i in range(1, route.size()):
			var closest := Geometry2D.get_closest_point_to_segment(uv, route[i - 1], route[i])
			if uv.distance_squared_to(closest) < radius * radius: return true
	return false

func _build_river_mesh(parent: Node3D, route: Array[Vector2], half_width: float) -> void:
	# Individual ground triangles handle tight river bends without intersecting
	# canvas polygons. Banks, shallows and water share the actual 3D camera.
	for band in 3:
		var width: float = half_width + [0.007, 0.0, -0.004][band]
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var lift := Vector3(0, 0.01 + band * 0.006, 0)
		for i in range(1, route.size()):
			var direction := (route[i] - route[i - 1]).normalized()
			var normal := Vector2(-direction.y, direction.x) * width
			var corners := [route[i - 1] - normal, route[i - 1] + normal, route[i] + normal, route[i] - normal]
			for corner in [0, 1, 2, 0, 2, 3]:
				surface.add_vertex(_ground_position(corners[corner]) + lift)
		# Round joins seal any gaps between neighboring segment banks.
		for uv in route:
			for k in 12:
				surface.add_vertex(_ground_position(uv) + lift)
				surface.add_vertex(_ground_position(uv + Vector2.from_angle(TAU * float(k) / 12.0) * width) + lift)
				surface.add_vertex(_ground_position(uv + Vector2.from_angle(TAU * float(k + 1) / 12.0) * width) + lift)
		var mesh := MeshInstance3D.new()
		mesh.mesh = surface.commit()
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.albedo_color = [Color("d8c68d"), Color("63afcb"), Color("176783")][band]
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mesh)

func _river_sample(route: Array[Vector2], phase: float) -> Dictionary:
	var total := 0.0
	for i in range(1, route.size()): total += route[i - 1].distance_to(route[i])
	var remaining := fposmod(phase, 1.0) * total
	for i in range(1, route.size()):
		var distance := route[i - 1].distance_to(route[i])
		if remaining <= distance:
			return {"pos": route[i - 1].lerp(route[i], remaining / maxf(distance, 0.00001)),
				"direction": (route[i] - route[i - 1]).normalized()}
		remaining -= distance
	return {"pos": route[-1], "direction": Vector2.RIGHT}

func _draw_yangtze_boats(c: Control) -> void:
	for i in 10:
		var sample := _river_sample(yangtze_route, elapsed * 0.007 + float(i) / 10.0)
		var uv: Vector2 = sample["pos"]
		var p := _wildlife_point(uv)
		var direction: Vector2 = (_wildlife_point(uv + sample["direction"] * 0.015) - p).normalized()
		c.draw_set_transform(p, direction.angle())
		# Small original pixel launches, with a hull, cabin and trailing wake.
		c.draw_line(Vector2(-24, -3), Vector2(-14, -2), Color("97d3cc"), 1.0)
		c.draw_line(Vector2(-24, 3), Vector2(-14, 2), Color("97d3cc"), 1.0)
		c.draw_colored_polygon(PackedVector2Array([Vector2(-13,-4), Vector2(8,-4), Vector2(14,0), Vector2(8,4), Vector2(-13,4)]), Color("694d36"))
		c.draw_rect(Rect2(-10, -3, 17, 6), Color("c79959"))
		c.draw_rect(Rect2(-6, -3, 8, 6), Color("f0dcaa"))
		c.draw_rect(Rect2(-4, -2, 4, 4), Color("4c7f83"))
		c.draw_set_transform(Vector2.ZERO)

func _build_meadow_scenery() -> void:
	# Original code-drawn pixel props: grass, flowers, shrubs, stones and pines.
	var palette := {"d": Color("456244"), "g": Color("668650"), "l": Color("9bb364"),
		"t": Color("73593e"), "r": Color("727b73"), "s": Color("a6ad97"),
		"w": Color("d8d6b5"), "f": Color("e2bc73"), "p": Color("d79196")}
	var patterns := [
		["........", "..l.....", "..g..l..", ".lg..g..", "..g.lg..", "..gdgd..", "...dd..."],
		["..p.....", ".pfp..w.", "..g..wfw", "..g...g.", ".lg..lg.", "..gd.g..", "...dd..."],
		["....ll....", "..llggll..", ".lggggggl.", "lgglgggggl", "gggggldggg", ".dggggggd.", "..dddddd.."],
		["..........", "...ssss...", "..swwsss..", ".sssssrsr.", ".srrsrrrr.", "..rrrrrr..", "...dddd..."],
		[".....l.....", "....lgl....", "....ggg....", "...lgggl...", "..lgggggl..", "...ggdgg...", "..lgggggl..", ".lgggggggl.", "..gggdggg..", ".lgggggggl.", "ggggdgggdgg", ".ddddddddd.", "....ttt....", "....ttt...."]
	]
	for rows in patterns:
		var image := Image.create(rows[0].length(), rows.size(), false, Image.FORMAT_RGBA8)
		image.fill(Color.TRANSPARENT)
		for y in rows.size():
			for x in rows[y].length():
				if palette.has(rows[y][x]): image.set_pixel(x, y, palette[rows[y][x]])
		prop_textures.append(ImageTexture.create_from_image(image))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261002
	for y in range(-12, 33):
		for x in range(-12, 33):
			if rng.randf() > 0.36: continue
			var uv := Vector2(x, y) * 0.055 + Vector2(rng.randf_range(-0.018, 0.018), rng.randf_range(-0.018, 0.018))
			if not _is_land(uv) or _in_river_corridor(uv, 0.04) or uv.distance_to(CREEPER_ANCHOR) < 0.15: continue
			var clear := true
			for site in house_sites:
				if uv.distance_to(site) < 0.06: clear = false; break
			if not clear: continue
			var roll := rng.randf()
			var kind := 5 if roll < 0.06 else (4 if roll < 0.15 else (3 if roll < 0.31 else (2 if roll < 0.51 else (1 if roll < 0.68 else 0))))
			scenery_props.append({"pos": uv, "kind": kind, "scale": rng.randf_range(1.9, 3.0)})
	scenery_props.sort_custom(func(a: Dictionary, b: Dictionary): return a["pos"].x + a["pos"].y < b["pos"].x + b["pos"].y)

func _draw_meadow_scenery(c: Control) -> void:
	for prop in scenery_props:
		if prop["kind"] == 5:
			_draw_tree(c, _wildlife_point(prop["pos"]), float(prop["scale"]) * 0.55)
			continue
		var texture: Texture2D = prop_textures[prop["kind"]]
		var extent := texture.get_size() * float(prop["scale"])
		var p := _wildlife_point(prop["pos"])
		c.draw_texture_rect(texture, Rect2((p - extent * Vector2(0.5, 0.9)).round(), extent.round()), false)

func _draw_wildlife(c: Control) -> void:
	_draw_meadow_scenery(c)
	_draw_yangtze_boats(c)
	# Frame the playable shore lightly; keep the secret Creeper's clearing open.
	for uv in EDGE_TREE_TARGETS:
		var clear := uv.distance_to(CREEPER_ANCHOR) > 0.13
		for home in house_sites:
			if uv.distance_to(home) < 0.065:
				clear = false
				break
		if clear and _is_land(uv):
			_draw_tree(c, _wildlife_point(uv), 0.78)
	# Ripples occupy open water, keeping the HUD readable.
	for i in 28:
		var p := _wildlife_point(WATER_ANCHORS[i % WATER_ANCHORS.size()])
		var alpha := 0.10 + 0.13 * (sin(elapsed * 1.5 + i * 2.0) + 1.0)
		c.draw_rect(Rect2(p, Vector2(8 + i % 4 * 3, 2)), Color(0.77, 0.94, 0.83, alpha))
	for i in clampi(int(float(metrics.get("fish", 50)) / 12.0), 0, 12):
		var p := _wildlife_point(WATER_ANCHORS[i % WATER_ANCHORS.size()])
		p.x += round(sin(elapsed * 0.35 + i) * 4)
		_draw_sprite(c, p, 3, Vector2(15, 24), Color(0.6, 0.85, 0.8, 0.45))
	# The old scene used plant populations / 7. Keep those visual thresholds and
	# scatter each kind only on its matching terrain color.
	for pid in GameState.PLANTS:
		var sites: Array = plant_sites.get(pid, [])
		var count := mini(int(float(plants.get(pid, 0)) / 7.0), sites.size())
		for i in count:
			var p := _wildlife_point(sites[i])
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
		var p := _wildlife_point(ISLAND_ANCHORS[i % ISLAND_ANCHORS.size()])
		p.y += round(sin(elapsed + i) * 1.0)
		c.draw_texture_rect(FLOATING_ISLAND, Rect2((p - Vector2(24, 31)).round(), Vector2(48, 48)), false)
	_draw_houses(c)
	for bird in bird_agents:
		if int(bird["slot"]) < _bird_count(str(bird["sid"])):
			_draw_bird_actor(c, bird)
	var boat_pos := _wildlife_point(BOAT_ANCHOR)
	boat_pos.x += round(sin(elapsed * 0.06) * 4)
	_draw_sprite(c, boat_pos, 7, Vector2(60, 62))

func _draw_houses(c: Control) -> void:
	var lit := roundi(float(metrics.get("community", 50)) / 100.0 * float(house_target_count))
	for i in house_sites.size():
		var p := _wildlife_point(house_sites[i])
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

func _bird_animation_frame(bird: Dictionary) -> int:
	var state: int = bird["state"]
	var age := float(bird.get("animation_age", 0.0))
	var previous := int(bird.get("animation_previous_state", 0))
	if not reduced_motion and age < 0.18:
		if state == 3 or state == 5: return 14 # Takeoff before wingbeat loop.
		if previous == 3 or previous == 5: return 15 # Feet-down landing.
	var tick := int(age * 7.0 + float(bird.get("slot", 0))) if not reduced_motion else 0
	match state:
		1: return 6 + tick % 3 # Bend, peck, lift.
		2: return 2 + tick % 4 # Four-step walking loop.
		3, 5: return 9 + tick % 4 # Four-phase wingbeat.
		4: return 13 # Folded wings while resting.
	return int(age * 2.0) % 2 if not reduced_motion else 0

func _bird_frame_region(species: int, frame: int) -> Rect2:
	var tile := Vector2(BIRD_ACTIONS[species].get_size()) / BIRD_ATLAS_GRID
	return Rect2(Vector2(frame % 4, floori(float(frame) / 4.0)) * tile, tile)

func _draw_bird_actor(c: Control, bird: Dictionary) -> void:
	var sprite_index: int = SPECIES_ART.get(str(bird["sid"]), 0)
	var state: int = bird["state"]
	var p := _wildlife_point(bird["pos"])
	var frame := _bird_animation_frame(bird)
	if state == 3 or state == 5:
		p.y -= 6.0 + round(sin(elapsed * 13.0) * 2.0)
	elif state == 4:
		p.y -= 5.0 + round(sin(elapsed * 4.0) * 1.0)
	var extent := (Vector2(46, 46) if sprite_index != 2 else Vector2(50, 50)) * BIRD_DISPLAY_SCALE
	if state == 3 or state == 5:
		extent *= 1.2
	# Billboard sprites remain upright: only mirror horizontally, never rotate.
	# Anchor the feet to the habitat point instead of the middle of the body.
	c.draw_set_transform(p, 0.0, Vector2(_bird_facing(bird), 1.0))
	c.draw_texture_rect_region(BIRD_ACTIONS[sprite_index], Rect2(-extent * Vector2(0.5, 0.875), extent), _bird_frame_region(sprite_index, frame))
	c.draw_set_transform(Vector2.ZERO)
