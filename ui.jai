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

Ratio :: struct {num, den: int;};
Creation_Side :: enum {TOP; BOTTOM; LEFT; RIGHT;}

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

panel_split :: (mother: *UI_Panel, ratio: Ratio, side: Creation_Side) -> UI_Panel {
	r := ratio;
	r.den = max(1, r.den);
	r.num = clamp(abs(r.num), 0, r.den);

	other: UI_Panel;
	other.colors = mother.colors;
	other.pos = mother.pos;
	other.size = mother.size;
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
	Simp.clear_render_target(cast(float, mother.colors.body[0])/255, cast(float, mother.colors.body[1])/255, cast(float, mother.colors.body[2])/255, cast(float, mother.colors.body[3])/255);

	other.target = Simp.texture_create_render_target(xx other.size[0], xx other.size[1], .RGBA8);
	Simp.set_render_target(*other.target);
	Simp.clear_render_target(cast(float, other.colors.body[0])/255, cast(float, other.colors.body[1])/255, cast(float, other.colors.body[2])/255, cast(float, other.colors.body[3])/255);
	return other;
}

panel_recolor :: (p: *UI_Panel, colors: Palette) {
	p.colors = colors;
	Simp.set_render_target(*p.target);
	Simp.clear_render_target(cast(float, p.colors.body[0])/255, cast(float, p.colors.body[1])/255, cast(float, p.colors.body[2])/255, cast(float, p.colors.body[3])/255);
}

draw_panel :: (window: X11.Window, p: *UI_Panel, destroy := true) {
	Simp.set_render_target(window);
	Simp.set_shader_for_images(*p.target);
	Simp.immediate_begin();

//	print("size: %, pos: %\n", p.size, p.pos);

	upc := int.[p.pos[0] + p.size[0], p.pos[1] + p.size[1]];
	Simp.immediate_quad(cast(float, p.pos[0]), cast(float, p.pos[1]), cast(float, upc[0]), cast(float, upc[1]), .{1, 1, 1, 1});

	if destroy {
		Simp.texture_destroy(*p.target);
		p.* = .{};
	}
}
