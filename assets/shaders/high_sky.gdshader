// Graphics: High. Godot's procedural sky, plus a less blue copy of it for
// lighting: in this renderer the shade outdoors is lit by the sky alone, and
// the sky's deep blue top turned every shadow blue. The sky you see is
// unchanged; reflections and bounced light get the paler copy.
shader_type sky;

uniform vec4 sky_top_color : source_color;
uniform vec4 sky_horizon_color : source_color;
uniform float sky_curve = 0.15;
uniform vec4 ground_bottom_color : source_color;
uniform vec4 ground_horizon_color : source_color;
uniform float ground_curve = 0.02;
uniform float sun_angle_max = 0.5;  // radians
uniform float sun_curve = 0.15;
uniform float light_saturation = 0.3;  // of the sky that lights the scene
uniform float light_energy = 1.25;

void sky() {
	float v_angle = acos(clamp(EYEDIR.y, -1.0, 1.0));
	float c = 1.0 - v_angle / (PI * 0.5);
	vec3 col = mix(sky_horizon_color.rgb, sky_top_color.rgb, clamp(1.0 - pow(1.0 - c, 1.0 / sky_curve), 0.0, 1.0));
	if (LIGHT0_ENABLED) {
		float sun_angle = acos(dot(LIGHT0_DIRECTION, EYEDIR));
		if (sun_angle < LIGHT0_SIZE) {
			col = LIGHT0_COLOR * LIGHT0_ENERGY;
		} else if (sun_angle < sun_angle_max) {
			float c2 = (sun_angle - LIGHT0_SIZE) / (sun_angle_max - LIGHT0_SIZE);
			col = mix(LIGHT0_COLOR * LIGHT0_ENERGY, col, clamp(1.0 - pow(1.0 - c2, 1.0 / sun_curve), 0.0, 1.0));
		}
	}
	c = (v_angle - PI * 0.5) / (PI * 0.5);
	vec3 ground = mix(ground_horizon_color.rgb, ground_bottom_color.rgb, clamp(1.0 - pow(1.0 - c, 1.0 / ground_curve), 0.0, 1.0));
	COLOR = mix(ground, col, step(0.0, EYEDIR.y));
	if (AT_CUBEMAP_PASS) {
		float grey = dot(COLOR, vec3(0.2126, 0.7152, 0.0722));
		COLOR = mix(vec3(grey), COLOR, light_saturation) * light_energy;
	}
}
