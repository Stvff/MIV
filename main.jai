Image_Context :: struct {
	fit : enum {ONE_TO_ONE; FIT_WIDTH; FIT_HEIGHT; FIT_BEST;}
	offset: Vector2;
	pre_pan_offset: Vector2;
	zoom_alignment: Zoom_Alignment_Setting;
	scale: float;
	angle: float;

	linear_upscaling: bool;
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

	left_button_switch: bool;

	using persistent: struct {
		shifted: bool;
		left_button: bool;
		right_button: bool;
		middle_button: bool;
		pointer_when_pressed: Vector2;
	}
}

window_size: [2]int;
os_window: X11.Window;
TARGET_FRAME_TIME :: 1.0/120.0;

main :: () {
	errors: [..]Error;
	settings: Settings_File_1 = load_registrations(*errors);
	defer cleanup_registrations(settings);

	/*# UI definitions */
	fontsize := 20;
	{
		window_width := 1400;
		window_height := 800;
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

	/*# Tooltip init */
	/* Counting this manually is inconvenient; I'd like to write a metaprogram that counts the amount of tooltips here, but it's hard. */
	/* The reason this isn't a dynamic array is because the pointer of that is unstable. Saving indices into a buffer is messy during usage. */
	tip: Tool_Tip;

	/*# Image context etc */
	img_ctx := Image_Context.{
		fit = .FIT_BEST,
		scale = 1.0,
		render = false,
		draw = true,
	};

	if !init(*img_ctx.watcher, file_change_callback, *img_ctx, events_to_watch = .ALL_EVENTS, merge_window_seconds = 2*TARGET_FRAME_TIME, verbose = false, watch_recursively = false) {
		give_error(*errors, "Could not initialize watcher");
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

	files_to_open: [..]string;
	{
		cli_args := get_command_line_arguments();
		cli_args.data += 1;
		cli_args.count -= 1;
		array_add(*files_to_open, ..cli_args);
	}
	gpu_texture: Simp.Texture;

	/*# UI state */
	display_metadata := false;
	display_settings_menu := false;
	settings_menu_just_opened := false;

	first_image_open := true;
	defer {
		if settings.pers_between_restarts.of_aa then settings.aa_setting_on_previous_close = img_ctx.linear_upscaling;
		if settings.pers_between_restarts.of_scale then settings.scale_on_previous_close = img_ctx.scale;
		if settings.pers_between_restarts.of_offset {
			settings.offset_on_previous_close = img_ctx.offset;
		}
		settings.zoom_alignment_on_previous_close = img_ctx.zoom_alignment;
	}

	/*# Timing */
	target_frame_time: float64 = TARGET_FRAME_TIME;
	last_1s_time := current_time_monotonic();
	prev_time := last_1s_time;

	frame_1s_counter := 0;
	frame_count_over_1s := 60;
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
				glXSwapIntervalEXT(X11.x_global_display, Simp.find_window_info(os_window).specific.glx_window, 0);
				img_ctx.auto_fit = true;
				img_ctx.offset = .{};
				img_ctx.angle = 0;
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
			if event.type == .DRAG_AND_DROP_FILES for event.files array_add(*files_to_open, copy_string(it));
			/* Press */
			if (event.type == .KEYBOARD) && event.key_pressed then if event.key_code == {
				case .ESCAPE; running = false;
				case .SHIFT; inp.shifted = true;
				case .ARROW_UP; inp.arrow_up = true;
				case .ARROW_DOWN; inp.arrow_down = true;
				case .ARROW_LEFT; inp.arrow_left = true;
				case .ARROW_RIGHT; inp.arrow_right = true;
				case #char "W"; inp.w = true;
				case #char "A"; inp.a = true;
				case #char "S"; inp.s = true;
				case #char "D"; inp.d = true;
				case .MOUSE_BUTTON_RIGHT;
					inp.pointer_when_pressed = get_pointer_position();
					inp.right_button = true;
				case .MOUSE_BUTTON_LEFT;
					inp.left_button_switch = true;
					inp.pointer_when_pressed = get_pointer_position();
					inp.left_button = true;
				case .MOUSE_BUTTON_MIDDLE;
					inp.pointer_when_pressed = get_pointer_position();
					inp.middle_button = true;
			}
			/* Release */
			if (event.type == .KEYBOARD) && !event.key_pressed then if event.key_code == {
				case .SHIFT; inp.shifted = false;
				case .MOUSE_BUTTON_LEFT; inp.left_button = false;
				case .MOUSE_BUTTON_RIGHT; inp.right_button = false;
				case .MOUSE_BUTTON_MIDDLE; inp.middle_button = false;
			}
			/* Scroll */
			if event.type == .MOUSE_WHEEL {
				inp.scroll_delta = cast(float, event.wheel_delta)/cast(float, event.typical_wheel_delta);
			}
		}
		/* mouse */
		inp.fpointer = get_pointer_position();
		inp.ipointer = .[xx inp.fpointer.x, xx inp.fpointer.y];

		/*# Files added via command line or drop-in */
		loading_time := current_time_monotonic();
		position_adjusted := false;
		temp_files_to_open := files_to_open;
		while temp_files_to_open.count {
			file_to_open := temp_files_to_open[0];
			give_log(*errors, "%", file_to_open);
			ext := get_extension(file_to_open);
			if ext == "so" {
				register_dynlib(file_to_open, true, *errors);
			} else {
				array_add(*file_history, file_to_open);
				img_ctx.render = true;
				if !position_adjusted {
					file_history_index = file_history.count-1;
					position_adjusted = true;
				}
			}
			temp_files_to_open.data += 1;
			temp_files_to_open.count -= 1;
		}
		if temp_files_to_open.count == 1 {
			fileq_setting = .DIRECTORY;
			/* I'm assuming there's always a valid file in this directory */
			discover_directory(*directory, file_history[file_history_index], *errors);
			sanitize_file_list(*directory, file_history[file_history_index], *directory_index, null);
			current_q = *directory;
			current_q_index = *directory_index;
		}
		array_reset(*files_to_open);

		/*# The watcher */
		process_changes(*img_ctx.watcher);
		if img_ctx.watcher_says_something_moved_somewhere {
			img_ctx.watcher_says_something_moved_somewhere = false;
			position_adjusted = true;
		}
		if img_ctx.watcher_says_rerender {
			img_ctx.watcher_says_rerender = false;
			img_ctx.render = true;
		}

		/*# Choosing the file to render */
		if position_adjusted {
			/* if position_adjusted? */
			sanitize_file_list(*file_history, file_history[file_history_index], *file_history_index, *errors);
			if fileq_setting == .DIRECTORY {
				/* I'm assuming there's always a valid file in this directory */
				discover_directory(*directory, file_history[file_history_index], *errors);
				sanitize_file_list(*directory, file_history[file_history_index], *directory_index, null);
			}
		}
		if current_q.count == 0 img_ctx.render = false;

		/*# image pre-render */
		if img_ctx.render {
			old_pre_info := img_ctx.pre_info;
			new_name := current_q.*[current_q_index.*];
			img_ctx.render = get_loading(new_name, get_extension(new_name), *img_ctx, *errors);
			if img_ctx.render {
				if old_pre_info.fileptr posix.fclose(old_pre_info.fileptr);
				/* retrieve previous offsets etc from some per-file history */

				if !settings.pers_between_files.of_scale img_ctx.auto_fit = true;
				if !settings.pers_between_files.of_offset img_ctx.offset = .{0, 0};
				if !settings.pers_between_files.of_aa img_ctx.linear_upscaling = false;

				if first_image_open {
					if settings.pers_between_restarts.of_aa then img_ctx.linear_upscaling = settings.aa_setting_on_previous_close;
					if settings.pers_between_restarts.of_scale {
						img_ctx.scale = settings.scale_on_previous_close;
						img_ctx.auto_fit = false;
					} else img_ctx.auto_fit = true;
					if settings.pers_between_restarts.of_offset then img_ctx.offset = settings.offset_on_previous_close;
					img_ctx.zoom_alignment = settings.zoom_alignment_on_previous_close;
					first_image_open = false;
				}
			} else {
				f, index := array_find(file_history, new_name);
				if f array_ordered_remove_by_index(*file_history, index);
				file_history_index = clamp(file_history_index, 0, file_history.count-1);
			}
			give_log(*errors, "%", img_ctx);
		}
		img_ctx.draw = true;

		/*# Image rendering (aka resolving the actual data) */
		if !img_ctx.plugin { img_ctx.render = false; img_ctx.draw = false; }
		if img_ctx.render {
			using img_ctx.render_info;
			buffer_width = img_ctx.pre_info.width;
			buffer_height = img_ctx.pre_info.height;
			array_resize(*(buffer), buffer_width*buffer_height);
			render_error := img_ctx.plugin.render(*img_ctx.pre_info, *img_ctx.render_info);
			if render_error {
				give_error(*errors, "File image data retrieval error: %", render_error);
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
			give_log(*errors, "Loading time: %, associated fps if we did nothing but this: %", to_float64_seconds(loading_time), 1/to_float64_seconds(loading_time));
		}

		{/*# Drawing time */
			/* First we define the broad outline of panels that we'll see (the ones that make the canvas smaller) */
			canvas := UI_Panel.{
				size = window_size,
				colors = palette,
				border_size = 1,
			};

			top_bar := panel_split(*canvas, .{bar_height, canvas.size[1]}, .TOP, false);
			bottom_bar := panel_split(*canvas, .{bar_height - 4, canvas.size[1]}, .BOTTOM, false);
			settings_menu_panel, metadata_panel: UI_Panel;

			if display_settings_menu
				settings_menu_panel = panel_split(*canvas, .{bar_height*8, canvas.size[0]}, .LEFT, false);
			if display_metadata
				metadata_panel = panel_split(*canvas, .{bar_height*5, canvas.size[0]}, .LEFT, false);

			first_layer_is_pressable := img_ctx.draw && errors.count == 0;

			/*# Image drawing */
			canvas.colors = bg_palette;
			panel_draw(*canvas);
			if img_ctx.draw {
				screen_offset := Vector2.{ cast(float, canvas.pos[0]), cast(float, canvas.pos[1]) };
				screen_center := Vector2.{ cast(float, canvas.size[0])/2, cast(float, canvas.size[1])/2 };
				image_center := Vector2.{ cast(float, img_ctx.pre_info.width)/2, cast(float, img_ctx.pre_info.height)/2 };

				/* we have to process our inputs (not using the keyboard yet) */
				if first_layer_is_pressable && pointer_is_in_panel(*canvas, inp.ipointer) {
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
						img_ctx.offset = img_ctx.pre_pan_offset + (inp.fpointer - inp.pointer_when_pressed)/img_ctx.scale;
					} else {
						img_ctx.pre_pan_offset = img_ctx.offset;
					}

					if inp.shifted && inp.d {
						img_ctx.auto_fit = false;
						img_ctx.angle -= 5;
					}
					if inp.shifted && inp.a {
						img_ctx.auto_fit = false;
						img_ctx.angle += 5;
					}
				}
				img_ctx.scale = clamp(img_ctx.scale, 1/cast(float, max(img_ctx.pre_info.width, img_ctx.pre_info.height)), cast(float, max(canvas.size[0], canvas.size[1])));

				now_fit := img_ctx.fit;
				if now_fit == .FIT_BEST {
					screen_woh := screen_center.x/screen_center.y;
					image_woh := image_center.x/image_center.y;
					if screen_woh > image_woh now_fit = .FIT_HEIGHT;
					else now_fit = .FIT_WIDTH;
				}

				if img_ctx.auto_fit {
					if now_fit == {
					case .ONE_TO_ONE;
						img_ctx.scale = 1;
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

				/* maybe shift arrow left right lolol */
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
				glBindTexture(GL_TEXTURE_2D, gpu_texture.gl_handle);
				if img_ctx.linear_upscaling glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
				else glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
				Simp.immediate_quad(image_bounds[0], image_bounds[1], image_bounds[2], image_bounds[3]);
			}
			panel_draw(*top_bar);
			panel_draw(*bottom_bar);

			clipping: Simp.Text_Clipping_Details = .{
				clip = true,
				legal_x_origin = 200, legal_y_origin = 200,
				legal_x_span = 5, legal_y_span = 30
			};
			Simp.draw_text(main_font, 200, 500, "ABCDEFGHIJKLMNOPQRSTUVW", clipping = clipping);

			/*# settings menu */
			if display_settings_menu {
				panel_draw(*settings_menu_panel);
				table_space := panel_split(*settings_menu_panel, .{bar_height*9/2, settings_menu_panel.size[1]}, .TOP, false);
				first_col := panel_split(*table_space, .{bar_height*3, table_space.size[0]}, .LEFT, false);
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
				panel_button(*table[0][0], inp.ipointer, false, *tip);
				panel_text(*table[0][0], main_font, "Persistence", .MIDDLE, .MIDDLE);
				panel_text(*table[1][0], main_font, "between", .MIDDLE, .TOP);
				panel_text(*table[1][0], main_font, "files", .MIDDLE, .BOTTOM);
				panel_text(*table[2][0], main_font, "between", .MIDDLE, .TOP);
				panel_text(*table[2][0], main_font, "restarts", .MIDDLE, .BOTTOM);

				panel_text(*table[0][1], main_font, "of aa", .MIDDLE, .MIDDLE);
				panel_text(*table[0][2], main_font, "of zoom", .MIDDLE, .MIDDLE);
				panel_text(*table[0][3], main_font, "of offset", .MIDDLE, .MIDDLE);

				settings_table: *[2][3]bool = xx *settings.pers_between_files;
				for col: 1..2 for row: 1..3 {
					if panel_toggle_button(*table[col][row], icon_font, ICON.TOGGLE, inp.ipointer, inp.left_button_switch, settings_table.*[col-1][row-1]) {
						settings_table.*[col-1][row-1] = !settings_table.*[col-1][row-1];
					}
				}

				/*# plugin settings */
				if img_ctx.plugin && img_ctx.plugin.has_settings {
					if settings_menu_just_opened || img_ctx.settings_info.options.data == null {
						img_ctx.settings_info.changed_index = -1;
						img_ctx.settings_info.changed_secondary_index = -1;
						settings_info := img_ctx.settings_info;
						error_str := img_ctx.plugin.settings(*img_ctx.pre_info, *img_ctx.render_info, *settings_info);
						if error_str {
							give_error(*errors, "Plugin for '%' settings retrieval error: %", img_ctx.plugin.name_filetype, error_str);
						} else img_ctx.settings_info = settings_info;
					}

					panel_split(*settings_menu_panel, .{bar_height, settings_menu_panel.size[1]}, .TOP, false);
					title_panel := panel_split(*settings_menu_panel, .{bar_height, settings_menu_panel.size[1]}, .TOP, false);
					panel_text(*title_panel, main_font, tprint("% settings:", img_ctx.plugin.name_filetype), .LEFT, .MIDDLE);

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
						}
						if changed {
							settings_info := img_ctx.settings_info;
							error_str := img_ctx.plugin.settings(*img_ctx.pre_info, *img_ctx.render_info, *settings_info);
							if error_str {
								give_error(*errors, "Plugin for '%' settings retrieval error: %", img_ctx.plugin.name_filetype, error_str);
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
			fit_buttons_space := panel_split(*top_bar, .{bar_height*4, top_bar.size[0]}, .LEFT, false);
			panel_split(*top_bar, .{bar_height, top_bar.size[0]}, .LEFT, false);
			aa_button := panel_split(*top_bar, .{bar_height*6/5, top_bar.size[0]}, .LEFT, false);
			panel_split(*top_bar, .{bar_height, top_bar.size[0]}, .LEFT, false);
			zoom_buttons_space := panel_split(*top_bar, .{bar_height*2, top_bar.size[0]}, .LEFT, false);

			/*# settings button */
			settings_button.colors = ifx display_settings_menu then selected_button_palette else button_palette;
			panel_draw(*settings_button);
			tip.text = "Toggle settings menu";
			if first_layer_is_pressable && panel_button(*settings_button, inp.ipointer, inp.left_button_switch, *tip){
				display_settings_menu = !display_settings_menu;
				if display_settings_menu then settings_menu_just_opened = true;
			}
			panel_text(*settings_button, icon_font, ICON.SETTINGS, .MIDDLE, .MIDDLE);

			/*# fit buttons */
			fit_buttons_space.colors = button_palette;
			panel_draw(*fit_buttons_space);
			fit_buttons := panel_subdivide(*fit_buttons_space, 4, .HORIZONTAL, false);
			if img_ctx.auto_fit {
				fit_buttons[img_ctx.fit].colors = selected_button_palette;
				panel_draw(*fit_buttons[img_ctx.fit]);
			}

			for fit_buttons {
				fit_tips :: string.["Fit pixel to pixel", "Fit to screen width", "Fit to screen height", "Use best fit"];
				tip.text = fit_tips[it_index];
				if first_layer_is_pressable && panel_button(*it, inp.ipointer, inp.left_button_switch, *tip) {
					img_ctx.fit = xx it_index;
					img_ctx.auto_fit = true;
					img_ctx.offset = .{};
					img_ctx.angle = 0;
				}
				fit_button_text :: string.[ICON.FIT_121, ICON.FIT_WIDTH, ICON.FIT_HEIGHT, ICON.FIT_BEST];
				panel_text(*it, icon_font, fit_button_text[it_index], .MIDDLE, .MIDDLE);
			}

			/*# AA button */
			aa_button.colors = ifx img_ctx.linear_upscaling then selected_button_palette else button_palette;
			panel_draw(*aa_button);
			tip.text = "Toggle anti-aliasing";
			if first_layer_is_pressable && panel_button(*aa_button, inp.ipointer, inp.left_button_switch, *tip) {
				img_ctx.linear_upscaling = !img_ctx.linear_upscaling;
			}
			panel_text(*aa_button, icon_font, ICON.ANTI_ALIAS, .MIDDLE, .MIDDLE);

			/*# zoom setting button */
			zoom_buttons_space.colors = button_palette;
			panel_draw(*zoom_buttons_space);
			zoom_buttons := panel_subdivide(*zoom_buttons_space, 2, .HORIZONTAL, false);

			zoom_buttons[xx img_ctx.zoom_alignment].colors = selected_button_palette;
			panel_draw(*zoom_buttons[xx img_ctx.zoom_alignment]);

			for zoom_buttons {
				zoom_tips :: string.["Zoom on screen center", "Zoom on pointer"];
				tip.text = zoom_tips[it_index];
				if first_layer_is_pressable && panel_button(*it, inp.ipointer, inp.left_button_switch, *tip){
					img_ctx.zoom_alignment = xx it_index;
				}
				zoom_button_text :: string.[ICON.ZOOM_CENTER, ICON.ZOOM_POINTER];
				panel_text(*it, icon_font, zoom_button_text[it_index], .MIDDLE, .MIDDLE);
			}

			/*# filename display */
			text := isolate_name(img_ctx.pre_info.name);
			if !img_ctx.draw text = "Drag an image or plugin into the window to start.";
			panel_text_split(*top_bar, main_font, text, .RIGHT);

			/*# bottom bar */
			if img_ctx.draw {
				text = tprint("%\%", formatFloat(img_ctx.scale*100, trailing_width = 2, zero_removal = .NO));
			} else {
				text = "----.--%";
			}
			panel_text_split(*bottom_bar, main_font, text, .LEFT);

			/*# metadata button */
			metadata_button := panel_split(*bottom_bar, .{bar_height*3/2, bottom_bar.size[0]}, .LEFT, false);
			metadata_button.colors = ifx display_metadata then selected_button_palette else button_palette;
			panel_draw(*metadata_button);
			tip.text = "Toggle image metadata view";
			if first_layer_is_pressable && panel_button(*metadata_button, inp.ipointer, inp.left_button_switch, *tip) {
				display_metadata = !display_metadata;
			}
			panel_text(*metadata_button, icon_font, ICON.METADATA, .MIDDLE, .MIDDLE);

			/*# fps counter */
			bottom_bar.colors.text = ifx frame_time < target_frame_time then u8.[100, 210, 25, 255] else .[220, 60, 25, 255];
			text = tprint("fps: %", frame_count_over_1s);
			panel_text(*bottom_bar, main_font, text, .LEFT, .MIDDLE);
			bottom_bar.colors.text = palette.text;
			show_fps := false;

			/*# Backwards and forwards buttons (bnf buttons) */
			bnf_menu_space := panel_split(*bottom_bar, .{bar_height*6, bottom_bar.size[0]}, .RIGHT, !show_fps);
			bnf_menu_space.colors = button_palette;
			bnf_button_space := panel_split(*bnf_menu_space, .{bar_height*2, bnf_menu_space.size[0]}, .RIGHT, true);

			bnf_buttons := panel_subdivide(*bnf_button_space, 2, .HORIZONTAL, true);
			if first_layer_is_pressable && current_q_index.* > 0 && current_q.count != 0 {
				tip.text = "Previous file in queue";
				if panel_button(*bnf_buttons[0], inp.ipointer, inp.left_button_switch, *tip) || inp.arrow_left {
					current_q_index.* -= 1;
					img_ctx.render = true;
				}
			} else {
				bnf_buttons[0].colors.body = palette.body;
				panel_draw(*bnf_buttons[0]);
			}
			if first_layer_is_pressable && current_q_index.* < current_q.count-1 && current_q.count != 0 {
				tip.text = "Next file in queue";
				if panel_button(*bnf_buttons[1], inp.ipointer, inp.left_button_switch, *tip) || inp.arrow_right {
					current_q_index.* += 1;
					img_ctx.render = true;
				}
			} else {
				bnf_buttons[1].colors.body = palette.body;
				panel_draw(*bnf_buttons[1]);
			}
			panel_text(*bnf_buttons[0], icon_font, ICON.PREV, .MIDDLE, .MIDDLE);
			panel_text(*bnf_buttons[1], icon_font, ICON.NEXT, .MIDDLE, .MIDDLE);

			/*# history or directory selector */
			bnf_selector_space := panel_split(*bnf_menu_space, .{bar_height*3, bnf_menu_space.size[0]}, .LEFT, false);
			bnf_menu_space.colors = palette;
			panel_draw(*bnf_menu_space);
			bnf_selector_buttons := panel_subdivide(*bnf_selector_space, 2, .HORIZONTAL, false);
			{ /* the selected button */
				selected := *bnf_selector_buttons[fileq_setting];
				selected.colors = selected_button_palette;
				panel_draw(selected);
			}

			fileq_setting_switch := false;
			for bnf_selector_buttons {
				fileq_tips :: string.["Set file queue to dropped files", "Set file queue to directory of the current file"];
				tip.text = fileq_tips[it_index];
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
				discover_directory(*directory, file_history[file_history_index], *errors);
				sanitize_file_list(*directory, file_history[file_history_index], *directory_index, null);
				current_q = *directory;
				current_q_index = *directory_index;
			}

			/*# queue position */
			if img_ctx.draw {
				panel_text(*bottom_bar, main_font, tprint("%/%", current_q_index.*+1, current_q.count), .RIGHT, .MIDDLE);
			}
		}
		{/*# Popups */
			pressed_option := -2;
			for error: errors {
				if error.kind == .LOG {
					// log("%", error);
					array_ordered_remove_by_index(*errors, it_index);
					continue;
				}
				if pressed_option > -2 continue;

				error_screen := UI_Panel.{
					size = .[window_size[0], bar_height*2],
					pos = .[0, window_size[1]/2 - bar_height],
					colors = error_message_palette,
				};
				options_bar := panel_split(*error_screen, .{1, 2}, .BOTTOM, true);
				panel_text(*error_screen, main_font, error.message, .MIDDLE, .MIDDLE);

				divisions := panel_subdivide(*options_bar, 3, .HORIZONTAL, true);
				if errors.count > 1 then panel_text(*divisions[2], main_font, tprint("% other error%", errors.count - 1, ifx errors.count-1 == 1 then "" else "s"), .RIGHT, .MIDDLE);

				buttons := panel_subdivide(*divisions[1], ifx error.options[1].count then 2 else 1, .HORIZONTAL, true);
				pressed_option = -1;
				for buttons {
					if panel_button(*it, inp.ipointer, inp.left_button_switch) {
						log("%", error);
						pressed_option = it_index;
					}
					panel_text(*it, main_font, error.options[it_index], .MIDDLE, .MIDDLE);
				}
				if pressed_option > -1 {
					array_ordered_remove_by_index(*errors, it_index);
				}
			}
			/* About errors, etc */
			/* A function can log an error, and can log a choice */
			/* Errors only have an 'ok' button */
			/* Choices can have two buttons with custom names */
			/* Functions that can log choices always carry the 'choice context', which contains info on what was chosen */

			/* Next to that, I want to write little popup windows about non-critical logs. They should be on a timer. */
			/* This latter one especially will need text flow functions (since it should be notifications in the bottomright). */
			/* I'm thinking to have the width be limited, and for the cut-off to initially not care about whitespace */
		}
		{/*# tooltip */
			if tip.state == .Decaying then tip.state = .Dormant;
			if tip.state == .Active && to_float64_seconds(current_time_monotonic() - tip.hover_started) > 0.5 {
				text_width := Simp.prepare_text(main_font, tip.text_to_be_displayed);
				padding := main_font.character_height;
				panel: UI_Panel;
				panel.size = .[text_width + padding, padding*2];
				panel.colors = default_tool_tip_palette;
				panel.pos = tip.pointer_position;

				if panel.pos[0] > window_size[0]/2 panel.pos[0] -= panel.size[0];
				if panel.pos[1] > window_size[1]/2 panel.pos[1] -= panel.size[1]*7/4;
				else panel.pos[1] += panel.size[1]/2;
				panel_draw(*panel);
				panel_text(*panel, main_font, tip.text_to_be_displayed, .MIDDLE, .MIDDLE);
				tip.state = .Decaying;
			}
		}

		Simp.immediate_flush();
		Simp.swap_buffers(os_window);
		reset_temporary_storage();
	}
	for errors {
		log("%", it);
	}
}

get_pointer_position :: () -> Vector2 {
	mouse_x, mouse_y := Winc.get_mouse_pointer_position();
	return .{xx mouse_x, xx (window_size[1] - xx mouse_y)};
}

FONT_PATH :: "./assets/LibertinusSerif-Regular.otf";
FONT_DATA :: #run cast([]u8) read_entire_file(FONT_PATH);

ICON_FONT_PATH :: "./assets/IconsMIV.otf";
ICON_FONT_DATA :: #run cast([]u8) read_entire_file(ICON_FONT_PATH);
ICON :: struct {
	SETTINGS :: "S";
	FIT_121 :: "1";
	FIT_WIDTH :: "W";
	FIT_HEIGHT :: "H";
	FIT_BEST :: "B";
	ANTI_ALIAS :: "A";
	ZOOM_CENTER :: "M";
	ZOOM_POINTER :: "P";

	METADATA :: "m";
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

#load "registration.jai";
#load "ui.jai";

Winc :: #import "Window_Creation";
Input :: #import "Input";
Simp :: #import "Simp";
X11 :: #import "X11";
#import "GL";

#import "Math";
#import "File";
#import "File_Watcher";
#import "String";
#import "Basic";
