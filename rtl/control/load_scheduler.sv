module load_scheduler
  import tensor_pkg::*;
(
  input  accel_cfg_t cfg_i,
  input  logic [5:0] tile_m_i,
  input  logic [5:0] tile_n_i,
  output logic [31:0] a_addr_o,
  output logic [31:0] b_addr_o,
  output logic [31:0] bias_addr_o,
  output logic [31:0] a_bytes_o,
  output logic [31:0] b_bytes_o,
  output logic [31:0] bias_bytes_o,
  output logic [15:0] a_spad_offset_o,
  output logic [15:0] b_spad_offset_o,
  output logic [15:0] bias_spad_offset_o
);
  logic [31:0] elem_b;
  logic [31:0] row_base;
  logic [31:0] col_base;
  logic [31:0] tile_rows;
  logic [31:0] tile_cols;

  always_comb begin
    elem_b = elem_bytes(cfg_i.precision);
    row_base = {26'd0, tile_m_i} << 2;
    col_base = {26'd0, tile_n_i} << 2;
    tile_rows = ((cfg_i.m_size - row_base) > 4) ? 32'd4 : (cfg_i.m_size - row_base);
    tile_cols = ((cfg_i.n_size - col_base) > 4) ? 32'd4 : (cfg_i.n_size - col_base);

    a_addr_o = cfg_i.a_base + ((row_base * cfg_i.k_size) * elem_b);
    b_addr_o = cfg_i.b_base + (col_base * elem_b);
    bias_addr_o = cfg_i.bias_base + (col_base << 2);
    a_bytes_o = tile_rows * cfg_i.k_size * elem_b;
    b_bytes_o = cfg_i.k_size * tile_cols * elem_b;
    bias_bytes_o = bias_enabled(cfg_i.post_op) ? (tile_cols << 2) : 32'd0;
    a_spad_offset_o = cfg_i.a_spad_offset[15:0];
    b_spad_offset_o = cfg_i.b_spad_offset[15:0];
    bias_spad_offset_o = cfg_i.bias_spad_offset[15:0];
  end
endmodule
