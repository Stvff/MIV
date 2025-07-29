/*
	Do not draw to panels before using them as a mother in a split call, because it will clear their content.

	If a function starts with `panel_`, then that function draws to panels.
	If a function ends with `panel_`, it does something with or to the panel, but does not draw on it
*/

UI_Panel :: struct {
	size: [2]int;
	pos: [2]int;
//	has_margin: bool;
	colors: Palette;
	target: Simp.Texture;
}

Palette :: struct {
	body, border, text, hover: [4]u8;
}

Ratio :: struct {num, den: int;}
Creation_Side :: enum {TOP; BOTTOM; LEFT; RIGHT;}

Text_Align_Ver :: enum {TOP; MIDDLE; BOTTOM;}
Text_Align_Hor :: enum {LEFT; MIDDLE; RIGHT;}

/* does not also panel_recolor */
create_panel :: (size: [2]int, colors: Palette) -> UI_Panel {
	p: UI_Panel;
	p.size = size;
	p.colors = colors;
	p.target = Simp.texture_create_render_target(xx size[0], xx size[1], .RGBA8);
	return p;
}

/* does not also panel_recolor */
reset_panel :: (p: *UI_Panel, size: [2]int, colors: Palette) {
	Simp.texture_destroy(*p.target);
	p.* = .{};
	p.size = size;
	p.colors = colors;
	p.target = Simp.texture_create_render_target(xx size[0], xx size[1], .RGBA8);
}

panel_split :: (mother: *UI_Panel, ratio: Ratio, side: Creation_Side, inheret := true, colors := Palette.{}) -> UI_Panel {
	r := ratio;
	r.den = max(1, r.den);
	r.num = clamp(abs(r.num), 1, r.den);

	other := mother.*;
	if inheret then other.colors = mother.colors;
	else other.colors = colors;

	if #complete side == {
	case .TOP;
		other.size[1] = mother.size[1]*r.num/r.den;
		other.pos[1] = mother.size[1] - other.size[1];

		mother.size[1] -= other.size[1];
	case .BOTTOM;
		other.size[1] = mother.size[1]*r.num/r.den;

		mother.size[1] -= other.size[1];
		mother.pos[1] += other.size[1];
	case .LEFT;
		other.size[0] = mother.size[0]*r.num/r.den;

		mother.size[0] -= other.size[0];
		mother.pos[0] += other.size[0];
	case .RIGHT;
		other.size[0] = mother.size[0]*r.num/r.den;
		other.pos[0] = mother.size[0] - other.size[0];

		mother.size[0] -= other.size[0];
	}

	Simp.texture_destroy(*mother.target);

	mother.target = Simp.texture_create_render_target(xx mother.size[0], xx mother.size[1], .RGBA8);
	Simp.set_render_target(*mother.target);
	body := float_rgb(mother.colors.body);
	Simp.clear_render_target(body.x, body.y, body.z, body.w);

	other.target = Simp.texture_create_render_target(xx other.size[0], xx other.size[1], .RGBA8);
	Simp.set_render_target(*other.target);
	body = float_rgb(other.colors.body);
	Simp.clear_render_target(body.x, body.y, body.z, body.w);
	return other;
}

panel_text :: (mother: *UI_Panel, font: *Simp.Dynamic_Font, text: string, align_h: Text_Align_Hor, align_v: Text_Align_Ver, split_on_h := false, split_on_v := false) {
	text_width := Simp.prepare_text(font, text);
	padding := font.character_height;
	x_pos, y_pos: int;
	text_panel := mother;

	if #complete align_h == {
	case .LEFT;
		x_pos = padding;
	case .MIDDLE;
		x_pos = text_panel.size[0]/2 - text_width/2;
	case .RIGHT;
		x_pos = text_panel.size[0] - text_width - padding;
	}
	if #complete align_v == {
	case .TOP;
		y_pos = text_panel.size[1] - padding*5/4; /* this is text_height + padding/4 */
	case .MIDDLE;
		y_pos = text_panel.size[1]/2 - padding/4; /* why is this div by 4?? */
	case .BOTTOM;
		y_pos = padding*3/4;
	}

	Simp.set_render_target(*text_panel.target);
	Simp.set_shader_for_text();
	Simp.draw_prepared_text(font, x_pos, y_pos, float_rgb(text_panel.colors.text));
}

panel_recolor :: (p: *UI_Panel, colors: Palette) {
	p.colors = colors;
	Simp.set_render_target(*p.target);
	fcolors := float_rgb(p.colors.body);
	Simp.clear_render_target(fcolors.x, fcolors.y, fcolors.z, fcolors.w);
}

draw_panel :: (window: X11.Window, p: *UI_Panel, destroy := true) {
	Simp.set_render_target(window);
	Simp.set_shader_for_images(*p.target);
	Simp.immediate_begin();

//	print("size: %, pos: %\n", p.size, p.pos);

	upc := int.[p.pos[0] + p.size[0], p.pos[1] + p.size[1]];
	Simp.immediate_quad(cast(float, p.pos[0]), cast(float, p.pos[1]), cast(float, upc[0]), cast(float, upc[1]), .{1, 1, 1, 1});

	if destroy {
		Simp.immediate_flush();
		Simp.texture_destroy(*p.target);
		p.* = .{};
	}
}

float_rgb :: (rgb: [4]u8) -> Vector4 {
	return .{cast(float, rgb[0])/255, cast(float, rgb[1])/255, cast(float, rgb[2])/255, cast(float, rgb[3])/255};
}
