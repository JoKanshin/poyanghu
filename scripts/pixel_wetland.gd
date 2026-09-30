extends Control
## Original pixel wetland, with read-only projections of the live ecology state.
## All decorative placement is deterministic; never consume gameplay RNG.
const LANDSCAPE := preload("res://assets/art/poyang-wetland.png")
const SPRITES := preload("res://assets/art/wetland-sprites.png")
const BIRDS := preload("res://assets/art/wetland-birds.png")
const SPECIES_ART := {"baihe": 0, "dongfangbaihuan": 1, "xiaotiane": 2, "baizhenhe": 3, "yanlei": 4}
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
var water_material: ShaderMaterial
var reduced_motion := false

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
	backdrop = TextureRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.texture = LANDSCAPE
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
uniform float quality = 0.65;
uniform float level = 0.5;
uniform float vegetation = 0.5;
uniform vec4 season_tint : source_color = vec4(1.0);
uniform float motion = 1.0;
void fragment() {
 vec4 original = texture(TEXTURE, UV);
 float water = smoothstep(0.04, 0.18, original.b - original.r) * smoothstep(0.04, 0.16, original.g - original.r);
 vec2 uv = UV;
 uv.x += sin(UV.y * 160.0 + TIME * 0.7) * 0.00065 * water * motion;
 vec4 col = texture(TEXTURE, uv);
 col.rgb = mix(col.rgb, col.rgb * vec3(0.85, 0.89, 0.58), water * (1.0 - quality) * 0.55);
 float shallows = water * smoothstep(0.42, 0.80, original.g);
 col.rgb = mix(col.rgb, vec3(0.69, 0.65, 0.42), shallows * (1.0 - level) * 0.55);
 float foliage = smoothstep(0.03, 0.17, original.g - original.b) * (1.0-water);
 col.rgb = mix(col.rgb, col.rgb * vec3(1.12, 0.88, 0.70), foliage * (1.0-vegetation) * 0.65);
 COLOR = col * season_tint;
}"""
	water_material = ShaderMaterial.new()
	water_material.shader = shader
	backdrop.material = water_material
	add_child(backdrop)
	# Draw wildlife above the illustrated terrain.
	var wildlife := Control.new()
	wildlife.name = "Wildlife"
	wildlife.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wildlife.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wildlife.draw.connect(_draw_wildlife.bind(wildlife))
	add_child(wildlife)
	resized.connect(func(): wildlife.queue_redraw())
	sync_state()

func sync_state() -> void:
	metrics = GameState.metrics.duplicate()
	populations = GameState.species_pop.duplicate()
	plants = GameState.plant_pop.duplicate()
	islands = GameState.floating_islands
	settlement = GameState.settlement
	season = maxi(0, GameState.SEASONS.find(GameState.current_season()))
	if water_material:
		water_material.set_shader_parameter("quality", float(metrics.get("water_quality", 65)) / 100.0)
		water_material.set_shader_parameter("vegetation", float(metrics.get("vegetation", 50)) / 100.0)
		water_material.set_shader_parameter("level", float(metrics.get("water_level", 50)) / 100.0)
		var tints := [Color.WHITE, Color(1.03, 1.02, 0.96), Color(1.06, 0.94, 0.80), Color(0.87, 0.95, 1.05)]
		water_material.set_shader_parameter("season_tint", tints[season])

func _process(delta: float) -> void:
	if not reduced_motion: elapsed += delta
	clock_accum += delta
	if clock_accum < 1.0 / 24.0: return
	clock_accum = 0.0
	get_node("Wildlife").queue_redraw()

func _point(uv: Vector2) -> Vector2:
	# Match TextureRect's COVER transform, including ultrawide windows.
	var factor := maxf(size.x / LANDSCAPE.get_width(), size.y / LANDSCAPE.get_height())
	var extent := Vector2(LANDSCAPE.get_size()) * factor
	return ((size - extent) * 0.5 + uv * extent).round()

func _px(c: Control, p: Vector2, rect: Rect2, color: Color, scale_px: float = 2.0) -> void:
	c.draw_rect(Rect2(p + rect.position * scale_px, rect.size * scale_px), color)

func _draw_wildlife(c: Control) -> void:
	# Ripples occupy open water, keeping the HUD readable.
	for i in 28:
		var uv := Vector2(0.31 + fmod(i * 0.137, 0.38), 0.36 + fmod(i * 0.091, 0.27))
		var p := _point(uv)
		var alpha := 0.10 + 0.13 * (sin(elapsed * 1.5 + i * 2.0) + 1.0)
		c.draw_rect(Rect2(p, Vector2(8 + i % 4 * 3, 2)), Color(0.77, 0.94, 0.83, alpha))
	# Individual species populations control visible flocks.
	var index := 0
	for sid in populations:
		var count := clampi(int(populations[sid]) / 18, 0, 5)
		for j in count:
			var habitat: Array[Vector2] = [Vector2(0.32, 0.26), Vector2(0.65, 0.29), Vector2(0.54, 0.39), Vector2(0.31, 0.47), Vector2(0.25, 0.59)]
			var species_index: int = SPECIES_ART.get(sid, 0)
			var base: Vector2 = habitat[species_index]
			var p := _point(base + Vector2(sin(index * 4.37) * 0.038, cos(index * 3.19) * 0.021))
			p.x += round(sin(elapsed * 0.30 + index) * 7)
			_draw_bird(c, p, index, str(sid))
			index += 1
	for i in clampi(int(metrics.get("fish", 50)) / 9, 0, 12):
		var p := _point(Vector2(0.37 + fmod(i * 0.077, 0.26), 0.46 + fmod(i * 0.033, 0.15)))
		p.x += round(sin(elapsed * 0.35 + i) * 22)
		_draw_sprite(c, p, 3, Vector2(15, 24), Color(0.6, 0.85, 0.8, 0.45))
	# Living reed patches change with vegetation along the foreground shoreline.
	for i in clampi(int(plants.get("luwei", 50)) / 5, 0, 20):
		var p := _point(Vector2(0.20 + i * 0.032, 0.79 + sin(i * 2.7) * 0.02))
		p.x += round(sin(elapsed + i) * 1.2)
		_draw_sprite(c, p, 4, Vector2(42, 56))
	for i in clampi(int(plants.get("lian", 50)) / 10, 0, 10):
		var p := _point(Vector2(0.69 + sin(i * 2.13) * 0.07, 0.63 + cos(i * 2.67) * 0.05))
		c.draw_texture_rect(bird_sprites[5], Rect2(p - Vector2(14, 18), Vector2(28, 28)), false)
	for i in islands:
		var p := _point(Vector2(0.43 + i * 0.055, 0.59))
		p.y += round(sin(elapsed + i) * 1.0)
		_draw_sprite(c, p, 5, Vector2(48, 48))
	# Active cottages read settlement and community trust. Scenic village remains backdrop.
	for i in 7:
		var p := _point(Vector2(0.83 + i * 0.013, 0.245 + i * 0.021))
		if i < roundi(settlement / 100.0 * 7.0):
			var lit := i < roundi(float(metrics.get("community", 50)) / 100.0 * 7)
			_draw_sprite(c, p, 6, Vector2(44, 58), Color.WHITE if lit else Color(0.65, 0.73, 0.7))
		else:
			_draw_sprite(c, p, 4, Vector2(32, 44))
	var boat_pos := _point(Vector2(0.68 + sin(elapsed * 0.06) * 0.035, 0.43))
	_draw_sprite(c, boat_pos, 7, Vector2(60, 62))
	# Slow airborne cranes are decorative and deterministic.
	for i in 3:
		var p := _point(Vector2(fmod(elapsed * 0.008 + i * 0.07 + 0.45, 1.0), 0.19 + i * 0.025))
		var wing: float = round(sin(elapsed * 3.0 + i) * 3)
		_px(c, p, Rect2(-5, wing, 5, 1), Color("f6eed7"))
		_px(c, p, Rect2(0, 0, 2, 3), Color("f6eed7"))
		_px(c, p, Rect2(2, wing, 5, 1), Color("f6eed7"))

func _draw_sprite(c: Control, p: Vector2, index: int, extent: Vector2, tint: Color = Color.WHITE) -> void:
	c.draw_texture_rect(sprites[index], Rect2((p - extent * Vector2(0.5, 0.85)).round(), extent), false, tint)

func _draw_bird(c: Control, p: Vector2, index: int, sid: String) -> void:
	var sprite_index: int = SPECIES_ART.get(sid, 0)
	p.y += round(sin(elapsed * 0.9 + index) * 1.0)
	var extent := Vector2(34, 34) if sprite_index != 2 else Vector2(38, 38)
	c.draw_texture_rect(bird_sprites[sprite_index], Rect2((p - extent * Vector2(0.5, 0.85)).round(), extent), false)
