create_clock -name clk -period $CLK_NS [get_ports clk]

set mac_inputs [get_ports {rst_n clear_i valid_i precision_i a_i[*] b_i[*]}]

set_input_delay  [expr $CLK_NS * 0.20] -clock clk $mac_inputs
set_output_delay [expr $CLK_NS * 0.20] -clock clk [all_outputs]

set_driving_cell -lib_cell INV_X1 $mac_inputs
set_load 0.010 [all_outputs]

set_false_path -from [get_ports rst_n]
