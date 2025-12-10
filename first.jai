#run build();

release :: false;

exe_name     :: "miv";
compile_MIV  :: true;
compile_pnm  :: true;
compile_bmp  :: true;
compile_qoi  :: true;
compile_vaim :: true;

build :: () {
	defer set_build_options_dc(.{do_output = false, write_added_strings=false});

	/* main program */
	if compile_MIV {
		MIV_w := compiler_create_workspace("Build MIV");
		options := get_build_options(); {
			options.output_executable_name = exe_name;

			options.backend = ifx release then .LLVM else .X64;
			options.text_output_flags = .OUTPUT_TIMING_INFO;
			if options.backend == .LLVM then set_optimization(*options, .VERY_OPTIMIZED);
		} set_build_options(options, MIV_w);
		add_build_file("main.jai", MIV_w);
	}

	jai_files: [..]string;
	c_files: [..]string;

	if compile_qoi array_add(*jai_files, "qoi");
	if compile_bmp array_add(*jai_files, "bmp");

	if compile_pnm array_add(*c_files, "pnm");
	/* This is a personal format that I used a lot in the past. I probably won't ship the plugin on releases unless someone asks for it */
	if compile_vaim array_add(*c_files, "vaim");

	for jai_file: jai_files {
		w := compiler_create_workspace(jai_file);
		options := get_build_options(); {
			options.output_type = .DYNAMIC_LIBRARY;
			options.output_executable_name = jai_file;
			options.output_path = "./plugins/";

			options.backend = ifx release then .LLVM else .X64;
			options.text_output_flags = .OUTPUT_TIMING_INFO;
			if options.backend == .LLVM then set_optimization(*options, .VERY_OPTIMIZED);
		} set_build_options(options, w);
		add_build_file(tprint("./plugins/%.jai", jai_file), w);
		compiler_destroy_workspace(w);
	}

	for c_file: c_files {
		input_file := tprint("./plugins/%.c", c_file);
		output_file := tprint("./plugins/%.so", c_file);

		command: [..]string;
		array_add(*command, "gcc", "-fPIC");
		if release array_add(*command, "-O3");
		array_add(*command, input_file, "-shared", "-o", output_file);
		process_result, output_string, error_string, timeout_reached := Process.run_command(..command);
		if process_result.exit_code != 0 {
			log_error("Attempted command: %\n%", command, error_string);
			log_error("\n");
		}
	}

}

Process :: #import "Process";
#import "Compiler";
#import "Basic";
