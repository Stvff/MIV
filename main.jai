Image_Context :: struct {
	fit : enum {ONE_TO_ONE; FIT_FILL; FIT_WIDTH; FIT_HEIGHT; FIT_BEST;}
	offset: Vector2;
	pre_pan_offset: Vector2;
	zoom_alignment: Zoom_Alignment_Setting;
	scale: float;
	angle: float;
	pre_rot_angle: float;

	smoothing_on: bool;
	linear_downscaling: bool;

	auto_fit: bool;
	render: bool;
	draw: bool;

	watcher_says_rerender: bool;
	watcher_says_something_moved_somewhere: bool;
	watcher: File_Watcher(Image_Context);

	plugin: *Registration_Entry;
	pre_info: Pre_Rendering_Info;
	render_info: Rendering_Info;
	settings_info: Settings_Info;
}

Input_State :: struct {
	arrow_up: bool;
	arrow_down: bool;

	arrow_left: bool;
	arrow_right: bool;

	scroll_delta: float;


	w, a, s, d: bool;

	fpointer: Vector2;
	ipointer: [2]int;

	right_button_switch: bool;
	left_button_switch: bool;
	middle_button_switch: bool;

	v: bool;

	using persistent: struct {
		arrow_left_repeat: bool;
		arrow_right_repeat: bool;

		shifted: bool;
		ctrl: bool;
		left_button: bool;
		right_button: bool;
		middle_button: bool;
		lpointer_when_pressed: Vector2;
		rpointer_when_pressed: Vector2;
	}
}

window_size: [2]int;
os_window: Winc.Window_Type;
MAX_FRAME_TIME :: 1.0/10.0;
DEFAULT_FRAME_TIME :: 1/120.0;
MIN_FRAME_TIME :: 1.0/240.0;
FRAME_TIME_CYCLE :: float64.[1/24.0, 1/29.97, 1/30.0, 1/60.0, 1/120.0];

