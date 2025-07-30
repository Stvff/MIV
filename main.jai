Image_Context :: struct {
	fit : enum {ONE_TO_ONE; FIT_WIDTH; FIT_HEIGHT; FIT_BEST;}
	offset: Vector2;
	pre_pan_offset: Vector2;
	scale: float;
	angle: float;

	auto_fit: bool;
	render: bool;
	draw: bool;

	plugin: *Registration_Entry;
	pre_info: Pre_Rendering_Info;
	render_info: Rendering_Info;
}

Input_State :: struct {
	arrow_up: bool;
	arrow_down: bool;
	scroll_delta: float;

	w, a, s, d: bool;

	fpointer: Vector2;
	ipointer: [2]int;

	using persistent: struct {
		shifted: bool;
		left_button: bool;
		right_button: bool;
		middle_button: bool;
		pointer_when_pressed: Vector2;
	}
}

palette :: Palette.{
	body = .[65, 65, 65, 255],
	border = .[75, 75, 75, 255],
	text = .[255, 255, 255, 255],
	hover = .[150, 150, 150, 255],
};

bg_palette :: Palette.{
	body = .[30, 25, 30, 255],
	border = .[32, 25, 30, 255],
	text = .[30, 25, 30, 255],
	hover = .[30, 25, 30, 255],
};

window_size: [2]int;

