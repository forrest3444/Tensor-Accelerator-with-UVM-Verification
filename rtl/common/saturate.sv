`timescale 1ns/1ps

module saturate #(
  parameter int IN_WIDTH  = 40,
  parameter int OUT_WIDTH = 32
) (
  input  logic signed [IN_WIDTH-1:0]  data_i,
  input  logic                        saturate_en_i,
  output logic signed [OUT_WIDTH-1:0] data_o,
  output logic                        overflow_o
);
  localparam logic signed [IN_WIDTH-1:0] MAX_VAL =
      {{(IN_WIDTH-OUT_WIDTH){1'b0}}, 1'b0, {(OUT_WIDTH-1){1'b1}}};
  localparam logic signed [IN_WIDTH-1:0] MIN_VAL =
      {{(IN_WIDTH-OUT_WIDTH){1'b1}}, 1'b1, {(OUT_WIDTH-1){1'b0}}};

  always_comb begin
    overflow_o = (data_i > MAX_VAL) || (data_i < MIN_VAL);
    if (saturate_en_i && (data_i > MAX_VAL)) begin
      data_o = {1'b0, {(OUT_WIDTH-1){1'b1}}};
    end else if (saturate_en_i && (data_i < MIN_VAL)) begin
      data_o = {1'b1, {(OUT_WIDTH-1){1'b0}}};
    end else begin
      data_o = data_i[OUT_WIDTH-1:0];
    end
  end
endmodule
