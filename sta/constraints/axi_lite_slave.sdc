create_clock -name clk -period $CLK_NS [get_ports clk]

set axil_inputs [get_ports {rst_n s_axil_awaddr[*] s_axil_awvalid s_axil_wdata[*] s_axil_wstrb[*] s_axil_wvalid s_axil_bready s_axil_araddr[*] s_axil_arvalid s_axil_rready reg_rd_data_i[*]}]

set_input_delay  [expr $CLK_NS * 0.20] -clock clk $axil_inputs
set_output_delay [expr $CLK_NS * 0.20] -clock clk [all_outputs]

set_driving_cell -lib_cell INV_X1 $axil_inputs
set_load 0.010 [all_outputs]

set_false_path -from [get_ports rst_n]
