shader_type spatial;
render_mode unshaded; //, cull_disabled;
uniform vec4 modulate : hint_color;
uniform sampler2D overlay : hint_albedo;
uniform sampler2D texture_albedo : hint_albedo;
uniform sampler2D inactive_albedo : hint_albedo;
uniform float mix_amount = 0.0;
uniform float deform_amount : hint_range(-1,1);
uniform float deform_speed : hint_range(0.5,4);

bool approx_eq(vec4 c1, vec4 c2) {
	return all( lessThan( abs( c1 - c2 ), vec4( 0.001, 0.001, 0.001, 0.001) ) ); 
}

void fragment() {
	
	// Camera view
	vec4 screen_view = texture(texture_albedo, SCREEN_UV);
	
	// Create texture warp
	vec2 new_uv = UV * 5.0;
	float offset_x = cos(TIME + new_uv.x + new_uv.y) * 0.05;
	float offset_y = sin(TIME + new_uv.x + new_uv.y) * 0.05;
	vec2 distorted_uv = UV + vec2(offset_x, offset_y);
	vec4 texture_view = texture(inactive_albedo, distorted_uv) * vec4(modulate.rgb, 1);

	// Portal Edges
	vec2 outline_uv = UV;
	vec4 outline = texture(overlay, outline_uv);
	
	if ( approx_eq(vec4(outline.rgb, 1.0), vec4(1.0, 0.0, 0.0, 1.0) )) {
		ALBEDO = mix(screen_view.rgb, texture_view.rgb, mix_amount);
	} else{
		ALBEDO = outline.rgb * modulate.rgb;
		ALPHA = outline.a;
	}
}