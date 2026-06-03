module accumulator #(
  parameter int ARRAY_M = 4,
  parameter int ARRAY_N = 4,
  parameter int ACC_WIDTH = 40
) (
  input  logic clk,
  input  logic rst_n,
  input  logic clear_i,
  input  logic load_i,
  input  logic signed [ARRAY_M*ARRAY_N*ACC_WIDTH-1:0] data_i,
  output logic signed [ARRAY_M*ARRAY_N*ACC_WIDTH-1:0] data_o
);
  genvar idx;
  generate
    for (idx = 0; idx < ARRAY_M * ARRAY_N; idx++) begin : g_acc_cell
      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          data_o[idx*ACC_WIDTH +: ACC_WIDTH] <= '0;
        end else begin
          data_o[idx*ACC_WIDTH +: ACC_WIDTH] <= data_i[idx*ACC_WIDTH +: ACC_WIDTH];
        end
      end
    end
  endgenerate
endmodule
