window_width := 1400;
window_height := 800;
main_font: *Simp.Dynamic_Font;

main :: () {
	handle := libc.dlopen("libm.so.6", libc.RTLD_NOW);
	if !handle {
		print("Dynamic library loading error: %s\n", to_string(libc.dlerror()));
		exit(1);
	}
	//print("%s\n", to_string(libc.dlerror()));

	cosine: (float64) -> float64 #c_call;

	cosine = libc.dlsym(handle, "cos");
	loading_error := to_string(libc.dlerror());
	if loading_error {
		print("Dynamic function loading error: %s\n", loading_error);
		exit(1);
	}

	print("%\n", cosine(2));

	libc.dlclose(handle);

	window := create_window(window_width, window_height, "FPL");
	Simp.set_render_target(window);

	/* Font loading */
	font_pixel_height := window_height / FONT_SCALE;
	main_font = Simp.get_font_at_size(FONT_DATA, font_pixel_height);

	running := true;
	while running {
		update_window_events();
		for get_window_resizes() {
			Simp.update_window(it.window);
			if it.window == window {

				window_width  = it.width;
				window_height = it.height;

				font_pixel_height = window_height / FONT_SCALE;
				main_font = Simp.get_font_at_size(FONT_DATA, font_pixel_height);
			}
		}
		for event: events_this_frame {
			if event.type == .QUIT then running = false;
		}
		Simp.clear_render_target(0.05, 0.05, 0.05, 1);

		text_color := Vector4.{1, 1, 1, 1};
		text := "MIV";

		Simp.set_shader_for_text();
		text_width := Simp.prepare_text(main_font, text);
		Simp.draw_prepared_text(main_font, window_width/2 - text_width/2, window_height*90/100, text_color);

		Simp.immediate_flush();
		Simp.swap_buffers(window);
		reset_temporary_storage();
	}
}

FONT_PATH :: "/usr/share/fonts/libertinus/LibertinusSerif-Regular.otf";
FONT_SCALE :: 30;
FONT_DATA :: #run cast([]u8) read_entire_file(FONT_PATH);

#import "Window_Creation";
#import "Input";
Simp :: #import "Simp";

libc :: #import "POSIX";

#import "Math";
#import "File";
#import "Basic";
