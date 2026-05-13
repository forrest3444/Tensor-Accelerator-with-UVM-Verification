`ifndef TENSOR_ACCEL_MATRIX_ITEM_SV
`define TENSOR_ACCEL_MATRIX_ITEM_SV

class tensor_accel_matrix_item extends uvm_sequence_item;
  `uvm_object_utils(tensor_accel_matrix_item)

  rand int unsigned m;
  rand int unsigned n;
  rand int unsigned k;
  rand precision_e  precision;
  rand post_op_e    post_op;
  rand sat_mode_e   sat_mode;

  int signed a_data[];
  int signed b_data[];
  int signed bias_data[];
  int signed expected_c[];
  int signed actual_c[];

  constraint c_dims {
    m inside {[1:MAX_DIM]};
    n inside {[1:MAX_DIM]};
    k inside {[1:MAX_DIM]};
  }

  function new(string name = "tensor_accel_matrix_item");
    super.new(name);
  endfunction
endclass

`endif
