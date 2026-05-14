module accumulator #(
  parameter int ARRAY_M = 4,
  parameter int ARRAY_N = 4
) (
  input  logic clk,
  input  logic rst_n,
  input  logic clear_i,
  input  logic load_i,
  input  logic [ARRAY_M-1:0][ARRAY_N-1:0][31:0] data_i,
  output logic [ARRAY_M-1:0][ARRAY_N-1:0][31:0] data_o
);
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      data_o <= '0;
    end else if (clear_i) begin
      data_o <= '0;
    end else if (load_i) begin
      data_o <= data_i;
    end
  end
endmodule
