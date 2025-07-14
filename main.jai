fake_image_width := 789;
fake_image_height := 600;
fontsize := 20;

main :: () {
	register_dynlib("./meow_c.so");

	/* UI definitions */
	window_width := 1400;
	window_height := 800;
	window := create_window(window_width, window_height, "MIV");
	Simp.set_render_target(window);
	bar_height := fontsize*2;
	canvas_width := window_width;
	canvas_height := window_height - bar_height;

	/* Font loading */
	font_pixel_height := bar_height/2;
	main_font: *Simp.Dynamic_Font;
	main_font = Simp.get_font_at_size(FONT_DATA, font_pixel_height);

	/* Image transform information */
	fit : enum {ONE_TO_ONE; FIT_WIDTH; FIT_HEIGHT; FIT_BEST;} = .FIT_BEST;
	image_offset: Vector2;
	image_scale: float = 1.0;
	image_angle := 0;

	shifted := false;
	initial_mouse_pos: Vector2;
	started_zooming := false;
	started_mouse_panning := false;

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
			}
		}
		for event: events_this_frame {
			if event.type == .QUIT then running = false;
			
			scale_amount := ifx shifted then 0.01 else 0.1;
			offset_amount := ifx shifted then 1 else 20;
			if (event.type == .KEYBOARD) && event.key_pressed then if event.key_code == {
				case .ESCAPE; running = false;
				case .SHIFT; shifted = true;
				case .ARROW_UP; image_scale += scale_amount; started_zooming = true;
				case .ARROW_DOWN; image_scale -= scale_amount; started_zooming = true;
				case #char "W"; image_offset.y += offset_amount;
				case #char "A"; image_offset.x -= offset_amount;
				case #char "S"; image_offset.y -= offset_amount;
				case #char "D"; image_offset.x += offset_amount;
				case .MOUSE_BUTTON_LEFT;
					mouse_x, mouse_y := get_mouse_pointer_position();
					initial_mouse_pos = .{xx mouse_x, xx mouse_y};
					started_mouse_panning = true;
				case .MOUSE_BUTTON_MIDDLE;
					if shifted image_offset = .{};
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
					image_scale += delta/100;
				} else {
					image_scale += delta/10;
				}

				image_scale = clamp(image_scale, 1/cast(float, max(fake_image_width, fake_image_height)), cast(float, max(canvas_width, canvas_height)));
			}
		}
		if started_mouse_panning {
			mouse_x, mouse_y := get_mouse_pointer_position();
			image_offset += .{xx mouse_x, xx -mouse_y} - .{initial_mouse_pos.x, -initial_mouse_pos.y};
			initial_mouse_pos = .{xx mouse_x, xx mouse_y};
		}

//		print("eol\n");
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

		Simp.clear_render_target(0.05, 0.05, 0.05, 1);

		/* image */
		screen_center := Vector2.{ cast(float, canvas_width)/2, cast(float, canvas_height)/2 };
		image_center := Vector2.{ cast(float, fake_image_width)/2, cast(float, fake_image_height)/2 };
		screen_woh := screen_center.x/screen_center.y;
		image_woh := image_center.x/image_center.y;

		now_fit := fit;
		if fit == .FIT_BEST {
			if screen_woh > image_woh now_fit = .FIT_HEIGHT;
			else now_fit = .FIT_WIDTH;
		}

		if !started_zooming if now_fit == {
		case .ONE_TO_ONE;
			image_scale = 1;
		case .FIT_WIDTH;
			image_scale = screen_center.x/image_center.x;
		case .FIT_HEIGHT;
			image_scale = screen_center.y/image_center.y;
		case .FIT_BEST; /* should be unreachable */
		}
		image_bounds := Vector2.[
			-image_center, .{image_center.x, -image_center.y}, image_center, .{-image_center.x, image_center.y}
		];

		rot_mat := Matrix2.{
			cos(2*PI*image_angle/360), -sin(2*PI*image_angle/360),
			sin(2*PI*image_angle/360), cos(2*PI*image_angle/360)
		};
		for * image_bounds { it.* = rot_mat*it.*; }
		for * image_bounds { it.* *= image_scale; it.* += screen_center + image_offset; }
		Simp.immediate_quad(image_bounds[0], image_bounds[1], image_bounds[2], image_bounds[3]);

		/* UI */
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


		text_color = Vector4.{1, 1, 1, 1};
		text = sprint("%\%", formatFloat(image_scale*100, trailing_width = 2, zero_removal = .NO));
		text_width = Simp.prepare_text(main_font, text);
		Simp.draw_prepared_text(main_font, font_pixel_height, window_height - font_pixel_height*6/5, text_color);

		Simp.immediate_flush();
		Simp.swap_buffers(window);
		{
			#import "X11"; #import "GL";
			glXSwapIntervalEXT(x_global_display, Simp.find_window_info(window).specific.glx_window, 0);
	    }
		reset_temporary_storage();
	}
}

FONT_PATH :: "/usr/share/fonts/libertinus/LibertinusSerif-Regular.otf";
FONT_DATA :: #run cast([]u8) read_entire_file(FONT_PATH);

#load "loader.jai";

#import "Window_Creation";
#import "Input";
Simp :: #import "Simp";

#import "Math";
#import "File";
#import "Basic";
