module tensor_accel_top
  import tensor_pkg::*;
#(
  parameter int TILE_M = ARRAY_M,
  parameter int TILE_N = ARRAY_N,
  parameter int OUT_BYTES = 4,
  parameter int BIAS_BYTES = 4,
  parameter int COMPUTE_PIPE_LATENCY = 3,
  parameter int MAX_BURST_BEATS = 16,
  parameter int READ_DESC_FIFO_DEPTH = 4,
  parameter int WRITE_DESC_FIFO_DEPTH = 2,
  parameter int C_STORE_NBLOCK = 2,
  parameter int SPAD_BUFFER_BYTES = 1024,
  parameter bit READ_AUTO_SPLIT_4KB = 1'b0
) 
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

`ifndef SYNTHESIS
  input  logic        tb_cmd_force_start_i,
  input  logic        tb_cmd_force_read_error_i,
  input  logic        tb_cmd_force_write_error_i,
  input  logic        tb_cmd_force_load_done_i,
`endif
  output logic irq
);
  localparam int TILE_M_INDEX_WIDTH = (TILE_M <= 2) ? 1 : $clog2(TILE_M);
  localparam int TILE_N_INDEX_WIDTH = (TILE_N <= 2) ? 1 : $clog2(TILE_N);
  localparam int TILE_M_COUNT_WIDTH = $clog2(TILE_M + 1);
  localparam int TILE_ELEMS_WIDTH = $clog2((TILE_M * TILE_N) + 1);
  localparam int MTILE_SLOTS = (MAX_DIM + TILE_M - 1) / TILE_M;
  localparam int MTILE_INDEX_WIDTH = (MTILE_SLOTS <= 2) ? 1 : $clog2(MTILE_SLOTS);
  localparam int NBLOCK_SLOT_WIDTH = (C_STORE_NBLOCK <= 2) ? 1 : $clog2(C_STORE_NBLOCK);

  accel_cfg_t cfg;
  accel_cfg_t cfg_active;
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
  logic cmd_start;
  logic cmd_read_error;
  logic cmd_write_error;
  logic cmd_load_tile_done;
  logic irq_en;
  logic cfg_valid;
  localparam int SPAD_FIXED_BYTES = 4 * SPAD_BUFFER_BYTES;
  localparam logic [15:0] A_SPAD_BASE1 = 16'(SPAD_BUFFER_BYTES);

  logic sched_init;
  logic sched_advance;
  logic load_tile_start;
  logic load_tile_done;
  logic load_a_start;
  logic load_b_start;
  logic load_bias_start;
  logic compute_start;
  logic post_process_start;
  logic post_process_done;
  logic store_start;
  logic [5:0] tile_m;
  logic [5:0] tile_n;
  logic last_tile;
  logic [TILE_M-1:0] row_valid;
  logic [TILE_N-1:0] col_valid;
  logic [TILE_M-1:0] compute_row_valid_q;
  logic [TILE_N-1:0] compute_col_valid_q;
  logic [31:0] c_ext_offset;
  logic [5:0] compute_tile_m_q;
  logic [5:0] compute_tile_n_q;
  logic [31:0] compute_col_base_q;
  logic [31:0] compute_c_ext_offset_q;
  logic [31:0] compute_tile_rows_q;
  logic [31:0] compute_tile_cols_q;
  logic [31:0] compute_c_write_bytes_q;
  logic [31:0] compute_c_store_row_bytes_q;
  logic [NBLOCK_SLOT_WIDTH-1:0] compute_nblock_slot;
  logic compute_nblock_tail;
  logic compute_store_required;
  logic [31:0] compute_c_block_ext_offset;
  logic [31:0] compute_c_block_row_bytes;
  logic [15:0] c_store_spad_row_stride;
  logic [31:0] a_addr;
  logic [31:0] b_addr;
  logic [31:0] bias_addr;
  logic [31:0] a_bytes;
  logic [31:0] b_bytes;
  logic [31:0] bias_bytes;
  logic [15:0] a_spad_offset;
  logic [15:0] b_spad_offset;
  logic [15:0] bias_spad_offset;
  logic [15:0] a_spad_base;
  logic [15:0] b_spad_base;
  logic [15:0] bias_spad_base;
  logic tile_buffer_sel;
  logic b_load_needed;
  logic bias_load_needed;

  logic read_start;
  logic [31:0] read_addr;
  logic [15:0] read_bytes;
  logic [15:0] read_spad_offset;
  dma_desc_t read_desc_push;
  dma_desc_t read_desc_pop;
  logic read_desc_push_en;
  logic read_desc_pop_en;
  logic read_desc_full;
  logic read_desc_empty;
  logic read_desc_ready;
  dma_desc_t write_desc_push;
  dma_desc_t write_desc_pop;
  logic write_desc_push_en;
  logic write_desc_pop_en;
  logic write_desc_full;
  logic write_desc_empty;
  logic write_desc_ready;
  logic read_busy;
  logic read_done;
  logic read_error;
  logic read_cross_4kb;
  logic write_busy;
  logic writer_done;
  logic write_done;
  logic write_error;
  logic write_cross_4kb;
  logic store_desc_push;
  logic store_active;
  logic store_busy;
  logic next_buffer_free;
  logic next_load_prefetch_safe;
  logic [31:0] tile_m_count;
  logic [31:0] active_store_c_ext_offset;
  logic [31:0] active_store_c_row_bytes;
  logic [TILE_M_COUNT_WIDTH-1:0] active_store_row_count;
  logic [TILE_M-1:0] active_store_row_ready;
  logic active_store_buffer;
  logic [MTILE_INDEX_WIDTH-1:0] active_store_tile_m;

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
  logic spad_req;
  logic spad_we;
  logic [15:0] spad_addr;
  logic [31:0] spad_wdata;
  logic [3:0] spad_wstrb;
  logic [31:0] spad_rdata;
  logic spad_ready;

  logic [7:0] compute_count;
  logic compute_active;
  logic compute_done;
  logic compute_launch;
  logic compute_valid;
  logic [7:0] compute_k_limit;
  logic [TILE_M-1:0] systolic_row_valid;
  logic [TILE_N-1:0] systolic_col_valid;
  logic [31:0] row_base;
  logic [31:0] col_base;
  logic [31:0] tile_rows;
  logic [31:0] tile_cols;
  logic [31:0] c_write_bytes;
  logic [31:0] c_store_row_bytes;
  logic [31:0] elem_b;
  logic [31:0] a_row_bytes;
  logic [31:0] b_row_bytes;
  logic [31:0] a_spad_stride;
  logic [31:0] b_spad_stride;
  logic [15:0] read_row_bytes;
  logic [15:0] read_ext_row_stride;
  logic [15:0] read_spad_row_stride;
  logic [3:0] read_row_count;
  logic read_row_mode;
  logic [TILE_M-1:0][15:0] a_vec;
  logic [TILE_N-1:0][15:0] b_vec;
  logic [1:0][TILE_M-1:0][MAX_DIM-1:0][15:0] a_panel_q;
  logic [TILE_M-1:0][MAX_DIM-1:0][15:0] a_panel_active;
  logic [MAX_DIM-1:0][TILE_N-1:0][15:0] b_panel_q;
  logic signed [39:0] array_acc [TILE_M-1:0][TILE_N-1:0];
  logic signed [39:0] acc_tile [TILE_M-1:0][TILE_N-1:0];
  logic [TILE_N-1:0][31:0] bias_vec;
  logic [TILE_N-1:0][31:0] bias_vec_q;
  logic [TILE_M-1:0][TILE_N-1:0][31:0] pp_result;
  logic overflow;
  logic array_overflow;
  logic post_process_overflow;
  logic [TILE_M_INDEX_WIDTH-1:0] pp_wb_row;
  logic [TILE_N_INDEX_WIDTH-1:0] pp_wb_col;
  logic pp_row_done_valid;
  logic [TILE_M_INDEX_WIDTH-1:0] pp_row_done_index;
  logic post_process_active;
  logic compute_buffer_q;
  logic load_a_buffer_sel;
  logic cfg_latch_en;

  assign irq = status.irq;
  assign cfg_latch_en = start_pulse && !status.busy && !status.done && !status.error;
