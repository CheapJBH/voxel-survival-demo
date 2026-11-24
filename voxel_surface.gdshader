shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;

// 地表配色（低多边形自然色）
uniform vec3 grass_color : source_color = vec3(0.40, 0.51, 0.32);
uniform vec3 dirt_color : source_color = vec3(0.44, 0.38, 0.28);
uniform vec3 rock_color : source_color = vec3(0.45, 0.45, 0.43);
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.95;
uniform float flat_shading : hint_range(0.0, 1.0) = 0.0;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.55;
// 远处溶解距离（配合雾，掩盖区块加载的硬边）
uniform float far_fade_start = 210.0;
uniform float far_fade_end = 258.0;

// 由 voxel 引擎自动赋值的 uniform
uniform int u_transition_mask;
uniform vec2 u_lod_fade;

varying vec3 v_world_normal;
varying vec3 v_world_pos;

float get_hash(vec2 c) {
	return fract(sin(dot(c.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// 平滑值噪声（无格子硬边）
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm2(vec2 p) {
	float v = 0.0;
	v += 0.55 * vnoise(p);
	v += 0.30 * vnoise(p * 2.13);
	v += 0.15 * vnoise(p * 4.37);
	return v;
}

// 计算顶点在 LOD 过渡处的次要位置系数
float get_transvoxel_secondary_factor(int idata) {
	int transition_mask = u_transition_mask & 0xff;

	int cell_border_mask = idata & 63;
	int vertex_border_mask = (idata >> 8) & 63;
	int m = transition_mask & cell_border_mask;
	float t = float(m != 0);
	t *= float((vertex_border_mask & ~transition_mask) == 0);
	return t;
}

vec3 get_transvoxel_position(vec3 vertex_pos, vec4 fdata) {
	int idata = floatBitsToInt(fdata.a);

	float secondary_factor = get_transvoxel_secondary_factor(idata);
	vec3 secondary_position = fdata.xyz;
	vec3 pos = mix(vertex_pos, secondary_position, secondary_factor);

	// 不按 u_transition_mask 剔除过渡三角形（移动端该 uniform 可能为 0，会把顶点拉到原点）
	return pos;
}

void vertex() {
	VERTEX = get_transvoxel_position(VERTEX, CUSTOM0);
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (flat_shading > 0.5) {
		NORMAL = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	}

	float slope = clamp(v_world_normal.y, 0.0, 1.0);
	float h = clamp((v_world_pos.y + 12.0) / 46.0, 0.0, 1.0);

	// 草只长在「平缓 + 较高 + 成片」的地方，挖开后的坑底/低处是土
	float grass_mask = smoothstep(0.74, 0.94, slope) * smoothstep(0.28, 0.58, h);
	grass_mask *= smoothstep(0.34, 0.64, fbm2(v_world_pos.xz * 0.55 + vec2(3.0, 11.0)));
	vec3 base = mix(dirt_color, grass_color, grass_mask);
	// 陡坡露岩
	base = mix(rock_color, base, smoothstep(0.42, 0.70, slope));
	base *= mix(0.93, 1.08, h);

	// 朝向明暗：朝上的面被天空照亮，垂直/朝下的面（洞壁、洞顶）明显更暗
	float upness = clamp(slope * 0.5 + 0.5, 0.0, 1.0);
	base *= mix(0.55, 1.05, upness);

	// 柔和噪声纹理（替代硬格子），给地面提供视差线索
	vec2 wp = v_world_pos.xz;
	float n_big = fbm2(wp * 0.30);
	float n_mid = fbm2(wp * 1.15 + vec2(13.0, 7.0));
	float shade = (n_big - 0.5) * 0.22 + (n_mid - 0.5) * 0.13;
	base *= 1.0 + shade * detail_strength;

	ALBEDO = base;
	ROUGHNESS = surface_roughness;
	METALLIC = 0.0;

}
