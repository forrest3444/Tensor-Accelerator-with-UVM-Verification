module c_store_coalescer
  import tensor_pkg::*;
#(
  parameter int TILE_M = ARRAY_M,
  parameter int TILE_N = ARRAY_N,
  parameter int C_STORE_NBLOCK = 2,
  parameter int DATA_WIDTH = 32,
  parameter int ADDR_WIDTH = 16,
  parameter int ROW_INDEX_WIDTH = (TILE_M <= 2) ? 1 : $clog2(TILE_M),
  parameter int MTILE_SLOTS = (MAX_DIM + TILE_M - 1) / TILE_M,
  parameter int MTILE_INDEX_WIDTH = (MTILE_SLOTS <= 2) ? 1 : $clog2(MTILE_SLOTS),
  parameter int NBLOCK_SLOT_WIDTH = (C_STORE_NBLOCK <= 2) ? 1 : $clog2(C_STORE_NBLOCK)
) (
  input  logic clk,
  input  logic rst_n,
  input  logic clear_i,

  input  logic row_write_i,
  input  logic [MTILE_INDEX_WIDTH-1:0] tile_m_i,
  input  logic [NBLOCK_SLOT_WIDTH-1:0] nblock_slot_i,
  input  logic [ROW_INDEX_WIDTH-1:0] row_write_index_i,
  input  logic [31:0] tile_cols_i,
  input  logic [TILE_M-1:0][TILE_N-1:0][DATA_WIDTH-1:0] tile_data_i,

  input  logic [MTILE_INDEX_WIDTH-1:0] read_tile_m_i,
  input  logic read_req_i,
  input  logic [ADDR_WIDTH-1:0] read_addr_i,
  output logic [DATA_WIDTH-1:0] read_data_o,
  output logic read_ready_o
);
  localparam int BLOCK_N = TILE_N * C_STORE_NBLOCK;
  localparam int ROW_BYTES = BLOCK_N * (DATA_WIDTH / 8);

  logic [MTILE_SLOTS-1:0][TILE_M-1:0][BLOCK_N-1:0][DATA_WIDTH-1:0] row_data_q;
  logic [DATA_WIDTH-1:0] read_data_q;

  assign read_data_o = read_data_q;
  assign read_ready_o = read_req_i;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int m = 0; m < MTILE_SLOTS; m++) begin
        for (int r = 0; r < TILE_M; r++) begin
          for (int c = 0; c < BLOCK_N; c++) begin
            row_data_q[m][r][c] <= '0;
          end
        end
      end
      read_data_q <= '0;
    end else begin
      if (clear_i) begin
        for (int m = 0; m < MTILE_SLOTS; m++) begin
          for (int r = 0; r < TILE_M; r++) begin
            for (int c = 0; c < BLOCK_N; c++) begin
              row_data_q[m][r][c] <= '0;
            end
          end
        end
        read_data_q <= '0;
      end else begin
        if (row_write_i &&
            (int'(tile_m_i) < MTILE_SLOTS) &&
            (int'(row_write_index_i) < TILE_M)) begin
          for (int c = 0; c < TILE_N; c++) begin
            if (c < tile_cols_i) begin
              int unsigned dst_col;

              dst_col = (int'(nblock_slot_i) * TILE_N) + c;
              if (dst_col < BLOCK_N) begin
                row_data_q[tile_m_i][row_write_index_i][dst_col] <=
                  tile_data_i[row_write_index_i][c];
              end
            end
          end
        end

        if (read_req_i) begin
          int unsigned byte_idx;
          int unsigned row_idx;
          int unsigned col_idx;

          byte_idx = read_addr_i;
          row_idx = byte_idx / ROW_BYTES;
          col_idx = (byte_idx % ROW_BYTES) >> 2;
          if ((int'(read_tile_m_i) < MTILE_SLOTS) &&
              (row_idx < TILE_M) &&
              (col_idx < BLOCK_N)) begin
            read_data_q <= row_data_q[read_tile_m_i][row_idx][col_idx];
          end else begin
            read_data_q <= '0;
          end
        end
      end
    end
  end

`ifdef ASSERT_ON
  always_ff @(posedge clk) begin
    if (rst_n && !clear_i) begin
      assert (!(row_write_i && (int'(tile_m_i) >= MTILE_SLOTS)))
        else $fatal(1, "C store coalescer write M tile out of range");
      assert (!(row_write_i && (int'(row_write_index_i) >= TILE_M)))
        else $fatal(1, "C store coalescer write row out of range");
      assert (!(row_write_i && (int'(nblock_slot_i) >= C_STORE_NBLOCK)))
        else $fatal(1, "C store coalescer write N block slot out of range");
      assert (!(read_req_i && (int'(read_tile_m_i) >= MTILE_SLOTS)))
        else $fatal(1, "C store coalescer read M tile out of range");
      assert (!(read_req_i && ((read_addr_i / ROW_BYTES) >= TILE_M)))
        else $fatal(1, "C store coalescer read row out of range");
    end
  end
`endif
endmodule
