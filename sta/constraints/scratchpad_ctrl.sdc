create_clock -name vclk -period $CLK_NS

set ctrl_inputs [get_ports {dma_req_i dma_we_i dma_addr_i[*] dma_wdata_i[*] dma_wstrb_i[*] compute_req_i compute_we_i compute_addr_i[*] compute_wdata_i[*] compute_wstrb_i[*] spad_rdata_i[*] spad_ready_i}]

set_input_delay  [expr $CLK_NS * 0.20] -clock vclk $ctrl_inputs
set_output_delay [expr $CLK_NS * 0.20] -clock vclk [all_outputs]

set_driving_cell -lib_cell INV_X1 $ctrl_inputs
set_load 0.010 [all_outputs]
