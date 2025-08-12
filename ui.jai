/*
	Do not draw to panels before using them as a mother in a split call, because it will clear their content.

	If a function starts with `panel_`, then that function draws to panels.
	If a function ends with `panel_`, it does something with or to the panel, but does not draw on it
*/

UI_Panel :: struct {
	size: [2]int;
	pos: [2]int;
	border_size := 1;
	colors: Palette;
}

Palette :: struct {
	body, border, text, hover: [4]u8;
}

Tool_Tip :: struct {
	tip: string;
	hovering: enum {Red; Orange; Green;};
	hover_started: Apollo_Time;
	panel: UI_Panel;
}

Ratio :: struct {num, den: int;}
Creation_Side :: enum {TOP; BOTTOM; LEFT; RIGHT;}

Text_Align_Ver :: enum {TOP; MIDDLE; BOTTOM;}
Text_Align_Hor :: enum {LEFT; MIDDLE; RIGHT;}

clipping_texture: Simp.Texture;

palette :: Palette.{
	body = .[65, 65, 65, 255],
	border = .[75, 75, 75, 255],
	text = .[255, 255, 255, 255],
	hover = .[150, 150, 150, 255],
};

button_palette :: Palette.{
	body = .[50, 50, 50, 255],
	border = .[75, 75, 75, 255],
	text = .[255, 255, 255, 255],
	hover = .[150, 150, 150, 255],
};

selected_button_palette :: Palette.{
	body = .[55, 55, 55, 255],
	border = .[75, 75, 75, 255],
	text = .[255, 127, 0, 255],
	hover = .[150, 150, 150, 255],
};

bg_palette :: Palette.{
	body = .[30, 25, 30, 255],
	border = .[32, 25, 30, 255],
	text = .[30, 25, 30, 255],
	hover = .[30, 25, 30, 255],
};

error_message_palette :: Palette.{
	body = .[160, 20, 20, 120],
	border = .[160, 30, 30, 120],
	text = .[255, 235, 235, 255],
	hover = .[160, 40, 40, 120],
};

default_tool_tip_palette :: Palette.{
	body = .[100, 100, 230, 255],
	border = .[30, 30, 200, 255],
	text = .[255, 255, 255, 255],
};

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

panel_button :: (p: *UI_Panel, pointer_position: [2]int, pressed: bool, tip: *Tool_Tip = null) -> bool {
	in_panel := pointer_is_in_panel(p, pointer_position);

	if in_panel {
		tc := p.colors;
		p.colors.body = tc.hover;
		panel_draw(p);
		p.colors = tc;
	}

	if tip {
		if in_panel {
			if tip.hovering == .Red {
				tip.hovering = .Green;
				tip.hover_started = current_time_monotonic();
			} else if tip.hovering == .Orange {
				tip.hovering = .Green;
			}
		} else {
			tip.hovering = .Red;
			return in_panel && pressed;
		}
		tip.panel.pos = pointer_position;
	}

	return in_panel && pressed;
}

make_tooltip :: (tip: string, font: *Simp.Dynamic_Font, colors := default_tool_tip_palette) -> Tool_Tip {
	text_width := Simp.prepare_text(font, tip);
	padding := font.character_height;
	tooltip: Tool_Tip;
	tooltip.tip = tip;
	tooltip.panel.size = .[text_width + padding, padding*2];
	tooltip.panel.colors = colors;
	return tooltip;
}

panel_text_split :: (mother: *UI_Panel, font: *Simp.Dynamic_Font, text: string, side: Creation_Side, other_align: enum {NEAR; MIDDLE; FAR;} = .MIDDLE) -> UI_Panel {
	text_width := Simp.prepare_text(font, text);
	padding := font.character_height;
	text_panel := mother.*;

	if #complete side == {
	case .TOP;
		text_panel = panel_split(mother, .{padding*3/2, mother.size[1]}, .TOP, true);
		panel_text(*text_panel, font, text, xx other_align, .MIDDLE);
	case .BOTTOM;
		text_panel = panel_split(mother, .{padding*3/2, mother.size[1]}, .BOTTOM, true);
		panel_text(*text_panel, font, text, xx other_align, .MIDDLE);
	case .LEFT;
		text_panel = panel_split(mother, .{text_width + padding, mother.size[0]}, .LEFT, true);
		panel_text(*text_panel, font, text, .MIDDLE, xx other_align);
	case .RIGHT;
		text_panel = panel_split(mother, .{text_width + padding, mother.size[0]}, .RIGHT, true);
		panel_text(*text_panel, font, text, .MIDDLE, xx other_align);
	}

	return text_panel;
}

panel_text :: (mother: *UI_Panel, font: *Simp.Dynamic_Font, text: string, align_h: Text_Align_Hor, align_v: Text_Align_Ver) {
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
	/* theoretically text could be clipped with two textures, and that needs minimal resizes and similar */
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

	border := float_rgb(p.colors.border);
	/* left and bottom */
	Simp.immediate_quad(bl.x, bl.y, bl.x+p.border_size, tr.y, border);
	Simp.immediate_quad(bl.x, bl.y, tr.x, bl.y+p.border_size, border);
	/* top and right */
	Simp.immediate_quad(bl.x, tr.y-p.border_size, tr.x, tr.y, border);
	Simp.immediate_quad(tr.x-p.border_size, bl.y, tr.x, tr.y, border);

	Simp.immediate_flush();
}

float_rgb :: (rgb: [4]u8) -> Vector4 {
	return .{cast(float, rgb[0])/255, cast(float, rgb[1])/255, cast(float, rgb[2])/255, cast(float, rgb[3])/255};
}
