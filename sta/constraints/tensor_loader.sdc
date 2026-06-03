create_clock -name clk -period $CLK_NS [get_ports clk]

set loader_inputs [get_ports {rst_n start_i ext_addr_i[*] byte_len_i[*] burst_len_i[*] spad_offset_i[*] row_mode_i row_count_i[*] row_bytes_i[*] ext_row_stride_i[*] spad_row_stride_i[*] m_axi_arready m_axi_rdata[*] m_axi_rid m_axi_rresp[*] m_axi_rlast m_axi_rvalid spad_ready_i}]

set_max_fanout 32 [current_design]

set_input_delay  [expr $CLK_NS * 0.20] -clock clk $loader_inputs
set_output_delay [expr $CLK_NS * 0.20] -clock clk [all_outputs]

set_driving_cell -lib_cell INV_X1 $loader_inputs
set_load 0.010 [all_outputs]

set_false_path -from [get_ports rst_n]
