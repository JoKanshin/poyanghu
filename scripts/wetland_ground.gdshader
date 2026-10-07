shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D terrain_texture : source_color, filter_nearest, repeat_disable;
uniform sampler2D shore_distance : filter_nearest, repeat_disable;
uniform sampler2D exterior_mask : filter_nearest, repeat_disable;
uniform int season = 0;
uniform int previous_season = 0;
uniform float season_progress = 1.0;
uniform float ground_size = 100.0;
uniform float lake_offset = 0.0;
uniform bool river_bank = false;
uniform bool meadow_only = false;
uniform vec4 meadow_color : source_color = vec4(0.510, 0.588, 0.400, 1.0);
uniform vec4 meadow_basis : source_color;
uniform vec4 summer_meadow : source_color;
uniform vec4 autumn_meadow : source_color;
uniform vec4 snow_color : source_color;
uniform vec4 water_deep : source_color;
uniform vec4 water_mid : source_color;
uniform vec4 water_shallow : source_color;
uniform vec4 sand_color : source_color;
uniform vec4 soil_color : source_color;
uniform vec4 bank_color : source_color = vec4(0.847, 0.776, 0.553, 1.0);
varying vec2 terrain_uv;

void vertex() {
 terrain_uv = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz / ground_size + vec2(0.5);
}

vec3 seasonal_grass(vec3 original, vec2 uv, int season_index) {
 float value = dot(original, vec3(0.25, 0.60, 0.15));
 float tone = clamp((value - 0.25) / 0.50, 0.0, 1.0);
 vec3 base = meadow_color.rgb;
 if (season_index == 1) base = summer_meadow.rgb;
 if (season_index == 2) base = autumn_meadow.rgb;
 if (season_index == 3) {
  vec2 cell = floor(uv * 320.0);
  float patch = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
  return mix(vec3(0.69, 0.77, 0.79), snow_color.rgb, patch > 0.15 ? 0.97 : 0.82);
 }
 return base * mix(0.87, 1.06, tone);
}

vec3 swept_grass(vec3 original, vec2 uv, float screen_y) {
 // Move a soft brush edge from above the screen to below it, including margins.
 float edge = mix(-0.10, 1.10, season_progress);
 float amount = 1.0 - smoothstep(edge - 0.08, edge + 0.08, screen_y);
 return mix(seasonal_grass(original, uv, previous_season), seasonal_grass(original, uv, season), amount);
}

vec3 lake_color(vec3 original) {
 float depth = clamp((original.g - 0.35) / 0.45, 0.0, 1.0);
 return depth < 0.55 ? mix(water_deep.rgb, water_mid.rgb, depth / 0.55) : mix(water_mid.rgb, water_shallow.rgb, (depth - 0.55) / 0.45);
}

void fragment() {
 // Continue the same meadow beyond the artwork, without stretching edge water.
 vec3 color = river_bank ? bank_color.rgb : swept_grass(meadow_basis.rgb, terrain_uv, SCREEN_UV.y);
 if (!meadow_only && all(greaterThanEqual(terrain_uv, vec2(0.0))) && all(lessThanEqual(terrain_uv, vec2(1.0)))) {
  vec3 original = texture(terrain_texture, terrain_uv).rgb;
  bool original_water = original.b > original.g && original.g > original.r;
  bool grass = original.g > original.r && original.r > original.b;
  color = (!river_bank || original_water) ? original : color;
  if (original_water) color = lake_color(original);
  else if (!river_bank) {
   if (grass) color = meadow_color.rgb * mix(0.87, 1.06, clamp((original.g - 0.25) / 0.55, 0.0, 1.0));
   else color = mix(soil_color.rgb, sand_color.rgb, clamp((original.r - 0.5) / 0.4, 0.0, 1.0));
  }
  vec2 mask = texture(shore_distance, terrain_uv).rg;
  float distance = (mask.r - 0.5) * 128.0;
  float edge = lake_offset * mask.g;
  if (mask.g > 0.0 && abs(lake_offset) > 0.01) {
   if (distance <= edge) {
    // Flood shore pixels with water; preserve the original deep-water artwork.
    if (distance > edge - 4.0) color = water_mid.rgb;
    else if (!original_water) color = water_deep.rgb;
   } else if (!river_bank && (original_water || distance <= edge + 3.0)) {
    // Falling water exposes a moving sand rim, then dry lakebed.
    color = distance <= edge + 3.0 ? sand_color.rgb : soil_color.rgb;
   }
  }
  // Only original peripheral grass, never rivers, lakebed, islands or flooded ground.
  bool flooded = mask.g > 0.0 && distance <= edge + 3.0;
  if (!river_bank && grass && !flooded && texture(exterior_mask, terrain_uv).r > 0.5) {
   color = swept_grass(original, terrain_uv, SCREEN_UV.y);
  }
 }
 ALBEDO = color;
}
