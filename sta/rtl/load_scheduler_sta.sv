module load_scheduler (
  input  logic clk,
  input  logic rst_n,
  input  logic clear_i,
  input  logic start_i,
  input  logic read_dma_done_i,
  input  logic [492:0] cfg_i,
  input  logic [5:0] tile_m_i,
  input  logic [5:0] tile_n_i,
  input  logic [5:0] tile_k_i,
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
  localparam logic [1:0] PREC_INT16     = 2'd1;
  localparam logic [1:0] POST_BIAS      = 2'd1;
  localparam logic [1:0] POST_BIAS_RELU = 2'd3;

  typedef enum logic [10:0] {
    LS_IDLE           = 11'b000_0000_0001,
    LS_REQ_A          = 11'b000_0000_0010,
    LS_WAIT_A_DESC    = 11'b000_0000_0100,
    LS_LOAD_A         = 11'b000_0000_1000,
    LS_REQ_B          = 11'b000_0001_0000,
    LS_WAIT_B_DESC    = 11'b000_0010_0000,
    LS_LOAD_B         = 11'b000_0100_0000,
    LS_REQ_BIAS       = 11'b000_1000_0000,
    LS_WAIT_BIAS_DESC = 11'b001_0000_0000,
    LS_LOAD_BIAS      = 11'b010_0000_0000,
    LS_DONE           = 11'b100_0000_0000
  } load_state_e;

  load_state_e state_q;

  logic desc_req;
  logic valid_s1_q;
  logic valid_s2_q;
  logic valid_s3_q;
  logic desc_valid_q;

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
  logic [1:0] post_op_s1_q;

  logic [31:0] elem_b_s2_q;
  logic [31:0] col_base_s2_q;
  logic [31:0] a_base_s2_q;
  logic [31:0] b_base_s2_q;
  logic [31:0] bias_base_s2_q;
  logic [31:0] a_spad_offset_s2_q;
  logic [31:0] b_spad_offset_s2_q;
  logic [31:0] bias_spad_offset_s2_q;
  logic [1:0] post_op_s2_q;
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
  logic [1:0] post_op_s3_q;

  assign desc_req = (state_q == LS_REQ_A) || (state_q == LS_REQ_B) ||
                    (state_q == LS_REQ_BIAS);
  assign done_o = ((state_q == LS_LOAD_B) && read_dma_done_i && !bias_enabled(cfg_i[394:393])) ||
                  ((state_q == LS_LOAD_BIAS) && read_dma_done_i);
  assign load_a_start_o = (state_q == LS_LOAD_A);
  assign load_b_start_o = (state_q == LS_LOAD_B);
  assign load_bias_start_o = (state_q == LS_LOAD_BIAS);

  function automatic logic bias_enabled(input logic [1:0] op);
    begin
      bias_enabled = (op == POST_BIAS) || (op == POST_BIAS_RELU);
    end
  endfunction

  function automatic logic [31:0] elem_bytes(input logic [1:0] precision);
    begin
      elem_bytes = (precision == PREC_INT16) ? 32'd2 : 32'd1;
    end
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= LS_IDLE;
      valid_s1_q <= 1'b0;
      valid_s2_q <= 1'b0;
      valid_s3_q <= 1'b0;
      desc_valid_q <= 1'b0;
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
            if (read_dma_done_i) state_q <= LS_REQ_B;
          end
          LS_REQ_B: begin
            state_q <= LS_WAIT_B_DESC;
          end
          LS_WAIT_B_DESC: begin
            if (desc_valid_q) state_q <= LS_LOAD_B;
          end
          LS_LOAD_B: begin
            if (read_dma_done_i) begin
              if (bias_enabled(cfg_i[394:393])) begin
                state_q <= LS_REQ_BIAS;
              end else begin
                state_q <= LS_DONE;
              end
            end
          end
          LS_REQ_BIAS: begin
            state_q <= LS_WAIT_BIAS_DESC;
          end
          LS_WAIT_BIAS_DESC: begin
            if (desc_valid_q) state_q <= LS_LOAD_BIAS;
          end
          LS_LOAD_BIAS: begin
            if (read_dma_done_i) state_q <= LS_DONE;
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
      end

      elem_b_s1_q <= elem_bytes(cfg_i[396:395]);
      row_base_s1_q <= {26'd0, tile_m_i} << 2;
      col_base_s1_q <= {26'd0, tile_n_i} << 2;
      k_base_s1_q <= 32'd0;
      m_size_s1_q <= cfg_i[492:461];
      n_size_s1_q <= cfg_i[460:429];
      k_size_s1_q <= cfg_i[428:397];
      a_base_s1_q <= cfg_i[391:360];
      b_base_s1_q <= cfg_i[359:328];
      bias_base_s1_q <= cfg_i[295:264];
      a_spad_offset_s1_q <= cfg_i[263:232];
      b_spad_offset_s1_q <= cfg_i[199:168];
      bias_spad_offset_s1_q <= cfg_i[71:40];
      post_op_s1_q <= cfg_i[394:393];

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
      tile_k_s2_q <= k_size_s1_q;
      a_elem_index_s2_q <= row_base_s1_q * k_size_s1_q;
      b_elem_index_s2_q <= col_base_s1_q * k_size_s1_q;

      begin
        logic [31:0] a_row_bytes;
        logic [31:0] b_row_bytes;

        a_row_bytes = tile_k_s2_q * elem_b_s2_q;
        b_row_bytes = tile_k_s2_q * elem_b_s2_q;
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
      b_bytes_o <= tile_cols_s3_q * b_row_stride_s3_q;
      bias_bytes_o <= bias_enabled(post_op_s3_q) ? (tile_cols_s3_q << 2) : 32'd0;
      a_spad_offset_o <= a_spad_offset_s3_q[15:0];
      b_spad_offset_o <= b_spad_offset_s3_q[15:0];
      bias_spad_offset_o <= bias_spad_offset_s3_q[15:0];
    end
  end
endmodule