main :: () {
	log_entries: [..]Log_Entry;
	option_entries := 0;
	context.logger_data = *log_entries;
	context.logger = logger;

	settings: Settings_File_3 = load_registrations();
	defer cleanup_registrations(settings);

	/*# UI definitions */
	fontsize := 17;
	{
		window_width := 1400;
		window_height := 800;
		// window_width := settings.window_size_on_previous_close[0];
		// window_height := settings.window_size_on_previous_close[1];
		// if window_width == 0 || window_height == 0 {
		// 	window_width = 1400;
		// 	window_height = 800;
		// }
		os_window = Winc.create_window(window_width, window_height, "MIV");
		Simp.prepare_window(os_window, 4);
		dnd_typelist := string.["url/url", "text/uri-list", "text/plain", "application/octet-stream"];
		X11.enable_drag_and_drop(os_window, dnd_typelist);
		window_size = .[window_width, window_height];
	}
	Simp.set_render_target(os_window);
	bar_height := fontsize*2;

	inp: Input_State;

	/*# Font loading */
	font_pixel_height := bar_height/2;
	main_font := Simp.get_font_at_size(FONT_DATA, font_pixel_height);
	icon_font := Simp.get_font_at_size(ICON_FONT_DATA, font_pixel_height);

	/*# Image context etc */
	img_ctx := Image_Context.{
		fit = .FIT_BEST,
		scale = 1.0,
		render = false,
		draw = true,
	};

	if !init(*img_ctx.watcher, file_change_callback, *img_ctx, events_to_watch = .ALL_EVENTS, merge_window_seconds = 2*DEFAULT_FRAME_TIME, verbose = false, watch_recursively = false) {
		log_error("Could not initialize watcher");
		return;
	}
	defer if img_ctx.watcher.callback deinit(img_ctx.watcher);

	/*# window specific image context */
	fileq_setting: enum {HISTORY; DIRECTORY;} = .HISTORY;
	file_history: [..]string;
	file_history_index: int;
	directory: [..]string;
	directory_index: int;
	current_q: *[..]string = *file_history;
	current_q_index: *int = *file_history_index;

	added_string_queue: [..]string;
	{
		cli_args := get_command_line_arguments();
		cli_args.data += 1;
		cli_args.count -= 1;
		array_add(*added_string_queue, ..cli_args);
	}
	gpu_texture: Simp.Texture;

	/*# UI state */
	display_metadata := false;
	DEFAULT_METADATA_WIDTH := bar_height*5;
	metadata_width := DEFAULT_METADATA_WIDTH;

	display_settings_menu := false;
	DEFAULT_SETTINGS_MENU_WIDTH := bar_height*8;
	settings_menu_width := DEFAULT_SETTINGS_MENU_WIDTH;
	settings_menu_just_opened := false;
	tip: Tool_Tip;
	elaborate_tips := settings.elaborate_tips;

	/*# Timing */
	target_frame_time: float64 = DEFAULT_FRAME_TIME;
	if settings.target_frame_time_on_previous_close >= MIN_FRAME_TIME && settings.target_frame_time_on_previous_close <= MAX_FRAME_TIME {
		target_frame_time = settings.target_frame_time_on_previous_close;
	}
	last_1s_time := current_time_monotonic();
	prev_time := last_1s_time;

	frame_1s_counter := 0;
	frame_count_over_1s := 60;

	/*# settings saving */
	first_image_open := true;
	defer {
		if settings.pers_between_restarts.of_aa {
			settings.smoothing_setting_on_previous_close = img_ctx.smoothing_on;
			settings.downscaling_on_previous_close = img_ctx.linear_downscaling;
		}
		if settings.pers_between_restarts.of_scale then settings.scale_on_previous_close = img_ctx.scale;
		if settings.pers_between_restarts.of_offset {
			settings.offset_on_previous_close = img_ctx.offset;
			settings.angle_on_previous_close = img_ctx.angle;
		}
		settings.zoom_alignment_on_previous_close = img_ctx.zoom_alignment;
		settings.target_frame_time_on_previous_close = target_frame_time;
		settings.elaborate_tips = elaborate_tips;

		settings.window_size_on_previous_close = window_size;
	}

	running := true;
	while running {
		/*# Timings etc */
		frame_1s_counter += 1;
		now := current_time_monotonic();
		if to_float64_seconds(now - last_1s_time) > 0.2 {
			frame_count_over_1s = frame_1s_counter*5;
			frame_1s_counter = 0;
			last_1s_time = now;
		}
		frame_time := to_float64_seconds(now - prev_time);
		if frame_time < target_frame_time {
			posix.usleep(cast(u32, (target_frame_time - frame_time)*1_000_000));
		}
		prev_time = current_time_monotonic();

		/*# Window resize */
		Input.update_window_events();
		for Input.get_window_resizes() {
			Simp.update_window(it.window);
			if it.window == os_window {
				window_size = .[it.width, it.height];
				/* if I ever dynamically adjust bar height, I would do it here (see how I did it in git) */
				Gl.glXSwapIntervalEXT(X11.x_global_display, Simp.find_window_info(os_window).specific.glx_window, 0);
			}
		}

		/*# Inputs */
		{ /* Reset */
			p := inp.persistent;
			inp = .{};
			inp.persistent = p;
		}
		for event: Input.events_this_frame {
			if event.type == .QUIT then running = false;
			/* Press */
			if (event.type == .KEYBOARD) && event.key_pressed then if event.key_code == {
				case .ESCAPE; running = false;
				case .SHIFT; inp.shifted = true;
				case .CTRL; inp.ctrl = true;
				case .ARROW_UP; inp.arrow_up = true;
				case .ARROW_DOWN; inp.arrow_down = true;
				case .ARROW_LEFT;
					inp.arrow_left = true;
					inp.arrow_left_repeat = event.repeat;
				case .ARROW_RIGHT;
					inp.arrow_right = true;
					inp.arrow_right_repeat = event.repeat;
				case #char "W"; inp.w = true;
				case #char "A"; inp.a = true;
				case #char "S"; inp.s = true;
				case #char "D"; inp.d = true;
				case #char "V"; inp.v = true;
				case .MOUSE_BUTTON_RIGHT;
					inp.right_button_switch = true;
					inp.rpointer_when_pressed = get_pointer_position();
					inp.right_button = true;
				case .MOUSE_BUTTON_LEFT;
					inp.left_button_switch = true;
					inp.lpointer_when_pressed = get_pointer_position();
					inp.left_button = true;
				case .MOUSE_BUTTON_MIDDLE;
					inp.middle_button_switch = true;
					inp.middle_button = true;
			}
			/* Release */
			if (event.type == .KEYBOARD) && !event.key_pressed then if event.key_code == {
				case .ARROW_LEFT; inp.arrow_left_repeat = false;
				case .ARROW_RIGHT; inp.arrow_right_repeat = false;
				case .SHIFT; inp.shifted = false;
				case .CTRL; inp.ctrl = false;
				case .MOUSE_BUTTON_LEFT; inp.left_button = false;
				case .MOUSE_BUTTON_RIGHT; inp.right_button = false;
				case .MOUSE_BUTTON_MIDDLE; inp.middle_button = false;
			}
			/* Scroll */
			if event.type == .MOUSE_WHEEL {
				inp.scroll_delta = cast(float, event.wheel_delta)/cast(float, event.typical_wheel_delta);
			}

			if event.type == .DRAG_AND_DROP_FILES for event.files {
				array_add(*added_string_queue, copy_string(it));
			}
			if inp.ctrl && inp.v {
				added_files := split(Clippy.os_clipboard_get_text(), "\n",, temp);
				for added_files array_add(*added_string_queue, copy_string(it));
			}
		}
		/* mouse */
		inp.fpointer = get_pointer_position();
		inp.ipointer = .[xx inp.fpointer.x, xx inp.fpointer.y];

		loading_time := current_time_monotonic();

		/* Filtering out .so files */
		filter_index := 0;
		while filter_index < added_string_queue.count {
			added_string := added_string_queue[filter_index];
			log("%", added_string, flags = .VERBOSE_ONLY);
			if get_extension(added_string) == "so" {
				register_dynlib(added_string, true, true);
				array_ordered_remove_by_index(*added_string_queue, filter_index);
			} else filter_index += 1;
		}
		/* filtering out unknown image formats */
		sanitize_file_list(*added_string_queue, "", null, true);

		for added_string_queue {
			array_add(*file_history, it);
			file_history_index = file_history.count-1;
			img_ctx.render = true; /* I know we're setting this for every dropped file, but it's worth it in code clarity imo */
		}
		if added_string_queue.count == 1 {
			fileq_setting = .DIRECTORY;
			/* I'm assuming there's always a valid file in this directory */
			discover_directory(*directory, file_history[file_history_index]);
			sanitize_file_list(*directory, file_history[file_history_index], *directory_index, false);
			current_q = *directory;
			current_q_index = *directory_index;
		} else if added_string_queue.count > 1 {
			fileq_setting = .HISTORY;
			current_q = *file_history;
			current_q_index = *file_history_index;
		}
		array_reset(*added_string_queue);

		/*# The watcher */
		process_changes(*img_ctx.watcher);
		if img_ctx.watcher_says_something_moved_somewhere {
			log("File watcher has noticed something", flags = .VERBOSE_ONLY);
			img_ctx.watcher_says_something_moved_somewhere = false;

			sanitize_file_list(*file_history, file_history[file_history_index], *file_history_index, false);
			if file_history_index == -1 {
				img_ctx.render = false;
			} else if fileq_setting == .DIRECTORY {
				/* I'm assuming there's always a valid file in this directory */
				discover_directory(*directory, file_history[file_history_index]);
				sanitize_file_list(*directory, file_history[file_history_index], *directory_index, false);
			}
		}
		if img_ctx.watcher_says_rerender {
			img_ctx.watcher_says_rerender = false;
			img_ctx.render = true;
		}

		if current_q.count == 0 img_ctx.render = false;
		pre_render_failed := false;
		/*# image pre-render */
		if img_ctx.render {
			old_pre_info := img_ctx.pre_info;
			new_name := current_q.*[current_q_index.*];
			img_ctx.render = get_loading(new_name, get_extension(new_name), *img_ctx, true);
			if img_ctx.render {
				if old_pre_info.fileptr posix.fclose(old_pre_info.fileptr);
				/* TODO: retrieve previous offsets etc from some per-file history */

				if !settings.pers_between_files.of_scale img_ctx.auto_fit = true;
				if !settings.pers_between_files.of_offset {
					img_ctx.offset = .{0, 0};
					img_ctx.angle = 0;
				}
				if !settings.pers_between_files.of_aa {
					img_ctx.smoothing_on = false;
					img_ctx.linear_downscaling = false;
				}

				if first_image_open {
					if settings.pers_between_restarts.of_aa {
						img_ctx.smoothing_on = settings.smoothing_setting_on_previous_close;
						img_ctx.linear_downscaling = settings.downscaling_on_previous_close;;
					}
					if settings.pers_between_restarts.of_scale {
						img_ctx.scale = settings.scale_on_previous_close;
						img_ctx.auto_fit = false;
					} else img_ctx.auto_fit = true;
					if settings.pers_between_restarts.of_offset {
						img_ctx.offset = settings.offset_on_previous_close;
						img_ctx.angle = settings.angle_on_previous_close;
					}
					img_ctx.zoom_alignment = settings.zoom_alignment_on_previous_close;
					first_image_open = false;
				}
			} else {
				pre_render_failed = true;
				f, index := array_find(file_history, new_name);
				if f array_ordered_remove_by_index(*file_history, index);
				file_history_index = clamp(file_history_index, 0, file_history.count-1);

				f, index = array_find(directory, new_name);
				if f array_ordered_remove_by_index(*directory, index);
				directory_index = clamp(directory_index, 0, directory.count-1);
			}
			new_print_style := context.print_style;
			new_print_style.default_format_struct.use_newlines_if_long_form = true;
			new_print_style.default_format_array.stop_printing_after_this_many_elements = 4;
			log("img_ctx = .%", img_ctx, flags = .VERBOSE_ONLY,, print_style = new_print_style);
		}
		if current_q_index.* == -1 || pre_render_failed then img_ctx.draw = false;
		else img_ctx.draw = true;

		/*# Image rendering (aka resolving the actual data) */
		if !img_ctx.plugin { img_ctx.render = false; img_ctx.draw = false; }
		if img_ctx.render {
			using img_ctx.render_info;
			buffer_width := img_ctx.pre_info.width;
			buffer_height := img_ctx.pre_info.height;
			array_resize(*(buffer), buffer_width*buffer_height);
			render_error := img_ctx.plugin.render(*img_ctx.pre_info, *img_ctx.render_info);
			if render_error {
				log_error("Image data retrieval error: %", render_error);
				img_ctx.draw = false;
			} else {
				bitmap: Simp.Bitmap;
				bitmap.width = xx buffer_width;
				bitmap.height = xx buffer_height;
				bitmap.data.count = buffer.count*size_of([4]u8);
				bitmap.data.data = xx buffer.data;
				bitmap.stride = cast(s32, buffer_width*size_of([4]u8));
				bitmap.format = .RGBA8;
				Simp.texture_load_from_bitmap(*gpu_texture, *bitmap);
			}
			img_ctx.render = false;

			loading_time = current_time_monotonic() - loading_time;
			log("Loading time: %, associated fps if we did nothing but this: %", to_float64_seconds(loading_time), 1/to_float64_seconds(loading_time), flags = .VERBOSE_ONLY);
		}

		{/*# Drawing time */
			/* First we define the broad outline of panels that we'll see (the ones that make the canvas smaller) */
			canvas := UI_Panel.{
				size = window_size,
				colors = default_palette,
				border_size = 1,
			};

			top_bar := panel_split(*canvas, .{bar_height, canvas.size[1]}, .TOP, false);
			bottom_bar := panel_split(*canvas, .{bar_height - 4, canvas.size[1]}, .BOTTOM, false);
			settings_menu_panel, metadata_panel: UI_Panel;

			if display_settings_menu
				settings_menu_panel = panel_split(*canvas, .{settings_menu_width, canvas.size[0]}, .LEFT, false);
			if display_metadata
				metadata_panel = panel_split(*canvas, .{metadata_width, canvas.size[0]}, .LEFT, false);

			first_layer_is_pressable := option_entries == 0;

			/*# Image drawing */
			canvas.colors = bg_palette;
			canvas.colors.body[0] = settings.bg_color[0];
			canvas.colors.body[1] = settings.bg_color[1];
			canvas.colors.body[2] = settings.bg_color[2];
			panel_draw(*canvas);
			if img_ctx.draw {
				screen_offset := Vector2.{ cast(float, canvas.pos[0]), cast(float, canvas.pos[1]) };
				screen_center := Vector2.{ cast(float, canvas.size[0])/2, cast(float, canvas.size[1])/2 };
				image_center := Vector2.{ cast(float, img_ctx.pre_info.width)/2, cast(float, img_ctx.pre_info.height)/2 };

				/* we have to process our inputs (not using the keyboard yet) */
				process_mouse_activity := first_layer_is_pressable && pointer_is_in_panel(*canvas, inp.ipointer);
				if inp.left_button && !pointer_is_in_panel(*canvas, .[xx inp.lpointer_when_pressed.x, xx inp.lpointer_when_pressed.y]) {
					process_mouse_activity = false;
				}
				if process_mouse_activity {
					if inp.scroll_delta if img_ctx.zoom_alignment == {
					case .CENTER;
						img_ctx.auto_fit = false;
						delta := inp.scroll_delta / ifx inp.shifted then 200 else 10;
						if delta < 0 img_ctx.scale /= 1 + abs(delta);
						else img_ctx.scale *= 1 + abs(delta);
					case .POINTER;
						img_ctx.auto_fit = false;
						delta := inp.scroll_delta / ifx inp.shifted then 200 else 10;
						old_scale := img_ctx.scale;
						if delta < 0 img_ctx.scale /= 1 + abs(delta);
						else img_ctx.scale *= 1 + abs(delta);
						diff := screen_offset + screen_center - inp.fpointer;
						diff = diff/old_scale - diff/img_ctx.scale;
						img_ctx.offset += diff;
					}
					if inp.middle_button {
						img_ctx.auto_fit = true;
						img_ctx.offset = .{};
						img_ctx.angle = 0;
					}

					if inp.left_button {
						img_ctx.auto_fit = false;
						diff := inp.fpointer - inp.lpointer_when_pressed;
						img_ctx.offset = img_ctx.pre_pan_offset + diff/img_ctx.scale;
					} else {
						img_ctx.pre_pan_offset = img_ctx.offset;
					}

					if inp.right_button {
						img_ctx.auto_fit = false;
						diff := inp.fpointer - inp.rpointer_when_pressed;
						from := normalize(inp.rpointer_when_pressed - screen_center - img_ctx.offset*img_ctx.scale);
						to := normalize(inp.fpointer - screen_center - img_ctx.offset*img_ctx.scale);
						cos_a := dot(from, to);
						sign := ifx from.x*to.y - from.y*to.x < 0 then -1 else 1;
						angle := sign*acos(cos_a)/TAU;
						img_ctx.angle = img_ctx.pre_rot_angle + angle*360;
					} else img_ctx.pre_rot_angle = img_ctx.angle;
				}
				img_ctx.scale = clamp(img_ctx.scale, 1/cast(float, max(img_ctx.pre_info.width, img_ctx.pre_info.height)), cast(float, max(canvas.size[0], canvas.size[1])));

				now_fit := img_ctx.fit;
				if now_fit == .FIT_BEST {
					screen_woh := screen_center.x/screen_center.y;
					image_woh := image_center.x/image_center.y;
					if screen_woh > image_woh now_fit = .FIT_HEIGHT;
					else now_fit = .FIT_WIDTH;
				}
				if now_fit == .FIT_FILL {
					screen_woh := screen_center.x/screen_center.y;
					image_woh := image_center.x/image_center.y;
					if screen_woh > image_woh now_fit = .FIT_WIDTH;
					else now_fit = .FIT_HEIGHT;
				}

				if img_ctx.auto_fit {
					if #complete now_fit == {
					case .ONE_TO_ONE;
						img_ctx.scale = 1;
					case .FIT_FILL; /* should be unreachable */
					case .FIT_WIDTH;
						img_ctx.scale = screen_center.x/image_center.x;
					case .FIT_HEIGHT;
						img_ctx.scale = screen_center.y/image_center.y;
					case .FIT_BEST; /* should be unreachable */
					}
				}

				image_bounds := Vector2.[
					-image_center, .{image_center.x, -image_center.y}, image_center, .{-image_center.x, image_center.y}
				];

				if 0 > img_ctx.angle || img_ctx.angle >= 360 {
					f := (img_ctx.angle + 720)/360;
					img_ctx.angle = (f - floor(f))*360;
				}
				if img_ctx.angle - floor(img_ctx.angle) >= 0.5 then img_ctx.angle = floor(img_ctx.angle) + 1;
				else img_ctx.angle = floor(img_ctx.angle);
				rad := 2*PI*img_ctx.angle/360;
				rot_mat := Matrix2.{
					cos(rad), -sin(rad),
					sin(rad), cos(rad)
				};
				for * image_bounds {
					it.* = rot_mat*it.*;

					it.* += img_ctx.offset;
					it.* *= img_ctx.scale;
					it.* += screen_center;

					it.* += .{xx canvas.pos[0], xx canvas.pos[1]};
				}

				Simp.set_shader_for_images(*gpu_texture);
				Simp.immediate_begin();
				Gl.glBindTexture(Gl.GL_TEXTURE_2D, gpu_texture.gl_handle);
				if img_ctx.smoothing_on {
					Gl.glTexParameteri(Gl.GL_TEXTURE_2D, Gl.GL_TEXTURE_MAG_FILTER, Gl.GL_LINEAR);
					if img_ctx.linear_downscaling Gl.glTexParameteri(Gl.GL_TEXTURE_2D, Gl.GL_TEXTURE_MIN_FILTER, Gl.GL_LINEAR);
					else Gl.glTexParameteri(Gl.GL_TEXTURE_2D, Gl.GL_TEXTURE_MIN_FILTER, Gl.GL_NEAREST);
				} else {
 					Gl.glTexParameteri(Gl.GL_TEXTURE_2D, Gl.GL_TEXTURE_MAG_FILTER, Gl.GL_NEAREST);
 					Gl.glTexParameteri(Gl.GL_TEXTURE_2D, Gl.GL_TEXTURE_MIN_FILTER, Gl.GL_NEAREST);
				}
				Simp.immediate_quad(image_bounds[0], image_bounds[1], image_bounds[2], image_bounds[3]);
			}
			panel_draw(*top_bar);
			panel_draw(*bottom_bar);

			/*# settings menu */
			if display_settings_menu {
				panel_draw(*settings_menu_panel);
				if panel_scrollbar(*settings_menu_panel, inp.ipointer, .[xx inp.lpointer_when_pressed.x, xx inp.lpointer_when_pressed.y], inp.left_button) {
					settings_menu_width += (inp.fpointer.x - inp.lpointer_when_pressed.x).(int);
					settings_menu_width = clamp(settings_menu_width, 0, window_size[0] - settings_menu_panel.pos[0]);
					inp.lpointer_when_pressed = inp.fpointer;
				}
				if settings_menu_width < SCROLLBAR_SIZE*7 {
					display_settings_menu = false;
					settings_menu_width = DEFAULT_SETTINGS_MENU_WIDTH;
					inp.left_button = false;
				}

				table_space := panel_split(*settings_menu_panel, .{bar_height*9/2, settings_menu_panel.size[1]}, .TOP, false);
				first_col := panel_split(*table_space, .{bar_height*7/2, table_space.size[0]}, .LEFT, false);
				remaining_cols := panel_subdivide(*table_space, 2, .HORIZONTAL, false);
				cols: [3]UI_Panel = .[first_col, remaining_cols[0], remaining_cols[1]];
				table: [3][4]UI_Panel;
				for col: 0..2 {
					col_p := *cols[col];
					row_p := panel_split(col_p, .{bar_height*3/2, col_p.size[1]}, .TOP, true);
					table[col][0] = row_p;

					remaining_rows := panel_subdivide(col_p, 3, .VERTICAL, true);
					table[col][1] = remaining_rows[0];
					table[col][2] = remaining_rows[1];
					table[col][3] = remaining_rows[2];
				}
				tip.text = "Menu for persistence of settings between files or restarts";
				if elaborate_tips tip.text = "Menu for persistence of settings between files or restarts:\nWith this menu, you can choose which settings are reset when you restart MIV,\nand which settings are reset every time a new image is opened.";
				panel_button(*table[0][0], inp.ipointer, false, *tip);
				panel_text(*table[0][0], main_font, "Persistence", .MIDDLE, .MIDDLE);
				panel_text(*table[1][0], main_font, "between", .MIDDLE, .TOP);
				panel_text(*table[1][0], main_font, "files", .MIDDLE, .BOTTOM);
				panel_text(*table[2][0], main_font, "between", .MIDDLE, .TOP);
				panel_text(*table[2][0], main_font, "restarts", .MIDDLE, .BOTTOM);

				panel_text(*table[0][1], main_font, "of smoothing", .MIDDLE, .MIDDLE);
				panel_text(*table[0][2], main_font, "of zoom", .MIDDLE, .MIDDLE);
				panel_text(*table[0][3], main_font, "of offset", .MIDDLE, .MIDDLE);

				settings_table: *[2][3]bool = xx *settings.pers_between_files;
				for col: 1..2 for row: 1..3 {
					if panel_toggle_button(*table[col][row], icon_font, ICON.TOGGLE, inp.ipointer, inp.left_button_switch, settings_table.*[col-1][row-1]) {
						settings_table.*[col-1][row-1] = !settings_table.*[col-1][row-1];
					}
				}

				panel_split(*settings_menu_panel, .{bar_height/2, settings_menu_panel.size[1]}, .TOP, false);
				/* debug logging toggle */
				debug_logging_panel := panel_split(*settings_menu_panel, .{bar_height, settings_menu_panel.size[1]}, .TOP, true);
				panel_text(*debug_logging_panel, main_font, "debug logging:", .LEFT, .MIDDLE);
				debug_button_panel := panel_split(*debug_logging_panel, .{bar_height*3/2, debug_logging_panel.size[0]}, .RIGHT, false);
				if panel_toggle_button(*debug_button_panel, icon_font, ICON.TOGGLE, inp.ipointer, inp.left_button_switch, context.log_level == .VERBOSE) {
					if context.log_level == .VERBOSE context.log_level = .NORMAL;
					else context.log_level = .VERBOSE;
				}

				/* downscaling setting */
				downscaling_panel := panel_split(*settings_menu_panel, .{bar_height, settings_menu_panel.size[1]}, .TOP, true);
				panel_text(*downscaling_panel, main_font, "linear downscaling:", .LEFT, .MIDDLE);
				downscaling_button_panel := panel_split(*downscaling_panel, .{bar_height*3/2, downscaling_panel.size[0]}, .RIGHT, false);
				if panel_toggle_button(*downscaling_button_panel, icon_font, ICON.TOGGLE, inp.ipointer, inp.left_button_switch, img_ctx.linear_downscaling) {
					img_ctx.linear_downscaling = !img_ctx.linear_downscaling;
				}

				/* elaborate tooltips settings */
				elaborate_tips_panel := panel_split(*settings_menu_panel, .{bar_height, settings_menu_panel.size[1]}, .TOP, true);
				panel_text(*elaborate_tips_panel, main_font, "elaborate tooltips:", .LEFT, .MIDDLE);
				elaborate_tips_button_panel := panel_split(*elaborate_tips_panel, .{bar_height*3/2, elaborate_tips_panel.size[0]}, .RIGHT, false);
				tip.text = "When turned on, tooltips will contain more information about what a setting or button does.";
				if panel_toggle_button(*elaborate_tips_button_panel, icon_font, ICON.TOGGLE, inp.ipointer, inp.left_button_switch, elaborate_tips, tip = *tip) {
					elaborate_tips = !elaborate_tips;
				}

				/* FPS slider */
				fps_panel := panel_split(*settings_menu_panel, .{bar_height*2, settings_menu_panel.size[1]}, .TOP, false);
				fps_slider_panel := panel_split(*fps_panel, .{1, 2}, .BOTTOM, true);
				fps_text := tprint("% fps, % ms", formatFloat(1/target_frame_time, trailing_width = 2), formatFloat(target_frame_time*1000, trailing_width = 2));
				panel_text_split(*fps_panel, main_font, fps_text, .RIGHT, .MIDDLE);
				panel_text(*fps_panel, main_font, "fps target:", .LEFT, .MIDDLE);

				slider_pos := (target_frame_time.(float) - MIN_FRAME_TIME)/(MAX_FRAME_TIME - MIN_FRAME_TIME);
				slider_pos = 1 - panel_slider(*fps_slider_panel, DEFAULT_SLIDER_HANDLE_SIZE, inp.ipointer, inp.left_button, 1 - slider_pos);
				target_frame_time = (MIN_FRAME_TIME + slider_pos*(MAX_FRAME_TIME - MIN_FRAME_TIME));

				if pointer_is_in_panel(*fps_slider_panel, inp.ipointer) && inp.middle_button_switch {
					found := false;
					for ft: FRAME_TIME_CYCLE {
						if abs(1/ft - 1/target_frame_time) < 0.001 {
							found = true;
							target_frame_time = FRAME_TIME_CYCLE[(it_index + 1)%FRAME_TIME_CYCLE.count];
							break;
						}
					}
					if !found target_frame_time = DEFAULT_FRAME_TIME;
				}

				/* Background color selection */
				bg_color_panel := panel_split(*settings_menu_panel, .{bar_height*4, settings_menu_panel.size[1]}, .TOP, false);
				bg_color_subpanels := panel_subdivide(*bg_color_panel, 4, .VERTICAL, false);
				bg_color_text := tprint("(%, %, %)", settings.bg_color[0], settings.bg_color[1], settings.bg_color[2]);
				panel_text_split(*bg_color_subpanels[3], main_font, bg_color_text, .RIGHT);
				panel_text(*bg_color_subpanels[3], main_font, "background color:", .LEFT, .MIDDLE);
				for 0..2 {
					if pointer_is_in_panel(*bg_color_subpanels[it], inp.ipointer) && inp.middle_button {
						settings.bg_color[0] = bg_palette.body[0];
						settings.bg_color[1] = bg_palette.body[1];
						settings.bg_color[2] = bg_palette.body[2];
					}
					colornames :: string.["B", "G", "R"];
					p := panel_split(*bg_color_subpanels[it], .{bar_height, bg_color_subpanels[it].size[0]}, .LEFT, true);
					panel_text(*p, main_font, colornames[it], .MIDDLE, .MIDDLE);
				}
				settings.bg_color[2] = cast(u8, panel_slider(*bg_color_subpanels[0], DEFAULT_SLIDER_HANDLE_SIZE, inp.ipointer, inp.left_button, settings.bg_color[2].(float)/255)*255);
				settings.bg_color[1] = cast(u8, panel_slider(*bg_color_subpanels[1], DEFAULT_SLIDER_HANDLE_SIZE, inp.ipointer, inp.left_button, settings.bg_color[1].(float)/255)*255);
				settings.bg_color[0] = cast(u8, panel_slider(*bg_color_subpanels[2], DEFAULT_SLIDER_HANDLE_SIZE, inp.ipointer, inp.left_button, settings.bg_color[0].(float)/255)*255);

				/*# plugin settings */
				if img_ctx.plugin && img_ctx.plugin.plugin_provided.has_settings {
					if settings_menu_just_opened || img_ctx.settings_info.options.data == null {
						img_ctx.settings_info.changed_index = -1;
						img_ctx.settings_info.changed_secondary_index = -1;
						settings_info := img_ctx.settings_info;
						error_str := img_ctx.plugin.settings(*img_ctx.pre_info, *img_ctx.render_info, *settings_info);
						if error_str {
							log_error("Plugin for '%' settings retrieval error: %", img_ctx.plugin.plugin_provided.name_of_filetype, error_str);
						} else img_ctx.settings_info = settings_info;
					}

					panel_split(*settings_menu_panel, .{bar_height, settings_menu_panel.size[1]}, .TOP, false);
					title_panel := panel_split(*settings_menu_panel, .{bar_height, settings_menu_panel.size[1]}, .TOP, false);
					panel_text(*title_panel, main_font, tprint("% settings:", img_ctx.plugin.plugin_provided.name_of_filetype), .LEFT, .MIDDLE);

					for * option: img_ctx.settings_info.options {
						changed := false;
						if #complete option.type == {
						case .TOGGLE;
							section := panel_split(*settings_menu_panel, .{bar_height, settings_menu_panel.size[1]}, .TOP, true);
							panel_text(*section, main_font, tprint(" %:", option.name), .LEFT, .MIDDLE);
							button_panel := panel_split(*section, .{bar_height*3/2, section.size[0]}, .RIGHT, false);

							if panel_toggle_button(*button_panel, icon_font, ICON.TOGGLE, inp.ipointer, inp.left_button_switch, option.toggle) {
								option.toggle = !option.toggle;
								img_ctx.settings_info.changed_index = xx it_index;
								changed = true;
							}

						case .LIST;
							list_panel := panel_split(*settings_menu_panel, .{bar_height*(1 + option.list.count), settings_menu_panel.size[1]}, .TOP, true);
							list_title_panel := panel_split(*list_panel, .{bar_height, list_panel.size[1]}, .TOP, true);
							panel_text(*list_title_panel, main_font, tprint(" %:", option.name), .LEFT, .MIDDLE);
							list_options_panels := panel_subdivide(*list_panel, option.list.count, .VERTICAL, false);
							current_option_index := it_index;
							for * list_options_panels {
								if panel_toggle_button(it, icon_font, ICON.RADIO, inp.ipointer, inp.left_button_switch, option.list[it_index].selected, optional_align_hor = .LEFT) {
									option.list[it_index].selected = !option.list[it_index].selected;
									img_ctx.settings_info.changed_index = xx current_option_index;
									img_ctx.settings_info.changed_secondary_index = xx it_index;
									changed = true;
								}

								panel_text(it, main_font, option.list[it_index].name, .RIGHT, .MIDDLE);
							}

						case .SLIDER;
							slider_panel := panel_split(*settings_menu_panel, .{bar_height*2, settings_menu_panel.size[1]}, .TOP, true);
							slider_track_panel := panel_split(*slider_panel, .{1, 2}, .BOTTOM, true);
							panel_text_split(*slider_panel, main_font, option.slider.value_text, .RIGHT, .MIDDLE);
							panel_text(*slider_panel, main_font, tprint("%:", option.name), .LEFT, .MIDDLE);

							result := panel_slider(*slider_track_panel, option.slider.handle_size, inp.ipointer, inp.left_button, option.slider.value);
							if result != option.slider.value {
								option.slider.value = result;
								img_ctx.settings_info.changed_index = xx it_index;
								changed = true;
							}
						}

						if changed {
							settings_info := img_ctx.settings_info;
							error_str := img_ctx.plugin.settings(*img_ctx.pre_info, *img_ctx.render_info, *settings_info);
							if error_str {
								log_error("Plugin for '%' settings retrieval error: %", img_ctx.plugin.plugin_provided.name_of_filetype, error_str);
							} else img_ctx.settings_info = settings_info;
							if #complete img_ctx.settings_info.response == {
							case .NOTHING;
							case .RE_RENDER; img_ctx.render = true;
							}
						}
					}
				}
				settings_menu_just_opened = false;
			}

			if display_metadata {
				panel_draw(*metadata_panel);
				if panel_scrollbar(*metadata_panel, inp.ipointer, .[xx inp.lpointer_when_pressed.x, xx inp.lpointer_when_pressed.y], inp.left_button) {
					metadata_width += (inp.fpointer.x - inp.lpointer_when_pressed.x).(int);
					metadata_width = clamp(metadata_width, 0, window_size[0] - metadata_panel.pos[0]);
					inp.lpointer_when_pressed = inp.fpointer;
				}
				if metadata_width < SCROLLBAR_SIZE*3 {
					display_metadata = false;
					metadata_width = DEFAULT_METADATA_WIDTH;
					inp.left_button = false;
				}
				panel_text_split(*metadata_panel, main_font, tprint("width: % px", img_ctx.pre_info.width), .TOP, .NEAR);
				panel_text_split(*metadata_panel, main_font, tprint("height: % px", img_ctx.pre_info.height), .TOP, .NEAR);
				panel_text_split(*metadata_panel, main_font, tprint("bit depth: % bits", img_ctx.pre_info.bit_depth), .TOP, .NEAR);
				panel_text_split(*metadata_panel, main_font, tprint("channels: %", img_ctx.pre_info.channels), .TOP, .NEAR);
				for img_ctx.pre_info.metadata {
					panel_text_split(*metadata_panel, main_font, tprint("%: %", it[0], it[1]), .TOP, .NEAR);
				}
			}

			/*# UI */
			/*# top bar */
			settings_button := panel_split(*top_bar, .{bar_height*6/5, top_bar.size[0]}, .LEFT, false);
			panel_split(*top_bar, .{bar_height, top_bar.size[0]}, .LEFT, false);
			fit_buttons_space := panel_split(*top_bar, .{bar_height*5, top_bar.size[0]}, .LEFT, false);
			panel_split(*top_bar, .{bar_height, top_bar.size[0]}, .LEFT, false);
			smoothing_button := panel_split(*top_bar, .{bar_height*6/5, top_bar.size[0]}, .LEFT, false);
			panel_split(*top_bar, .{bar_height, top_bar.size[0]}, .LEFT, false);
			zoom_buttons_space := panel_split(*top_bar, .{bar_height*2, top_bar.size[0]}, .LEFT, false);
			panel_split(*top_bar, .{bar_height, top_bar.size[0]}, .LEFT, false);
			rotation_button := panel_split(*top_bar, .{bar_height, top_bar.size[0]}, .LEFT, false);

			/*# settings button */
			tip.text = "Toggle settings menu";
			if elaborate_tips tip.text = "Toggle settings menu:\nThe settings menu will appear when this button is clicked.\nIf the settings menu is already visible, it will instead disappear.";
			if first_layer_is_pressable && panel_toggle_button(*settings_button, icon_font, ICON.SETTINGS, inp.ipointer, inp.left_button_switch,  display_settings_menu, *tip){
				display_settings_menu = !display_settings_menu;
				if display_settings_menu then settings_menu_just_opened = true;
			}

			/*# fit buttons */
			fit_buttons_space.colors = button_palette;
			panel_draw(*fit_buttons_space);
			fit_buttons := panel_subdivide(*fit_buttons_space, 5, .HORIZONTAL, false);
			if img_ctx.auto_fit {
				fit_buttons[img_ctx.fit].colors = selected_button_palette;
				panel_draw(*fit_buttons[img_ctx.fit]);
			}

			for fit_buttons {
				fit_tips :: string.["Fit pixel to pixel", "Fit to fill", "Fit to screen width", "Fit to screen height", "Use best fit"];
				elaborate_fit_tips :: string.[
					"Fit pixel to pixel:\nThis setting scales the image so that one pixel on the\nscreen corresponds to exactly one pixel of the image.",
					"Fit to fill:\nThis setting scales the image so that it completely fills the view,\nat any aspect ratio of the screen or image.",
					"Fit to screen width:\nThis setting scales the image so that the image takes up the full width of the screen.",
					"Fit to screen height:\nThis setting scales the image so that the image takes up the full height of the screen.",
					"Use best fit:\nThis setting scales the image so that it is fully visible,\nat any aspect ratio of the screen or image."
				];
				tip.text = fit_tips[it_index];
				if elaborate_tips tip.text = elaborate_fit_tips[it_index];
				if first_layer_is_pressable && panel_button(*it, inp.ipointer, inp.left_button_switch, *tip) {
					img_ctx.fit = xx it_index;
					img_ctx.auto_fit = true;
					img_ctx.offset = .{};
					img_ctx.angle = 0;
				}
				fit_button_text :: string.[ICON.FIT_121, ICON.FIT_FILL, ICON.FIT_WIDTH, ICON.FIT_HEIGHT, ICON.FIT_BEST];
				panel_text(*it, icon_font, fit_button_text[it_index], .MIDDLE, .MIDDLE);
			}

			/*# Smoothing button */
			tip.text = "Toggle smoothing";
			if elaborate_tips tip.text = "Toggle smoothing:\nIf turned on, pixels will be smoothed out when upscaling,\nwhich makes lower resolution photos look better.";
			if first_layer_is_pressable && panel_toggle_button(*smoothing_button, icon_font, ICON.ANTI_ALIAS, inp.ipointer, inp.left_button_switch, img_ctx.smoothing_on, *tip) {
				img_ctx.smoothing_on = !img_ctx.smoothing_on;
			}

			/*# zoom setting button */
			zoom_buttons_space.colors = button_palette;
			panel_draw(*zoom_buttons_space);
			zoom_buttons := panel_subdivide(*zoom_buttons_space, 2, .HORIZONTAL, false);

			zoom_buttons[xx img_ctx.zoom_alignment].colors = selected_button_palette;
			panel_draw(*zoom_buttons[xx img_ctx.zoom_alignment]);

			for zoom_buttons {
				zoom_tips :: string.["Zoom on screen center", "Zoom on pointer"];
				elaborate_zoom_tips :: string.[
					"Zoom on screen center:\nWhen performing zooming actions, the image will scale so that\nthe image pixel in the center of the screen stays in that same spot.",
					"Zoom on pointer:\nWhen performing zooming actions, the image will scale so that\nthe image pixel underneath the mouse pointer stays in that same spot."
				];
				tip.text = zoom_tips[it_index];
				if elaborate_tips tip.text = elaborate_zoom_tips[it_index];
				if first_layer_is_pressable && panel_button(*it, inp.ipointer, inp.left_button_switch, *tip){
					img_ctx.zoom_alignment = xx it_index;
				}
				zoom_button_text :: string.[ICON.ZOOM_CENTER, ICON.ZOOM_POINTER];
				panel_text(*it, icon_font, zoom_button_text[it_index], .MIDDLE, .MIDDLE);
			}

			/*# Rotation button */
			tip.text = "Rotate 90 degrees or reset";
			if elaborate_tips tip.text = "Rotate 90 degrees or reset:\nIf the image is at an angle of 0°, 90°, 180° or 270°,\nthis button will futher turn the image by another 90°.\nIf it is at another angle, this button will reset it to 0°.";
			if first_layer_is_pressable && panel_toggle_button(*rotation_button, icon_font, ICON.ROTATE, inp.ipointer, inp.left_button_switch, img_ctx.angle != 0, *tip) {
				if img_ctx.angle != 0.00 && img_ctx.angle != 90 && img_ctx.angle != 180 && img_ctx.angle != 270 {
					img_ctx.angle = 0;
				} else img_ctx.angle -= 90;
			}

			/*# filename display */
			if !img_ctx.draw {
				panel_text_split(*top_bar, main_font, "Drag an image or plugin into the window to start.", .RIGHT);
			} else {
				text := isolate_name(img_ctx.pre_info.name);
				file_display := panel_text_split(*top_bar, main_font, text, .RIGHT);

				tip.text = img_ctx.pre_info.name;
				if elaborate_tips tip.text = tprint("The full filepath to this image (click to copy to clipboard):\n%", tip.text);
				if first_layer_is_pressable && panel_button(*file_display, inp.ipointer, inp.left_button_switch, *tip) {
					Clippy.os_clipboard_set_text(img_ctx.pre_info.name);
					log("Filepath copied to clipboard.", flags = .CONTENT);
				}
				panel_text(*file_display, main_font, text, .MIDDLE, .MIDDLE);
			}

			/*# bottom bar */

			/*# metadata button */
			metadata_button := panel_split(*bottom_bar, .{bar_height*3/2, bottom_bar.size[0]}, .LEFT, false);
			tip.text = "Toggle image metadata view";
			if elaborate_tips tip.text = "Toggle image metadata view:\nMetadata is extra information stored in images, about the image itself,\nlike image size, camera information, time of photo, etc.\nThe metadata view will appear when this button is clicked.\nIf the metadata view is already visible, it will instead disappear.";
			if first_layer_is_pressable && panel_toggle_button(*metadata_button, icon_font, ICON.METADATA, inp.ipointer, inp.left_button_switch, display_metadata, *tip) {
				display_metadata = !display_metadata;
			}

			scale_text: string;
			if img_ctx.draw {
				scale_text = tprint("%\%", formatFloat(img_ctx.scale*100, trailing_width = 2, zero_removal = .NO));
			} else {
				scale_text = "----.--%";
			}
			panel_text_split(*bottom_bar, main_font, scale_text, .LEFT);

			/*# angle indicator */
			angle_text := tprint("%°", img_ctx.angle);
			angle_panel := panel_text_split(*bottom_bar, main_font, angle_text, .LEFT);

			/*# fps counter */
			if inp.arrow_left_repeat || inp.arrow_right_repeat {
				bottom_bar.colors.text = ifx frame_time < target_frame_time then u8.[100, 210, 25, 255] else .[220, 60, 25, 255];
				panel_text_split(*bottom_bar, main_font, tprint("fps: %", frame_count_over_1s), .LEFT, .MIDDLE);
				bottom_bar.colors.text = default_palette.text;
			}

			/*# Backwards and forwards buttons (bnf buttons) */
			bnf_menu_space := panel_split(*bottom_bar, .{bar_height*6, bottom_bar.size[0]}, .RIGHT, false);
			bnf_menu_space.colors = button_palette;
			bnf_button_space := panel_split(*bnf_menu_space, .{bar_height*2, bnf_menu_space.size[0]}, .RIGHT, true);

			bnf_buttons := panel_subdivide(*bnf_button_space, 2, .HORIZONTAL, true);
			if first_layer_is_pressable && current_q_index.* > 0 && current_q.count != 0 {
				tip.text = "Previous file in queue";
				if elaborate_tips tip.text = "Next file in queue:\nWhen pressed, the previous file in the current image queue will be displayed.";
				if panel_button(*bnf_buttons[0], inp.ipointer, inp.left_button_switch, *tip) || inp.arrow_left || inp.arrow_left_repeat {
					current_q_index.* -= 1;
					img_ctx.render = true;
				}
			} else {
				bnf_buttons[0].colors.body = default_palette.body;
				panel_draw(*bnf_buttons[0]);
			}
			if first_layer_is_pressable && current_q_index.* < current_q.count-1 && current_q.count != 0 {
				tip.text = "Next file in queue";
				if elaborate_tips tip.text = "Next file in queue:\nWhen pressed, the next file in the current image queue will be displayed.";
				if panel_button(*bnf_buttons[1], inp.ipointer, inp.left_button_switch, *tip) || inp.arrow_right || inp.arrow_right_repeat {
					current_q_index.* += 1;
					img_ctx.render = true;
				}
			} else {
				bnf_buttons[1].colors.body = default_palette.body;
				panel_draw(*bnf_buttons[1]);
			}
			panel_text(*bnf_buttons[0], icon_font, ICON.PREV, .MIDDLE, .MIDDLE);
			panel_text(*bnf_buttons[1], icon_font, ICON.NEXT, .MIDDLE, .MIDDLE);

			/*# history or directory selector */
			bnf_selector_space := panel_split(*bnf_menu_space, .{bar_height*3, bnf_menu_space.size[0]}, .LEFT, false);
			bnf_menu_space.colors = default_palette;
			panel_draw(*bnf_menu_space);
			bnf_selector_buttons := panel_subdivide(*bnf_selector_space, 2, .HORIZONTAL, false);
			{ /* the selected button */
				selected := *bnf_selector_buttons[fileq_setting];
				selected.colors = selected_button_palette;
				panel_draw(selected);
			}

			/* TODO: make unpressable if arrays are empty */
			fileq_setting_switch := false;
			for bnf_selector_buttons {
				fileq_tips :: string.["Set file queue to dropped files", "Set file queue to directory of the current file"];
				elaborate_fileq_tips :: string.[
					"Set file queue to dropped files:\nWhen selected, the viewing queue will become the list of\nfiles that has been added via drop-in or via the command line.",
					"Set file queue to directory of the current file:\nWhen selected, the viewing queue will become the list of\nviewable images in the directory of the current image."
				];
				tip.text = fileq_tips[it_index];
				if elaborate_tips tip.text = elaborate_fileq_tips[it_index];
				if first_layer_is_pressable && panel_button(*it, inp.ipointer, inp.left_button_switch, *tip) {
					fileq_setting_switch = true;
					fileq_setting = xx it_index;
				}
				fileq_setting_text :: string.[ICON.HISTORY, ICON.DIRECTORY];
				panel_text(*it, icon_font, fileq_setting_text[it_index], .MIDDLE, .MIDDLE);
			}
			if fileq_setting_switch if #complete fileq_setting == {
			case .HISTORY;
				file_history_index = file_history.count-1;
				current_q = *file_history;
				current_q_index = *file_history_index;
			case .DIRECTORY;
				/* I'm assuming there's always a valid file in this directory */
				if file_history.count {
					discover_directory(*directory, file_history[file_history_index]);
					sanitize_file_list(*directory, file_history[file_history_index], *directory_index, false);
				} else {
					array_reset(*directory);
					current_q_index.* = -1;
				}
				current_q = *directory;
				current_q_index = *directory_index;
			}

			/*# queue position */
			if img_ctx.draw {
				panel_text(*bottom_bar, main_font, tprint("%/%", current_q_index.*+1, current_q.count), .RIGHT, .MIDDLE);
			}
		}
		{/*# Popups */
			/* What I'd like to do with errors/options */
			/* A function can log an error, and can log a choice */
			/* Errors only have an 'ok' button */
			/* Choices can have two buttons with custom names */
			/* Functions that can log choices always carry the 'choice context', which contains info on what was chosen */
			option_entries = 0;
			for < entry: log_entries if entry.options[0] != "" option_entries += 1;

			log_decay_time :: 5;
			y_travel := bar_height*6/5;
			keepalive := false;
			for < * entry: log_entries {
				palette := default_palette;
				if entry.info.common_flags == {
					case .ERROR; palette = error_message_palette;
					case .WARNING; palette = warning_message_palette;
					case .CONTENT; palette = good_message_palette;
				}

			if entry.options[0] != "" { /* This is in case the log_entry has an option setting (like errors) */
					error_screen := UI_Panel.{
						size = .[window_size[0], bar_height*2],
						pos = .[0, window_size[1]/2 - bar_height],
						colors = palette,
					};
					options_bar := panel_split(*error_screen, .{1, 2}, .BOTTOM, true);
					panel_text(*error_screen, main_font, entry.text, .MIDDLE, .MIDDLE);

					divisions := panel_subdivide(*options_bar, 3, .HORIZONTAL, true);
					if option_entries > 1 then panel_text(*divisions[2], main_font, tprint("% other message%", option_entries - 1, ifx option_entries-1 == 1 then "" else "s"), .RIGHT, .MIDDLE);

					buttons := panel_subdivide(*divisions[1], ifx entry.options[1].count then 2 else 1, .HORIZONTAL, true);
					pressed_option := -1;
					for buttons {
						if panel_button(*it, inp.ipointer, inp.left_button_switch) {
							inp.left_button_switch = false;
							pressed_option = it_index;
						}
						panel_text(*it, main_font, entry.options[it_index], .MIDDLE, .MIDDLE);
					}
					if pressed_option > -1 {
						free(entry.text);
						array_ordered_remove_by_index(*log_entries, it_index);
						option_entries -= 1;
					}
					keepalive = true;
					entry.wakeup_time = current_time_monotonic();

				} else if !option_entries { /* This is just the normal notifs */
					popup_panel := panel_from_text(main_font, entry.text, .[window_size[0] - bar_height/10, y_travel], .RIGHT, .BOTTOM, palette);
					y_travel += popup_panel.size[1] + bar_height*1/5;

					if pointer_is_in_panel(*popup_panel, inp.ipointer) {
						keepalive = true;
					}

					if panel_button(*popup_panel, inp.ipointer, inp.left_button_switch) {
						free(entry.text);
						array_ordered_remove_by_index(*log_entries, it_index);
					} else {
						draw_flow_text(main_font, split(entry.text, "\n",, temp), popup_panel.pos, popup_panel.size);
					}
				}
			}
			for < * entry: log_entries {
				if to_float64_seconds(current_time_monotonic() - entry.wakeup_time) > log_decay_time {
					if keepalive {
						entry.wakeup_time += to_apollo(log_decay_time);
					} else {
						free(entry.text);
						array_ordered_remove_by_index(*log_entries, it_index);
					}
				}
			}
		}
		{/*# tooltip */
			if tip.state == .Decaying then tip.state = .Dormant;
			if tip.state == .Active && to_float64_seconds(current_time_monotonic() - tip.hover_started) > 0.5 {
				pos := tip.pointer_position;
				align_h := Text_Align_Hor.LEFT;
				align_v := Text_Align_Ver.BOTTOM;
				if pos[0] > window_size[0]/2 then align_h = .RIGHT;
				if pos[1] > window_size[1]/2 {
					align_v = .TOP;
					pos[1] -= bar_height*3/4;
				} else {
					pos[1] += bar_height/2;
				}
				panel_from_text(main_font, tip.text_to_be_displayed, pos, align_h, align_v, tool_tip_palette);
				tip.state = .Decaying;
			}
		}

		Simp.immediate_flush();
		Simp.swap_buffers(os_window);
		reset_temporary_storage();
	}
	for log_entries {
		print("leftover log (level: %): \"%\"\n", it.info.common_flags, it.text);
	}
}

get_pointer_position :: () -> Vector2 {
	mouse_x, mouse_y, success := Winc.get_mouse_pointer_position(os_window, true);
	if !success return .{-10, -10};
	return .{xx mouse_x, xx mouse_y};
}

Log_Entry :: struct {
	text: string;
	path: string;
	options: [2]string;
	wakeup_time: Apollo_Time;
	info: Log_Info;
}

logger :: (message: string, data: *void, info: Log_Info) {
	if info.common_flags == .VERBOSE_ONLY && context.log_level != .VERBOSE then return;
	if !message then return;

	entries := data.(*[..]Log_Entry);
	entry := Log_Entry.{
		text = copy_string(message),
		wakeup_time = current_time_monotonic(),
		info = info
	};
	if info.user_flags == 1 {
		entry.options[0] = "dismiss";
	}
	array_add(entries, entry);
}

#load "registration.jai";
#load "ui.jai";

Clippy :: #import "Clipboard";
Winc :: #import "Window_Creation";
Input :: #import "Input";
Simp :: #import "Simp";
X11 :: #import "X11";
Gl :: #import "GL";

Hash :: #import "Hash";

#import "Math";
#import "File";
#import "File_Watcher";
#import "String";
#import "Basic";
