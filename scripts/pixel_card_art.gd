extends RefCounted
## Bitmap card fronts preserve category artwork and the existing glyph font.
const PAPER := preload("res://assets/art/artist-test-card-blank.png")
const SUITS := {
	"ecology": preload("res://assets/art/card-suits/ecology.png"),
	"social": preload("res://assets/art/card-suits/social.png"),
	"manage": preload("res://assets/art/card-suits/manage.png"),
}
## 图鉴使用完整知识卡牌面，与普通手牌和紧急调度分别取材。
const KNOWLEDGE_FACES := {
	"植物": preload("res://assets/art/knowledge/kd-08.png"),
	"鸟类": preload("res://assets/art/knowledge/kd-09.png"),
}
## 未解锁统一用这张：图上自带「未知 / ？ / UNKNOW」，一个字都不用再写。
const KNOWLEDGE_FACE_BLANK := preload("res://assets/art/knowledge/category-blank.png")
const KNOWLEDGE_CATEGORIES := ["地理", "水生动物", "外来物种", "机制", "保护行动", "案例", "管理策略"]
const DISPATCH_SUITS := {
	"ecology": preload("res://assets/art/dispatch/ecology.png"),
	"social": preload("res://assets/art/dispatch/social.png"),
	"manage": preload("res://assets/art/dispatch/manage.png"),
}
const KNOWLEDGE_FACE_LOCKED := preload("res://assets/art/knowledge/kd-11.png")
## 彩蛋卡：整张画好的卡面（含内页插画与名字），与旧的 card-suits/dixinhu.png 逐像素相同。
const KNOWLEDGE_FACE_EGG := preload("res://assets/art/knowledge/kd-07.png")
## 往新卡面上写卡名用的排版参数（测试也读这三个，别在别处再写一遍魔数）
const FACE_SCALE := 4        # 400×600 卡面上，字形放大 4 倍（与行动卡的卡名同规格）
const FACE_SPACING := 80     # 行距
const FACE_BAND_CENTER := 338 # 中间空白带的垂直中心（实测卡面 145~530）
const GLYPHS := preload("res://assets/art/card-font-glyphs.png")
const SHADOW := Color8(150, 150, 150)
const INK := Color.BLACK
static var mapping: Dictionary = {}
static var glyph_image: Image
static var paper_image: Image
static var textures: Dictionary = {}
static var suit_images: Dictionary = {}
static var knowledge_category_faces: Dictionary = {}

static func _load_pixels() -> void:
	if paper_image != null:
		return
	mapping = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art/card-font-glyphs.json"))
	glyph_image = GLYPHS.get_image()
	paper_image = PAPER.get_image()
	paper_image.convert(Image.FORMAT_RGBA8)
	# Knowledge cards have no action suit. Restore the baked social icon's area
	# from the opposite blank corner, including the paper edge and outer frame.
	var knowledge_paper := paper_image.duplicate() as Image
	for y in range(6, 34):
		for x in range(64, 94):
			knowledge_paper.set_pixel(x, y, paper_image.get_pixel(95 - x, y))
	suit_images["knowledge"] = knowledge_paper
	for category in SUITS:
		var image: Image = SUITS[category].get_image()
		image.convert(Image.FORMAT_RGBA8)
		suit_images[category] = image

static func category_for(title: String) -> String:
	for card in GameState.ACTION_CARDS:
		if str(card["name"]) == title: return str(card["category"])
	return ""

static func base_image(category: String) -> Image:
	_load_pixels()
	return suit_images.get(category, paper_image)


## 全部已收集知识卡都有无便签纸的完整卡面。
static func knowledge_face(category: String) -> Texture2D:
	_load_pixels()
	if KNOWLEDGE_FACES.has(category):
		return KNOWLEDGE_FACES[category]
	if category not in KNOWLEDGE_CATEGORIES:
		return null
	if not knowledge_category_faces.has(category):
		var image := KNOWLEDGE_FACE_BLANK.get_image().duplicate() as Image
		image.convert(Image.FORMAT_RGBA8)
		image.resize(400, 600, Image.INTERPOLATE_NEAREST)
		_write(image, category, 72, Color("557530"), -1, 2)
		knowledge_category_faces[category] = ImageTexture.create_from_image(image)
	return knowledge_category_faces[category]

## 专用素材牌库按 id 读取整张副本；生成素材时只写名称，不写费用。
static func dispatch_texture(card: Dictionary, baked: bool = true) -> Texture2D:
	_load_pixels()
	var key := "dispatch\n" + str(card["id"])
	if baked and textures.has(key):
		return textures[key]
	var path := "res://assets/art/dispatch/cards/%s.png" % str(card["id"])
	if baked and ResourceLoader.exists(path):
		textures[key] = load(path)
		return textures[key]
	var image := (DISPATCH_SUITS[str(card["category"])] as Texture2D).get_image().duplicate() as Image
	image.convert(Image.FORMAT_RGBA8)
	image.resize(400, 600, Image.INTERPOLATE_NEAREST)
	var lines := _lines(str(card["name"]))
	var top := 133 if lines.size() >= 4 else 167
	var spacing := 71 if lines.size() >= 4 else 75
	for i in lines.size():
		_write(image, lines[i], top + i * spacing, INK, -1, 4)
	var result := ImageTexture.create_from_image(image)
	if baked: textures[key] = result
	return result


