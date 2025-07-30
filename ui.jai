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
//	target: Simp.Texture;
}

Palette :: struct {
	body, border, text, hover: [4]u8;
}

Ratio :: struct {num, den: int;}
Creation_Side :: enum {TOP; BOTTOM; LEFT; RIGHT;}

Text_Align_Ver :: enum {TOP; MIDDLE; BOTTOM;}
Text_Align_Hor :: enum {LEFT; MIDDLE; RIGHT;}

clipping_texture: Simp.Texture;

panel_split :: (mother: *UI_Panel, ratio: Ratio, side: Creation_Side, already_draw: bool) -> UI_Panel {
	r := ratio;
	r.den = max(1, r.den);
	r.num = clamp(abs(r.num), 1, r.den);

	other := mother.*;
	other.colors = mother.colors;

	if #complete side == {
	case .TOP;
		other.size[1] = mother.size[1]*r.num/r.den;
		other.pos[1] += mother.size[1] - other.size[1];

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
		other.pos[0] += mother.size[0] - other.size[0];

		mother.size[0] -= other.size[0];
	}

	if already_draw {
		panel_draw(mother);
		panel_draw(*other);
	}

	return other;
}

panel_subdivide :: (mother: *UI_Panel, n: int, direction: enum {HORIZONTAL; VERTICAL;}, already_draw: bool) -> []UI_Panel {
	panels: []UI_Panel; {
		push_allocator(temp);
		panels = NewArray(n, UI_Panel);
	}

	templ := mother.*;
	stride: int;
	if direction == .HORIZONTAL {
		stride = mother.size[0]/n;
		templ.size[0] = stride;
	} else {
		stride = mother.size[1]/n;
		templ.size[1] = stride;
	}

	for * panels {
		it.* = templ;

		if direction == .HORIZONTAL {
			it.pos[0] += it_index*stride;
		} else {
			it.pos[1] += it_index*stride;
		}

		if already_draw panel_draw(it);
	}

	return panels;
}

pointer_is_in_panel :: (p: *UI_Panel, pointer_position: [2]int) -> bool {
	horizontal := p.pos[0] < pointer_position[0] && pointer_position[0] < p.pos[0] + p.size[0];
	vertical := p.pos[1] < pointer_position[1] && pointer_position[1] < p.pos[1] + p.size[1];
	return vertical && horizontal;
}

panel_button :: (p: *UI_Panel, pointer_position: [2]int, pressed: bool) -> bool {
	in_panel := pointer_is_in_panel(p, pointer_position);

	if in_panel {
		tc := p.colors;
		p.colors.body = tc.hover;
		panel_draw(p);
		p.colors = tc;
	}

	return in_panel && pressed;
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

	/* All this commented out text _does_ work, but the texture looks all wrong, and also it's pretty slow again */
	// Simp.texture_destroy(*clipping_texture);
	// clipping_texture = Simp.texture_create_render_target(xx mother.size[0], xx mother.size[1], .RGBA8);
	// Simp.set_render_target(*clipping_texture);
	Simp.set_shader_for_text();
	Simp.draw_prepared_text(font, x_pos + xx mother.pos[0], y_pos + xx mother.pos[1], float_rgb(text_panel.colors.text));
	// Simp.immediate_flush();
	// Simp.set_render_target(os_window);
	// Simp.set_shader_for_images(*clipping_texture);
	// bl := Vector2.{xx mother.pos[0], xx mother.pos[1]};
	// tr := bl + Vector2.{xx mother.size[0], xx mother.size[1]};
	// Simp.immediate_quad(bl.x, bl.y, tr.x, tr.y, .{1, 1, 1, 1});
	// Simp.immediate_flush();
}

panel_draw :: (p: *UI_Panel) {
	Simp.immediate_begin();
	Simp.set_shader_for_color();

	bl := Vector2.{xx p.pos[0], xx p.pos[1]};
	tr := bl + Vector2.{xx p.size[0], xx p.size[1]};
	Simp.immediate_quad(bl.x, bl.y, tr.x, tr.y, float_rgb(p.colors.body));

	/* drawing the borders */
	border_size := 1;

	border := float_rgb(p.colors.border);
	/* left and bottom */
	Simp.immediate_quad(bl.x, bl.y, bl.x+border_size, tr.y, border);
	Simp.immediate_quad(bl.x, bl.y, tr.x, bl.y+border_size, border);
	/* top and right */
	Simp.immediate_quad(bl.x, tr.y-border_size, tr.x, tr.y, border);
	Simp.immediate_quad(tr.x-border_size, bl.y, tr.x, tr.y, border);

	Simp.immediate_flush();
}

float_rgb :: (rgb: [4]u8) -> Vector4 {
	return .{cast(float, rgb[0])/255, cast(float, rgb[1])/255, cast(float, rgb[2])/255, cast(float, rgb[3])/255};
}
