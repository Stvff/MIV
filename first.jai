#run build();

release :: true;

exe_name :: "miv";
compile_MIV :: true;
compile_ppm_c :: true;
compile_qoi_jai :: true;

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
			// intercept_flags: Intercept_Flags;
			// compiler_begin_intercept(MIV_w, intercept_flags);
			// defer compiler_end_intercept(MIV_w);

			add_build_file("main.jai", MIV_w);

			// tip_amount := 0;
			// while true {
			// 	message := compiler_wait_for_message();
			// 	if message.kind == {
			// 	case .COMPLETE; break;
			// 	case .ERROR;
			// 		continue;
			// 	}
			// }
		}
	}

	if compile_ppm_c {
		command: [..]string;
		array_add(*command, "gcc", "-fPIC");
		if release array_add(*command, "-O3");
		array_add(*command, "./plugins/ppm.c", "-shared", "-o", "./plugins/ppm.so");
		process_result, output_string, error_string, timeout_reached := Process.run_command(..command);
		if process_result.exit_code != 0 {
			log_error("Attempted command: %\n%", command, error_string);
			log_error("\n");
		}
	}

	if compile_qoi_jai {
		qoi_w := compiler_create_workspace("Build qoi.jai");
		current_build_options := get_build_options();
		options: Build_Options;
			copy_commonly_propagated_fields(current_build_options, *options);
			options.import_path = current_build_options.import_path;
			options.output_type = .DYNAMIC_LIBRARY;
			options.output_executable_name = "qoi";
			options.output_path = "./plugins/";
			if release options.backend = .LLVM;
			else options.backend = .X64;
			options.text_output_flags = .OUTPUT_TIMING_INFO;
			if options.backend == .LLVM then set_optimization(*options, .VERY_OPTIMIZED);

		set_build_options(options, qoi_w);
		add_build_file("./plugins/qoi.jai", qoi_w);
		compiler_destroy_workspace(qoi_w);
	}
}

Process :: #import "Process";
#import "Compiler";
#import "Basic";
