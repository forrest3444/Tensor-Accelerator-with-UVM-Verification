module load_scheduler
  import tensor_pkg::*;
#(
  parameter int TILE_M = ARRAY_M,
  parameter int TILE_N = ARRAY_N,
  parameter int BIAS_BYTES = 4
) 
(
  input  logic clk,
  input  logic rst_n,
  input  logic clear_i,
  input  logic start_i,
  input  logic read_dma_done_i,
  input  logic desc_ready_i,
  input  accel_cfg_t cfg_i,
  input  logic [5:0] tile_m_i,
  input  logic [5:0] tile_n_i,
  input  logic [5:0] tile_k_i,
  input  logic [15:0] a_spad_base_i,
  input  logic [15:0] b_spad_base_i,
  input  logic [15:0] bias_spad_base_i,
  output logic done_o,
  output logic load_a_start_o,
  output logic load_b_start_o,
  output logic load_bias_start_o,
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
  typedef enum logic [11:0] {
    LS_IDLE           = 12'b0000_0000_0001,
    LS_REQ_A          = 12'b0000_0000_0010,
    LS_WAIT_A_DESC    = 12'b0000_0000_0100,
    LS_LOAD_A         = 12'b0000_0000_1000,
    LS_REQ_B          = 12'b0000_0001_0000,
    LS_WAIT_B_DESC    = 12'b0000_0010_0000,
    LS_LOAD_B         = 12'b0000_0100_0000,
    LS_REQ_BIAS       = 12'b0000_1000_0000,
    LS_WAIT_BIAS_DESC = 12'b0001_0000_0000,
    LS_LOAD_BIAS      = 12'b0010_0000_0000,
    LS_WAIT_DRAIN     = 12'b0100_0000_0000,
    LS_DONE           = 12'b1000_0000_0000
  } load_state_e;

  load_state_e state_q;

  logic desc_req;
  logic valid_s1_q;
  logic valid_s2_q;
  logic valid_s3_q;
  logic desc_valid_q;
  logic [2:0] pending_desc_q;
  logic desc_issue;
  logic pending_done;
  logic b_load_needed;
  logic bias_load_needed;

  assign b_load_needed = (tile_m_i == 6'd0);
  assign bias_load_needed = bias_enabled(cfg_i.post_op) && (tile_m_i == 6'd0);

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
  logic [31:0] row_base_s2_q;
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

  assign desc_req = (state_q == LS_REQ_A) || (state_q == LS_REQ_B) ||
                    (state_q == LS_REQ_BIAS);
  assign desc_issue = ((state_q == LS_LOAD_A) ||
                       (state_q == LS_LOAD_B) ||
                       (state_q == LS_LOAD_BIAS)) && desc_ready_i;
  assign pending_done = (pending_desc_q == 3'd1) && read_dma_done_i && !desc_issue;
  assign done_o = (state_q == LS_WAIT_DRAIN) && pending_done;
  assign load_a_start_o = (state_q == LS_LOAD_A) && desc_ready_i;
  assign load_b_start_o = (state_q == LS_LOAD_B) && desc_ready_i;
  assign load_bias_start_o = (state_q == LS_LOAD_BIAS) && desc_ready_i;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= LS_IDLE;
      valid_s1_q <= 1'b0;
      valid_s2_q <= 1'b0;
      valid_s3_q <= 1'b0;
      desc_valid_q <= 1'b0;
      pending_desc_q <= 3'd0;
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
        state_q <= LS_IDLE;
        valid_s1_q <= 1'b0;
        valid_s2_q <= 1'b0;
        valid_s3_q <= 1'b0;
        desc_valid_q <= 1'b0;
        pending_desc_q <= 3'd0;
      end else begin
        unique case (state_q)
          LS_IDLE: begin
            if (start_i) state_q <= LS_REQ_A;
          end
          LS_REQ_A: begin
            state_q <= LS_WAIT_A_DESC;
          end
          LS_WAIT_A_DESC: begin
            if (desc_valid_q) state_q <= LS_LOAD_A;
          end
          LS_LOAD_A: begin
            if (desc_ready_i) begin
              if (b_load_needed) state_q <= LS_REQ_B;
              else if (bias_load_needed) state_q <= LS_REQ_BIAS;
              else state_q <= LS_WAIT_DRAIN;
            end
          end
          LS_REQ_B: begin
            state_q <= LS_WAIT_B_DESC;
          end
          LS_WAIT_B_DESC: begin
            if (desc_valid_q) state_q <= LS_LOAD_B;
          end
          LS_LOAD_B: begin
            if (desc_ready_i) begin
              if (bias_load_needed) state_q <= LS_REQ_BIAS;
              else state_q <= LS_WAIT_DRAIN;
            end
          end
          LS_REQ_BIAS: begin
            state_q <= LS_WAIT_BIAS_DESC;
          end
          LS_WAIT_BIAS_DESC: begin
            if (desc_valid_q) state_q <= LS_LOAD_BIAS;
          end
          LS_LOAD_BIAS: begin
            if (desc_ready_i) state_q <= LS_WAIT_DRAIN;
          end
          LS_WAIT_DRAIN: begin
            if (pending_done) state_q <= LS_DONE;
          end
          LS_DONE: begin
            state_q <= LS_IDLE;
          end
          default: state_q <= LS_IDLE;
        endcase

        valid_s1_q <= desc_req;
        valid_s2_q <= valid_s1_q;
        valid_s3_q <= valid_s2_q;
        if (desc_req) desc_valid_q <= 1'b0;
        else if (valid_s3_q) desc_valid_q <= 1'b1;

        unique case ({desc_issue, read_dma_done_i})
          2'b10: pending_desc_q <= pending_desc_q + 1'b1;
          2'b01: pending_desc_q <= pending_desc_q - 1'b1;
          default: pending_desc_q <= pending_desc_q;
        endcase
      end

      elem_b_s1_q <= elem_bytes(cfg_i.precision);
      row_base_s1_q <= {26'd0, tile_m_i} * 32'(TILE_M);
      col_base_s1_q <= {26'd0, tile_n_i} * 32'(TILE_N);
      k_base_s1_q <= 32'd0;
      m_size_s1_q <= cfg_i.m_size;
      n_size_s1_q <= cfg_i.n_size;
      k_size_s1_q <= cfg_i.k_size;
      a_base_s1_q <= cfg_i.a_base;
      b_base_s1_q <= cfg_i.b_base;
      bias_base_s1_q <= cfg_i.bias_base;
      a_spad_offset_s1_q <= {16'd0, a_spad_base_i};
      b_spad_offset_s1_q <= {16'd0, b_spad_base_i};
      bias_spad_offset_s1_q <= {16'd0, bias_spad_base_i};
      post_op_s1_q <= cfg_i.post_op;

      elem_b_s2_q <= elem_b_s1_q;
      row_base_s2_q <= row_base_s1_q;
      col_base_s2_q <= col_base_s1_q;
      a_base_s2_q <= a_base_s1_q;
      b_base_s2_q <= b_base_s1_q;
      bias_base_s2_q <= bias_base_s1_q;
      a_spad_offset_s2_q <= a_spad_offset_s1_q;
      b_spad_offset_s2_q <= b_spad_offset_s1_q;
      bias_spad_offset_s2_q <= bias_spad_offset_s1_q;
      post_op_s2_q <= post_op_s1_q;
      tile_rows_s2_q <= ((m_size_s1_q - row_base_s1_q) > 32'(TILE_M)) ?
                        32'(TILE_M) : (m_size_s1_q - row_base_s1_q);
      tile_cols_s2_q <= ((n_size_s1_q - col_base_s1_q) > 32'(TILE_N)) ?
                        32'(TILE_N) : (n_size_s1_q - col_base_s1_q);
      tile_k_s2_q <= k_size_s1_q;
      a_elem_index_s2_q <= row_base_s1_q * k_size_s1_q;
      b_elem_index_s2_q <= col_base_s1_q * k_size_s1_q;

      begin
        logic [31:0] a_row_bytes;
        logic [31:0] b_row_bytes;

        a_row_bytes = tile_k_s2_q * elem_b_s2_q;
        b_row_bytes = tile_k_s2_q * elem_b_s2_q;
        a_row_stride_s3_q <= align8_bytes(a_row_bytes);
        b_row_stride_s3_q <= align8_bytes(b_row_bytes);
      end
      tile_rows_s3_q <= tile_rows_s2_q;
      tile_cols_s3_q <= tile_cols_s2_q;
      tile_k_s3_q <= tile_k_s2_q;
      a_base_s3_q <= a_base_s2_q;
      b_base_s3_q <= b_base_s2_q;
      bias_base_s3_q <= bias_base_s2_q;
      col_base_s3_q <= col_base_s2_q;
      a_start_byte_s3_q <= row_base_s2_q * align8_bytes(tile_k_s2_q * elem_b_s2_q);
      b_start_byte_s3_q <= col_base_s2_q * align8_bytes(tile_k_s2_q * elem_b_s2_q);
      a_spad_offset_s3_q <= a_spad_offset_s2_q;
      b_spad_offset_s3_q <= b_spad_offset_s2_q;
      bias_spad_offset_s3_q <= bias_spad_offset_s2_q;
      post_op_s3_q <= post_op_s2_q;

      a_addr_o <= a_base_s3_q + a_start_byte_s3_q;
      b_addr_o <= b_base_s3_q + b_start_byte_s3_q;
      bias_addr_o <= bias_base_s3_q + (col_base_s3_q * 32'(BIAS_BYTES));
      a_bytes_o <= tile_rows_s3_q * a_row_stride_s3_q;
      b_bytes_o <= tile_cols_s3_q * b_row_stride_s3_q;
      bias_bytes_o <= bias_enabled(post_op_s3_q) ? (tile_cols_s3_q * 32'(BIAS_BYTES)) : 32'd0;
      a_spad_offset_o <= a_spad_offset_s3_q[15:0];
      b_spad_offset_o <= b_spad_offset_s3_q[15:0];
      bias_spad_offset_o <= bias_spad_offset_s3_q[15:0];
    end
  end
endmodule
