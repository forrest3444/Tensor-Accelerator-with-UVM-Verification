module mac_unit
  import tensor_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,
  input  logic        clear_i,
  input  logic        valid_i,
  input  precision_e  precision_i,
  input  logic [15:0] a_i,
  input  logic [15:0] b_i,
  output logic signed [39:0] acc_o,
  output logic        overflow_o
);
  logic signed [15:0] a_mul;
  logic signed [15:0] b_mul;
  logic signed [31:0] product_d;
  logic signed [31:0] product_q;
  logic signed [39:0] product_ext;
  logic signed [40:0] sum_ext;
  logic               add_overflow;
  logic               valid_q;

  always_comb begin
    unique case (precision_i)
      PREC_INT16: begin
        a_mul = a_i;
        b_mul = b_i;
      end
      PREC_INT4: begin
        a_mul = {{12{a_i[3]}}, a_i[3:0]};
        b_mul = {{12{b_i[3]}}, b_i[3:0]};
      end
      default: begin
        a_mul = {{8{a_i[7]}}, a_i[7:0]};
        b_mul = {{8{b_i[7]}}, b_i[7:0]};
      end
    endcase
    product_d = a_mul * b_mul;

    product_ext = {{8{product_q[31]}}, product_q};
    sum_ext = {acc_o[39], acc_o} + {product_ext[39], product_ext};

    // overflow_o tracks signed int32 range overflow of the accumulated value.
    add_overflow = (sum_ext[40:31] != {10{sum_ext[31]}});
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      product_q <= 32'sd0;
      valid_q <= 1'b0;
      acc_o <= 40'sd0;
      overflow_o <= 1'b0;
    end else if (clear_i) begin
      product_q <= 32'sd0;
      valid_q <= 1'b0;
      acc_o <= 40'sd0;
      overflow_o <= 1'b0;
    end else begin
      product_q <= product_d;
      valid_q <= valid_i;

      if (valid_q) begin
        acc_o <= sum_ext[39:0];
        overflow_o <= overflow_o || add_overflow;
      end
    end
  end
endmodule
