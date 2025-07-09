
main :: () {
	// handle := libc.dlopen("./meow_c.so", libc.RTLD_NOW);
	// if !handle {
	// 	print("Dynamic library loading error: %s\n", to_string(libc.dlerror()));
	// 	exit(1);
	// }
	// libc.dlerror()

	// meow :: #type (s64) -> float64 #c_call;

	// meow_c: meow = libc.dlsym(handle, "meow");
	// loading_error := to_string(libc.dlerror());
	// if loading_error {
	// 	print("Dynamic function loading error: %s\n", loading_error);
	// 	exit(1);
	// }

	// print("%\n", meow_c(2));

	// libc.dlclose(handle);

	window_width := 1400;
	window_height := 800;
	window := create_window(window_width, window_height, "MIV");
	Simp.set_render_target(window);
	bar_height := window_height/10;

	/* Font loading */
	font_pixel_height := bar_height/2;
	main_font: *Simp.Dynamic_Font;
	main_font = Simp.get_font_at_size(FONT_DATA, font_pixel_height);

	target_frame_time: float64 = 1.0/69.0;

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

				bar_height = window_height/10;
				font_pixel_height = bar_height/2;
				main_font = Simp.get_font_at_size(FONT_DATA, font_pixel_height);
			}
		}
		for event: events_this_frame {
			if event.type == .QUIT then running = false;
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

		Simp.clear_render_target(0.05, 0.05, 0.05, 1);

		/* image */
		Simp.immediate_quad(Vector2.{10, 10} + .{0, 0}, Vector2.{10, 10} + .{300, 0}, Vector2.{10, 10} + .{400, 300}, Vector2.{10, 10} + .{0, 200});

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
		text = sprint("%", frame_count_over_1s);
		text_width = Simp.prepare_text(main_font, text);
		Simp.draw_prepared_text(main_font, window_width - text_width*3/2, window_height - font_pixel_height*6/5, text_color);


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

#import "Window_Creation";
#import "Input";
Simp :: #import "Simp";

libc :: #import "POSIX";

#import "Math";
#import "File";
#import "Basic";
