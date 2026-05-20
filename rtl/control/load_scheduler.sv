module load_scheduler
  import tensor_pkg::*;
(
  input  accel_cfg_t cfg_i,
  input  logic [5:0] tile_m_i,
  input  logic [5:0] tile_n_i,
  input  logic [5:0] tile_k_i,
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
  logic [31:0] k_base;
  logic [31:0] a_start_byte;
  logic [31:0] b_start_byte;
  logic [31:0] a_row_bytes;
  logic [31:0] b_row_bytes;
  logic [31:0] a_row_stride;
  logic [31:0] b_row_stride;
  logic [31:0] tile_rows;
  logic [31:0] tile_cols;
  logic [31:0] tile_k;

  always_comb begin
    elem_b = elem_bytes(cfg_i.precision);
    row_base = {26'd0, tile_m_i} << 2;
    col_base = {26'd0, tile_n_i} << 2;
    k_base = {26'd0, tile_k_i} << 2;
    a_start_byte = ((row_base * cfg_i.k_size) + k_base) * elem_b;
    b_start_byte = ((k_base * cfg_i.n_size) + col_base) * elem_b;
    tile_rows = ((cfg_i.m_size - row_base) > 4) ? 32'd4 : (cfg_i.m_size - row_base);
    tile_cols = ((cfg_i.n_size - col_base) > 4) ? 32'd4 : (cfg_i.n_size - col_base);
    tile_k = ((cfg_i.k_size - k_base) > 4) ? 32'd4 : (cfg_i.k_size - k_base);
    a_row_bytes = tile_k * elem_b;
    b_row_bytes = tile_cols * elem_b;
    a_row_stride = (a_row_bytes + 32'd14) & 32'hffff_fff8;
    b_row_stride = (b_row_bytes + 32'd14) & 32'hffff_fff8;

    a_addr_o = cfg_i.a_base + a_start_byte;
    b_addr_o = cfg_i.b_base + b_start_byte;
    bias_addr_o = cfg_i.bias_base + (col_base << 2);
    a_bytes_o = tile_rows * a_row_stride;
    b_bytes_o = tile_k * b_row_stride;
    bias_bytes_o = bias_enabled(cfg_i.post_op) ? (tile_cols << 2) : 32'd0;
    a_spad_offset_o = cfg_i.a_spad_offset[15:0];
    b_spad_offset_o = cfg_i.b_spad_offset[15:0];
    bias_spad_offset_o = cfg_i.bias_spad_offset[15:0];
  end
endmodule
