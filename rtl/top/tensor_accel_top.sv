module tensor_accel_top
  import tensor_pkg::*;
(
  input  logic clk,
  input  logic rst_n,

  input  logic [15:0] s_axil_awaddr,
  input  logic        s_axil_awvalid,
  output logic        s_axil_awready,
  input  logic [31:0] s_axil_wdata,
  input  logic [3:0]  s_axil_wstrb,
  input  logic        s_axil_wvalid,
  output logic        s_axil_wready,
  output logic [1:0]  s_axil_bresp,
  output logic        s_axil_bvalid,
  input  logic        s_axil_bready,
  input  logic [15:0] s_axil_araddr,
  input  logic        s_axil_arvalid,
  output logic        s_axil_arready,
  output logic [31:0] s_axil_rdata,
  output logic [1:0]  s_axil_rresp,
  output logic        s_axil_rvalid,
  input  logic        s_axil_rready,

  output logic [31:0] m_axi_araddr,
  output logic        m_axi_arid,
  output logic [7:0]  m_axi_arlen,
  output logic [2:0]  m_axi_arsize,
  output logic [1:0]  m_axi_arburst,
  output logic        m_axi_arvalid,
  input  logic        m_axi_arready,
  input  logic [63:0] m_axi_rdata,
  input  logic        m_axi_rid,
  input  logic [1:0]  m_axi_rresp,
  input  logic        m_axi_rlast,
  input  logic        m_axi_rvalid,
  output logic        m_axi_rready,

  output logic [31:0] m_axi_awaddr,
  output logic        m_axi_awid,
  output logic [7:0]  m_axi_awlen,
  output logic [2:0]  m_axi_awsize,
  output logic [1:0]  m_axi_awburst,
  output logic        m_axi_awvalid,
  input  logic        m_axi_awready,
  output logic [63:0] m_axi_wdata,
  output logic [7:0]  m_axi_wstrb,
  output logic        m_axi_wlast,
  output logic        m_axi_wvalid,
  input  logic        m_axi_wready,
  input  logic [1:0]  m_axi_bresp,
  input  logic        m_axi_bid,
  input  logic        m_axi_bvalid,
  output logic        m_axi_bready,

  output logic irq
);
  accel_cfg_t cfg;
  accel_status_t status;
  error_code_e cfg_error;
  error_code_e error_code;
  logic [31:0] ovf_count;

  logic reg_wr_en;
  logic [15:0] reg_wr_addr;
  logic [31:0] reg_wr_data;
  logic [3:0] reg_wr_strb;
  logic reg_rd_en;
  logic [15:0] reg_rd_addr;
  logic [31:0] reg_rd_data;
  logic start_pulse;
  logic soft_reset_pulse;
  logic clear_done_pulse;
  logic clear_error_pulse;
  logic clear_irq_pulse;
  logic irq_en;
  logic cfg_valid;

  logic sched_init;
  logic sched_advance_k;
  logic sched_advance;
  logic load_a_start;
  logic load_b_start;
  logic load_bias_start;
  logic compute_start;
  logic post_process_start;
  logic post_process_done;
  logic store_start;
  logic [5:0] tile_m;
  logic [5:0] tile_n;
  logic [5:0] tile_k;
  logic last_tile;
  logic first_k_tile;
  logic last_k_tile;
  logic [3:0] row_valid;
  logic [3:0] col_valid;
  logic [31:0] c_spad_offset;
  logic [31:0] c_ext_offset;
  logic [31:0] a_addr;
  logic [31:0] b_addr;
  logic [31:0] bias_addr;
  logic [31:0] a_bytes;
  logic [31:0] b_bytes;
  logic [31:0] bias_bytes;
  logic [15:0] a_spad_offset;
  logic [15:0] b_spad_offset;
  logic [15:0] bias_spad_offset;

  logic read_start;
  logic [31:0] read_addr;
  logic [31:0] read_bytes;
  logic [15:0] read_spad_offset;
  logic read_busy;
  logic read_done;
  logic read_error;
  logic read_cross_4kb;
  logic write_busy;
  logic writer_done;
  logic write_done;
  logic write_error;
  logic write_cross_4kb;
  logic store_active_q;
  logic [2:0] store_row_q;
  logic writer_start;
  logic [31:0] store_row_offset;
  logic [31:0] c_store_row_bytes;

  logic dma_spad_req;
  logic dma_spad_we;
  logic [15:0] dma_spad_addr;
  logic [31:0] dma_spad_wdata;
  logic [3:0] dma_spad_wstrb;
  logic [31:0] dma_spad_rdata;
  logic dma_spad_ready;
  logic writer_spad_req;
  logic writer_spad_we;
  logic [15:0] writer_spad_addr;
  logic [31:0] writer_spad_rdata;
  logic writer_spad_ready;
  logic ctrl_spad_req;
  logic ctrl_spad_we;
  logic [15:0] ctrl_spad_addr;
  logic [31:0] ctrl_spad_wdata;
  logic [3:0] ctrl_spad_wstrb;
  logic [31:0] ctrl_spad_rdata;
  logic ctrl_spad_ready;
  logic pp_spad_req;
  logic pp_spad_we;
  logic [15:0] pp_spad_addr;
  logic [31:0] pp_spad_wdata;
  logic [3:0] pp_spad_wstrb;
  logic [31:0] pp_spad_rdata;
  logic pp_spad_ready;
  logic spad_req;
  logic spad_we;
  logic [15:0] spad_addr;
  logic [31:0] spad_wdata;
  logic [3:0] spad_wstrb;
  logic [31:0] spad_rdata;
  logic spad_ready;

  logic [3:0] compute_count_q;
  logic compute_active_q;
  logic compute_done;
  logic compute_valid;
  logic [3:0] compute_k_limit;
  logic [31:0] row_base;
  logic [31:0] k_base;
  logic [31:0] k_remaining;
  logic [31:0] col_base;
  logic [31:0] tile_rows;
  logic [31:0] tile_cols;
  logic [31:0] c_write_bytes;
  logic [31:0] elem_b;
  logic [31:0] a_start_byte;
  logic [31:0] b_start_byte;
  logic [31:0] a_row_bytes;
  logic [31:0] b_row_bytes;
  logic [31:0] a_spad_stride;
  logic [31:0] b_spad_stride;
  logic [31:0] read_row_bytes;
  logic [31:0] read_ext_row_stride;
  logic [31:0] read_spad_row_stride;
  logic [2:0] read_row_count;
  logic read_row_mode;
  logic [3:0][15:0] a_vec;
  logic [3:0][15:0] b_vec;
  logic [3:0][3:0][15:0] a_tile_q;
  logic [3:0][3:0][15:0] b_tile_q;
  logic [3:0][3:0][31:0] array_acc;
  logic [3:0][3:0][31:0] acc_tile;
  logic [3:0][31:0] bias_vec;
  logic [3:0][31:0] bias_vec_q;
  logic [3:0][3:0][31:0] pp_result;
  logic overflow;
  logic array_overflow;
  logic post_process_overflow;
  logic pp_wb_active_q;
  logic [3:0] pp_wb_count_q;
  logic [1:0] pp_wb_row;
  logic [1:0] pp_wb_col;
  logic [4:0] pp_wb_elems;
  logic pp_wb_last;

  assign irq = status.irq;
  assign read_start = load_a_start || load_b_start || load_bias_start;
  assign read_addr = load_a_start ? a_addr : (load_b_start ? b_addr : bias_addr);
  assign read_bytes = load_a_start ? a_bytes : (load_b_start ? b_bytes : bias_bytes);
  assign read_spad_offset = load_a_start ? a_spad_offset : (load_b_start ? b_spad_offset : bias_spad_offset);
  assign dma_spad_req = writer_spad_req ? 1'b0 : ctrl_spad_req;
  assign dma_spad_we = dma_spad_req && ctrl_spad_we;
  assign dma_spad_addr = ctrl_spad_addr;
  assign dma_spad_wdata = ctrl_spad_wdata;
  assign dma_spad_wstrb = ctrl_spad_wstrb;
  assign ctrl_spad_rdata = dma_spad_rdata;
  assign writer_spad_rdata = dma_spad_rdata;
  assign ctrl_spad_ready = dma_spad_ready && !writer_spad_req;
  assign writer_spad_ready = dma_spad_ready && writer_spad_req;
  assign row_base = {26'd0, tile_m} << 2;
  assign k_base = {26'd0, tile_k} << 2;
  assign k_remaining = cfg.k_size - k_base;
  assign col_base = {26'd0, tile_n} << 2;
  assign tile_rows = (cfg.m_size - row_base > 32'd4) ? 32'd4 : (cfg.m_size - row_base);
  assign tile_cols = (cfg.n_size - col_base > 32'd4) ? 32'd4 : (cfg.n_size - col_base);
  assign c_write_bytes = tile_rows * tile_cols * 32'd4;
  assign c_store_row_bytes = tile_cols << 2;
  assign compute_k_limit = (k_remaining > 32'd4) ? 4'd4 : k_remaining[3:0];
  assign compute_valid = compute_active_q && (compute_count_q < compute_k_limit);
  assign compute_done = compute_active_q && (compute_count_q == compute_k_limit);
  assign overflow = array_overflow || post_process_overflow;
  assign elem_b = elem_bytes(cfg.precision);
  assign a_start_byte = ((row_base * cfg.k_size) + k_base) * elem_b;
  assign b_start_byte = ((k_base * cfg.n_size) + col_base) * elem_b;
  assign a_row_bytes = {28'd0, compute_k_limit} * elem_b;
  assign b_row_bytes = tile_cols * elem_b;
  assign a_spad_stride = (a_row_bytes + 32'd14) & 32'hffff_fff8;
  assign b_spad_stride = (b_row_bytes + 32'd14) & 32'hffff_fff8;
  assign read_row_mode = load_a_start || load_b_start;
  assign read_row_count = load_a_start ? tile_rows[2:0] :
                          (load_b_start ? compute_k_limit[2:0] : 3'd1);
  assign read_row_bytes = load_a_start ? a_row_bytes :
                          (load_b_start ? b_row_bytes : read_bytes);
  assign read_ext_row_stride = load_a_start ? (cfg.k_size * elem_b) :
                               (load_b_start ? (cfg.n_size * elem_b) : 32'd0);
  assign read_spad_row_stride = load_a_start ? a_spad_stride :
                                (load_b_start ? b_spad_stride : 32'd0);
  assign store_row_offset = {30'd0, store_row_q} * cfg.n_size * 32'd4;
  assign writer_start = (store_start && !store_active_q) ||
                        (store_active_q && !write_busy && !writer_done);
  assign write_done = store_active_q && writer_done &&
                      ({29'd0, store_row_q} == (tile_rows - 1'b1));

  axi_lite_slave u_axi_lite_slave (
    .clk(clk),
    .rst_n(rst_n),
    .s_axil_awaddr(s_axil_awaddr),
    .s_axil_awvalid(s_axil_awvalid),
    .s_axil_awready(s_axil_awready),
    .s_axil_wdata(s_axil_wdata),
    .s_axil_wstrb(s_axil_wstrb),
    .s_axil_wvalid(s_axil_wvalid),
    .s_axil_wready(s_axil_wready),
    .s_axil_bresp(s_axil_bresp),
    .s_axil_bvalid(s_axil_bvalid),
    .s_axil_bready(s_axil_bready),
    .s_axil_araddr(s_axil_araddr),
    .s_axil_arvalid(s_axil_arvalid),
    .s_axil_arready(s_axil_arready),
    .s_axil_rdata(s_axil_rdata),
    .s_axil_rresp(s_axil_rresp),
    .s_axil_rvalid(s_axil_rvalid),
    .s_axil_rready(s_axil_rready),
    .reg_wr_en_o(reg_wr_en),
    .reg_wr_addr_o(reg_wr_addr),
    .reg_wr_data_o(reg_wr_data),
    .reg_wr_strb_o(reg_wr_strb),
    .reg_rd_en_o(reg_rd_en),
    .reg_rd_addr_o(reg_rd_addr),
    .reg_rd_data_i(reg_rd_data)
  );

  reg_file u_reg_file (
    .clk(clk),
    .rst_n(rst_n),
    .wr_en_i(reg_wr_en),
    .wr_addr_i(reg_wr_addr),
    .wr_data_i(reg_wr_data),
    .wr_strb_i(reg_wr_strb),
    .rd_en_i(reg_rd_en),
    .rd_addr_i(reg_rd_addr),
    .rd_data_o(reg_rd_data),
    .status_i(status),
    .error_code_i(error_code),
    .ovf_count_i(ovf_count),
    .cfg_o(cfg),
    .start_pulse_o(start_pulse),
    .soft_reset_pulse_o(soft_reset_pulse),
    .irq_en_o(irq_en),
    .clear_done_pulse_o(clear_done_pulse),
    .clear_error_pulse_o(clear_error_pulse),
    .clear_irq_pulse_o(clear_irq_pulse)
  );

  region_checker u_region_checker (
    .cfg_i(cfg),
    .valid_o(cfg_valid),
    .error_code_o(cfg_error)
  );

  command_fsm u_command_fsm (
    .clk(clk),
    .rst_n(rst_n),
    .start_i(start_pulse),
    .soft_reset_i(soft_reset_pulse),
    .clear_done_i(clear_done_pulse),
    .clear_error_i(clear_error_pulse),
    .clear_irq_i(clear_irq_pulse),
    .irq_en_i(irq_en),
    .cfg_i(cfg),
    .cfg_valid_i(cfg_valid),
    .cfg_error_i(cfg_error),
    .read_dma_done_i(read_done),
    .read_dma_error_i(read_error),
    .write_dma_done_i(write_done),
    .write_dma_error_i(write_error),
    .read_cross_4kb_i(read_cross_4kb),
    .write_cross_4kb_i(write_cross_4kb),
    .compute_done_i(compute_done),
    .post_process_done_i(post_process_done),
    .overflow_i(overflow),
    .last_tile_i(last_tile),
    .last_k_tile_i(last_k_tile),
    .sched_init_o(sched_init),
    .sched_advance_k_o(sched_advance_k),
    .sched_advance_o(sched_advance),
    .load_a_start_o(load_a_start),
    .load_b_start_o(load_b_start),
    .load_bias_start_o(load_bias_start),
    .compute_start_o(compute_start),
    .post_process_start_o(post_process_start),
    .store_start_o(store_start),
    .status_o(status),
    .error_code_o(error_code),
    .ovf_count_o(ovf_count)
  );

  tile_scheduler u_tile_scheduler (
    .clk(clk),
    .rst_n(rst_n),
    .init_i(sched_init),
    .advance_k_i(sched_advance_k),
    .advance_i(sched_advance),
    .cfg_i(cfg),
    .tile_m_o(tile_m),
    .tile_n_o(tile_n),
    .tile_k_o(tile_k),
    .last_tile_o(last_tile),
    .first_k_tile_o(first_k_tile),
    .last_k_tile_o(last_k_tile),
    .row_valid_o(row_valid),
    .col_valid_o(col_valid),
    .c_spad_offset_o(c_spad_offset),
    .c_ext_offset_o(c_ext_offset)
  );

  load_scheduler u_load_scheduler (
    .cfg_i(cfg),
    .tile_m_i(tile_m),
    .tile_n_i(tile_n),
    .tile_k_i(tile_k),
    .a_addr_o(a_addr),
    .b_addr_o(b_addr),
    .bias_addr_o(bias_addr),
    .a_bytes_o(a_bytes),
    .b_bytes_o(b_bytes),
    .bias_bytes_o(bias_bytes),
    .a_spad_offset_o(a_spad_offset),
    .b_spad_offset_o(b_spad_offset),
    .bias_spad_offset_o(bias_spad_offset)
  );

  tensor_loader u_tensor_loader (
    .clk(clk),
    .rst_n(rst_n),
    .start_i(read_start),
    .ext_addr_i(read_addr),
    .byte_len_i(read_bytes),
    .spad_offset_i(read_spad_offset),
    .row_mode_i(read_row_mode),
    .row_count_i(read_row_count),
    .row_bytes_i(read_row_bytes),
    .ext_row_stride_i(read_ext_row_stride),
    .spad_row_stride_i(read_spad_row_stride[15:0]),
    .busy_o(read_busy),
    .done_o(read_done),
    .error_o(read_error),
    .cross_4kb_o(read_cross_4kb),
    .m_axi_araddr(m_axi_araddr),
    .m_axi_arid(m_axi_arid),
    .m_axi_arlen(m_axi_arlen),
    .m_axi_arsize(m_axi_arsize),
    .m_axi_arburst(m_axi_arburst),
    .m_axi_arvalid(m_axi_arvalid),
    .m_axi_arready(m_axi_arready),
    .m_axi_rdata(m_axi_rdata),
    .m_axi_rid(m_axi_rid),
    .m_axi_rresp(m_axi_rresp),
    .m_axi_rlast(m_axi_rlast),
    .m_axi_rvalid(m_axi_rvalid),
    .m_axi_rready(m_axi_rready),
    .spad_req_o(ctrl_spad_req),
    .spad_we_o(ctrl_spad_we),
    .spad_addr_o(ctrl_spad_addr),
    .spad_wdata_o(ctrl_spad_wdata),
    .spad_wstrb_o(ctrl_spad_wstrb),
    .spad_ready_i(ctrl_spad_ready)
  );

  tensor_writer u_tensor_writer (
    .clk(clk),
    .rst_n(rst_n),
    .start_i(writer_start),
    .ext_addr_i(cfg.c_base + c_ext_offset + store_row_offset),
    .byte_len_i(c_store_row_bytes),
    .spad_offset_i(c_spad_offset[15:0] + store_row_offset[15:0]),
    .busy_o(write_busy),
    .done_o(writer_done),
    .error_o(write_error),
    .cross_4kb_o(write_cross_4kb),
    .m_axi_awaddr(m_axi_awaddr),
    .m_axi_awid(m_axi_awid),
    .m_axi_awlen(m_axi_awlen),
    .m_axi_awsize(m_axi_awsize),
    .m_axi_awburst(m_axi_awburst),
    .m_axi_awvalid(m_axi_awvalid),
    .m_axi_awready(m_axi_awready),
    .m_axi_wdata(m_axi_wdata),
    .m_axi_wstrb(m_axi_wstrb),
    .m_axi_wlast(m_axi_wlast),
    .m_axi_wvalid(m_axi_wvalid),
    .m_axi_wready(m_axi_wready),
    .m_axi_bresp(m_axi_bresp),
    .m_axi_bid(m_axi_bid),
    .m_axi_bvalid(m_axi_bvalid),
    .m_axi_bready(m_axi_bready),
    .spad_req_o(writer_spad_req),
    .spad_we_o(writer_spad_we),
    .spad_addr_o(writer_spad_addr),
    .spad_rdata_i(writer_spad_rdata),
    .spad_ready_i(writer_spad_ready)
  );

  scratchpad_ctrl u_scratchpad_ctrl (
    .dma_req_i(writer_spad_req ? writer_spad_req : dma_spad_req),
    .dma_we_i(writer_spad_req ? writer_spad_we : dma_spad_we),
    .dma_addr_i(writer_spad_req ? writer_spad_addr : dma_spad_addr),
    .dma_wdata_i(dma_spad_wdata),
    .dma_wstrb_i(dma_spad_wstrb),
    .dma_rdata_o(dma_spad_rdata),
    .dma_ready_o(dma_spad_ready),
    .compute_req_i(pp_spad_req),
    .compute_we_i(pp_spad_we),
    .compute_addr_i(pp_spad_addr),
    .compute_wdata_i(pp_spad_wdata),
    .compute_wstrb_i(pp_spad_wstrb),
    .compute_rdata_o(pp_spad_rdata),
    .compute_ready_o(pp_spad_ready),
    .spad_req_o(spad_req),
    .spad_we_o(spad_we),
    .spad_addr_o(spad_addr),
    .spad_wdata_o(spad_wdata),
    .spad_wstrb_o(spad_wstrb),
    .spad_rdata_i(spad_rdata),
    .spad_ready_i(spad_ready)
  );

  scratchpad u_scratchpad (
    .clk(clk),
    .req_i(spad_req),
    .we_i(spad_we),
    .addr_i(spad_addr),
    .wdata_i(spad_wdata),
    .wstrb_i(spad_wstrb),
    .rdata_o(spad_rdata),
    .ready_o(spad_ready)
  );

  always_comb begin
    for (int i = 0; i < 4; i++) begin
      a_vec[i] = compute_valid ? a_tile_q[i][compute_count_q[1:0]] : 16'd0;
      b_vec[i] = compute_valid ? b_tile_q[compute_count_q[1:0]][i] : 16'd0;
      bias_vec[i] = bias_vec_q[i];
    end
  end

  systolic_array u_systolic_array (
    .clk(clk),
    .rst_n(rst_n),
    .clear_i(compute_start && !compute_active_q && first_k_tile),
    .valid_i(compute_valid),
    .precision_i(cfg.precision == PREC_INT16),
    .row_valid_i(row_valid),
    .col_valid_i(col_valid),
    .a_vec_i(a_vec),
    .b_vec_i(b_vec),
    .acc_o(array_acc),
    .overflow_o(array_overflow)
  );

  accumulator u_accumulator (
    .clk(clk),
    .rst_n(rst_n),
    .clear_i(compute_start && !compute_active_q && first_k_tile),
    .load_i(compute_done),
    .data_i(array_acc),
    .data_o(acc_tile)
  );

  post_process u_post_process (
    .post_op_i(cfg.post_op),
    .sat_mode_i(cfg.sat_mode),
    .acc_i(acc_tile),
    .bias_i(bias_vec),
    .result_o(pp_result),
    .overflow_o(post_process_overflow)
  );

  assign pp_wb_elems = c_write_bytes[6:2];
  assign pp_wb_row = (tile_cols == 32'd0) ? 2'd0 : 2'({28'd0, pp_wb_count_q} / tile_cols);
  assign pp_wb_col = (tile_cols == 32'd0) ? 2'd0 : 2'({28'd0, pp_wb_count_q} % tile_cols);
  assign pp_wb_last = (pp_wb_elems == 5'd0) || ({1'b0, pp_wb_count_q} == (pp_wb_elems - 1'b1));
  assign pp_spad_req = pp_wb_active_q;
  assign pp_spad_we = pp_wb_active_q;
  assign pp_spad_addr = c_spad_offset[15:0] +
                        (({14'd0, pp_wb_row} * cfg.n_size + {30'd0, pp_wb_col}) << 2);
  assign pp_spad_wdata = pp_result[pp_wb_row][pp_wb_col];
  assign pp_spad_wstrb = 4'hf;
  assign post_process_done = pp_wb_active_q && pp_wb_last && pp_spad_ready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int r = 0; r < 4; r++) begin
        for (int c = 0; c < 4; c++) begin
          a_tile_q[r][c] <= 16'd0;
          b_tile_q[r][c] <= 16'd0;
        end
        bias_vec_q[r] <= 32'd0;
      end
    end else if (soft_reset_pulse || sched_init) begin
      for (int r = 0; r < 4; r++) begin
        for (int c = 0; c < 4; c++) begin
          a_tile_q[r][c] <= 16'd0;
          b_tile_q[r][c] <= 16'd0;
        end
        bias_vec_q[r] <= 32'd0;
      end
    end else if (ctrl_spad_req && ctrl_spad_we && ctrl_spad_ready) begin
      if ((ctrl_spad_addr >= a_spad_offset) &&
          (ctrl_spad_addr < (a_spad_offset + a_bytes[15:0]))) begin
        int unsigned byte_off;
        int unsigned row_slot;
        int unsigned byte_in_row;
        int unsigned row_start_byte;
        int unsigned row_align_bytes;
        int unsigned byte_pos;
        int unsigned elem_k;
        int unsigned rel_row;
        int unsigned rel_k;

        byte_off = ctrl_spad_addr - a_spad_offset;
        row_slot = byte_off / a_spad_stride;
        byte_in_row = byte_off % a_spad_stride;
        row_start_byte = (((row_base + row_slot) * cfg.k_size) + k_base) * elem_b;
        row_align_bytes = row_start_byte % 32'd8;
        if (cfg.precision == PREC_INT16) begin
          for (int lane = 0; lane < 2; lane++) begin
            byte_pos = byte_in_row + (2 * lane);
            elem_k = (byte_pos - row_align_bytes) >> 1;
            if ((ctrl_spad_wstrb[(2*lane) +: 2] == 2'b11) &&
                (row_slot < tile_rows) && (byte_pos >= row_align_bytes) &&
                (elem_k < compute_k_limit)) begin
              rel_row = row_slot;
              rel_k = elem_k;
              a_tile_q[rel_row[1:0]][rel_k[1:0]] <= ctrl_spad_wdata[16*lane +: 16];
            end
          end
        end else begin
          for (int lane = 0; lane < 4; lane++) begin
            byte_pos = byte_in_row + lane;
            elem_k = byte_pos - row_align_bytes;
            if (ctrl_spad_wstrb[lane] &&
                (row_slot < tile_rows) && (byte_pos >= row_align_bytes) &&
                (elem_k < compute_k_limit)) begin
              rel_row = row_slot;
              rel_k = elem_k;
              a_tile_q[rel_row[1:0]][rel_k[1:0]] <= {{8{ctrl_spad_wdata[(8*lane)+7]}},
                                                     ctrl_spad_wdata[8*lane +: 8]};
            end
          end
        end
      end
      if ((ctrl_spad_addr >= b_spad_offset) &&
          (ctrl_spad_addr < (b_spad_offset + b_bytes[15:0]))) begin
        int unsigned byte_off;
        int unsigned row_slot;
        int unsigned byte_in_row;
        int unsigned row_start_byte;
        int unsigned row_align_bytes;
        int unsigned byte_pos;
        int unsigned elem_col;
        int unsigned rel_k;
        int unsigned rel_col;

        byte_off = ctrl_spad_addr - b_spad_offset;
        row_slot = byte_off / b_spad_stride;
        byte_in_row = byte_off % b_spad_stride;
        row_start_byte = (((k_base + row_slot) * cfg.n_size) + col_base) * elem_b;
        row_align_bytes = row_start_byte % 32'd8;
        if (cfg.precision == PREC_INT16) begin
          for (int lane = 0; lane < 2; lane++) begin
            byte_pos = byte_in_row + (2 * lane);
            elem_col = (byte_pos - row_align_bytes) >> 1;
            if ((ctrl_spad_wstrb[(2*lane) +: 2] == 2'b11) &&
                (row_slot < compute_k_limit) && (byte_pos >= row_align_bytes) &&
                (elem_col < tile_cols)) begin
              rel_k = row_slot;
              rel_col = elem_col;
              b_tile_q[rel_k[1:0]][rel_col[1:0]] <= ctrl_spad_wdata[16*lane +: 16];
            end
          end
        end else begin
          for (int lane = 0; lane < 4; lane++) begin
            byte_pos = byte_in_row + lane;
            elem_col = byte_pos - row_align_bytes;
            if (ctrl_spad_wstrb[lane] &&
                (row_slot < compute_k_limit) && (byte_pos >= row_align_bytes) &&
                (elem_col < tile_cols)) begin
              rel_k = row_slot;
              rel_col = elem_col;
              b_tile_q[rel_k[1:0]][rel_col[1:0]] <= {{8{ctrl_spad_wdata[(8*lane)+7]}},
                                                     ctrl_spad_wdata[8*lane +: 8]};
            end
          end
        end
      end
      if ((ctrl_spad_addr >= bias_spad_offset) &&
          (ctrl_spad_addr < (bias_spad_offset + 16'd16))) begin
        int unsigned word_idx;

        word_idx = (ctrl_spad_addr - bias_spad_offset) >> 2;
        bias_vec_q[word_idx] <= ctrl_spad_wdata;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      compute_active_q <= 1'b0;
      compute_count_q <= 4'd0;
    end else if (soft_reset_pulse) begin
      compute_active_q <= 1'b0;
      compute_count_q <= 4'd0;
    end else if (compute_start && !compute_active_q) begin
      compute_active_q <= 1'b1;
      compute_count_q <= 4'd0;
    end else if (compute_active_q) begin
      compute_count_q <= compute_count_q + 1'b1;
      if (compute_done) begin
        compute_active_q <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pp_wb_active_q <= 1'b0;
      pp_wb_count_q <= 4'd0;
    end else if (soft_reset_pulse) begin
      pp_wb_active_q <= 1'b0;
      pp_wb_count_q <= 4'd0;
    end else begin
      if (post_process_start && !pp_wb_active_q) begin
        pp_wb_active_q <= 1'b1;
        pp_wb_count_q <= 4'd0;
      end else if (pp_wb_active_q && pp_spad_ready) begin
        if (pp_wb_last) begin
          pp_wb_active_q <= 1'b0;
          pp_wb_count_q <= 4'd0;
        end else begin
          pp_wb_count_q <= pp_wb_count_q + 1'b1;
        end
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      store_active_q <= 1'b0;
      store_row_q <= 3'd0;
    end else if (soft_reset_pulse) begin
      store_active_q <= 1'b0;
      store_row_q <= 3'd0;
    end else begin
      if (store_start && !store_active_q) begin
        store_active_q <= 1'b1;
        store_row_q <= 3'd0;
      end else if (store_active_q && writer_done) begin
        if ({29'd0, store_row_q} == (tile_rows - 1'b1)) begin
          store_active_q <= 1'b0;
          store_row_q <= 3'd0;
        end else begin
          store_row_q <= store_row_q + 1'b1;
        end
      end
    end
  end
endmodule
