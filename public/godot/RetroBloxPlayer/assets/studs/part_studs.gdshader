shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Authentic Classic Roblox Studded Plastic Shader with 3D Normal Mapping & Procedural Fallback
uniform vec4 albedo : source_color = vec4(0.56, 0.56, 0.58, 1.0);
uniform sampler2D stud_normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stud_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float stud_density : hint_range(0.25, 4.0) = 1.0;
uniform float normal_depth : hint_range(0.0, 3.0) = 1.35;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.38;
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

	float dist_cam = length(world_pos - CAMERA_POSITION_WORLD);

	if (world_normal.y > 0.7) {
		// Top face: studs
		vec2 uv_stud = world_pos.xz * stud_density;
		vec2 local_cell = fract(uv_stud) - vec2(0.5);
		float dist = length(local_cell);

		if (dist_cam < 55.0) {
			// Near camera: full 3D normal mapping & AO highlights
			vec2 uv_norm = world_pos.xz * (stud_density * 0.25);
			vec4 n_tex_sample = texture(stud_normal_tex, uv_norm);
			if (length(n_tex_sample.rgb) > 0.05) {
				NORMAL_MAP = n_tex_sample.rgb;
				NORMAL_MAP_DEPTH = normal_depth;
			} else {
				if (dist < 0.33) {
					vec2 dir = dist > 0.001 ? normalize(local_cell) : vec2(0.0);
					float slope = smoothstep(0.23, 0.32, dist);
					NORMAL_MAP = vec3(0.5 + dir.x * slope * 0.45, 0.5 - dir.y * slope * 0.45, 1.0);
					NORMAL_MAP_DEPTH = normal_depth;
				}
			}

			float rim_shadow = smoothstep(0.25, 0.31, dist) * (1.0 - smoothstep(0.31, 0.38, dist));
			float top_rim = smoothstep(0.22, 0.27, dist) * (1.0 - smoothstep(0.27, 0.32, dist));
			float stud_cap = 1.0 - smoothstep(0.0, 0.25, dist);

			base *= (1.0 - rim_shadow * 0.22);
			base += vec3(top_rim * 0.07 + stud_cap * 0.04);
			r_out = clamp(roughness_val - (top_rim * 0.14 + stud_cap * 0.07), 0.18, 0.88);
			s_out = clamp(specular_val + stud_cap * 0.10, 0.0, 1.0);
		} else {
			// Fast optimized stud highlights for far pixels
			if (dist < 0.28) {
				base += vec3(0.04);
			}
		}
	} else if (world_normal.y < -0.7) {
		// Underside: classic recessed darker plastic
		base *= 0.82;
		r_out = clamp(roughness_val + 0.12, 0.25, 0.95);
	} else {
		// Side faces: sleek molded plastic with subtle bevel seams
		float v_seam = smoothstep(0.48, 0.50, abs(fract(world_pos.y * stud_density) - 0.5));
		base *= 1.0 - v_seam * 0.05;
	}

	ALBEDO = base;
	ROUGHNESS = r_out;
	SPECULAR = s_out;
}
