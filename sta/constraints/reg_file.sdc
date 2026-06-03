create_clock -name clk -period $CLK_NS [get_ports clk]

set reg_file_inputs [get_ports {rst_n wr_en_i wr_addr_i[*] wr_data_i[*] wr_strb_i[*] rd_en_i rd_addr_i[*] status_i[*] error_code_i[*] ovf_count_i[*]}]

set_input_delay  [expr $CLK_NS * 0.20] -clock clk $reg_file_inputs
set_output_delay [expr $CLK_NS * 0.20] -clock clk [all_outputs]

set_driving_cell -lib_cell INV_X1 $reg_file_inputs
set_load 0.010 [all_outputs]

set_false_path -from [get_ports rst_n]