main :: () {
	load_registration_file();
	defer cleanup_registrations();

	/* UI definitions */
	fontsize := 20;

	os_window: X11.Window;
	canvas: UI_Panel;
	{
		window_width := 1400;
		window_height := 800;
		os_window = Winc.create_window(window_width, window_height, "MIV");
		Simp.prepare_window(os_window, 4);
		dnd_typelist := string.["url/url", "text/uri-list", "text/plain", "application/octet-stream"];
		X11.enable_drag_and_drop(os_window, dnd_typelist);

		canvas = create_panel(.[window_width, window_height], palette);
	}
	window_size = canvas.size;

	// Simp.set_render_target(window);
	bar_height := fontsize*2;
	// canvas_width := window_width;
	// canvas_height := window_height - bar_height;

	/* Font loading */
	font_pixel_height := bar_height/2;
	main_font: *Simp.Dynamic_Font;
	main_font = Simp.get_font_at_size(FONT_DATA, font_pixel_height);

	/* Image context etc */
	img_ctx := Image_Context.{
		fit = .FIT_BEST,
		scale = 1.0,
		render = true,
		draw = true,
	};

	/* window specific image context */
	files_to_open: [..]string;
	{
		cli_args := get_command_line_arguments();
		cli_args.data += 1;
		cli_args.count -= 1;
		array_add(*files_to_open, ..cli_args);
	}
	gpu_texture: Simp.Texture;

	inp: Input_State;

	/* Timing */
	target_frame_time: float64 = 1.0/120.0;
	last_1s_time := current_time_monotonic();
	prev_time := last_1s_time;

	frame_1s_counter := 0;
	frame_count_over_1s := 60;
	running := true;
	while running {
		/* Timings etc */
		frame_1s_counter += 1;
		now := current_time_monotonic();
		if to_float64_seconds(now - last_1s_time) > 0.2 {
			frame_count_over_1s = frame_1s_counter*5;
			frame_1s_counter = 0;
			last_1s_time = now;
		}
		frame_time := to_float64_seconds(now - prev_time);
		if frame_time < target_frame_time {
			libc.usleep(cast(u32, (target_frame_time - frame_time)*1_000_000));
		}
		prev_time = current_time_monotonic();

		/* Window resize */
		Input.update_window_events();
		for Input.get_window_resizes() {
			Simp.update_window(it.window);
			if it.window == os_window {
				reset_panel(*canvas, .[it.width, it.height], palette);
				window_size = canvas.size;
				/* if I ever dynamically adjust bar height, I would do it here (see how I did it in git) */
				GL.glXSwapIntervalEXT(X11.x_global_display, Simp.find_window_info(os_window).specific.glx_window, 0);
			}
		}

		/* Inputs */
		{ /* Reset */
			p := inp.persistent;
			inp = .{};
			inp.persistent = p;
		}
		for event: Input.events_this_frame {
			if event.type == .QUIT then running = false;
			if event.type == .DRAG_AND_DROP_FILES array_add(*files_to_open, ..event.files);
			/* Press */
			if (event.type == .KEYBOARD) && event.key_pressed then if event.key_code == {
				case .ESCAPE; running = false;
				case .SHIFT; inp.shifted = true;
				case .ARROW_UP; inp.arrow_up = true;
				case .ARROW_DOWN; inp.arrow_down = true;
				case #char "W"; inp.w = true;
				case #char "A"; inp.a = true;
				case #char "S"; inp.s = true;
				case #char "D"; inp.d = true;
				case .MOUSE_BUTTON_RIGHT;
					inp.pointer_when_pressed = get_pointer_position();
					inp.right_button = true;
				case .MOUSE_BUTTON_LEFT;
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
		/* Files added via command line or drop-in */
		for files_to_open {
			print("%\n", it);
			ext := get_extension(it);
			if ext == "so" register_dynlib(it, true);
			else {
				old_name := img_ctx.pre_info.name;
				old_handle := img_ctx.pre_info.fileptr;
				img_ctx.render = get_loading(copy_string(it), ext, *img_ctx);
				if img_ctx.render {
					array_reset(*cast([]u8, old_name));
					if old_handle libc.fclose(old_handle);

					/* retrieve previous offsets etc if available, for now we just reset */
					img_ctx.offset = .{0, 0};
					img_ctx.auto_fit = true;
				}
				print("%\n", img_ctx);
			}
			array_unordered_remove_by_index(*files_to_open, 0);
		}
		img_ctx.draw = true;

		/* Image rendering (aka resolving the actual data) */
		/* At some point we might want to move this to after panning and zooming, to get up-to-date subviews */
		if !img_ctx.plugin { img_ctx.render = false; img_ctx.draw = false; }
		if img_ctx.render {
			using img_ctx.render_info;
			buffer_width = img_ctx.pre_info.width;
			buffer_height = img_ctx.pre_info.height;
			array_resize(*(buffer), buffer_width*buffer_height);
			render_error := img_ctx.plugin.render(*img_ctx.pre_info, *img_ctx.render_info);
			if render_error {
				log_error("File image data retrieval error: %", render_error);
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
		}

		{/* Drawing time */
			/* First we define the broad outline of panels that we'll see (the ones that make the canvas smaller) */
			reset_panel(*canvas, window_size, bg_palette);
			defer draw_panel(os_window, *canvas, false);

			top_bar := panel_split(*canvas, .{bar_height, canvas.size[1]}, .TOP, false, palette);
			defer draw_panel(os_window, *top_bar);
			bottom_bar := panel_split(*canvas, .{bar_height - 4, canvas.size[1]}, .BOTTOM, false, palette);
			defer draw_panel(os_window, *bottom_bar);

			/* This needs to run after both an input change and a window change. */
			/* I could have a seperate `if rescale` block or whatever, but for now this is simplest */
			img_ctx.scale = clamp(img_ctx.scale, 1/cast(float, max(img_ctx.pre_info.width, img_ctx.pre_info.height)), cast(float, max(canvas.size[0], canvas.size[1])));

			/* Image drawing */
			if img_ctx.draw {
				/* we have to process our inputs (not using the keyboard yet) */
				if pointer_is_in_panel(*canvas, inp.ipointer) {
					if inp.scroll_delta {
						img_ctx.auto_fit = false;
						delta := inp.scroll_delta / ifx inp.shifted then 200 else 10;
						if delta < 0 img_ctx.scale /= 1 + abs(delta);
						else img_ctx.scale *= 1 + abs(delta);
					}
					if inp.middle_button {
						img_ctx.auto_fit = true;
						img_ctx.offset = .{};
					}

					if inp.left_button {
						img_ctx.auto_fit = false;
						img_ctx.offset = img_ctx.pre_pan_offset + inp.fpointer - inp.pointer_when_pressed;
					} else {
						img_ctx.pre_pan_offset = img_ctx.offset;
					}
				}

				screen_center := Vector2.{ cast(float, canvas.size[0])/2, cast(float, canvas.size[1])/2 };
				image_center := Vector2.{ cast(float, img_ctx.pre_info.width)/2, cast(float, img_ctx.pre_info.height)/2 };

				now_fit := img_ctx.fit;
				if now_fit == .FIT_BEST {
					screen_woh := screen_center.x/screen_center.y;
					image_woh := image_center.x/image_center.y;
					if screen_woh > image_woh now_fit = .FIT_HEIGHT;
					else now_fit = .FIT_WIDTH;
				}

				if img_ctx.auto_fit if now_fit == {
				case .ONE_TO_ONE;
					img_ctx.scale = 1;
				case .FIT_WIDTH;
					img_ctx.scale = screen_center.x/image_center.x;
				case .FIT_HEIGHT;
					img_ctx.scale = screen_center.y/image_center.y;
				case .FIT_BEST; /* should be unreachable */
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
				for * image_bounds { it.* = rot_mat*it.*; }
				for * image_bounds { it.* *= img_ctx.scale; it.* += screen_center + img_ctx.offset; }

				Simp.set_render_target(*canvas.target);
				Simp.set_shader_for_images(*gpu_texture);
				Simp.immediate_begin();
				Simp.immediate_quad(image_bounds[0], image_bounds[1], image_bounds[2], image_bounds[3]);
			}

			/* UI */
			/* We have to reserve some space for buttons */
			fit_buttons_space := panel_split(*top_bar, .{bar_height*4, top_bar.size[0]}, .LEFT);
			fit_buttons_space.colors.body = .[55, 55, 55, 255];
			fit_buttons := panel_subdivide(*fit_buttons_space, 4, .HORIZONTAL);
			if img_ctx.auto_fit && img_ctx.draw fit_buttons[img_ctx.fit].colors.text = .[255, 127, 0, 255];
			for fit_buttons {
				if panel_button(*it, inp.ipointer, inp.left_button) {
					img_ctx.fit = xx it_index;
					img_ctx.auto_fit = true;
				}
				fit_button_text :: string.["1:1", "W", "H", "B"];
				panel_text(*it, main_font, fit_button_text[it_index], .MIDDLE, .MIDDLE);
			}

			defer for fit_buttons draw_panel(os_window, *it);

			text := isolate_name(img_ctx.pre_info.name);
			panel_text(*top_bar, main_font, text, .RIGHT, .MIDDLE);

			if frame_time < target_frame_time then bottom_bar.colors.text = .[100, 210, 25, 255];
			else bottom_bar.colors.text = .[220, 60, 25, 255];
			text = sprint("fps: %", frame_count_over_1s);
			panel_text(*bottom_bar, main_font, text, .RIGHT, .MIDDLE);
			bottom_bar.colors.text = palette.text;

			if img_ctx.draw {
				text = sprint("%\%", formatFloat(img_ctx.scale*100, trailing_width = 2, zero_removal = .NO));
				panel_text(*bottom_bar, main_font, text, .LEFT, .MIDDLE);
			}

		}
		{/* Popups */
			/* In here, I wanna write the big dialogue with the buttons and stuff */
			/* Next to that, I want to write little popup windows about non-critical logs. */
			/* This latter one will need text flow functions. I'm thinking to have the width be limited, and for the cut-off to initially not care about whitespace */
		}

		Simp.immediate_flush();
		Simp.swap_buffers(os_window);
		reset_temporary_storage();
	}
}

get_pointer_position :: () -> Vector2 {
	mouse_x, mouse_y := Winc.get_mouse_pointer_position();
	return .{xx mouse_x, xx (window_size[1] - xx mouse_y)};
}

FONT_PATH :: "/usr/share/fonts/libertinus/LibertinusSerif-Regular.otf";
FONT_DATA :: #run cast([]u8) read_entire_file(FONT_PATH);

#load "registration.jai";
#load "ui.jai";

Winc :: #import "Window_Creation";
Input :: #import "Input";
Simp :: #import "Simp";
X11 :: #import "X11";
GL :: #import "GL";

#import "Math";
#import "File";
#import "String";
#import "Basic";
