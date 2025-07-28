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

panel_split :: (mother: *UI_Panel, ratio: Ratio, side: Creation_Side) -> UI_Panel {
	r := ratio;
	r.den = max(1, r.den);
	r.num = clamp(abs(r.num), 0, r.den);

	other: UI_Panel;
	other.colors = mother.colors;
	other.pos = mother.pos;
	other.size = mother.size;
	if side == {
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

