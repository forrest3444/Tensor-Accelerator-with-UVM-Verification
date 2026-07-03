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
  input  logic cfg_valid_i,
  input  error_code_e cfg_error_i,
  input  logic read_dma_error_i,
  input  logic write_dma_done_i,
  input  logic write_dma_error_i,
  input  logic store_busy_i,
  input  logic store_required_i,
  input  logic read_cross_4kb_i,
  input  logic write_cross_4kb_i,
  input  logic compute_done_i,
  input  logic post_process_active_i,
  input  logic post_process_done_i,
  input  logic overflow_i,
  input  logic last_tile_i,
  input  logic next_buffer_free_i,
  input  logic next_load_prefetch_safe_i,
  input  logic load_tile_done_i,
  output logic sched_init_o,
  output logic sched_advance_o,
  output logic load_tile_start_o,
  output logic compute_start_o,
  output logic post_process_start_o,
  output logic store_start_o,
  output accel_status_t status_o,
  output error_code_e error_code_o,
  output logic [31:0] ovf_count_o
);
  typedef enum logic [14:0] {
    ST_IDLE              = 15'b000_0000_0000_0001,
    ST_CHECK_CONFIG      = 15'b000_0000_0000_0010,
    ST_PREPARE_TILE      = 15'b000_0000_0000_0100,
    ST_LOAD_TILE         = 15'b000_0000_0000_1000,
    ST_COMPUTE_TILE      = 15'b000_0000_0001_0000,
    ST_PIPE_ADVANCE      = 15'b000_0000_0010_0000,
    ST_PIPE_LOAD         = 15'b000_0000_0100_0000,
    ST_PIPE_WAIT_LOAD    = 15'b000_0000_1000_0000,
    ST_PIPE_WAIT_COMPUTE = 15'b000_0001_0000_0000,
    ST_POST_PROCESS_TILE = 15'b000_0010_0000_0000,
    ST_WAIT_STORE_SLOT   = 15'b000_0100_0000_0000,
    ST_STORE_TILE        = 15'b000_1000_0000_0000,
    ST_WAIT_FINAL_STORE  = 15'b001_0000_0000_0000,
    ST_DONE              = 15'b010_0000_0000_0000,
    ST_ERROR             = 15'b100_0000_0000_0000
  } state_e;

  state_e state_q, state_d;
  accel_status_t status_q;
  error_code_e error_q;
  logic overflow_seen_q;
  logic active_last_tile_q;
  logic prefetch_valid_q;
  logic compute_issued_q;
  logic compute_complete;
  logic [31:0] watchdog_q;
  logic timeout_hit;

  assign status_o = status_q;
  assign error_code_o = error_q;
  assign timeout_hit = (watchdog_q == 32'h000f_ffff);
  assign compute_complete = compute_issued_q && compute_done_i;

  always_comb begin
    state_d = state_q;
    sched_init_o = 1'b0;
    sched_advance_o = 1'b0;
    load_tile_start_o = 1'b0;
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
        state_d = ST_LOAD_TILE;
      end
      ST_LOAD_TILE: begin
        load_tile_start_o = 1'b1;
        if (read_dma_error_i || write_dma_error_i ||
            read_cross_4kb_i || write_cross_4kb_i || timeout_hit) state_d = ST_ERROR;
        else if (load_tile_done_i) state_d = ST_COMPUTE_TILE;
      end
      ST_COMPUTE_TILE: begin
        compute_start_o = 1'b1;
        if (write_dma_error_i || write_cross_4kb_i || timeout_hit) state_d = ST_ERROR;
        else if (!last_tile_i && next_load_prefetch_safe_i) begin
          sched_advance_o = 1'b1;
          state_d = ST_PIPE_LOAD;
        end
        else if (compute_complete) state_d = ST_POST_PROCESS_TILE;
      end
      ST_PIPE_ADVANCE: begin
        sched_advance_o = 1'b1;
        if (write_dma_error_i || write_cross_4kb_i || timeout_hit) state_d = ST_ERROR;
        else state_d = ST_PIPE_LOAD;
      end
      ST_PIPE_LOAD: begin
        load_tile_start_o = 1'b1;
        if (read_dma_error_i || write_dma_error_i ||
            read_cross_4kb_i || write_cross_4kb_i || timeout_hit) begin
          state_d = ST_ERROR;
        end else if (load_tile_done_i && compute_complete) begin
          state_d = ST_POST_PROCESS_TILE;
        end else if (compute_complete) begin
          state_d = ST_PIPE_WAIT_LOAD;
        end else if (load_tile_done_i) begin
          state_d = ST_PIPE_WAIT_COMPUTE;
        end
      end
      ST_PIPE_WAIT_LOAD: begin
        load_tile_start_o = 1'b1;
        if (read_dma_error_i || write_dma_error_i ||
            read_cross_4kb_i || write_cross_4kb_i || timeout_hit) state_d = ST_ERROR;
        else if (load_tile_done_i) state_d = ST_POST_PROCESS_TILE;
      end
      ST_PIPE_WAIT_COMPUTE: begin
        if (write_dma_error_i || write_cross_4kb_i || timeout_hit) state_d = ST_ERROR;
        else if (compute_complete) state_d = ST_POST_PROCESS_TILE;
      end
      ST_POST_PROCESS_TILE: begin
        if (write_dma_error_i || write_cross_4kb_i || timeout_hit) state_d = ST_ERROR;
        else if (store_required_i && store_busy_i && !post_process_active_i) begin
          state_d = ST_WAIT_STORE_SLOT;
        end else begin
          post_process_start_o = 1'b1;
          if (store_required_i && !store_busy_i) store_start_o = 1'b1;
          if (post_process_done_i && (!store_required_i || write_dma_done_i)) begin
            if (active_last_tile_q) begin
              state_d = ST_DONE;
            end else if (prefetch_valid_q) begin
              state_d = ST_COMPUTE_TILE;
            end else begin
              sched_advance_o = 1'b1;
              state_d = ST_LOAD_TILE;
            end
          end else if (post_process_done_i) begin
            if (!store_required_i) begin
              if (active_last_tile_q) begin
                state_d = ST_DONE;
              end else if (prefetch_valid_q) begin
                state_d = ST_COMPUTE_TILE;
              end else begin
                sched_advance_o = 1'b1;
                state_d = ST_LOAD_TILE;
              end
            end else if (active_last_tile_q) begin
              state_d = ST_WAIT_FINAL_STORE;
            end else begin
              state_d = ST_STORE_TILE;
            end
          end
        end
      end
      ST_WAIT_STORE_SLOT: begin
        if (write_dma_error_i || write_cross_4kb_i || timeout_hit) begin
          state_d = ST_ERROR;
        end else if (!store_required_i) begin
          if (active_last_tile_q) begin
            state_d = ST_DONE;
          end else if (prefetch_valid_q) begin
            state_d = ST_COMPUTE_TILE;
          end else begin
            sched_advance_o = 1'b1;
            state_d = ST_LOAD_TILE;
          end
        end else if (!store_busy_i) begin
          state_d = ST_POST_PROCESS_TILE;
        end
      end
      ST_STORE_TILE: begin
        if (write_dma_error_i || write_cross_4kb_i || timeout_hit) state_d = ST_ERROR;
        else if (write_dma_done_i) begin
          if (prefetch_valid_q) begin
            state_d = ST_COMPUTE_TILE;
          end else begin
            sched_advance_o = 1'b1;
            state_d = ST_LOAD_TILE;
          end
        end
      end
      ST_WAIT_FINAL_STORE: begin
        if (write_dma_error_i || write_cross_4kb_i || timeout_hit) state_d = ST_ERROR;
        else if (write_dma_done_i) state_d = ST_DONE;
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
      active_last_tile_q <= 1'b0;
      prefetch_valid_q <= 1'b0;
      compute_issued_q <= 1'b0;
      watchdog_q <= 32'd0;
    end else if (soft_reset_i) begin
      state_q <= ST_IDLE;
      status_q <= '0;
      error_q <= ERR_NO_ERROR;
      ovf_count_o <= 32'd0;
      overflow_seen_q <= 1'b0;
      active_last_tile_q <= 1'b0;
      prefetch_valid_q <= 1'b0;
      compute_issued_q <= 1'b0;
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

      if (state_q == ST_COMPUTE_TILE) begin
        active_last_tile_q <= last_tile_i;
      end
      if (state_d == ST_POST_PROCESS_TILE || state_d == ST_DONE ||
          state_d == ST_ERROR || state_d == ST_IDLE) begin
        compute_issued_q <= 1'b0;
      end else if ((state_q == ST_COMPUTE_TILE ||
                    state_q == ST_PIPE_LOAD ||
                    state_q == ST_PIPE_WAIT_LOAD ||
                    state_q == ST_PIPE_WAIT_COMPUTE) &&
                   !compute_done_i) begin
        compute_issued_q <= 1'b1;
      end
      if (state_q == ST_PIPE_LOAD && load_tile_done_i) begin
        prefetch_valid_q <= 1'b1;
      end else if (state_q == ST_PIPE_WAIT_LOAD && load_tile_done_i) begin
        prefetch_valid_q <= 1'b1;
      end else if ((state_q == ST_WAIT_STORE_SLOT) && !store_busy_i &&
                   prefetch_valid_q && !active_last_tile_q) begin
        prefetch_valid_q <= 1'b0;
      end else if ((state_q == ST_STORE_TILE) && write_dma_done_i &&
                   prefetch_valid_q && !active_last_tile_q) begin
        prefetch_valid_q <= 1'b0;
      end else if ((state_q == ST_POST_PROCESS_TILE) && post_process_done_i &&
                   (!store_required_i || write_dma_done_i) &&
                   prefetch_valid_q && !active_last_tile_q) begin
        prefetch_valid_q <= 1'b0;
      end else if (state_q == ST_LOAD_TILE) begin
        prefetch_valid_q <= 1'b0;
      end

      if (state_d == state_q &&
          (state_q == ST_LOAD_TILE || state_q == ST_COMPUTE_TILE ||
           state_q == ST_PIPE_LOAD || state_q == ST_PIPE_WAIT_LOAD ||
           state_q == ST_PIPE_WAIT_COMPUTE ||
           state_q == ST_POST_PROCESS_TILE || state_q == ST_WAIT_STORE_SLOT ||
           state_q == ST_STORE_TILE || state_q == ST_WAIT_FINAL_STORE)) begin
        watchdog_q <= watchdog_q + 1'b1;
      end else begin
        watchdog_q <= 32'd0;
      end
    end
  end

endmodule
