extends RefCounted
## Test skin shared by all card fronts. Only glyph/shadow pixels are changed.
const PAPER := preload("res://assets/art/artist-test-card-blank.png")
const GLYPHS := preload("res://assets/art/card-font-glyphs.png")
const SHADOW := Color8(150, 150, 150)
const INK := Color.BLACK
static var mapping: Dictionary = {}
static var glyph_image: Image
static var paper_image: Image
static var textures: Dictionary = {}

static func _load_pixels() -> void:
	if paper_image != null:
		return
	mapping = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art/card-font-glyphs.json"))
	glyph_image = GLYPHS.get_image()
	paper_image = PAPER.get_image()
	paper_image.convert(Image.FORMAT_RGBA8)

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

static func _write(image: Image, text: String, top: int, ink: Color = INK) -> void:
	var left := 16 + int((64 - _width(text)) / 2.0)
	# All shadows first, then all foregrounds: neighboring glyphs never overwrite ink.
	for pass_index in 2:
		var x := left
		var offset := 1 if pass_index == 0 else 0
		var color := SHADOW if pass_index == 0 else ink
		for character in text:
			var glyph: Array = mapping.get(character, mapping["？"])
			for y in 16:
				for gx in int(glyph[2]):
					if glyph_image.get_pixel(int(glyph[0]) + gx, int(glyph[1]) + y).a > 0.5:
						image.set_pixel(x + gx + offset, top + y + offset, color)
			x += int(glyph[2])

static func texture(title: String, footer: String = "") -> Texture2D:
	_load_pixels()
	var key := title + "\n" + footer
	if textures.has(key):
		return textures[key]
	var image := paper_image.duplicate() as Image
	var lines := _lines(title)
	var top := 32 if lines.size() >= 4 else 40
	var spacing := 17 if lines.size() >= 4 else 18
	for i in lines.size():
		_write(image, lines[i], top + i * spacing)
	if not footer.is_empty():
		_write(image, footer, 100)
	var result := ImageTexture.create_from_image(image)
	textures[key] = result
	return result

static func add_face(panel: PanelContainer, title: String, footer: String = "", locked: bool = false) -> TextureRect:
	var face := TextureRect.new()
	face.name = "PixelCardFace"
	face.texture = texture(title, footer)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if locked:
		face.modulate = Color(0.68, 0.68, 0.68)
	panel.add_child(face)
	panel.set_meta("pixel_face", face)
	return face
