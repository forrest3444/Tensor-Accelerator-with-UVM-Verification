create_clock -name clk -period $CLK_NS [get_ports clk]

set spad_inputs [get_ports {req_i we_i addr_i[*] wdata_i[*] wstrb_i[*]}]

set_input_delay  [expr $CLK_NS * 0.20] -clock clk $spad_inputs
set_output_delay [expr $CLK_NS * 0.20] -clock clk [all_outputs]

set_driving_cell -lib_cell INV_X1 $spad_inputs
set_load 0.010 [all_outputs]