## 用画好的卡面做一张知识卡：只写卡名，按行数垂直居中放在卡面中间那块空白里
## （底部「点击查看」在 y≈540，所以文字块别压下去）。图里的类别与「知识卡」是印好的，不再写。
static func knowledge_texture(title: String, category: String) -> Texture2D:
	_load_pixels()
	var key := "kface\n" + title + "\n" + category
	if textures.has(key):
		return textures[key]
	var source: Texture2D = knowledge_face(category)
	var image := source.get_image().duplicate() as Image
	image.convert(Image.FORMAT_RGBA8)
	var lines := _lines(title)
	var block_h := 16 * FACE_SCALE + (lines.size() - 1) * FACE_SPACING
	var top := FACE_BAND_CENTER - block_h / 2
	for i in lines.size():
		_write(image, lines[i], top + i * FACE_SPACING, INK, -1, FACE_SCALE)
	var result := ImageTexture.create_from_image(image)
	textures[key] = result
	return result


## 新卡面上卡名该占的那条带（测试拿它断言「只有这条带被改过」）
static func knowledge_text_band(title: String) -> Rect2i:
	var lines := _lines(title)
	var block_h := 16 * FACE_SCALE + (lines.size() - 1) * FACE_SPACING
	var top := FACE_BAND_CENTER - block_h / 2
	return Rect2i(0, top, 400, block_h)

static func _width(text: String) -> int:
	var width := 0
	for character in text:
		width += int(mapping.get(character, mapping["？"])[2])
	return width

static func _lines(text: String) -> Array[String]:
	var lines: Array[String] = []
	var line := ""
	for character in text:
		if not line.is_empty() and _width(line + character) > 64:
			lines.append(line)
			line = ""
		line += character
	if not line.is_empty():
		lines.append(line)
	return lines

static func _write(image: Image, text: String, top: int, ink: Color = INK, left_override: int = -1, glyph_scale: int = 1) -> void:
	var left := int((image.get_width() - _width(text) * glyph_scale) / 2.0) if left_override < 0 else left_override
	# All shadows first, then all foregrounds: neighboring glyphs never overwrite ink.
	for pass_index in 2:
		var x := left
		var offset := glyph_scale if pass_index == 0 else 0
		var color := SHADOW if pass_index == 0 else ink
		for character in text:
			var glyph: Array = mapping.get(character, mapping["？"])
			for y in 16:
				for gx in int(glyph[2]):
					if glyph_image.get_pixel(int(glyph[0]) + gx, int(glyph[1]) + y).a > 0.5:
						for sy in glyph_scale:
							for sx in glyph_scale:
								image.set_pixel(x + gx * glyph_scale + offset + sx, top + y * glyph_scale + offset + sy, color)
			x += int(glyph[2]) * glyph_scale

static func texture(title: String, footer: String = "", category: String = "") -> Texture2D:
	_load_pixels()
	if category.is_empty():
		category = "knowledge" if footer in ["知识卡", "未收集"] else category_for(title)
	var key := title + "\n" + footer + "\n" + category
	if textures.has(key):
		return textures[key]
	var image := base_image(category).duplicate() as Image
	var lines := _lines(title)
	var top := 32 if lines.size() >= 4 else 40
	var spacing := 17 if lines.size() >= 4 else 18
	var glyph_scale := 4 if SUITS.has(category) else 1
	if SUITS.has(category):
		top = 133 if lines.size() >= 4 else 167
		spacing = 71 if lines.size() >= 4 else 75
	for i in lines.size():
		_write(image, lines[i], top + i * spacing, INK, -1, glyph_scale)
	if not footer.is_empty():
		# Costs are already in ten-thousands; the supplied banknote prints 萬.
		if SUITS.has(category):
			_write(image, footer, 417, Color("35482d"), 179 - _width(footer) * 2, glyph_scale)
		else: _write(image, footer, 100)
	var result := ImageTexture.create_from_image(image)
	textures[key] = result
	return result

static func add_face(panel: PanelContainer, title: String, footer: String = "", locked: bool = false, category: String = "", dixinhu: bool = false, knowledge_category: String = "") -> TextureRect:
	var face := TextureRect.new()
	face.name = "PixelCardFace"
	# 卡面来源：彩蛋 → 画好的整张；未解锁 → 统一的「未知」卡面；有该类别卡面 → 卡面 + 写卡名；
	# 其余（还没画卡面的知识卡类别、行动卡）→ 老路：空白纸 + 卡名 + footer。
	var art: Texture2D = null
	if dixinhu:
		art = KNOWLEDGE_FACE_EGG
	elif locked and KNOWLEDGE_FACE_LOCKED != null:
		art = KNOWLEDGE_FACE_LOCKED
	elif knowledge_face(knowledge_category) != null:
		art = knowledge_texture(title, knowledge_category)
	face.texture = art if art != null else texture(title, footer, category)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 新卡面自带灰调（kd-11），再压一层 0.68 会发黑，所以只有老路那条才调暗。
	if locked and art == null:
		face.modulate = Color(0.68, 0.68, 0.68)
	panel.add_child(face)
	panel.set_meta("pixel_face", face)
	var outline := Node2D.new()
	outline.set_script(preload("res://scripts/card_outline.gd"))
	outline.name = "CardArtOutline"
	outline.use_parent_material = true
	panel.add_child(outline)
	return face
