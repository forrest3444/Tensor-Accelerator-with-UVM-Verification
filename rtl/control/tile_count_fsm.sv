module tile_count_fsm
  import tensor_pkg::*;
#(
  parameter int TILE_M = ARRAY_M,
  parameter int TILE_N = ARRAY_N,
  parameter int TILE_K = ARRAY_M,
  parameter int OUT_BYTES = 4
)
(
  input  logic clk,
  input  logic rst_n,
  input  logic init_i,
  input  logic advance_k_i,
  input  logic advance_i,
  input  accel_cfg_t cfg_i,
  output logic [5:0] tile_m_o,
  output logic [5:0] tile_n_o,
  output logic [5:0] tile_k_o,
  output logic last_tile_o,
  output logic first_k_tile_o,
  output logic last_k_tile_o,
  output logic [TILE_M-1:0] row_valid_o,
  output logic [TILE_N-1:0] col_valid_o,
  output logic [31:0] tile_m_count_o,
  output logic [31:0] row_base_o,
  output logic [31:0] col_base_o,
  output logic [31:0] c_ext_offset_o
);
  logic [5:0] tile_m_q;
  logic [5:0] tile_n_q;
  logic [5:0] tile_k_q;
  logic [31:0] tile_m_count;
  logic [31:0] tile_n_count;
  logic [31:0] tile_k_count;
  logic [31:0] row_base;
  logic [31:0] col_base;

  assign tile_m_count = ceil_div(cfg_i.m_size, 32'(TILE_M));
  assign tile_n_count = ceil_div(cfg_i.n_size, 32'(TILE_N));
  assign tile_k_count = ceil_div(cfg_i.k_size, 32'(TILE_K));
  assign row_base = {26'd0, tile_m_q} * 32'(TILE_M);
  assign col_base = {26'd0, tile_n_q} * 32'(TILE_N);

  assign tile_m_o = tile_m_q;
  assign tile_n_o = tile_n_q;
  assign tile_k_o = tile_k_q;
  assign last_tile_o = (tile_m_q == tile_m_count[5:0] - 1'b1) &&
                       (tile_n_q == tile_n_count[5:0] - 1'b1);
  assign first_k_tile_o = (tile_k_q == 6'd0);
  assign last_k_tile_o = (tile_k_q == tile_k_count[5:0] - 1'b1);
  assign tile_m_count_o = tile_m_count;
  assign row_base_o = row_base;
  assign col_base_o = col_base;
  assign c_ext_offset_o = ((row_base * cfg_i.n_size + col_base) * 32'(OUT_BYTES));

  always_comb begin
    for (int r = 0; r < TILE_M; r++) begin
      row_valid_o[r] = (row_base + r[31:0]) < cfg_i.m_size;
    end
    for (int c = 0; c < TILE_N; c++) begin
      col_valid_o[c] = (col_base + c[31:0]) < cfg_i.n_size;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tile_m_q <= '0;
      tile_n_q <= '0;
      tile_k_q <= '0;
    end else if (init_i) begin
      tile_m_q <= '0;
      tile_n_q <= '0;
      tile_k_q <= '0;
    end else if (advance_k_i) begin
      tile_k_q <= tile_k_q + 1'b1;
    end else if (advance_i) begin
      tile_k_q <= '0;
      if (tile_m_q == tile_m_count[5:0] - 1'b1) begin
        tile_m_q <= '0;
        tile_n_q <= tile_n_q + 1'b1;
      end else begin
        tile_m_q <= tile_m_q + 1'b1;
      end
    end
  end
endmodule
