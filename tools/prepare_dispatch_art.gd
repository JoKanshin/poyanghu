extends SceneTree
## Generated repairs supply only the removed note region; retain original frame/header pixels.
func _init() -> void:
	for category in ["ecology", "social", "manage"]:
		var original := Image.load_from_file("res://assets/art/card-suits/%s.png" % category)
		var repair := Image.load_from_file("res://tools/art_sources/%s-generated.png" % category)
		original.convert(Image.FORMAT_RGBA8)
		repair.convert(Image.FORMAT_RGBA8)
		repair.resize(400, 600, Image.INTERPOLATE_NEAREST)
		original.blit_rect(repair, Rect2i(30, 383, 320, 145), Vector2i(30, 383))
		# Restore the right paper edge/frame where the clip extended beyond the note.
		original.blit_rect(original, Rect2i(350, 180, 29, 145), Vector2i(350, 383))
		original.save_png("res://assets/art/dispatch/%s.png" % category)
	var knowledge := Image.load_from_file("res://assets/art/knowledge/kd-08.png")
	var blank := Image.load_from_file("res://tools/art_sources/category-generated.png")
	knowledge.convert(Image.FORMAT_RGBA8)
	blank.convert(Image.FORMAT_RGBA8)
	blank.resize(400, 600, Image.INTERPOLATE_NEAREST)
	knowledge.blit_rect(blank, Rect2i(130, 70, 145, 34), Vector2i(130, 70))
	knowledge.save_png("res://assets/art/knowledge/category-blank.png")
	var car := Image.load_from_file("res://tools/art_sources/community-car-generated.png")
	car.convert(Image.FORMAT_RGBA8)
	# Cut transparent padding so its visual scale is explicit relative to 76px houses.
	var left := car.get_width()
	var top := car.get_height()
	var right := 0
	var bottom := 0
	for y in car.get_height():
		for x in car.get_width():
			if car.get_pixel(x, y).a > 0.5:
				left = mini(left, x)
				top = mini(top, y)
				right = maxi(right, x + 1)
				bottom = maxi(bottom, y + 1)
	var bounds := Rect2i(left, top, right - left, bottom - top)
	car = car.get_region(bounds)
	car.save_png("res://assets/houses/community-car.png")
	quit()
