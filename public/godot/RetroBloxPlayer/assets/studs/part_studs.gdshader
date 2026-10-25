shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// High-Detail Classic Roblox Studded Plastic Shader with 3D Stud & Tile Seam Normal Relief
// Renders the 512x512 stud tile texture on top-facing surfaces (world_normal.y > 0.7)
// with 3D normal mapping, contact AO, and subtle surface roughness variation, without overexposing albedo.

uniform vec4 albedo : source_color = vec4(0.56, 0.56, 0.58, 1.0);
uniform sampler2D stud_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float stud_density : hint_range(0.25, 4.0) = 1.0;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.46;
uniform float specular_val : hint_range(0.0, 1.0) = 0.48;

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
		vec2 cell = fract(uv) - vec2(0.5);
		float dist = length(cell);

		// 3D stud cylinder rim normal + tile border bevel normal
		float rim_slope = smoothstep(0.23, 0.285, dist) * (1.0 - smoothstep(0.285, 0.34, dist));
		vec2 radial = (dist > 0.001) ? (cell / dist) : vec2(0.0);
		vec2 border_n = smoothstep(0.46, 0.50, abs(cell)) * sign(cell) * 0.28;
		vec3 n_map = normalize(vec3(-radial.x * rim_slope * 0.72 - border_n.x, -radial.y * rim_slope * 0.72 - border_n.y, 1.0));
		NORMAL_MAP = n_map * 0.5 + 0.5;
		NORMAL_MAP_DEPTH = 1.05;

		// Preserve true albedo richness (never blow out to white) with contact AO in the stud collar
		float tex_mod = clamp(s_center / 0.93, 0.68, 1.03);
		float collar_ao = 1.0 - smoothstep(0.26, 0.31, dist) * (1.0 - smoothstep(0.31, 0.38, dist)) * 0.16;
		base *= tex_mod * collar_ao;
		r_out = clamp(roughness_val - (1.0 - smoothstep(0.0, 0.25, dist)) * 0.07 + rim_slope * 0.08, 0.22, 0.92);
	} else if (world_normal.y < -0.7) {
		// Subtle darker underside inlet
		base *= 0.84;
		r_out = clamp(roughness_val + 0.10, 0.25, 0.95);
	} else {
		// Subtle horizontal molding seam on vertical brick faces
		float v_seam = smoothstep(0.47, 0.50, abs(fract(world_pos.y * stud_density) - 0.5));
		base *= 1.0 - v_seam * 0.06;
		r_out = clamp(roughness_val + 0.04, 0.25, 0.92);
	}
	ALBEDO = base;
	ROUGHNESS = r_out;
	SPECULAR = s_out;
}
