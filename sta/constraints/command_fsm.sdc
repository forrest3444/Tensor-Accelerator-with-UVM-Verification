create_clock -name clk -period $CLK_NS [get_ports clk]

set fsm_inputs [get_ports {rst_n start_i soft_reset_i clear_done_i clear_error_i clear_irq_i irq_en_i cfg_valid_i cfg_error_i[*] read_dma_error_i write_dma_done_i write_dma_error_i read_cross_4kb_i write_cross_4kb_i compute_done_i post_process_done_i overflow_i last_tile_i last_k_tile_i load_tile_done_i}]

set_input_delay  [expr $CLK_NS * 0.20] -clock clk $fsm_inputs
set_output_delay [expr $CLK_NS * 0.20] -clock clk [all_outputs]

set_driving_cell -lib_cell INV_X1 $fsm_inputs
set_load 0.010 [all_outputs]

set_false_path -from [get_ports rst_n]
