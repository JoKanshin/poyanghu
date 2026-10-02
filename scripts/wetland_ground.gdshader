shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D terrain_texture : source_color, filter_nearest, repeat_disable;
uniform sampler2D shore_distance : filter_nearest, repeat_disable;
uniform float ground_size = 100.0;
uniform float lake_offset = 0.0;
uniform bool river_bank = false;
uniform vec4 bank_color : source_color = vec4(0.847, 0.776, 0.553, 1.0);
varying vec2 terrain_uv;

void vertex() {
 terrain_uv = VERTEX.xz / ground_size + vec2(0.5);
}

void fragment() {
 vec3 color = bank_color.rgb;
 if (all(greaterThanEqual(terrain_uv, vec2(0.0))) && all(lessThanEqual(terrain_uv, vec2(1.0)))) {
  vec3 original = texture(terrain_texture, terrain_uv).rgb;
  bool original_water = original.b > original.g && original.g > original.r;
  color = (!river_bank || original_water) ? original : color;
  vec2 mask = texture(shore_distance, terrain_uv).rg;
  float distance = (mask.r - 0.5) * 128.0;
  float edge = lake_offset * mask.g;
  if (mask.g > 0.0 && abs(lake_offset) > 0.01) {
   if (distance <= edge) {
    // Flood shore pixels with water; preserve the original deep-water artwork.
    if (distance > edge - 4.0) color = vec3(0.388, 0.686, 0.796);
    else if (!original_water) color = vec3(0.090, 0.404, 0.514);
   } else if (!river_bank && (original_water || distance <= edge + 3.0)) {
    // Falling water exposes a moving sand rim, then dry lakebed.
    color = distance <= edge + 3.0 ? vec3(0.847, 0.776, 0.553) : vec3(0.647, 0.631, 0.447);
   }
  }
 }
 ALBEDO = color;
}
