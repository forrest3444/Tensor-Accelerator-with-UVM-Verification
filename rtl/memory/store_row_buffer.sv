module store_row_buffer
  import tensor_pkg::*;
#(
  parameter int TILE_M = ARRAY_M,
  parameter int TILE_N = ARRAY_N,
  parameter int DATA_WIDTH = 32,
  parameter int ADDR_WIDTH = 16,
  parameter int ROW_INDEX_WIDTH = (TILE_M <= 2) ? 1 : $clog2(TILE_M)
) (
  input  logic clk,
  input  logic rst_n,
  input  logic clear_i,

  input  logic row_write_i,
  input  logic write_bank_i,
  input  logic [ROW_INDEX_WIDTH-1:0] row_write_index_i,
  input  logic [TILE_M-1:0][TILE_N-1:0][DATA_WIDTH-1:0] tile_data_i,

  input  logic read_bank_i,
  input  logic [ROW_INDEX_WIDTH-1:0] read_row_i,
  input  logic read_req_i,
  input  logic [ADDR_WIDTH-1:0] read_addr_i,
  output logic [DATA_WIDTH-1:0] read_data_o,
  output logic read_ready_o
);
  logic [1:0][TILE_M-1:0][TILE_N-1:0][DATA_WIDTH-1:0] row_data_q;
  logic [DATA_WIDTH-1:0] read_data_q;
  localparam int ROW_BYTES = TILE_N * (DATA_WIDTH / 8);

  assign read_data_o = read_data_q;
  assign read_ready_o = read_req_i;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int b = 0; b < 2; b++) begin
        for (int r = 0; r < TILE_M; r++) begin
          for (int c = 0; c < TILE_N; c++) begin
            row_data_q[b][r][c] <= '0;
          end
        end
      end
      read_data_q <= '0;
    end else begin
      if (clear_i) begin
        for (int b = 0; b < 2; b++) begin
          for (int r = 0; r < TILE_M; r++) begin
            for (int c = 0; c < TILE_N; c++) begin
              row_data_q[b][r][c] <= '0;
            end
          end
        end
        read_data_q <= '0;
      end else begin
        if (row_write_i && (int'(row_write_index_i) < TILE_M)) begin
          for (int c = 0; c < TILE_N; c++) begin
            row_data_q[write_bank_i][row_write_index_i][c] <=
              tile_data_i[row_write_index_i][c];
          end
        end

        if (read_req_i) begin
          int unsigned byte_idx;
          int unsigned row_idx;
          int unsigned col_idx;

          byte_idx = read_addr_i;
          row_idx = read_row_i + (byte_idx / ROW_BYTES);
          col_idx = (byte_idx % ROW_BYTES) >> 2;
          if ((row_idx < TILE_M) && (col_idx < TILE_N)) begin
            read_data_q <= row_data_q[read_bank_i][row_idx][col_idx];
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
      assert (!(row_write_i && (int'(row_write_index_i) >= TILE_M)))
        else $fatal(1, "Store row buffer write row out of range");
      assert (!(read_req_i && ((read_addr_i / ROW_BYTES) >= TILE_M)))
        else $fatal(1, "Store row buffer read row out of range");
    end
  end
`endif
endmodule
