module load_scheduler
  import tensor_pkg::*;
(
  input  logic clk,
  input  logic rst_n,
  input  logic clear_i,
  input  logic req_i,
  input  accel_cfg_t cfg_i,
  input  logic [5:0] tile_m_i,
  input  logic [5:0] tile_n_i,
  input  logic [5:0] tile_k_i,
  output logic desc_valid_o,
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
  logic valid_s1_q;
  logic valid_s2_q;
  logic valid_s3_q;

  logic [31:0] elem_b_s1_q;
  logic [31:0] row_base_s1_q;
  logic [31:0] col_base_s1_q;
  logic [31:0] k_base_s1_q;
  logic [31:0] m_size_s1_q;
  logic [31:0] n_size_s1_q;
  logic [31:0] k_size_s1_q;
  logic [31:0] a_base_s1_q;
  logic [31:0] b_base_s1_q;
  logic [31:0] bias_base_s1_q;
  logic [31:0] a_spad_offset_s1_q;
  logic [31:0] b_spad_offset_s1_q;
  logic [31:0] bias_spad_offset_s1_q;
  post_op_e post_op_s1_q;

  logic [31:0] elem_b_s2_q;
  logic [31:0] col_base_s2_q;
  logic [31:0] a_base_s2_q;
  logic [31:0] b_base_s2_q;
  logic [31:0] bias_base_s2_q;
  logic [31:0] a_spad_offset_s2_q;
  logic [31:0] b_spad_offset_s2_q;
  logic [31:0] bias_spad_offset_s2_q;
  post_op_e post_op_s2_q;
  logic [31:0] tile_rows_s2_q;
  logic [31:0] tile_cols_s2_q;
  logic [31:0] tile_k_s2_q;
  logic [31:0] a_elem_index_s2_q;
  logic [31:0] b_elem_index_s2_q;

  logic [31:0] a_row_stride_s3_q;
  logic [31:0] b_row_stride_s3_q;
  logic [31:0] tile_rows_s3_q;
  logic [31:0] tile_cols_s3_q;
  logic [31:0] tile_k_s3_q;
  logic [31:0] a_base_s3_q;
  logic [31:0] b_base_s3_q;
  logic [31:0] bias_base_s3_q;
  logic [31:0] col_base_s3_q;
  logic [31:0] a_start_byte_s3_q;
  logic [31:0] b_start_byte_s3_q;
  logic [31:0] a_spad_offset_s3_q;
  logic [31:0] b_spad_offset_s3_q;
  logic [31:0] bias_spad_offset_s3_q;
  post_op_e post_op_s3_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_s1_q <= 1'b0;
      valid_s2_q <= 1'b0;
      valid_s3_q <= 1'b0;
      desc_valid_o <= 1'b0;
      a_addr_o <= 32'd0;
      b_addr_o <= 32'd0;
      bias_addr_o <= 32'd0;
      a_bytes_o <= 32'd0;
      b_bytes_o <= 32'd0;
      bias_bytes_o <= 32'd0;
      a_spad_offset_o <= 16'd0;
      b_spad_offset_o <= 16'd0;
      bias_spad_offset_o <= 16'd0;
    end else begin
      if (clear_i) begin
        valid_s1_q <= 1'b0;
        valid_s2_q <= 1'b0;
        valid_s3_q <= 1'b0;
        desc_valid_o <= 1'b0;
      end else begin
        valid_s1_q <= req_i;
        valid_s2_q <= valid_s1_q;
        valid_s3_q <= valid_s2_q;
        if (req_i) desc_valid_o <= 1'b0;
        else if (valid_s3_q) desc_valid_o <= 1'b1;
      end

      elem_b_s1_q <= elem_bytes(cfg_i.precision);
      row_base_s1_q <= {26'd0, tile_m_i} << 2;
      col_base_s1_q <= {26'd0, tile_n_i} << 2;
      k_base_s1_q <= {26'd0, tile_k_i} << 2;
      m_size_s1_q <= cfg_i.m_size;
      n_size_s1_q <= cfg_i.n_size;
      k_size_s1_q <= cfg_i.k_size;
      a_base_s1_q <= cfg_i.a_base;
      b_base_s1_q <= cfg_i.b_base;
      bias_base_s1_q <= cfg_i.bias_base;
      a_spad_offset_s1_q <= cfg_i.a_spad_offset;
      b_spad_offset_s1_q <= cfg_i.b_spad_offset;
      bias_spad_offset_s1_q <= cfg_i.bias_spad_offset;
      post_op_s1_q <= cfg_i.post_op;

      elem_b_s2_q <= elem_b_s1_q;
      col_base_s2_q <= col_base_s1_q;
      a_base_s2_q <= a_base_s1_q;
      b_base_s2_q <= b_base_s1_q;
      bias_base_s2_q <= bias_base_s1_q;
      a_spad_offset_s2_q <= a_spad_offset_s1_q;
      b_spad_offset_s2_q <= b_spad_offset_s1_q;
      bias_spad_offset_s2_q <= bias_spad_offset_s1_q;
      post_op_s2_q <= post_op_s1_q;
      tile_rows_s2_q <= ((m_size_s1_q - row_base_s1_q) > 4) ? 32'd4 : (m_size_s1_q - row_base_s1_q);
      tile_cols_s2_q <= ((n_size_s1_q - col_base_s1_q) > 4) ? 32'd4 : (n_size_s1_q - col_base_s1_q);
      tile_k_s2_q <= ((k_size_s1_q - k_base_s1_q) > 4) ? 32'd4 : (k_size_s1_q - k_base_s1_q);
      a_elem_index_s2_q <= (row_base_s1_q * k_size_s1_q) + k_base_s1_q;
      b_elem_index_s2_q <= (k_base_s1_q * n_size_s1_q) + col_base_s1_q;

      begin
        logic [31:0] a_row_bytes;
        logic [31:0] b_row_bytes;

        a_row_bytes = tile_k_s2_q * elem_b_s2_q;
        b_row_bytes = tile_cols_s2_q * elem_b_s2_q;
        a_row_stride_s3_q <= (a_row_bytes + 32'd14) & 32'hffff_fff8;
        b_row_stride_s3_q <= (b_row_bytes + 32'd14) & 32'hffff_fff8;
      end
      tile_rows_s3_q <= tile_rows_s2_q;
      tile_cols_s3_q <= tile_cols_s2_q;
      tile_k_s3_q <= tile_k_s2_q;
      a_base_s3_q <= a_base_s2_q;
      b_base_s3_q <= b_base_s2_q;
      bias_base_s3_q <= bias_base_s2_q;
      col_base_s3_q <= col_base_s2_q;
      a_start_byte_s3_q <= a_elem_index_s2_q * elem_b_s2_q;
      b_start_byte_s3_q <= b_elem_index_s2_q * elem_b_s2_q;
      a_spad_offset_s3_q <= a_spad_offset_s2_q;
      b_spad_offset_s3_q <= b_spad_offset_s2_q;
      bias_spad_offset_s3_q <= bias_spad_offset_s2_q;
      post_op_s3_q <= post_op_s2_q;

      a_addr_o <= a_base_s3_q + a_start_byte_s3_q;
      b_addr_o <= b_base_s3_q + b_start_byte_s3_q;
      bias_addr_o <= bias_base_s3_q + (col_base_s3_q << 2);
      a_bytes_o <= tile_rows_s3_q * a_row_stride_s3_q;
      b_bytes_o <= tile_k_s3_q * b_row_stride_s3_q;
      bias_bytes_o <= bias_enabled(post_op_s3_q) ? (tile_cols_s3_q << 2) : 32'd0;
      a_spad_offset_o <= a_spad_offset_s3_q[15:0];
      b_spad_offset_o <= b_spad_offset_s3_q[15:0];
      bias_spad_offset_o <= bias_spad_offset_s3_q[15:0];
    end
  end
endmodule
