module fifo #(
  parameter int WIDTH = 32,
  parameter int DEPTH = 4,
  localparam int PTR_WIDTH = (DEPTH <= 2) ? 1 : $clog2(DEPTH)
) (
  input  logic             clk,
  input  logic             rst_n,
  input  logic             clear_i,
  input  logic             push_i,
  input  logic [WIDTH-1:0] push_data_i,
  input  logic             pop_i,
  output logic [WIDTH-1:0] pop_data_o,
  output logic             full_o,
  output logic             empty_o,
  output logic [PTR_WIDTH:0] count_o
);
  logic [WIDTH-1:0] mem [DEPTH];
  logic [PTR_WIDTH-1:0] rd_ptr;
  logic [PTR_WIDTH-1:0] wr_ptr;

  assign empty_o = (count_o == '0);
  assign full_o  = (count_o == DEPTH[PTR_WIDTH:0]);
  assign pop_data_o = mem[rd_ptr];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_ptr  <= '0;
      wr_ptr  <= '0;
      count_o <= '0;
    end else if (clear_i) begin
      rd_ptr  <= '0;
      wr_ptr  <= '0;
      count_o <= '0;
    end else begin
      if (push_i && !full_o) begin
        mem[wr_ptr] <= push_data_i;
        wr_ptr <= (wr_ptr == DEPTH-1) ? '0 : wr_ptr + 1'b1;
      end
      if (pop_i && !empty_o) begin
        rd_ptr <= (rd_ptr == DEPTH-1) ? '0 : rd_ptr + 1'b1;
      end
      unique case ({push_i && !full_o, pop_i && !empty_o})
        2'b10: count_o <= count_o + 1'b1;
        2'b01: count_o <= count_o - 1'b1;
        default: count_o <= count_o;
      endcase
    end
  end

`ifdef ASSERT_ON
  always_ff @(posedge clk) begin
    if (rst_n && !clear_i) begin
      assert (!(push_i && full_o && !pop_i))
        else $fatal(1, "FIFO push while full");
      assert (!(pop_i && empty_o && !push_i))
        else $fatal(1, "FIFO pop while empty");
    end
  end
`endif
endmodule
