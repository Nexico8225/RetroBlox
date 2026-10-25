shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Authentic Classic Roblox Studded Plastic Shader with 3D Stud Normal Relief
// Renders the 1x1 stud tile texture on top-facing surfaces (world_normal.y > 0.7)
// with procedural 3D bevel normal mapping & micro-AO, while keeping side/bottom faces smooth plastic.

uniform vec4 albedo : source_color = vec4(0.56, 0.56, 0.58, 1.0);
uniform sampler2D stud_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float stud_density : hint_range(0.25, 4.0) = 1.0;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.42;
uniform float specular_val : hint_range(0.0, 1.0) = 0.52;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	vec3 base = albedo.rgb;
	float r_out = roughness_val;
	float s_out = specular_val;
	if (world_normal.y > 0.7) {
		vec2 uv = world_pos.xz * stud_density;
		float s_center = texture(stud_tex, uv).r;
		// Procedural 3D stud rim normal + micro ambient occlusion
		vec2 cell = fract(uv) - vec2(0.5);
		float dist = length(cell);
		float rim_slope = smoothstep(0.22, 0.30, dist) * (1.0 - smoothstep(0.30, 0.37, dist));
		vec2 radial = (dist > 0.001) ? (cell / dist) : vec2(0.0);
		vec3 n_map = normalize(vec3(-radial.x * rim_slope * 0.55, -radial.y * rim_slope * 0.55, 1.0));
		NORMAL_MAP = n_map * 0.5 + 0.5;
		NORMAL_MAP_DEPTH = 0.9;
		float factor = mix(1.0, s_center / 0.94, 0.92);
		float groove_ao = 1.0 - rim_slope * 0.14;
		base *= clamp(factor * groove_ao, 0.60, 1.14);
		r_out = clamp(roughness_val - (1.0 - smoothstep(0.0, 0.26, dist)) * 0.08, 0.18, 0.95);
	} else if (world_normal.y < -0.7) {
		// Subtle darker underside inlet
		base *= 0.86;
		r_out = clamp(roughness_val + 0.08, 0.2, 0.95);
	}
	ALBEDO = base;
	ROUGHNESS = r_out;
	SPECULAR = s_out;
}
