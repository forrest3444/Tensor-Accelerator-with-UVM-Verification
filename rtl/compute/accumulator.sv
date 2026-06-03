module accumulator #(
  parameter int ARRAY_M = 4,
  parameter int ARRAY_N = 4,
  parameter int ACC_WIDTH = 40
) (
  input  logic clk,
  input  logic rst_n,
  input  logic clear_i,
  input  logic load_i,
  input  logic signed [ACC_WIDTH-1:0] data_i [ARRAY_M-1:0][ARRAY_N-1:0],
  output logic signed [ACC_WIDTH-1:0] data_o [ARRAY_M-1:0][ARRAY_N-1:0]
);
  genvar r;
  genvar c;
  generate
    for (r = 0; r < ARRAY_M; r++) begin : g_acc_row
      for (c = 0; c < ARRAY_N; c++) begin : g_acc_col
        always_ff @(posedge clk or negedge rst_n) begin
          if (!rst_n) begin
            data_o[r][c] <= '0;
          end else begin
            data_o[r][c] <= data_i[r][c];
          end
        end
      end
    end
  endgenerate
endmodule
