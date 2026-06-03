create_clock -name vclk -period $CLK_NS

set splitter_inputs [get_ports {addr_i[*] bytes_i[*] burst_len_i[*]}]

set_input_delay  [expr $CLK_NS * 0.20] -clock vclk $splitter_inputs
set_output_delay [expr $CLK_NS * 0.20] -clock vclk [all_outputs]

set_driving_cell -lib_cell INV_X1 $splitter_inputs
set_load 0.010 [all_outputs]
