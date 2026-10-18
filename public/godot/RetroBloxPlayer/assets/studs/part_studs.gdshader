shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Classic studded plastic: the part's paint color, with the circular stud
// grid multiplied on top of up-facing surfaces only (sides stay smooth).
// The tile is one stud per world unit, so studs land on a 1-stud grid no
// matter how big or where the part is.

uniform vec4 albedo : source_color = vec4(0.64, 0.63, 0.65, 1.0);
uniform sampler2D stud_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float stud_density : hint_range(0.25, 4.0) = 1.0;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	vec3 base = albedo.rgb;
	if (world_normal.y > 0.7) {
		base *= texture(stud_tex, world_pos.xz * stud_density).rgb;
	}
	ALBEDO = base;
	ROUGHNESS = 0.82;
}
