create_clock -name vclk -period $CLK_NS

set sat_inputs [get_ports {data_i[*] saturate_en_i}]

set_input_delay  [expr $CLK_NS * 0.20] -clock vclk $sat_inputs
set_output_delay [expr $CLK_NS * 0.20] -clock vclk [all_outputs]

set_driving_cell -lib_cell INV_X1 $sat_inputs
set_load 0.010 [all_outputs]
