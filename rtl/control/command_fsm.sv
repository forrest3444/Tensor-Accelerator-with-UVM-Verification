module command_fsm
  import tensor_pkg::*;
(
  input  logic clk,
  input  logic rst_n,
  input  logic start_i,
  input  logic soft_reset_i,
  input  logic clear_done_i,
  input  logic clear_error_i,
  input  logic clear_irq_i,
  input  logic irq_en_i,
  input  accel_cfg_t cfg_i,
  input  logic cfg_valid_i,
  input  error_code_e cfg_error_i,
  input  logic read_dma_done_i,
  input  logic read_dma_error_i,
  input  logic write_dma_done_i,
  input  logic write_dma_error_i,
  input  logic read_cross_4kb_i,
  input  logic write_cross_4kb_i,
  input  logic compute_done_i,
  input  logic post_process_done_i,
  input  logic overflow_i,
  input  logic last_tile_i,
  input  logic last_k_tile_i,
  input  logic load_desc_valid_i,
  output logic sched_init_o,
  output logic sched_advance_k_o,
  output logic sched_advance_o,
  output logic load_desc_req_o,
  output logic load_a_start_o,
  output logic load_b_start_o,
  output logic load_bias_start_o,
  output logic compute_start_o,
  output logic post_process_start_o,
  output logic store_start_o,
  output accel_status_t status_o,
  output error_code_e error_code_o,
  output logic [31:0] ovf_count_o
);
  typedef enum logic [4:0] {
    ST_IDLE,
    ST_CHECK_CONFIG,
    ST_PREPARE_TILE,
    ST_REQ_A_TILE,
    ST_WAIT_A_DESC,
    ST_LOAD_A_TILE,
    ST_REQ_B_TILE,
    ST_WAIT_B_DESC,
    ST_LOAD_B_TILE,
    ST_REQ_BIAS,
    ST_WAIT_BIAS_DESC,
    ST_LOAD_BIAS,
    ST_COMPUTE_TILE,
    ST_NEXT_K_TILE,
    ST_POST_PROCESS_TILE,
    ST_STORE_TILE,
    ST_NEXT_TILE,
    ST_DONE,
    ST_ERROR
  } state_e;

  state_e state_q, state_d;
  accel_status_t status_q;
  error_code_e error_q;
  logic overflow_seen_q;
  logic [31:0] watchdog_q;
  logic timeout_hit;

  assign status_o = status_q;
  assign error_code_o = error_q;
  assign timeout_hit = (watchdog_q == 32'h000f_ffff);

  always_comb begin
    state_d = state_q;
    sched_init_o = 1'b0;
    sched_advance_k_o = 1'b0;
    sched_advance_o = 1'b0;
    load_desc_req_o = 1'b0;
    load_a_start_o = 1'b0;
    load_b_start_o = 1'b0;
    load_bias_start_o = 1'b0;
    compute_start_o = 1'b0;
    post_process_start_o = 1'b0;
    store_start_o = 1'b0;

    unique case (state_q)
      ST_IDLE: begin
        if (start_i) state_d = ST_CHECK_CONFIG;
      end
      ST_CHECK_CONFIG: begin
        if (!cfg_valid_i) state_d = ST_ERROR;
        else state_d = ST_PREPARE_TILE;
      end
      ST_PREPARE_TILE: begin
        sched_init_o = 1'b1;
        state_d = ST_REQ_A_TILE;
      end
      ST_REQ_A_TILE: begin
        load_desc_req_o = 1'b1;
        state_d = ST_WAIT_A_DESC;
      end
      ST_WAIT_A_DESC: begin
        if (timeout_hit) state_d = ST_ERROR;
        else if (load_desc_valid_i) state_d = ST_LOAD_A_TILE;
      end
      ST_LOAD_A_TILE: begin
        load_a_start_o = 1'b1;
        if (read_dma_error_i || read_cross_4kb_i || timeout_hit) state_d = ST_ERROR;
        else if (read_dma_done_i) state_d = ST_REQ_B_TILE;
      end
      ST_REQ_B_TILE: begin
        load_desc_req_o = 1'b1;
        state_d = ST_WAIT_B_DESC;
      end
      ST_WAIT_B_DESC: begin
        if (timeout_hit) state_d = ST_ERROR;
        else if (load_desc_valid_i) state_d = ST_LOAD_B_TILE;
      end
      ST_LOAD_B_TILE: begin
        load_b_start_o = 1'b1;
        if (read_dma_error_i || read_cross_4kb_i || timeout_hit) state_d = ST_ERROR;
        else if (read_dma_done_i) state_d = bias_enabled(cfg_i.post_op) ? ST_REQ_BIAS : ST_COMPUTE_TILE;
      end
      ST_REQ_BIAS: begin
        load_desc_req_o = 1'b1;
        state_d = ST_WAIT_BIAS_DESC;
      end
      ST_WAIT_BIAS_DESC: begin
        if (timeout_hit) state_d = ST_ERROR;
        else if (load_desc_valid_i) state_d = ST_LOAD_BIAS;
      end
      ST_LOAD_BIAS: begin
        load_bias_start_o = 1'b1;
        if (read_dma_error_i || read_cross_4kb_i || timeout_hit) state_d = ST_ERROR;
        else if (read_dma_done_i) state_d = ST_COMPUTE_TILE;
      end
      ST_COMPUTE_TILE: begin
        compute_start_o = 1'b1;
        if (timeout_hit) state_d = ST_ERROR;
        else if (compute_done_i) begin
          if (last_k_tile_i) state_d = ST_POST_PROCESS_TILE;
          else state_d = ST_NEXT_K_TILE;
        end
      end
      ST_NEXT_K_TILE: begin
        sched_advance_k_o = 1'b1;
        state_d = ST_REQ_A_TILE;
      end
      ST_POST_PROCESS_TILE: begin
        post_process_start_o = 1'b1;
        if (timeout_hit) state_d = ST_ERROR;
        else if (post_process_done_i) state_d = ST_STORE_TILE;
      end
      ST_STORE_TILE: begin
        store_start_o = 1'b1;
        if (write_dma_error_i || write_cross_4kb_i || timeout_hit) state_d = ST_ERROR;
        else if (write_dma_done_i) state_d = ST_NEXT_TILE;
      end
      ST_NEXT_TILE: begin
        if (last_tile_i) state_d = ST_DONE;
        else begin
          sched_advance_o = 1'b1;
          state_d = ST_REQ_A_TILE;
        end
      end
      ST_DONE: begin
        if (start_i) state_d = ST_ERROR;
        else if (clear_done_i) state_d = ST_IDLE;
      end
      ST_ERROR: begin
        if (clear_error_i) state_d = ST_IDLE;
      end
      default: state_d = ST_IDLE;
    endcase

    if (start_i && (state_q != ST_IDLE)) begin
      state_d = ST_ERROR;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= ST_IDLE;
      status_q <= '0;
      error_q <= ERR_NO_ERROR;
      ovf_count_o <= 32'd0;
      overflow_seen_q <= 1'b0;
      watchdog_q <= 32'd0;
    end else if (soft_reset_i) begin
      state_q <= ST_IDLE;
      status_q <= '0;
      error_q <= ERR_NO_ERROR;
      ovf_count_o <= 32'd0;
      overflow_seen_q <= 1'b0;
      watchdog_q <= 32'd0;
    end else begin
      state_q <= state_d;
      status_q.busy <= (state_d != ST_IDLE) && (state_d != ST_DONE) && (state_d != ST_ERROR);
      status_q.done <= (state_d == ST_DONE) ? 1'b1 : (clear_done_i ? 1'b0 : status_q.done);
      status_q.error <= (state_d == ST_ERROR) ? 1'b1 : (clear_error_i ? 1'b0 : status_q.error);
      status_q.irq <= (clear_irq_i || clear_done_i || clear_error_i) ? 1'b0 :
                      ((((state_q != ST_DONE) && (state_d == ST_DONE)) ||
                        ((state_q != ST_ERROR) && (state_d == ST_ERROR))) && irq_en_i) ?
                       1'b1 : status_q.irq;

      if (start_i && state_q != ST_IDLE) begin
        error_q <= ERR_COMMAND_WHILE_BUSY;
      end else if (state_q == ST_CHECK_CONFIG && !cfg_valid_i) begin
        error_q <= cfg_error_i;
      end else if (read_cross_4kb_i || write_cross_4kb_i) begin
        error_q <= ERR_BURST_CROSS_4KB;
      end else if (timeout_hit) begin
        error_q <= ERR_INTERNAL_TIMEOUT;
      end else if (read_dma_error_i) begin
        error_q <= ERR_AXI_READ_ERROR;
      end else if (write_dma_error_i) begin
        error_q <= ERR_AXI_WRITE_ERROR;
      end else if (clear_error_i) begin
        error_q <= ERR_NO_ERROR;
      end

      if (overflow_i) begin
        overflow_seen_q <= 1'b1;
        ovf_count_o <= ovf_count_o + 1'b1;
      end else if (start_i && state_q == ST_IDLE) begin
        overflow_seen_q <= 1'b0;
        ovf_count_o <= 32'd0;
      end
      status_q.overflow_seen <= overflow_seen_q;

      if (state_d == state_q &&
          (state_q == ST_LOAD_A_TILE || state_q == ST_LOAD_B_TILE ||
           state_q == ST_LOAD_BIAS || state_q == ST_WAIT_A_DESC ||
           state_q == ST_WAIT_B_DESC || state_q == ST_WAIT_BIAS_DESC ||
           state_q == ST_COMPUTE_TILE ||
           state_q == ST_POST_PROCESS_TILE || state_q == ST_STORE_TILE)) begin
        watchdog_q <= watchdog_q + 1'b1;
      end else begin
        watchdog_q <= 32'd0;
      end
    end
  end
endmodule
