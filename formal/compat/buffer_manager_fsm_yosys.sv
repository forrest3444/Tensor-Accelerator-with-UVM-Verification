import tensor_pkg::*;

module buffer_manager_fsm #(
  parameter int SPAD_BUFFER_BYTES = 1024
) (
  input  logic clk,
  input  logic rst_n,
  input  logic clear_i,
  input  logic [5:0] tile_m_i,
  input  logic [5:0] tile_n_i,
  input  logic [31:0] tile_m_count_i,
  input  logic last_tile_i,
  input  logic store_buffer_i,
  input  logic store_start_i,
  input  logic store_done_i,
  output logic current_buffer_o,
  output logic next_buffer_free_o,
  output logic next_load_prefetch_safe_o,
  output logic [15:0] a_spad_base_o,
  output logic [15:0] b_spad_base_o,
  output logic [15:0] bias_spad_base_o,
  output logic b_load_needed_o
);
  typedef enum logic [1:0] {
    BUF_FREE    = 2'b00,
    BUF_IN_USE  = 2'b01,
    BUF_STORING = 2'b10
  } buffer_state_e;

  localparam logic [15:0] A_SPAD_BASE0   = 16'h0000;
  localparam logic [15:0] A_SPAD_BASE1   = 16'(SPAD_BUFFER_BYTES);
  localparam logic [15:0] B_SPAD_BASE0   = 16'(2 * SPAD_BUFFER_BYTES);
  localparam logic [15:0] BIAS_SPAD_BASE = 16'(3 * SPAD_BUFFER_BYTES);

  buffer_state_e buffer_state_q [2];
  logic next_tile_m_wrap;
  logic [5:0] next_tile_m;
  logic [5:0] next_tile_n;
  logic current_buffer;
  logic next_buffer;
  logic store_buffer_q;

  assign current_buffer = tile_m_i[0] ^ (tile_n_i[0] & tile_m_count_i[0]);
  assign next_tile_m_wrap = (tile_m_i == tile_m_count_i[5:0] - 1'b1);
  assign next_tile_m = next_tile_m_wrap ? 6'd0 : (tile_m_i + 1'b1);
  assign next_tile_n = next_tile_m_wrap ? (tile_n_i + 1'b1) : tile_n_i;
  assign next_buffer = next_tile_m[0] ^ (next_tile_n[0] & tile_m_count_i[0]);

  assign current_buffer_o = current_buffer;
  assign next_buffer_free_o = last_tile_i ||
                              ((next_buffer != current_buffer) &&
                               (buffer_state_q[next_buffer] == BUF_FREE));
  assign next_load_prefetch_safe_o = next_buffer_free_o && (next_tile_m != 6'd0);
  assign a_spad_base_o = current_buffer ? A_SPAD_BASE1 : A_SPAD_BASE0;
  assign b_spad_base_o = B_SPAD_BASE0;
  assign bias_spad_base_o = BIAS_SPAD_BASE;
  assign b_load_needed_o = (tile_m_i == 6'd0);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      buffer_state_q[0] <= BUF_FREE;
      buffer_state_q[1] <= BUF_FREE;
      store_buffer_q <= 1'b0;
    end else if (clear_i) begin
      buffer_state_q[0] <= BUF_FREE;
      buffer_state_q[1] <= BUF_FREE;
      store_buffer_q <= 1'b0;
    end else begin
      if (store_start_i) begin
        buffer_state_q[store_buffer_i] <= BUF_STORING;
        store_buffer_q <= store_buffer_i;
      end
      if (store_done_i) begin
        buffer_state_q[store_buffer_q] <= BUF_FREE;
      end
    end
  end
endmodule
