Image_Context :: struct {
	fit : enum {ONE_TO_ONE; FIT_WIDTH; FIT_HEIGHT; FIT_BEST;}
	offset: Vector2;
	scale: float;
	angle: float;

	plugin: *Registration_Entry;
	pre_info: Pre_Rendering_Info;
	render_info: Rendering_Info;
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
//	load_registration_file();
//	register_dynlib("./meow_c.so");

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

		// pre_info.width = 789,
		// pre_info.height = 600,
		// pre_info.bit_depth = 8,
		// pre_info.channels = 3,
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
	shifted := false;
	initial_mouse_pos: Vector2;
	started_zooming := false;
	started_mouse_panning := false;
	render_image := true;
	draw_image := true;

	/* Timing */
	target_frame_time: float64 = 1.0/120.0;
	last_1s_time := current_time_monotonic();
	prev_time := last_1s_time;

	frame_1s_counter := 0;
	frame_count_over_1s := 60;
	running := true;
	while running {
		frame_1s_counter += 1;
		Input.update_window_events();
		for Input.get_window_resizes() {
			Simp.update_window(it.window);
			if it.window == os_window {
				reset_panel(*canvas, .[it.width, it.height], palette);
				window_size = canvas.size;
				// window_width  = it.width;
				// window_height = it.height;

				/* if I ever dynamically adjust bar height, I would do it here */
				// bar_height = fontsize*2;
				// font_pixel_height = bar_height/2;
				// main_font = Simp.get_font_at_size(FONT_DATA, font_pixel_height);

				// canvas_width = window_width;
				// canvas_height = window_height - bar_height;

				GL.glXSwapIntervalEXT(X11.x_global_display, Simp.find_window_info(os_window).specific.glx_window, 0);
			}
		}
		for event: Input.events_this_frame {
			if event.type == .QUIT then running = false;

			if event.type == .DRAG_AND_DROP_FILES array_add(*files_to_open, ..event.files);

			scale_amount := ifx shifted then 0.01 else 0.1;
			offset_amount := ifx shifted then 1 else 20;
			if (event.type == .KEYBOARD) && event.key_pressed then if event.key_code == {
				case .ESCAPE; running = false;
				case .SHIFT; shifted = true;
				case .ARROW_UP; img_ctx.scale += scale_amount; started_zooming = true;
				case .ARROW_DOWN; img_ctx.scale -= scale_amount; started_zooming = true;
				case #char "W"; img_ctx.offset.y += offset_amount;
				case #char "A"; img_ctx.offset.x -= offset_amount;
				case #char "S"; img_ctx.offset.y -= offset_amount;
				case #char "D"; img_ctx.offset.x += offset_amount;
				case .MOUSE_BUTTON_LEFT;
					initial_mouse_pos = get_pointer_position();
					started_mouse_panning = true;
				case .MOUSE_BUTTON_MIDDLE;
					img_ctx.offset = .{};
					started_zooming = false;
			}
			if (event.type == .KEYBOARD) && !event.key_pressed then if event.key_code == {
				case .SHIFT; shifted = false;
				case .MOUSE_BUTTON_LEFT; started_mouse_panning = false;
			}

			if event.type == .MOUSE_WHEEL {
				/* Should still apply a transform based on the position of the mouse during this event */
				/* While zooming, also lerp between current offset and mouse offset within the image */
				/* img_ctx.offset = lerp(img_ctx.offset, mouse_pos_in_image, some_val) */
				started_zooming = true;
				delta := cast(float, event.wheel_delta)/cast(float, event.typical_wheel_delta);
				if shifted {
					delta /= 200;
				} else {
					delta /= 10;
				}
				if delta < 0 img_ctx.scale /= 1 + abs(delta);
				else img_ctx.scale *= 1 + abs(delta);

				mouse := get_pointer_position();
				offset_towards := mouse - Vector2.{xx window_size[0], xx window_size[1]}/2;
				img_ctx.offset = lerp(offset_towards, img_ctx.offset, delta);
			}
		}
		for files_to_open {
			print("%\n", it);
			ext := get_extension(it);
			if ext == "so" register_dynlib(it);
			else {
				old_name := img_ctx.pre_info.name;
				old_handle := img_ctx.pre_info.fileptr;
				render_image = get_loading(copy_string(it), ext, *img_ctx);
				if render_image {
					array_reset(*cast([]u8, old_name));
					if old_handle libc.fclose(old_handle);

					/* retrieve previous offsets etc if available, for now we just reset */
					started_mouse_panning = false;
					img_ctx.offset = .{0, 0};
					started_zooming = false;
				}
				print("%\n", img_ctx);
			}
			array_unordered_remove_by_index(*files_to_open, 0);
		}
		draw_image = true;

		if started_mouse_panning {
			mouse := get_pointer_position();
			img_ctx.offset += .{mouse.x - initial_mouse_pos.x, mouse.y - initial_mouse_pos.y};

			initial_mouse_pos = mouse;
		}

		/* image rendering (aka resolving the actual data) */
		if !img_ctx.plugin { render_image = false; draw_image = false; }
		if render_image {
			using img_ctx.render_info;
			buffer_width = img_ctx.pre_info.width;
			buffer_height = img_ctx.pre_info.height;
			array_resize(*(buffer), buffer_width*buffer_height);
			render_error := img_ctx.plugin.render(*img_ctx.pre_info, *img_ctx.render_info);
			if render_error {
				log_error("File image data retrieval error: %", render_error);
				draw_image = false;
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
			render_image = false;
		}

		/* timings etc */
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


		{/* drawing time */
			/* first we define the broad outline of panels that we'll see (the ones that make the canvas smaller) */
			reset_panel(*canvas, window_size, bg_palette);
			defer draw_panel(os_window, *canvas, false);

			top_bar := panel_split(*canvas, .{bar_height, canvas.size[1]}, .TOP, false, palette);
			defer draw_panel(os_window, *top_bar);
			bottom_bar := panel_split(*canvas, .{bar_height - 4, canvas.size[1]}, .BOTTOM, false, palette);
			defer draw_panel(os_window, *bottom_bar);

			/* This needs to run after both an input change and a window change. */
			/* I could have a seperate `if rescale` block or whatever, but for now this is simplest */
			img_ctx.scale = clamp(img_ctx.scale, 1/cast(float, max(img_ctx.pre_info.width, img_ctx.pre_info.height)), cast(float, max(canvas.size[0], canvas.size[1])));

			/* image drawing */
			//panel_recolor(*canvas, .{body = .[66, 66, 127, 255]});
			if draw_image {

				screen_center := Vector2.{ cast(float, canvas.size[0])/2, cast(float, canvas.size[1])/2 };
				image_center := Vector2.{ cast(float, img_ctx.pre_info.width)/2, cast(float, img_ctx.pre_info.height)/2 };
				screen_woh := screen_center.x/screen_center.y;
				image_woh := image_center.x/image_center.y;

				now_fit := img_ctx.fit;
				if now_fit == .FIT_BEST {
					if screen_woh > image_woh now_fit = .FIT_HEIGHT;
					else now_fit = .FIT_WIDTH;
				}

				if !started_zooming if now_fit == {
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
			/* we have to reserve some space for buttons */
			fit_buttons_space := panel_split(*top_bar, .{bar_height*4, top_bar.size[0]}, .LEFT);
			fit_buttons_space.colors.body = .[55, 55, 55, 255];
			fit_buttons := panel_subdivide(*fit_buttons_space, 4, .HORIZONTAL);
			if !started_zooming && draw_image fit_buttons[img_ctx.fit].colors.text = .[255, 127, 0, 255];
			for fit_buttons {
				pp := get_pointer_position();
				pointer_position := int.[xx pp.x, xx pp.y];
				if panel_button(*it, pointer_position, started_mouse_panning) {
					img_ctx.fit = xx it_index;
					started_zooming = false;
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

			if draw_image {
				text = sprint("%\%", formatFloat(img_ctx.scale*100, trailing_width = 2, zero_removal = .NO));
				panel_text(*bottom_bar, main_font, text, .LEFT, .MIDDLE);
			}

		}
		{/* popups */
			/* in here, I wanna write the big dialogue with the buttons and stuff */
			/* Next to that, I want to write little popup windows about non-critical logs. */
			/* This latter one will need text flow functions. I'm thinking to have the width be limited, and for the cut-off to initially not care about whitespace */
		}

		Simp.immediate_flush();
		Simp.swap_buffers(os_window);
		reset_temporary_storage();
	}
}

get_extension :: (path: string) -> string {
	ext: string;
	ext.count = 0;
	ext.data = path.data + path.count;
	while ext.count != path.count {
		ext.count += 1;
		ext.data -= 1;
		if ext[0] == "." {
			ext.count -= 1;
			ext.data += 1;
			return ext;
		}
	}
	return "";
}

isolate_name :: (path: string) -> string {
	ext: string;
	ext.count = 0;
	ext.data = path.data + path.count;
	while ext.count != path.count {
		ext.count += 1;
		ext.data -= 1;
		if ext[0] == "/" {
			ext.count -= 1;
			ext.data += 1;
			return ext;
		}
	}
	return path;
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
