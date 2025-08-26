#run build();

release :: false;

exe_name :: "miv";
compile_MIV :: true;
compile_ppm_c :: true;
compile_meow_jai :: false;

build :: () {
	defer set_build_options_dc(.{do_output = false, write_added_strings=false});

	/* main program */
	if compile_MIV {
		MIV_w := compiler_create_workspace("Build MIV");
		options := get_build_options(); {
			options.output_executable_name = exe_name;
			if release options.backend = .LLVM; else options.backend = .X64;
			options.text_output_flags = .OUTPUT_TIMING_INFO;
			if options.backend == .LLVM then set_optimization(*options, .VERY_OPTIMIZED);
		} set_build_options(options, MIV_w);

		{ /* checking for messages (to see when it's done, so that we don't run before it's done) */
			intercept_flags: Intercept_Flags;
			compiler_begin_intercept(MIV_w, intercept_flags);
			defer compiler_end_intercept(MIV_w);

			add_build_file("main.jai", MIV_w);

			tip_amount := 0;
			while true {
				message := compiler_wait_for_message();
				if message.kind == {
				case .COMPLETE; break;
				case .ERROR;
					continue;
				}
			}
		}
	}

	if compile_ppm_c {
		command: []string;
		if release command = string.["gcc", "-fPIC", "-O3", "./plugins/ppm.c", "-shared", "-o", "./plugins/ppm.so"];
		else command = string.["gcc", "-fPIC", "./plugins/ppm.c", "-shared", "-o", "./plugins/ppm.so"];
		process_result, output_string, error_string, timeout_reached := Process.run_command(..command);
		if process_result.exit_code != 0 {
			log_error("Attempted command: %\n%", command, error_string);
			log_error("\n");
		}
	}

	if compile_meow_jai {
		meow_jai_w := compiler_create_workspace("Build meow.jai");
		options: Build_Options;
		copy_commonly_propagated_fields(get_build_options(), *options);
			options.output_type = .DYNAMIC_LIBRARY;
			options.output_executable_name = "meow_jai";
			options.output_path = "./plugins/";
			options.backend = .X64;
			if options.backend == .LLVM then set_optimization(*options, .VERY_OPTIMIZED);
			options.text_output_flags = .OUTPUT_TIMING_INFO;

		set_build_options(options, meow_jai_w);
		add_build_file("./plugins/meow.jai", meow_jai_w);
		compiler_destroy_workspace(meow_jai_w);
	}


}

Process :: #import "Process";
#import "Compiler";
#import "Basic";
