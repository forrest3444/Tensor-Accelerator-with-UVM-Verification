module tile_scheduler
  import tensor_pkg::*;
(
  input  logic clk,
  input  logic rst_n,
  input  logic init_i,
  input  logic advance_i,
  input  accel_cfg_t cfg_i,
  output logic [5:0] tile_m_o,
  output logic [5:0] tile_n_o,
  output logic last_tile_o,
  output logic [3:0] row_valid_o,
  output logic [3:0] col_valid_o,
  output logic [31:0] c_spad_offset_o,
  output logic [31:0] c_ext_offset_o
);
  logic [5:0] tile_m_q;
  logic [5:0] tile_n_q;
  logic [31:0] tile_m_count;
  logic [31:0] tile_n_count;
  logic [31:0] row_base;
  logic [31:0] col_base;

  assign tile_m_count = ceil_div4(cfg_i.m_size);
  assign tile_n_count = ceil_div4(cfg_i.n_size);
  assign tile_m_o = tile_m_q;
  assign tile_n_o = tile_n_q;
  assign last_tile_o = (tile_m_q == tile_m_count[5:0] - 1'b1) &&
                       (tile_n_q == tile_n_count[5:0] - 1'b1);
  assign row_base = {26'd0, tile_m_q} << 2;
  assign col_base = {26'd0, tile_n_q} << 2;
  assign c_spad_offset_o = cfg_i.c_spad_offset + ((row_base * cfg_i.n_size + col_base) << 2);
  assign c_ext_offset_o = ((row_base * cfg_i.n_size + col_base) << 2);

  always_comb begin
    for (int r = 0; r < 4; r++) begin
      row_valid_o[r] = (row_base + r[31:0]) < cfg_i.m_size;
    end
    for (int c = 0; c < 4; c++) begin
      col_valid_o[c] = (col_base + c[31:0]) < cfg_i.n_size;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tile_m_q <= '0;
      tile_n_q <= '0;
    end else if (init_i) begin
      tile_m_q <= '0;
      tile_n_q <= '0;
    end else if (advance_i) begin
      if (tile_n_q == tile_n_count[5:0] - 1'b1) begin
        tile_n_q <= '0;
        tile_m_q <= tile_m_q + 1'b1;
      end else begin
        tile_n_q <= tile_n_q + 1'b1;
      end
    end
  end
endmodule
