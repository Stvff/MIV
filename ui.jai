/*
	Do not draw to panels before using them as a mother in a split call, because it will clear their content.

	If a function starts with `panel_`, then that function draws to panels.
	If a function ends with `panel`, it does something with or to the panel, but does not draw on it
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
	text: string;
	text_to_be_displayed: string;
	state: enum {Dormant; Decaying; Active;};
	hover_started: Apollo_Time;
	pointer_position: [2]int;
}

Ratio :: struct {num, den: int;}
Creation_Side :: enum {TOP; BOTTOM; LEFT; RIGHT;}

Text_Align_Ver :: enum {TOP; MIDDLE; BOTTOM;}
Text_Align_Hor :: enum {LEFT; MIDDLE; RIGHT;}

SCROLLBAR_SIZE :: 10;

default_palette :: Palette.{
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

warning_message_palette :: Palette.{
	body = .[180, 140, 40, 255],
	border = .[230, 170, 20, 255],
	text = .[255, 255, 255, 255],
	hover = .[255, 180, 30, 255],
};

good_message_palette :: Palette.{
	body = .[20, 160, 20, 255],
	border = .[30, 170, 30, 255],
	text = .[235, 255, 235, 255],
	hover = .[40, 180, 40, 255],
};

tool_tip_palette :: Palette.{
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
	horizontal := p.pos[0] <= pointer_position[0] && pointer_position[0] <= p.pos[0] + p.size[0];
	vertical := p.pos[1] <= pointer_position[1] && pointer_position[1] <= p.pos[1] + p.size[1];
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
			if tip.state == .Dormant {
				tip.state = .Active;
				tip.hover_started = current_time_monotonic();
			} else if tip.state == .Decaying {
				tip.state = .Active;
			}
			tip.text_to_be_displayed = tip.text;
		}
		tip.pointer_position = pointer_position;
	}

	return in_panel && pressed;
}

panel_toggle_button :: (p: *UI_Panel, font: *Simp.Dynamic_Font, toggle_text: [2]string, pointer_position: [2]int, pressed: bool, current_state: bool, tip: *Tool_Tip = null, optional_align_hor: Text_Align_Hor = .MIDDLE) -> bool {
	text := toggle_text[0];
	p.colors = button_palette;
	if current_state {
		text = toggle_text[1];
		p.colors = selected_button_palette;
	}

	panel_draw(p);
	button_pressed := panel_button(p, pointer_position, pressed, tip);
	panel_text(p, font, text, optional_align_hor, .MIDDLE);
	return button_pressed;
}

panel_scrollbar :: (p: *UI_Panel, pointer_position: [2]int, pointer_when_pressed: [2]int, pressed: bool) -> bool {
	bar := panel_split(p, .{SCROLLBAR_SIZE, p.size[0]}, .RIGHT, false);
	should_move := panel_button(*bar, ifx !pressed then pointer_position else pointer_when_pressed, pressed);
	return should_move;
}

panel_settings_toggle :: (p: *UI_Panel, icon_font: *Simp.Dynamic_Font, font: *Simp.Dynamic_Font, setting_text: string,
                          pointer_position: [2]int, pressed: bool, current_state: bool, tip: *Tool_Tip = null) -> bool {
	bar_height := font.character_height*2;
	this_setting_panel := panel_split(p, .{bar_height, p.size[1]}, .TOP, true);
	panel_text(*this_setting_panel, font, setting_text, .LEFT, .MIDDLE);
	this_setting_button_panel := panel_split(*this_setting_panel, .{bar_height*3/2, this_setting_panel.size[0]}, .RIGHT, false);
	return panel_toggle_button(*this_setting_button_panel, icon_font, ICON.TOGGLE, pointer_position, pressed, current_state, tip);
}

panel_slider :: (p: *UI_Panel, handle_size: int, pointer_position: [2]int, pressed: bool, current_state: float, tip: *Tool_Tip = null) -> float {
	in_panel := pointer_is_in_panel(p, pointer_position);
	p.colors = selected_button_palette;

	new_state := current_state;
	if in_panel {
		p.colors.body = p.colors.hover;
		if pressed {
			pos := pointer_position[0] - p.pos[0] - handle_size/2;
			pos = clamp(pos, 0, p.size[0] - handle_size);
			new_state = pos.(float)/(p.size[0] - handle_size).(float);
		}
	}
	panel_draw(p);

	handle: UI_Panel;
	handle.pos[0] = p.pos[0] + cast(int, new_state*(p.size[0] - handle_size).(float));
	handle.pos[1] = p.pos[1];
	handle.size[0] = handle_size;
	handle.size[1] = p.size[1];
	handle.colors.body = selected_button_palette.text;
	panel_draw(*handle);

	if tip {
		if in_panel {
			if tip.state == .Dormant {
				tip.state = .Active;
				tip.hover_started = current_time_monotonic();
			} else if tip.state == .Decaying {
				tip.state = .Active;
			}
			tip.text_to_be_displayed = tip.text;
		}
		tip.pointer_position = pointer_position;
	}
	return clamp(new_state, 0, 1);
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

	clip := Simp.Text_Clipping_Info.{
		do_clip = true,
		x_start = mother.pos[0], y_start = mother.pos[1],
		x_end = mother.pos[0] + mother.size[0], y_end = mother.pos[1] + mother.size[1]
	};

	Simp.set_shader_for_text();
	Simp.draw_prepared_text(font, x_pos + xx mother.pos[0], y_pos + xx mother.pos[1], float_rgb(text_panel.colors.text), clipping = clip);
}

panel_from_text :: (font: *Simp.Dynamic_Font, text: string, pos: [2]int, align_h: Text_Align_Hor, align_v: Text_Align_Ver, palette := default_palette) -> UI_Panel {
	text_size, lines := flow_text(font, text);

	// text_width := Simp.prepare_text(font, text);
	padding := font.character_height;
	panel: UI_Panel;
	panel.size = text_size;
	// panel.size = .[text_width + padding, padding*2];
	panel.colors = palette;
	panel.pos = pos;

	if #complete align_h == {
	case .LEFT;
	case .MIDDLE;
		panel.pos[0] -= panel.size[0]/2;
	case .RIGHT;
		panel.pos[0] -= panel.size[0];
	}
	if #complete align_v == {
	case .TOP;
		panel.pos[1] -= panel.size[1];
	case .MIDDLE;
		panel.pos[1] -= panel.size[1]/2;
	case .BOTTOM;
	}

	panel_draw(*panel);
	// panel_text(*panel, font, text, .MIDDLE, .MIDDLE);
	draw_flow_text(font, lines, panel.pos, panel.size);
	return panel;
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

flow_text :: (font: *Simp.Dynamic_Font, text: string) -> [2]int, []string {
	lines := split(text, "\n",, allocator = temp);
	padding := font.character_height;
	size := int.[0, padding];
	for line: lines {
		width := Simp.prepare_text(font, line) + padding;
		if width > size[0] size[0] = width;
		size[1] += font.character_height;
	}
	return size, lines;
}

draw_flow_text :: (font: *Simp.Dynamic_Font, lines: []string, pos: [2]int, size: [2]int) {
	padding := font.character_height;
	tpos := int.[pos[0] + padding/2, pos[1] + size[1] - padding - padding/4];
	for line: lines {
		Simp.draw_text(font, tpos[0], tpos[1], line);
		tpos[1] -= padding;
	}
}

draw_line :: (start: Vector2, end: Vector2, thickness: float, color: [4]u8) {
	Simp.immediate_begin();
	Simp.set_shader_for_color();
	fcolor := float_rgb(color);
	thick := start - end;
	thick = thickness*Vector2.{ -thick.y, thick.x}/(2*length(thick));
	bl := start + thick;
	br := start - thick;
	tr := end - thick;
	tl := end + thick;
	Simp.immediate_quad(bl, br, tr, tl, fcolor);
	// Simp.immediate_quad(start[0].(float), start[1].(float), end[0].(float), end[1].(float), fcolor);
	Simp.immediate_flush();

}

FONT_PATH :: "./assets/LibertinusSerif-Regular.otf";
FONT_DATA :: #run cast([]u8) read_entire_file(FONT_PATH);

ICON_FONT_PATH :: "./assets/IconsMIV.otf";
ICON_FONT_DATA :: #run cast([]u8) read_entire_file(ICON_FONT_PATH);
ICON :: struct {
	SETTINGS :: string.["S", "S"];
	FIT_121 :: "1";
	FIT_FILL :: "F";
	FIT_WIDTH :: "W";
	FIT_HEIGHT :: "H";
	FIT_BEST :: "B";
	ANTI_ALIAS :: string.["A", "A"];
	ZOOM_CENTER :: "M";
	ZOOM_POINTER :: "P";
	ROTATE :: string.["R", "R"];
	COPY :: "c";
	COPY_TEXT :: "T"; //Unused

	METADATA :: string.["m", "m"];
	HISTORY :: "C";
	DIRECTORY :: "D";
	PREV :: "<";
	NEXT :: ">";

	OFF :: "[)";
	ON :: "(]";
	RADIO_OFF :: "o";
	RADIO_ON :: "O";

	TOGGLE :: string.[ICON.OFF, ICON.ON];
	RADIO :: string.[ICON.RADIO_OFF, ICON.RADIO_ON];
}
