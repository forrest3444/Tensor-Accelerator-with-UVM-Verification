`ifndef TENSOR_ACCEL_RANDOM_CORNER_DATA_VSEQ_SV
`define TENSOR_ACCEL_RANDOM_CORNER_DATA_VSEQ_SV

class tensor_random_corner_data_vseq extends tensor_random_legal_vseq;
  `uvm_object_utils(tensor_random_corner_data_vseq)

  function new(string name = "tensor_random_corner_data_vseq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(), "Running random corner-data scenario", UVM_LOW)
    super.body();
  endtask

  virtual function int signed random_operand();
    if (precision == PREC_INT16) begin
      case ($urandom_range(0, 5))
        0: return 0;
        1: return 1;
        2: return -1;
        3: return 32767;
        4: return -32768;
        default: return int'($urandom_range(0, 65535)) - 32768;
      endcase
    end

    case ($urandom_range(0, 5))
      0: return 0;
      1: return 1;
      2: return -1;
      3: return 127;
      4: return -128;
      default: return int'($urandom_range(0, 255)) - 128;
    endcase
  endfunction

  virtual function int signed random_bias();
    case ($urandom_range(0, 4))
      0: return 0;
      1: return int'($urandom_range(1, 4096));
      2: return -int'($urandom_range(1, 4096));
      3: return ($urandom_range(0, 1) == 0) ? 32'sh7fff_ffff : 32'sh8000_0000;
      default: return int'($urandom());
    endcase
  endfunction
endclass

`endif
