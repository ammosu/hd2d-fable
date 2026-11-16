shader_type sky;
uniform vec3 top : source_color = vec3(0.16, 0.2, 0.5);
uniform vec3 mid : source_color = vec3(0.6, 0.5, 0.86);
uniform vec3 horizon : source_color = vec3(1.0, 0.86, 0.68);
uniform vec3 sun_col : source_color = vec3(1.0, 0.7, 0.4);
uniform float bands = 0.0;
void sky() {
	float y = EYEDIR.y;
	if (bands > 0.0) y = floor(y * bands + 0.5) / bands;
	vec3 c = mix(horizon, mid, smoothstep(0.0, 0.07, y));
	c = mix(c, top, smoothstep(0.05, 0.22, y));
	float s = max(dot(EYEDIR, LIGHT0_DIRECTION), 0.0);
	c += sun_col * (pow(s, 8.0) * 0.28 + pow(s, 80.0) * 0.8 + pow(s, 1500.0) * 6.0);
	if (EYEDIR.y < 0.0) c = mix(horizon * 0.6, vec3(0.08, 0.07, 0.1), smoothstep(0.0, -0.3, EYEDIR.y));
	COLOR = c;
}
