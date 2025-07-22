Image_Context :: struct {
	fit : enum {ONE_TO_ONE; FIT_WIDTH; FIT_HEIGHT; FIT_BEST;}
	offset: Vector2;
	scale: float;
	angle: float;

	plugin: *Registration_Entry;
	pre_info: Pre_Rendering_Info;
	render_info: Rendering_Info;
}

main :: () {
//	load_registration_file();
//	register_dynlib("./meow_c.so");

	defer cleanup_registrations();

	/* UI definitions */
	fontsize := 20;

	window_width := 1400;
	window_height := 800;
	window := create_window(window_width, window_height, "MIV");
	dnd_typelist := string.["url/url", "text/uri-list", "text/plain", "application/octet-stream"];
	X11.enable_drag_and_drop(window, dnd_typelist);
	Simp.set_render_target(window);
	bar_height := fontsize*2;
	canvas_width := window_width;
	canvas_height := window_height - bar_height;

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
		update_window_events();
		for get_window_resizes() {
			Simp.update_window(it.window);
			if it.window == window {
				window_width  = it.width;
				window_height = it.height;

				bar_height = fontsize*2;
				canvas_width = window_width;
				canvas_height = window_height - bar_height;

				font_pixel_height = bar_height/2;
				main_font = Simp.get_font_at_size(FONT_DATA, font_pixel_height);
				GL.glXSwapIntervalEXT(X11.x_global_display, Simp.find_window_info(window).specific.glx_window, 0);
			}
		}
		for event: events_this_frame {
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
					mouse_x, mouse_y := get_mouse_pointer_position();
					initial_mouse_pos = .{xx mouse_x, xx mouse_y};
					started_mouse_panning = true;
				case .MOUSE_BUTTON_MIDDLE;
					if shifted img_ctx.offset = .{};
					else started_zooming = false;
			}
			if (event.type == .KEYBOARD) && !event.key_pressed then if event.key_code == {
				case .SHIFT; shifted = false;
				case .MOUSE_BUTTON_LEFT; started_mouse_panning = false;
			}

			if event.type == .MOUSE_WHEEL {
				started_zooming = true;
				delta := cast(float, event.wheel_delta)/cast(float, event.typical_wheel_delta);
				if shifted {
					img_ctx.scale += delta/100;
				} else {
					img_ctx.scale += delta/10;
				}

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
				}
				print("%\n", img_ctx);
			}
			array_unordered_remove_by_index(*files_to_open, 0);
		}

		/* This is here because it needs to run after both an input change and a window change. */
		/* I could have a seperate `if rescale` block or whatever, but for now this is simplest */
		img_ctx.scale = clamp(img_ctx.scale, 1/cast(float, max(img_ctx.pre_info.width, img_ctx.pre_info.height)), cast(float, max(canvas_width, canvas_height)));
		draw_image = true;

		if started_mouse_panning {
			mouse_x, mouse_y := get_mouse_pointer_position();
			img_ctx.offset += .{xx mouse_x, xx -mouse_y} - .{initial_mouse_pos.x, -initial_mouse_pos.y};
			initial_mouse_pos = .{xx mouse_x, xx mouse_y};
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

		Simp.clear_render_target(0.2, 0.2, 0.5, 1);

		/* image drawing */
		if draw_image {
			screen_center := Vector2.{ cast(float, canvas_width)/2, cast(float, canvas_height)/2 };
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

			Simp.set_shader_for_images(*gpu_texture);
			Simp.immediate_begin();
			Simp.immediate_quad(image_bounds[0], image_bounds[1], image_bounds[2], image_bounds[3]);
		}

		/* UI */
		Simp.set_shader_for_color();
		Simp.immediate_quad(0, xx window_height, xx window_width, xx(window_height - bar_height), .{0.2, 0.2, 0.2, 1});

		text_color := Vector4.{1, 1, 1, 1};
		text := "MIV";

		Simp.set_shader_for_text();
		text_width := Simp.prepare_text(main_font, text);
		Simp.draw_prepared_text(main_font, window_width/2 - text_width/2, window_height - font_pixel_height*6/5, text_color);

		if frame_time < target_frame_time {
			text_color = Vector4.{0.3, 0.7, 0.1, 1};
		} else {
			text_color = Vector4.{0.8, 0.2, 0.1, 1};
		}
		text = sprint("fps: %", frame_count_over_1s);
		text_width = Simp.prepare_text(main_font, text);
		Simp.draw_prepared_text(main_font, window_width - text_width - font_pixel_height, window_height - font_pixel_height*6/5, text_color);

		if draw_image {
			text_color = Vector4.{1, 1, 1, 1};
			text = sprint("%\%", formatFloat(img_ctx.scale*100, trailing_width = 2, zero_removal = .NO));
			text_width = Simp.prepare_text(main_font, text);
			Simp.draw_prepared_text(main_font, font_pixel_height, window_height - font_pixel_height*6/5, text_color);
		}

		Simp.immediate_flush();
		Simp.swap_buffers(window);
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

FONT_PATH :: "/usr/share/fonts/libertinus/LibertinusSerif-Regular.otf";
FONT_DATA :: #run cast([]u8) read_entire_file(FONT_PATH);

#load "registration.jai";

#import "Window_Creation";
#import "Input";
Simp :: #import "Simp";
X11 :: #import "X11";
GL :: #import "GL";

#import "Math";
#import "File";
#import "String";
#import "Basic";
