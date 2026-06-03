create_clock -name clk -period $CLK_NS [get_ports clk]

set acc_inputs [get_ports {rst_n clear_i load_i data_i[*]}]

set_input_delay  [expr $CLK_NS * 0.20] -clock clk $acc_inputs
set_output_delay [expr $CLK_NS * 0.20] -clock clk [all_outputs]

set_driving_cell -lib_cell INV_X1 $acc_inputs
set_load 0.010 [all_outputs]

set_false_path -from [get_ports rst_n]
