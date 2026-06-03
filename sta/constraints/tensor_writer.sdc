create_clock -name clk -period $CLK_NS [get_ports clk]

set writer_inputs [get_ports {rst_n start_i ext_addr_i[*] byte_len_i[*] burst_len_i[*] spad_offset_i[*] m_axi_awready m_axi_wready m_axi_bresp[*] m_axi_bid m_axi_bvalid spad_rdata_i[*] spad_ready_i}]

set_input_delay  [expr $CLK_NS * 0.20] -clock clk $writer_inputs
set_output_delay [expr $CLK_NS * 0.20] -clock clk [all_outputs]

set_driving_cell -lib_cell INV_X1 $writer_inputs
set_load 0.010 [all_outputs]

set_false_path -from [get_ports rst_n]