`ifndef SYNTHESIS
  assign cmd_start = start_pulse || tb_cmd_force_start_i;
  assign cmd_read_error = read_error || tb_cmd_force_read_error_i;
  assign cmd_write_error = write_error || tb_cmd_force_write_error_i;
  assign cmd_load_tile_done = load_tile_done || tb_cmd_force_load_done_i;
`else
  assign cmd_start = start_pulse;
  assign cmd_read_error = read_error;
  assign cmd_write_error = write_error;
  assign cmd_load_tile_done = load_tile_done;
`endif
  assign bias_load_needed = bias_enabled(cfg_active.post_op) && (tile_m == 6'd0);
  assign read_desc_ready = !read_desc_full;
  assign write_desc_ready = !write_desc_full;
  assign read_desc_push_en = load_a_start || load_b_start || load_bias_start;
  assign read_desc_pop_en = !read_desc_empty && !read_busy && !read_done;
  assign read_start = read_desc_pop_en;
  assign read_addr = read_desc_pop.addr;
  assign read_bytes = read_desc_pop.byte_len;
  assign read_spad_offset = read_desc_pop.spad_offset;
  assign read_desc_push.addr = load_a_start ? a_addr : (load_b_start ? b_addr : bias_addr);
  assign read_desc_push.byte_len = load_a_start ? a_bytes[15:0] :
                                   (load_b_start ? b_bytes[15:0] : bias_bytes[15:0]);
  assign read_desc_push.spad_offset = load_a_start ? a_spad_offset :
                                      (load_b_start ? b_spad_offset :
                                       bias_spad_offset);
  assign read_desc_push.row_mode = load_a_start || load_b_start;
  assign read_desc_push.row_count = load_a_start ? 4'(tile_rows) :
                                    (load_b_start ? 4'(tile_cols) : 4'd1);
  assign read_desc_push.row_bytes = load_a_start ? a_spad_stride[15:0] :
                                    (load_b_start ? b_spad_stride[15:0] : bias_bytes[15:0]);
  assign read_desc_push.ext_row_stride = load_a_start ? a_spad_stride[15:0] :
                                         (load_b_start ? b_spad_stride[15:0] : 16'd0);
  assign read_desc_push.spad_row_stride = load_a_start ? a_spad_stride[15:0] :
                                          (load_b_start ? b_spad_stride[15:0] : 16'd0);
  assign dma_spad_req = ctrl_spad_req;
  assign dma_spad_we = dma_spad_req && ctrl_spad_we;
  assign dma_spad_addr = ctrl_spad_addr;
  assign dma_spad_wdata = ctrl_spad_wdata;
  assign dma_spad_wstrb = ctrl_spad_wstrb;
  assign ctrl_spad_rdata = dma_spad_rdata;
  assign ctrl_spad_ready = dma_spad_ready;
  assign tile_rows = (cfg_active.m_size - row_base > 32'(TILE_M)) ?
                     32'(TILE_M) : (cfg_active.m_size - row_base);
  assign tile_cols = (cfg_active.n_size - col_base > 32'(TILE_N)) ?
                     32'(TILE_N) : (cfg_active.n_size - col_base);
  assign c_write_bytes = tile_rows * tile_cols * 32'(OUT_BYTES);
  assign c_store_row_bytes = tile_cols * 32'(OUT_BYTES);
  assign compute_nblock_slot = NBLOCK_SLOT_WIDTH'(int'(compute_tile_n_q) % C_STORE_NBLOCK);
  assign compute_nblock_tail = (compute_col_base_q + compute_tile_cols_q) >= cfg_active.n_size;
  assign compute_store_required = (compute_nblock_slot == NBLOCK_SLOT_WIDTH'(C_STORE_NBLOCK - 1)) ||
                                  compute_nblock_tail;
  assign compute_c_block_ext_offset = compute_c_ext_offset_q -
                                      (32'(compute_nblock_slot) * 32'(TILE_N) * 32'(OUT_BYTES));
  assign compute_c_block_row_bytes = ((32'(compute_nblock_slot) * 32'(TILE_N)) +
                                     compute_tile_cols_q) * 32'(OUT_BYTES);
  assign c_store_spad_row_stride = 16'(C_STORE_NBLOCK * TILE_N * OUT_BYTES);
  assign compute_k_limit = cfg_active.k_size[7:0];
  assign overflow = array_overflow || post_process_overflow;
  assign elem_b = elem_bytes(cfg_active.precision);
  assign a_row_bytes = packed_row_bytes({24'd0, compute_k_limit}, cfg_active.precision);
  assign b_row_bytes = packed_row_bytes({24'd0, compute_k_limit}, cfg_active.precision);
  assign a_spad_stride = align8_bytes(a_row_bytes);
  assign b_spad_stride = align8_bytes(b_row_bytes);
  assign load_a_buffer_sel = (a_spad_offset == A_SPAD_BASE1);
  assign read_row_mode = read_desc_pop.row_mode;
  assign read_row_count = read_desc_pop.row_count;
  assign read_row_bytes = read_desc_pop.row_bytes;
  assign read_ext_row_stride = read_desc_pop.ext_row_stride;
  assign read_spad_row_stride = read_desc_pop.spad_row_stride;
  assign write_desc_push_en = store_desc_push;
  assign write_desc_pop_en = !write_desc_empty && !write_busy && !writer_done;
  assign write_desc_push.addr = cfg_active.c_base + active_store_c_ext_offset;
  assign write_desc_push.byte_len = active_store_c_row_bytes[15:0];
  assign write_desc_push.spad_offset = 16'd0;
  assign write_desc_push.row_mode = 1'b1;
  assign write_desc_push.row_count = 4'(active_store_row_count);
  assign write_desc_push.row_bytes = active_store_c_row_bytes[15:0];
  assign write_desc_push.ext_row_stride = 16'(cfg_active.n_size * 32'(OUT_BYTES));
  assign write_desc_push.spad_row_stride = c_store_spad_row_stride;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cfg_active <= '0;
    end else if (soft_reset_pulse) begin
      cfg_active <= '0;
    end else if (cfg_latch_en) begin
      cfg_active <= cfg;
    end
  end

`ifdef ASSERT_ON
  always_ff @(posedge clk) begin
    if (rst_n && !soft_reset_pulse) begin
      assert (!(write_desc_push_en && write_desc_full))
        else $fatal(1, "Write descriptor FIFO push while full");
      assert (!(write_desc_pop_en && write_desc_empty))
        else $fatal(1, "Write descriptor FIFO pop while empty");
      assert (!(read_desc_push_en && read_desc_full))
        else $fatal(1, "Read descriptor FIFO push while full");
      assert (!(read_desc_pop_en && read_desc_empty))
        else $fatal(1, "Read descriptor FIFO pop while empty");
      assert (!(store_desc_push && !store_active))
        else $fatal(1, "Store descriptor pushed without active store context");
      assert (!(store_desc_push && (active_store_row_count == '0)))
        else $fatal(1, "Store descriptor pushed with zero row count");
    end
  end
`endif

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

  region_checker #(
    .TILE_M(TILE_M),
    .TILE_N(TILE_N),
    .OUT_BYTES(OUT_BYTES),
    .BIAS_BYTES(BIAS_BYTES),
    .SPAD_BUFFER_BYTES(SPAD_BUFFER_BYTES),
    .SPAD_FIXED_BYTES(SPAD_FIXED_BYTES)
  ) u_region_checker (
    .clk(clk),
    .rst_n(rst_n),
    .cfg_i(cfg),
    .valid_o(cfg_valid),
    .error_code_o(cfg_error)
  );

  command_fsm u_command_fsm (
    .clk(clk),
    .rst_n(rst_n),
    .start_i(cmd_start),
    .soft_reset_i(soft_reset_pulse),
    .clear_done_i(clear_done_pulse),
    .clear_error_i(clear_error_pulse),
    .clear_irq_i(clear_irq_pulse),
    .irq_en_i(irq_en),
    .cfg_valid_i(cfg_valid),
    .cfg_error_i(cfg_error),
    .read_dma_error_i(cmd_read_error),
    .write_dma_done_i(write_done),
    .write_dma_error_i(cmd_write_error),
    .store_busy_i(store_busy),
    .store_required_i(compute_store_required),
    .read_cross_4kb_i(read_cross_4kb),
    .write_cross_4kb_i(write_cross_4kb),
    .compute_done_i(compute_done),
    .post_process_active_i(post_process_active),
    .post_process_done_i(post_process_done),
    .overflow_i(overflow),
    .last_tile_i(last_tile),
    .next_buffer_free_i(next_buffer_free),
    .next_load_prefetch_safe_i(next_load_prefetch_safe),
    .load_tile_done_i(cmd_load_tile_done),
    .sched_init_o(sched_init),
    .sched_advance_o(sched_advance),
    .load_tile_start_o(load_tile_start),
    .compute_start_o(compute_start),
    .post_process_start_o(post_process_start),
    .store_start_o(store_start),
    .status_o(status),
    .error_code_o(error_code),
    .ovf_count_o(ovf_count)
  );

  tile_count_fsm #(
    .TILE_M(TILE_M),
    .TILE_N(TILE_N),
    .OUT_BYTES(OUT_BYTES)
  ) u_tile_count_fsm (
    .clk(clk),
    .rst_n(rst_n),
    .init_i(sched_init),
    .advance_i(sched_advance),
    .cfg_i(cfg_active),
    .tile_m_o(tile_m),
    .tile_n_o(tile_n),
    .last_tile_o(last_tile),
    .row_valid_o(row_valid),
    .col_valid_o(col_valid),
    .tile_m_count_o(tile_m_count),
    .row_base_o(row_base),
    .col_base_o(col_base),
    .c_ext_offset_o(c_ext_offset)
  );

  buffer_manager_fsm #(
    .SPAD_BUFFER_BYTES(SPAD_BUFFER_BYTES),
    .SPAD_BYTES(SPAD_FIXED_BYTES)
  ) u_buffer_manager_fsm (
    .clk(clk),
    .rst_n(rst_n),
    .clear_i(soft_reset_pulse || sched_init),
    .tile_m_i(tile_m),
    .tile_n_i(tile_n),
    .tile_m_count_i(tile_m_count),
    .last_tile_i(last_tile),
    .store_buffer_i(compute_buffer_q),
    .store_start_i(store_start),
    .store_done_i(write_done),
    .current_buffer_o(tile_buffer_sel),
    .next_buffer_free_o(next_buffer_free),
    .next_load_prefetch_safe_o(next_load_prefetch_safe),
    .a_spad_base_o(a_spad_base),
    .b_spad_base_o(b_spad_base),
    .bias_spad_base_o(bias_spad_base),
    .b_load_needed_o(b_load_needed)
  );

  store_fsm #(
    .TILE_M(TILE_M),
    .ROW_INDEX_WIDTH(TILE_M_INDEX_WIDTH),
    .ROW_COUNT_WIDTH(TILE_M_COUNT_WIDTH),
    .MTILE_INDEX_WIDTH(MTILE_INDEX_WIDTH)
  ) u_store_fsm (
    .clk(clk),
    .rst_n(rst_n),
    .clear_i(soft_reset_pulse),
    .start_i(store_start),
    .row_ready_i(pp_row_done_valid),
    .row_ready_index_i(pp_row_done_index),
    .pp_tile_done_i(post_process_done),
    .desc_ready_i(write_desc_ready),
    .writer_done_i(writer_done),
    .store_buffer_i(compute_buffer_q),
    .tile_m_i(MTILE_INDEX_WIDTH'(compute_tile_m_q)),
    .c_ext_offset_i(compute_c_block_ext_offset),
    .tile_rows_i(compute_tile_rows_q),
    .c_row_bytes_i(compute_c_block_row_bytes),
    .desc_push_o(store_desc_push),
    .active_o(store_active),
    .busy_o(store_busy),
    .done_o(write_done),
    .active_c_ext_offset_o(active_store_c_ext_offset),
    .active_c_row_bytes_o(active_store_c_row_bytes),
    .active_row_count_o(active_store_row_count),
    .active_row_ready_o(active_store_row_ready),
    .active_buffer_o(active_store_buffer),
    .active_tile_m_o(active_store_tile_m)
  );

  load_scheduler #(
    .TILE_M(TILE_M),
    .TILE_N(TILE_N),
    .BIAS_BYTES(BIAS_BYTES)
  ) u_load_scheduler (
    .clk(clk),
    .rst_n(rst_n),
    .clear_i(soft_reset_pulse),
    .start_i(load_tile_start),
    .read_dma_done_i(read_done),
    .desc_ready_i(read_desc_ready),
    .cfg_i(cfg_active),
    .tile_m_i(tile_m),
    .tile_n_i(tile_n),
    .a_spad_base_i(a_spad_base),
    .b_spad_base_i(b_spad_base),
    .bias_spad_base_i(bias_spad_base),
    .done_o(load_tile_done),
    .load_a_start_o(load_a_start),
    .load_b_start_o(load_b_start),
    .load_bias_start_o(load_bias_start),
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

  dma_descriptor_fifo #(
    .DEPTH(READ_DESC_FIFO_DEPTH)
  ) u_read_descriptor_fifo (
    .clk(clk),
    .rst_n(rst_n),
    .clear_i(soft_reset_pulse),
    .push_i(read_desc_push_en),
    .push_desc_i(read_desc_push),
    .pop_i(read_desc_pop_en),
    .pop_desc_o(read_desc_pop),
    .full_o(read_desc_full),
    .empty_o(read_desc_empty)
  );

  dma_descriptor_fifo #(
    .DEPTH(WRITE_DESC_FIFO_DEPTH)
  ) u_write_descriptor_fifo (
    .clk(clk),
    .rst_n(rst_n),
    .clear_i(soft_reset_pulse),
    .push_i(write_desc_push_en),
    .push_desc_i(write_desc_push),
    .pop_i(write_desc_pop_en),
    .pop_desc_o(write_desc_pop),
    .full_o(write_desc_full),
    .empty_o(write_desc_empty)
  );

  tensor_loader #(
    .MAX_BURST_BEATS(MAX_BURST_BEATS),
    .READ_AUTO_SPLIT_4KB(READ_AUTO_SPLIT_4KB),
    .ROW_COUNT_WIDTH(4)
  ) u_tensor_loader (
    .clk(clk),
    .rst_n(rst_n),
    .start_i(read_start),
    .ext_addr_i(read_addr),
    .byte_len_i(read_bytes),
    .burst_len_i(cfg_active.burst_len),
    .spad_offset_i(read_spad_offset),
    .row_mode_i(read_row_mode),
    .row_count_i(read_row_count),
    .row_bytes_i(read_row_bytes),
    .ext_row_stride_i(read_ext_row_stride),
    .spad_row_stride_i(read_spad_row_stride),
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

  tensor_writer #(
    .MAX_BURST_BEATS(MAX_BURST_BEATS),
    .ROW_COUNT_WIDTH(4),
    .ROW_READY_WIDTH(TILE_M)
  ) u_tensor_writer (
    .clk(clk),
    .rst_n(rst_n),
    .start_i(write_desc_pop_en),
    .ext_addr_i(write_desc_pop.addr),
    .byte_len_i(write_desc_pop.byte_len),
    .burst_len_i(cfg_active.burst_len),
    .spad_offset_i(write_desc_pop.spad_offset),
    .row_mode_i(write_desc_pop.row_mode),
    .row_count_i(write_desc_pop.row_count),
    .row_ready_i(active_store_row_ready),
    .row_bytes_i(write_desc_pop.row_bytes),
    .ext_row_stride_i(write_desc_pop.ext_row_stride),
    .spad_row_stride_i(write_desc_pop.spad_row_stride),
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

  c_store_coalescer #(
    .TILE_M(TILE_M),
    .TILE_N(TILE_N),
    .C_STORE_NBLOCK(C_STORE_NBLOCK),
    .ROW_INDEX_WIDTH(TILE_M_INDEX_WIDTH),
    .MTILE_SLOTS(MTILE_SLOTS),
    .MTILE_INDEX_WIDTH(MTILE_INDEX_WIDTH),
    .NBLOCK_SLOT_WIDTH(NBLOCK_SLOT_WIDTH)
  ) u_c_store_coalescer (
    .clk(clk),
    .rst_n(rst_n),
    .clear_i(soft_reset_pulse || sched_init),
    .row_write_i(pp_row_done_valid),
    .tile_m_i(MTILE_INDEX_WIDTH'(compute_tile_m_q)),
    .nblock_slot_i(compute_nblock_slot),
    .row_write_index_i(pp_row_done_index),
    .tile_cols_i(compute_tile_cols_q),
    .tile_data_i(pp_result),
    .read_tile_m_i(active_store_tile_m),
    .read_req_i(writer_spad_req),
    .read_addr_i(writer_spad_addr),
    .read_data_o(writer_spad_rdata),
    .read_ready_o(writer_spad_ready)
  );

  scratchpad_ctrl u_scratchpad_ctrl (
    .dma_req_i(dma_spad_req),
    .dma_we_i(dma_spad_we),
    .dma_addr_i(dma_spad_addr),
    .dma_wdata_i(dma_spad_wdata),
    .dma_wstrb_i(dma_spad_wstrb),
    .dma_rdata_o(dma_spad_rdata),
    .dma_ready_o(dma_spad_ready),
    .compute_req_i(1'b0),
    .compute_we_i(1'b0),
    .compute_addr_i(16'd0),
    .compute_wdata_i(32'd0),
    .compute_wstrb_i(4'd0),
    .compute_rdata_o(),
    .compute_ready_o(),
    .spad_req_o(spad_req),
    .spad_we_o(spad_we),
    .spad_addr_o(spad_addr),
    .spad_wdata_o(spad_wdata),
    .spad_wstrb_o(spad_wstrb),
    .spad_rdata_i(spad_rdata),
    .spad_ready_i(spad_ready)
  );

  scratchpad #(
    .DEPTH_WORDS(SPAD_FIXED_BYTES / (SPAD_DATA_WIDTH / 8))
  ) u_scratchpad (
    .clk(clk),
    .req_i(spad_req),
    .we_i(spad_we),
    .addr_i(spad_addr),
    .wdata_i(spad_wdata),
    .wstrb_i(spad_wstrb),
    .rdata_o(spad_rdata),
    .ready_o(spad_ready)
  );

  compute_fsm #(
    .COMPUTE_PIPE_LATENCY(COMPUTE_PIPE_LATENCY),
    .ARRAY_M(TILE_M),
    .ARRAY_N(TILE_N)
  ) u_compute_fsm (
    .clk(clk),
    .rst_n(rst_n),
    .clear_i(soft_reset_pulse),
    .start_i(compute_start),
    .k_limit_i(compute_k_limit),
    .launch_o(compute_launch),
    .active_o(compute_active),
    .valid_o(compute_valid),
    .done_o(compute_done),
    .count_o(compute_count)
  );

  always_comb begin
    for (int r = 0; r < TILE_M; r++) begin
      for (int k = 0; k < MAX_DIM; k++) begin
        a_panel_active[r][k] = a_panel_q[compute_buffer_q][r][k];
      end
    end
    for (int c = 0; c < TILE_N; c++) begin
      bias_vec[c] = bias_vec_q[c];
    end
  end

  assign systolic_row_valid = compute_launch ? row_valid : compute_row_valid_q;
  assign systolic_col_valid = compute_launch ? col_valid : compute_col_valid_q;

  wavefront_feeder #(
    .ARRAY_M(TILE_M),
    .ARRAY_N(TILE_N),
    .MAX_K(MAX_DIM)
  ) u_wavefront_feeder (
    .valid_i(compute_valid),
    .count_i(compute_count),
    .k_limit_i(compute_k_limit),
    .row_valid_i(systolic_row_valid),
    .col_valid_i(systolic_col_valid),
    .a_panel_i(a_panel_active),
    .b_panel_i(b_panel_q),
    .left_a_o(a_vec),
    .top_b_o(b_vec)
  );

  systolic_array #(
    .ARRAY_M(TILE_M),
    .ARRAY_N(TILE_N)
  ) u_systolic_array (
    .clk(clk),
    .rst_n(rst_n),
    .clear_i(compute_launch),
    .valid_i(compute_valid),
    .precision_i(cfg_active.precision),
    .row_valid_i(systolic_row_valid),
    .col_valid_i(systolic_col_valid),
    .a_vec_i(a_vec),
    .b_vec_i(b_vec),
    .acc_o(array_acc),
    .overflow_o(array_overflow)
  );

  accumulator #(
    .ARRAY_M(TILE_M),
    .ARRAY_N(TILE_N)
  ) u_accumulator (
    .clk(clk),
    .rst_n(rst_n),
    .clear_i(compute_launch),
    .load_i(compute_done),
    .data_i(array_acc),
    .data_o(acc_tile)
  );

  post_process #(
    .ARRAY_M(TILE_M),
    .ARRAY_N(TILE_N)
  ) u_post_process (
    .clk(clk),
    .rst_n(rst_n),
    .post_op_i(cfg_active.post_op),
    .sat_mode_i(cfg_active.sat_mode),
    .acc_i(acc_tile),
    .bias_i(bias_vec),
    .result_o(pp_result),
    .overflow_o(post_process_overflow)
  );

  post_process_fsm #(
    .TILE_M(TILE_M),
    .TILE_N(TILE_N),
    .ROW_INDEX_WIDTH(TILE_M_INDEX_WIDTH),
    .COL_INDEX_WIDTH(TILE_N_INDEX_WIDTH),
    .TILE_ELEMS_WIDTH(TILE_ELEMS_WIDTH)
  ) u_post_process_fsm (
    .clk(clk),
    .rst_n(rst_n),
    .clear_i(soft_reset_pulse),
    .start_i(post_process_start),
    .c_write_bytes_i(compute_c_write_bytes_q),
    .tile_cols_i(compute_tile_cols_q),
    .spad_ready_i(1'b1),
    .wb_row_o(pp_wb_row),
    .wb_col_o(pp_wb_col),
    .row_done_valid_o(pp_row_done_valid),
    .row_done_index_o(pp_row_done_index),
    .active_o(post_process_active),
    .done_o(post_process_done)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      compute_buffer_q <= 1'b0;
      compute_row_valid_q <= '0;
      compute_col_valid_q <= '0;
      compute_tile_m_q <= 6'd0;
      compute_tile_n_q <= 6'd0;
      compute_col_base_q <= 32'd0;
      compute_c_ext_offset_q <= 32'd0;
      compute_tile_rows_q <= 32'd0;
      compute_tile_cols_q <= 32'd0;
      compute_c_write_bytes_q <= 32'd0;
      compute_c_store_row_bytes_q <= 32'd0;
    end else if (soft_reset_pulse || sched_init) begin
      compute_buffer_q <= 1'b0;
      compute_row_valid_q <= '0;
      compute_col_valid_q <= '0;
      compute_tile_m_q <= 6'd0;
      compute_tile_n_q <= 6'd0;
      compute_col_base_q <= 32'd0;
      compute_c_ext_offset_q <= 32'd0;
      compute_tile_rows_q <= 32'd0;
      compute_tile_cols_q <= 32'd0;
      compute_c_write_bytes_q <= 32'd0;
      compute_c_store_row_bytes_q <= 32'd0;
    end else if (compute_launch) begin
      compute_buffer_q <= tile_buffer_sel;
      compute_row_valid_q <= row_valid;
      compute_col_valid_q <= col_valid;
      compute_tile_m_q <= tile_m;
      compute_tile_n_q <= tile_n;
      compute_col_base_q <= col_base;
      compute_c_ext_offset_q <= c_ext_offset;
      compute_tile_rows_q <= tile_rows;
      compute_tile_cols_q <= tile_cols;
      compute_c_write_bytes_q <= c_write_bytes;
      compute_c_store_row_bytes_q <= c_store_row_bytes;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int b = 0; b < 2; b++) begin
        for (int r = 0; r < TILE_M; r++) begin
          for (int k = 0; k < MAX_DIM; k++) begin
            a_panel_q[b][r][k] <= 16'd0;
          end
        end
      end
      for (int k = 0; k < MAX_DIM; k++) begin
        for (int c = 0; c < TILE_N; c++) begin
          b_panel_q[k][c] <= 16'd0;
        end
      end
      for (int c = 0; c < TILE_N; c++) begin
        bias_vec_q[c] <= 32'd0;
      end
    end else if (soft_reset_pulse || sched_init) begin
      for (int b = 0; b < 2; b++) begin
        for (int r = 0; r < TILE_M; r++) begin
          for (int k = 0; k < MAX_DIM; k++) begin
            a_panel_q[b][r][k] <= 16'd0;
          end
        end
      end
      for (int k = 0; k < MAX_DIM; k++) begin
        for (int c = 0; c < TILE_N; c++) begin
          b_panel_q[k][c] <= 16'd0;
        end
      end
      for (int c = 0; c < TILE_N; c++) begin
        bias_vec_q[c] <= 32'd0;
      end
    end else if (ctrl_spad_req && ctrl_spad_we && ctrl_spad_ready) begin
      if ((ctrl_spad_addr >= a_spad_offset) &&
          (ctrl_spad_addr < (a_spad_offset + a_bytes[15:0]))) begin
        int unsigned byte_off;
        int unsigned row_slot;
        int unsigned byte_in_row;
        int unsigned byte_pos;
        int unsigned elem_k;
        int unsigned rel_row;
        int unsigned rel_k;

        byte_off = ctrl_spad_addr - a_spad_offset;
        row_slot = byte_off / a_spad_stride;
        byte_in_row = byte_off % a_spad_stride;
        if (cfg_active.precision == PREC_INT16) begin
          for (int lane = 0; lane < 2; lane++) begin
            byte_pos = byte_in_row + (2 * lane);
            elem_k = byte_pos >> 1;
            if ((ctrl_spad_wstrb[(2*lane) +: 2] == 2'b11) &&
                (row_slot < tile_rows) && (elem_k < compute_k_limit)) begin
              rel_row = row_slot;
              rel_k = elem_k;
              a_panel_q[load_a_buffer_sel][rel_row][rel_k[5:0]] <=
                ctrl_spad_wdata[16*lane +: 16];
            end
          end
        end else if (cfg_active.precision == PREC_INT4) begin
          for (int lane = 0; lane < 4; lane++) begin
            byte_pos = byte_in_row + lane;
            elem_k = byte_pos << 1;
            if (ctrl_spad_wstrb[lane] &&
                (row_slot < tile_rows) && (elem_k < compute_k_limit)) begin
              rel_row = row_slot;
              rel_k = elem_k;
              a_panel_q[load_a_buffer_sel][rel_row][rel_k[5:0]] <=
                {{12{ctrl_spad_wdata[(8*lane)+3]}}, ctrl_spad_wdata[(8*lane) +: 4]};
            end
            if (ctrl_spad_wstrb[lane] &&
                (row_slot < tile_rows) && ((elem_k + 1) < compute_k_limit)) begin
              rel_row = row_slot;
              rel_k = elem_k + 1;
              a_panel_q[load_a_buffer_sel][rel_row][rel_k[5:0]] <=
                {{12{ctrl_spad_wdata[(8*lane)+7]}}, ctrl_spad_wdata[(8*lane)+4 +: 4]};
            end
          end
        end else begin
          for (int lane = 0; lane < 4; lane++) begin
            byte_pos = byte_in_row + lane;
            elem_k = byte_pos;
            if (ctrl_spad_wstrb[lane] &&
                (row_slot < tile_rows) && (elem_k < compute_k_limit)) begin
              rel_row = row_slot;
              rel_k = elem_k;
              a_panel_q[load_a_buffer_sel][rel_row][rel_k[5:0]] <=
                {{8{ctrl_spad_wdata[(8*lane)+7]}}, ctrl_spad_wdata[8*lane +: 8]};
            end
          end
        end
      end
      if ((ctrl_spad_addr >= b_spad_offset) &&
          (ctrl_spad_addr < (b_spad_offset + b_bytes[15:0]))) begin
        int unsigned byte_off;
        int unsigned row_slot;
        int unsigned byte_in_row;
        int unsigned byte_pos;
        int unsigned elem_k;
        int unsigned rel_k;
        int unsigned rel_col;

        byte_off = ctrl_spad_addr - b_spad_offset;
        row_slot = byte_off / b_spad_stride;
        byte_in_row = byte_off % b_spad_stride;
        if (cfg_active.precision == PREC_INT16) begin
          for (int lane = 0; lane < 2; lane++) begin
            byte_pos = byte_in_row + (2 * lane);
            elem_k = byte_pos >> 1;
            if ((ctrl_spad_wstrb[(2*lane) +: 2] == 2'b11) &&
                (row_slot < tile_cols) && (elem_k < compute_k_limit)) begin
              rel_k = elem_k;
              rel_col = row_slot;
              b_panel_q[rel_k[5:0]][rel_col] <= ctrl_spad_wdata[16*lane +: 16];
            end
          end
        end else if (cfg_active.precision == PREC_INT4) begin
          for (int lane = 0; lane < 4; lane++) begin
            byte_pos = byte_in_row + lane;
            elem_k = byte_pos << 1;
            if (ctrl_spad_wstrb[lane] &&
                (row_slot < tile_cols) && (elem_k < compute_k_limit)) begin
              rel_k = elem_k;
              rel_col = row_slot;
              b_panel_q[rel_k[5:0]][rel_col] <=
                {{12{ctrl_spad_wdata[(8*lane)+3]}}, ctrl_spad_wdata[(8*lane) +: 4]};
            end
            if (ctrl_spad_wstrb[lane] &&
                (row_slot < tile_cols) && ((elem_k + 1) < compute_k_limit)) begin
              rel_k = elem_k + 1;
              rel_col = row_slot;
              b_panel_q[rel_k[5:0]][rel_col] <=
                {{12{ctrl_spad_wdata[(8*lane)+7]}}, ctrl_spad_wdata[(8*lane)+4 +: 4]};
            end
          end
        end else begin
          for (int lane = 0; lane < 4; lane++) begin
            byte_pos = byte_in_row + lane;
            elem_k = byte_pos;
            if (ctrl_spad_wstrb[lane] &&
                (row_slot < tile_cols) && (elem_k < compute_k_limit)) begin
              rel_k = elem_k;
              rel_col = row_slot;
              b_panel_q[rel_k[5:0]][rel_col] <= {{8{ctrl_spad_wdata[(8*lane)+7]}},
                                                 ctrl_spad_wdata[8*lane +: 8]};
            end
          end
        end
      end
      if ((ctrl_spad_addr >= bias_spad_offset) &&
          (ctrl_spad_addr < (bias_spad_offset + 16'(TILE_N * BIAS_BYTES)))) begin
        int unsigned word_idx;

        word_idx = (ctrl_spad_addr - bias_spad_offset) >> 2;
        bias_vec_q[word_idx] <= ctrl_spad_wdata;
      end
    end
  end

endmodule
