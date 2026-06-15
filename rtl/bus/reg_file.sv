module reg_file
  import tensor_pkg::*;
(
  input  logic clk,
  input  logic rst_n,
  input  logic wr_en_i,
  input  logic [15:0] wr_addr_i,
  input  logic [31:0] wr_data_i,
  input  logic [3:0] wr_strb_i,
  input  logic rd_en_i,
  input  logic [15:0] rd_addr_i,
  output logic [31:0] rd_data_o,

  input  accel_status_t status_i,
  input  error_code_e error_code_i,
  input  logic [31:0] ovf_count_i,
  input  perf_counter_t perf_i,
  output accel_cfg_t cfg_o,
  output logic start_pulse_o,
  output logic soft_reset_pulse_o,
  output logic irq_en_o,
  output logic clear_done_pulse_o,
  output logic clear_error_pulse_o,
  output logic clear_irq_pulse_o
);
  localparam logic [15:0] CTRL             = 16'h0000;
  localparam logic [15:0] STATUS           = 16'h0004;
  localparam logic [15:0] M_SIZE           = 16'h0008;
  localparam logic [15:0] N_SIZE           = 16'h000c;
  localparam logic [15:0] K_SIZE           = 16'h0010;
  localparam logic [15:0] PRECISION        = 16'h0014;
  localparam logic [15:0] POST_OP          = 16'h0018;
  localparam logic [15:0] SAT_MODE         = 16'h001c;
  localparam logic [15:0] A_BASE           = 16'h0020;
  localparam logic [15:0] B_BASE           = 16'h0024;
  localparam logic [15:0] C_BASE           = 16'h0028;
  localparam logic [15:0] BIAS_BASE        = 16'h002c;
  localparam logic [15:0] A_SPAD_OFFSET    = 16'h0030;
  localparam logic [15:0] A_SPAD_SIZE      = 16'h0034;
  localparam logic [15:0] B_SPAD_OFFSET    = 16'h0038;
  localparam logic [15:0] B_SPAD_SIZE      = 16'h003c;
  localparam logic [15:0] C_SPAD_OFFSET    = 16'h0040;
  localparam logic [15:0] C_SPAD_SIZE      = 16'h0044;
  localparam logic [15:0] BIAS_SPAD_OFFSET = 16'h0048;
  localparam logic [15:0] BIAS_SPAD_SIZE   = 16'h004c;
  localparam logic [15:0] DMA_CFG          = 16'h0050;
  localparam logic [15:0] IRQ_STATUS       = 16'h0054;
  localparam logic [15:0] OVF_COUNT        = 16'h0058;
  localparam logic [15:0] ERROR_CODE       = 16'h005c;
  localparam logic [15:0] PERF_TOTAL       = 16'h0060;
  localparam logic [15:0] PERF_LOAD        = 16'h0064;
  localparam logic [15:0] PERF_COMPUTE     = 16'h0068;
  localparam logic [15:0] PERF_POST        = 16'h006c;
  localparam logic [15:0] PERF_STORE       = 16'h0070;
  localparam logic [15:0] PERF_IDLE        = 16'h0074;
  localparam logic [15:0] PERF_RD_BYTES    = 16'h0078;
  localparam logic [15:0] PERF_WR_BYTES    = 16'h007c;
  localparam logic [15:0] PERF_TILE_COUNT  = 16'h0080;
  localparam logic [15:0] PERF_RD_BURSTS   = 16'h0084;
  localparam logic [15:0] PERF_WR_BURSTS   = 16'h0088;
  localparam logic [15:0] PERF_RD_STALL    = 16'h008c;
  localparam logic [15:0] PERF_WR_STALL    = 16'h0090;
  localparam logic [15:0] PERF_SPAD_STALL  = 16'h0094;

  accel_cfg_t cfg_q;
  logic wr_en_q;
  logic [15:0] wr_addr_q;
  logic [31:0] wr_data_q;
  logic [3:0] wr_strb_q;
  logic rd_en_q;
  logic [15:0] rd_addr_q;
  logic [31:0] rd_data_d;

  assign cfg_o = cfg_q;

  function automatic logic [31:0] apply_wstrb(
    input logic [31:0] old_data,
    input logic [31:0] new_data,
    input logic [3:0]  strb
  );
    logic [31:0] merged;
    begin
      merged = old_data;
      for (int byte_idx = 0; byte_idx < 4; byte_idx++) begin
        if (strb[byte_idx]) merged[8*byte_idx +: 8] = new_data[8*byte_idx +: 8];
      end
      return merged;
    end
  endfunction

  always_comb begin
    rd_data_d = 32'd0;
    if (rd_en_q) begin
      unique case (rd_addr_q)
        CTRL: rd_data_d = {29'd0, irq_en_o, 2'd0};
        STATUS: rd_data_d = {27'd0, status_i.overflow_seen, status_i.irq,
                             status_i.error, status_i.done, status_i.busy};
        M_SIZE: rd_data_d = cfg_q.m_size;
        N_SIZE: rd_data_d = cfg_q.n_size;
        K_SIZE: rd_data_d = cfg_q.k_size;
        PRECISION: rd_data_d = {30'd0, cfg_q.precision};
        POST_OP: rd_data_d = {30'd0, cfg_q.post_op};
        SAT_MODE: rd_data_d = {31'd0, cfg_q.sat_mode};
        A_BASE: rd_data_d = cfg_q.a_base;
        B_BASE: rd_data_d = cfg_q.b_base;
        C_BASE: rd_data_d = cfg_q.c_base;
        BIAS_BASE: rd_data_d = cfg_q.bias_base;
        A_SPAD_OFFSET: rd_data_d = cfg_q.a_spad_offset;
        A_SPAD_SIZE: rd_data_d = cfg_q.a_spad_size;
        B_SPAD_OFFSET: rd_data_d = cfg_q.b_spad_offset;
        B_SPAD_SIZE: rd_data_d = cfg_q.b_spad_size;
        C_SPAD_OFFSET: rd_data_d = cfg_q.c_spad_offset;
        C_SPAD_SIZE: rd_data_d = cfg_q.c_spad_size;
        BIAS_SPAD_OFFSET: rd_data_d = cfg_q.bias_spad_offset;
        BIAS_SPAD_SIZE: rd_data_d = cfg_q.bias_spad_size;
        DMA_CFG: rd_data_d = {24'd0, cfg_q.burst_len};
        IRQ_STATUS: rd_data_d = {31'd0, status_i.irq};
        OVF_COUNT: rd_data_d = ovf_count_i;
        ERROR_CODE: rd_data_d = {28'd0, error_code_i};
        PERF_TOTAL: rd_data_d = perf_i.total_cycles;
        PERF_LOAD: rd_data_d = perf_i.load_cycles;
        PERF_COMPUTE: rd_data_d = perf_i.compute_cycles;
        PERF_POST: rd_data_d = perf_i.post_process_cycles;
        PERF_STORE: rd_data_d = perf_i.store_cycles;
        PERF_IDLE: rd_data_d = perf_i.idle_or_wait_cycles;
        PERF_RD_BYTES: rd_data_d = perf_i.axi_read_bytes;
        PERF_WR_BYTES: rd_data_d = perf_i.axi_write_bytes;
        PERF_TILE_COUNT: rd_data_d = perf_i.tile_count;
        PERF_RD_BURSTS: rd_data_d = perf_i.read_burst_count;
        PERF_WR_BURSTS: rd_data_d = perf_i.write_burst_count;
        PERF_RD_STALL: rd_data_d = perf_i.stall_on_axi_read;
        PERF_WR_STALL: rd_data_d = perf_i.stall_on_axi_write;
        PERF_SPAD_STALL: rd_data_d = perf_i.stall_on_spad;
        default: rd_data_d = 32'd0;
      endcase
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cfg_q <= '0;
      cfg_q.burst_len <= 8'd16;
      irq_en_o <= 1'b0;
      start_pulse_o <= 1'b0;
      soft_reset_pulse_o <= 1'b0;
      clear_done_pulse_o <= 1'b0;
      clear_error_pulse_o <= 1'b0;
      clear_irq_pulse_o <= 1'b0;
      wr_en_q <= 1'b0;
      wr_addr_q <= '0;
      wr_data_q <= '0;
      wr_strb_q <= '0;
      rd_en_q <= 1'b0;
      rd_addr_q <= '0;
      rd_data_o <= '0;
    end else begin
      wr_en_q <= wr_en_i;
      wr_addr_q <= wr_addr_i;
      wr_data_q <= wr_data_i;
      wr_strb_q <= wr_strb_i;
      rd_en_q <= rd_en_i;
      rd_addr_q <= rd_addr_i;
      rd_data_o <= rd_data_d;
      start_pulse_o <= 1'b0;
      soft_reset_pulse_o <= 1'b0;
      clear_done_pulse_o <= 1'b0;
      clear_error_pulse_o <= 1'b0;
      clear_irq_pulse_o <= 1'b0;
      if (wr_en_q) begin
        unique case (wr_addr_q)
          CTRL: begin
            start_pulse_o <= wr_strb_q[0] && wr_data_q[0];
            soft_reset_pulse_o <= wr_strb_q[0] && wr_data_q[1];
            irq_en_o <= wr_strb_q[0] ? wr_data_q[2] : irq_en_o;
            clear_done_pulse_o <= wr_strb_q[0] && wr_data_q[3];
            clear_error_pulse_o <= wr_strb_q[0] && wr_data_q[4];
          end
          M_SIZE: cfg_q.m_size <= apply_wstrb(cfg_q.m_size, wr_data_q, wr_strb_q);
          N_SIZE: cfg_q.n_size <= apply_wstrb(cfg_q.n_size, wr_data_q, wr_strb_q);
          K_SIZE: cfg_q.k_size <= apply_wstrb(cfg_q.k_size, wr_data_q, wr_strb_q);
          PRECISION: if (wr_strb_q[0]) cfg_q.precision <= precision_e'(wr_data_q[1:0]);
          POST_OP: if (wr_strb_q[0]) cfg_q.post_op <= post_op_e'(wr_data_q[1:0]);
          SAT_MODE: if (wr_strb_q[0]) cfg_q.sat_mode <= sat_mode_e'(wr_data_q[0]);
          A_BASE: cfg_q.a_base <= apply_wstrb(cfg_q.a_base, wr_data_q, wr_strb_q);
          B_BASE: cfg_q.b_base <= apply_wstrb(cfg_q.b_base, wr_data_q, wr_strb_q);
          C_BASE: cfg_q.c_base <= apply_wstrb(cfg_q.c_base, wr_data_q, wr_strb_q);
          BIAS_BASE: cfg_q.bias_base <= apply_wstrb(cfg_q.bias_base, wr_data_q, wr_strb_q);
          A_SPAD_OFFSET: cfg_q.a_spad_offset <= apply_wstrb(cfg_q.a_spad_offset, wr_data_q, wr_strb_q);
          A_SPAD_SIZE: cfg_q.a_spad_size <= apply_wstrb(cfg_q.a_spad_size, wr_data_q, wr_strb_q);
          B_SPAD_OFFSET: cfg_q.b_spad_offset <= apply_wstrb(cfg_q.b_spad_offset, wr_data_q, wr_strb_q);
          B_SPAD_SIZE: cfg_q.b_spad_size <= apply_wstrb(cfg_q.b_spad_size, wr_data_q, wr_strb_q);
          C_SPAD_OFFSET: cfg_q.c_spad_offset <= apply_wstrb(cfg_q.c_spad_offset, wr_data_q, wr_strb_q);
          C_SPAD_SIZE: cfg_q.c_spad_size <= apply_wstrb(cfg_q.c_spad_size, wr_data_q, wr_strb_q);
          BIAS_SPAD_OFFSET: cfg_q.bias_spad_offset <= apply_wstrb(cfg_q.bias_spad_offset, wr_data_q, wr_strb_q);
          BIAS_SPAD_SIZE: cfg_q.bias_spad_size <= apply_wstrb(cfg_q.bias_spad_size, wr_data_q, wr_strb_q);
          DMA_CFG: if (wr_strb_q[0]) cfg_q.burst_len <= wr_data_q[7:0];
          IRQ_STATUS: clear_irq_pulse_o <= wr_strb_q[0] && wr_data_q[0];
          default: ;
        endcase
      end
    end
  end
endmodule
