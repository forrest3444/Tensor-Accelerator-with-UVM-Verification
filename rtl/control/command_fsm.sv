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
  input  logic compute_done_i,
  input  logic overflow_i,
  input  logic last_tile_i,
  output logic sched_init_o,
  output logic sched_advance_o,
  output logic load_a_start_o,
  output logic load_b_start_o,
  output logic load_bias_start_o,
  output logic compute_start_o,
  output logic store_start_o,
  output accel_status_t status_o,
  output error_code_e error_code_o,
  output logic [31:0] ovf_count_o
);
  typedef enum logic [3:0] {
    ST_IDLE,
    ST_CHECK_CONFIG,
    ST_PREPARE_TILE,
    ST_LOAD_A_TILE,
    ST_LOAD_B_TILE,
    ST_LOAD_BIAS,
    ST_COMPUTE_TILE,
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

  assign status_o = status_q;
  assign error_code_o = error_q;

  always_comb begin
    state_d = state_q;
    sched_init_o = 1'b0;
    sched_advance_o = 1'b0;
    load_a_start_o = 1'b0;
    load_b_start_o = 1'b0;
    load_bias_start_o = 1'b0;
    compute_start_o = 1'b0;
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
        state_d = ST_LOAD_A_TILE;
      end
      ST_LOAD_A_TILE: begin
        load_a_start_o = 1'b1;
        if (read_dma_error_i) state_d = ST_ERROR;
        else if (read_dma_done_i) state_d = ST_LOAD_B_TILE;
      end
      ST_LOAD_B_TILE: begin
        load_b_start_o = 1'b1;
        if (read_dma_error_i) state_d = ST_ERROR;
        else if (read_dma_done_i) state_d = bias_enabled(cfg_i.post_op) ? ST_LOAD_BIAS : ST_COMPUTE_TILE;
      end
      ST_LOAD_BIAS: begin
        load_bias_start_o = 1'b1;
        if (read_dma_error_i) state_d = ST_ERROR;
        else if (read_dma_done_i) state_d = ST_COMPUTE_TILE;
      end
      ST_COMPUTE_TILE: begin
        compute_start_o = 1'b1;
        if (compute_done_i) state_d = ST_POST_PROCESS_TILE;
      end
      ST_POST_PROCESS_TILE: begin
        state_d = ST_STORE_TILE;
      end
      ST_STORE_TILE: begin
        store_start_o = 1'b1;
        if (write_dma_error_i) state_d = ST_ERROR;
        else if (write_dma_done_i) state_d = ST_NEXT_TILE;
      end
      ST_NEXT_TILE: begin
        if (last_tile_i) state_d = ST_DONE;
        else begin
          sched_advance_o = 1'b1;
          state_d = ST_LOAD_A_TILE;
        end
      end
      ST_DONE: begin
        if (clear_done_i) state_d = ST_IDLE;
      end
      ST_ERROR: begin
        if (clear_error_i) state_d = ST_IDLE;
      end
      default: state_d = ST_IDLE;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= ST_IDLE;
      status_q <= '0;
      error_q <= ERR_NO_ERROR;
      ovf_count_o <= 32'd0;
      overflow_seen_q <= 1'b0;
    end else if (soft_reset_i) begin
      state_q <= ST_IDLE;
      status_q <= '0;
      error_q <= ERR_NO_ERROR;
      ovf_count_o <= 32'd0;
      overflow_seen_q <= 1'b0;
    end else begin
      state_q <= state_d;
      status_q.busy <= (state_d != ST_IDLE) && (state_d != ST_DONE) && (state_d != ST_ERROR);
      status_q.done <= (state_d == ST_DONE) ? 1'b1 : (clear_done_i ? 1'b0 : status_q.done);
      status_q.error <= (state_d == ST_ERROR) ? 1'b1 : (clear_error_i ? 1'b0 : status_q.error);
      status_q.irq <= (((state_d == ST_DONE) || (state_d == ST_ERROR)) && irq_en_i) ? 1'b1 :
                      ((clear_irq_i || clear_done_i || clear_error_i) ? 1'b0 : status_q.irq);

      if (state_q == ST_IDLE && start_i && status_q.busy) begin
        error_q <= ERR_COMMAND_WHILE_BUSY;
      end else if (state_q == ST_CHECK_CONFIG && !cfg_valid_i) begin
        error_q <= cfg_error_i;
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
      end
      status_q.overflow_seen <= overflow_seen_q;
    end
  end
endmodule
