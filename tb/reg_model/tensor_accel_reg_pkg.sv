package tensor_accel_reg_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import svt_uvm_pkg::*;
  import svt_axi_uvm_pkg::*;
  import tensor_pkg::*;

  class tensor_accel_rw_reg extends uvm_reg;
    `uvm_object_utils(tensor_accel_rw_reg)

    rand uvm_reg_field value;
    bit [31:0] reset_value;
    string access;

    function new(string name = "tensor_accel_rw_reg",
                 bit [31:0] reset_value = 32'd0,
                 string access = "RW");
      super.new(name, 32, UVM_NO_COVERAGE);
      this.reset_value = reset_value;
      this.access = access;
    endfunction

    virtual function void build();
      value = uvm_reg_field::type_id::create("value");
      value.configure(this, 32, 0, access, 0, reset_value, 1, 1, 0);
    endfunction
  endclass

  class tensor_accel_ctrl_reg extends uvm_reg;
    `uvm_object_utils(tensor_accel_ctrl_reg)

    rand uvm_reg_field start;
    rand uvm_reg_field soft_reset;
    rand uvm_reg_field irq_en;
    rand uvm_reg_field clear_done;
    rand uvm_reg_field clear_error;
    rand uvm_reg_field reserved;

    function new(string name = "tensor_accel_ctrl_reg");
      super.new(name, 32, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
      start       = uvm_reg_field::type_id::create("start");
      soft_reset  = uvm_reg_field::type_id::create("soft_reset");
      irq_en      = uvm_reg_field::type_id::create("irq_en");
      clear_done  = uvm_reg_field::type_id::create("clear_done");
      clear_error = uvm_reg_field::type_id::create("clear_error");
      reserved    = uvm_reg_field::type_id::create("reserved");

      start.configure(this,       1, 0, "WO", 0, 1'b0, 0, 1, 0);
      soft_reset.configure(this,  1, 1, "WO", 0, 1'b0, 0, 1, 0);
      irq_en.configure(this,      1, 2, "RW", 0, 1'b0, 1, 1, 0);
      clear_done.configure(this,  1, 3, "WO", 0, 1'b0, 0, 1, 0);
      clear_error.configure(this, 1, 4, "WO", 0, 1'b0, 0, 1, 0);
      reserved.configure(this,   27, 5, "RO", 0, 27'd0, 0, 0, 0);
    endfunction
  endclass

  class tensor_accel_status_reg extends uvm_reg;
    `uvm_object_utils(tensor_accel_status_reg)

    uvm_reg_field busy;
    uvm_reg_field done;
    uvm_reg_field error;
    uvm_reg_field irq;
    uvm_reg_field overflow_seen;
    uvm_reg_field reserved;

    function new(string name = "tensor_accel_status_reg");
      super.new(name, 32, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
      busy          = uvm_reg_field::type_id::create("busy");
      done          = uvm_reg_field::type_id::create("done");
      error         = uvm_reg_field::type_id::create("error");
      irq           = uvm_reg_field::type_id::create("irq");
      overflow_seen = uvm_reg_field::type_id::create("overflow_seen");
      reserved      = uvm_reg_field::type_id::create("reserved");

      busy.configure(this,          1, 0, "RO", 1, 1'b0, 1, 0, 0);
      done.configure(this,          1, 1, "RO", 1, 1'b0, 1, 0, 0);
      error.configure(this,         1, 2, "RO", 1, 1'b0, 1, 0, 0);
      irq.configure(this,           1, 3, "RO", 1, 1'b0, 1, 0, 0);
      overflow_seen.configure(this, 1, 4, "RO", 1, 1'b0, 1, 0, 0);
      reserved.configure(this,     27, 5, "RO", 0, 27'd0, 0, 0, 0);
    endfunction
  endclass

  class tensor_accel_precision_reg extends uvm_reg;
    `uvm_object_utils(tensor_accel_precision_reg)

    rand uvm_reg_field precision;
    rand uvm_reg_field reserved;

    function new(string name = "tensor_accel_precision_reg");
      super.new(name, 32, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
      precision = uvm_reg_field::type_id::create("precision");
      reserved = uvm_reg_field::type_id::create("reserved");
      precision.configure(this, 2, 0, "RW", 0, 2'd0, 1, 1, 0);
      reserved.configure(this, 30, 2, "RO", 0, 30'd0, 0, 0, 0);
    endfunction
  endclass

  class tensor_accel_post_op_reg extends uvm_reg;
    `uvm_object_utils(tensor_accel_post_op_reg)

    rand uvm_reg_field post_op;
    rand uvm_reg_field reserved;

    function new(string name = "tensor_accel_post_op_reg");
      super.new(name, 32, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
      post_op = uvm_reg_field::type_id::create("post_op");
      reserved = uvm_reg_field::type_id::create("reserved");
      post_op.configure(this, 2, 0, "RW", 0, 2'd0, 1, 1, 0);
      reserved.configure(this, 30, 2, "RO", 0, 30'd0, 0, 0, 0);
    endfunction
  endclass

  class tensor_accel_sat_mode_reg extends uvm_reg;
    `uvm_object_utils(tensor_accel_sat_mode_reg)

    rand uvm_reg_field sat_mode;
    rand uvm_reg_field reserved;

    function new(string name = "tensor_accel_sat_mode_reg");
      super.new(name, 32, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
      sat_mode = uvm_reg_field::type_id::create("sat_mode");
      reserved = uvm_reg_field::type_id::create("reserved");
      sat_mode.configure(this, 1, 0, "RW", 0, 1'b0, 1, 1, 0);
      reserved.configure(this, 31, 1, "RO", 0, 31'd0, 0, 0, 0);
    endfunction
  endclass

  class tensor_accel_dma_cfg_reg extends uvm_reg;
    `uvm_object_utils(tensor_accel_dma_cfg_reg)

    rand uvm_reg_field burst_len;
    rand uvm_reg_field reserved;

    function new(string name = "tensor_accel_dma_cfg_reg");
      super.new(name, 32, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
      burst_len = uvm_reg_field::type_id::create("burst_len");
      reserved = uvm_reg_field::type_id::create("reserved");
      burst_len.configure(this, 8, 0, "RW", 0, 8'd16, 1, 1, 0);
      reserved.configure(this, 24, 8, "RO", 0, 24'd0, 0, 0, 0);
    endfunction
  endclass

  class tensor_accel_irq_status_reg extends uvm_reg;
    `uvm_object_utils(tensor_accel_irq_status_reg)

    rand uvm_reg_field irq;
    rand uvm_reg_field reserved;

    function new(string name = "tensor_accel_irq_status_reg");
      super.new(name, 32, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
      irq = uvm_reg_field::type_id::create("irq");
      reserved = uvm_reg_field::type_id::create("reserved");
      irq.configure(this, 1, 0, "W1C", 1, 1'b0, 1, 1, 0);
      reserved.configure(this, 31, 1, "RO", 0, 31'd0, 0, 0, 0);
    endfunction
  endclass

  class tensor_accel_error_code_reg extends uvm_reg;
    `uvm_object_utils(tensor_accel_error_code_reg)

    uvm_reg_field code;
    uvm_reg_field reserved;

    function new(string name = "tensor_accel_error_code_reg");
      super.new(name, 32, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
      code = uvm_reg_field::type_id::create("code");
      reserved = uvm_reg_field::type_id::create("reserved");
      code.configure(this, 4, 0, "RO", 1, 4'd0, 1, 0, 0);
      reserved.configure(this, 28, 4, "RO", 0, 28'd0, 0, 0, 0);
    endfunction
  endclass

  class tensor_accel_reg_block extends uvm_reg_block;
    `uvm_object_utils(tensor_accel_reg_block)

    rand tensor_accel_ctrl_reg       CTRL;
    rand tensor_accel_status_reg     STATUS;
    rand tensor_accel_rw_reg         M_SIZE;
    rand tensor_accel_rw_reg         N_SIZE;
    rand tensor_accel_rw_reg         K_SIZE;
    rand tensor_accel_precision_reg  PRECISION;
    rand tensor_accel_post_op_reg    POST_OP;
    rand tensor_accel_sat_mode_reg   SAT_MODE;
    rand tensor_accel_rw_reg         A_BASE;
    rand tensor_accel_rw_reg         B_BASE;
    rand tensor_accel_rw_reg         C_BASE;
    rand tensor_accel_rw_reg         BIAS_BASE;
    rand tensor_accel_rw_reg         A_SPAD_OFFSET;
    rand tensor_accel_rw_reg         A_SPAD_SIZE;
    rand tensor_accel_rw_reg         B_SPAD_OFFSET;
    rand tensor_accel_rw_reg         B_SPAD_SIZE;
    rand tensor_accel_rw_reg         C_SPAD_OFFSET;
    rand tensor_accel_rw_reg         C_SPAD_SIZE;
    rand tensor_accel_rw_reg         BIAS_SPAD_OFFSET;
    rand tensor_accel_rw_reg         BIAS_SPAD_SIZE;
    rand tensor_accel_dma_cfg_reg    DMA_CFG;
    rand tensor_accel_irq_status_reg IRQ_STATUS;
    rand tensor_accel_rw_reg         OVF_COUNT;
    rand tensor_accel_error_code_reg ERROR_CODE;

    function new(string name = "tensor_accel_reg_block");
      super.new(name, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
      default_map = create_map("default_map", 0, 4, UVM_LITTLE_ENDIAN, 1);

      CTRL = tensor_accel_ctrl_reg::type_id::create("CTRL");
      CTRL.configure(this);
      CTRL.build();
      default_map.add_reg(CTRL, 'h0000, "RW");

      STATUS = tensor_accel_status_reg::type_id::create("STATUS");
      STATUS.configure(this);
      STATUS.build();
      default_map.add_reg(STATUS, 'h0004, "RO");

      M_SIZE = create_rw_reg("M_SIZE", 32'd0);
      default_map.add_reg(M_SIZE, 'h0008, "RW");
      N_SIZE = create_rw_reg("N_SIZE", 32'd0);
      default_map.add_reg(N_SIZE, 'h000c, "RW");
      K_SIZE = create_rw_reg("K_SIZE", 32'd0);
      default_map.add_reg(K_SIZE, 'h0010, "RW");

      PRECISION = tensor_accel_precision_reg::type_id::create("PRECISION");
      PRECISION.configure(this);
      PRECISION.build();
      default_map.add_reg(PRECISION, 'h0014, "RW");

      POST_OP = tensor_accel_post_op_reg::type_id::create("POST_OP");
      POST_OP.configure(this);
      POST_OP.build();
      default_map.add_reg(POST_OP, 'h0018, "RW");

      SAT_MODE = tensor_accel_sat_mode_reg::type_id::create("SAT_MODE");
      SAT_MODE.configure(this);
      SAT_MODE.build();
      default_map.add_reg(SAT_MODE, 'h001c, "RW");

      A_BASE = create_rw_reg("A_BASE", 32'd0);
      default_map.add_reg(A_BASE, 'h0020, "RW");
      B_BASE = create_rw_reg("B_BASE", 32'd0);
      default_map.add_reg(B_BASE, 'h0024, "RW");
      C_BASE = create_rw_reg("C_BASE", 32'd0);
      default_map.add_reg(C_BASE, 'h0028, "RW");
      BIAS_BASE = create_rw_reg("BIAS_BASE", 32'd0);
      default_map.add_reg(BIAS_BASE, 'h002c, "RW");
      A_SPAD_OFFSET = create_rw_reg("A_SPAD_OFFSET", 32'd0);
      default_map.add_reg(A_SPAD_OFFSET, 'h0030, "RW");
      A_SPAD_SIZE = create_rw_reg("A_SPAD_SIZE", 32'd0);
      default_map.add_reg(A_SPAD_SIZE, 'h0034, "RW");
      B_SPAD_OFFSET = create_rw_reg("B_SPAD_OFFSET", 32'd0);
      default_map.add_reg(B_SPAD_OFFSET, 'h0038, "RW");
      B_SPAD_SIZE = create_rw_reg("B_SPAD_SIZE", 32'd0);
      default_map.add_reg(B_SPAD_SIZE, 'h003c, "RW");
      C_SPAD_OFFSET = create_rw_reg("C_SPAD_OFFSET", 32'd0);
      default_map.add_reg(C_SPAD_OFFSET, 'h0040, "RW");
      C_SPAD_SIZE = create_rw_reg("C_SPAD_SIZE", 32'd0);
      default_map.add_reg(C_SPAD_SIZE, 'h0044, "RW");
      BIAS_SPAD_OFFSET = create_rw_reg("BIAS_SPAD_OFFSET", 32'd0);
      default_map.add_reg(BIAS_SPAD_OFFSET, 'h0048, "RW");
      BIAS_SPAD_SIZE = create_rw_reg("BIAS_SPAD_SIZE", 32'd0);
      default_map.add_reg(BIAS_SPAD_SIZE, 'h004c, "RW");

      DMA_CFG = tensor_accel_dma_cfg_reg::type_id::create("DMA_CFG");
      DMA_CFG.configure(this);
      DMA_CFG.build();
      default_map.add_reg(DMA_CFG, 'h0050, "RW");

      IRQ_STATUS = tensor_accel_irq_status_reg::type_id::create("IRQ_STATUS");
      IRQ_STATUS.configure(this);
      IRQ_STATUS.build();
      default_map.add_reg(IRQ_STATUS, 'h0054, "RW");

      OVF_COUNT = create_rw_reg("OVF_COUNT", 32'd0, "RO");
      default_map.add_reg(OVF_COUNT, 'h0058, "RO");

      ERROR_CODE = tensor_accel_error_code_reg::type_id::create("ERROR_CODE");
      ERROR_CODE.configure(this);
      ERROR_CODE.build();
      default_map.add_reg(ERROR_CODE, 'h005c, "RO");
    endfunction

    local function tensor_accel_rw_reg create_rw_reg(string name,
                                                     bit [31:0] reset_value,
                                                     string access = "RW");
      tensor_accel_rw_reg reg_h;
      reg_h = tensor_accel_rw_reg::type_id::create(name);
      reg_h.reset_value = reset_value;
      reg_h.access = access;
      reg_h.configure(this);
      reg_h.build();
      return reg_h;
    endfunction
  endclass

  class tensor_accel_reg_adapter extends uvm_reg_adapter;
    `uvm_object_utils(tensor_accel_reg_adapter)

    svt_axi_port_configuration p_cfg;

    function new(string name = "tensor_accel_reg_adapter");
      super.new(name);
      supports_byte_enable = 1;
      provides_responses = 1;
    endfunction

    virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
      svt_axi_master_transaction tr;
      bit [2:0] burst_size;

      tr = new("tr", p_cfg);
      burst_size = 3'd2;
      if (rw.n_bits <= 8) burst_size = 3'd0;
      else if (rw.n_bits <= 16) burst_size = 3'd1;

      if (!tr.randomize() with {
        xact_type        == ((rw.kind == UVM_WRITE) ? svt_axi_transaction::WRITE :
                                                       svt_axi_transaction::READ);
        atomic_type      == svt_axi_transaction::NORMAL;
        addr             == rw.addr;
        burst_length     == 1;
        burst_size       == local::burst_size;
        burst_type       == svt_axi_transaction::INCR;
        data_before_addr == 0;
        if (rw.kind == UVM_WRITE) {
          data.size() == 1;
          data[0] == rw.data;
          wstrb.size() == 1;
          wstrb[0] == 4'hf;
        }
      }) begin
        `uvm_fatal(get_type_name(), "Failed to randomize AXI register transaction")
      end

      return tr;
    endfunction

    virtual function void bus2reg(uvm_sequence_item bus_item,
                                  ref uvm_reg_bus_op rw);
      svt_axi_transaction tr;

      if (!$cast(tr, bus_item)) begin
        rw.status = UVM_NOT_OK;
        `uvm_error(get_type_name(), "bus2reg received a non-AXI transaction")
        return;
      end

      rw.addr = tr.addr;
      if (tr.xact_type == svt_axi_transaction::READ) begin
        rw.kind = UVM_READ;
        rw.data = (tr.data.size() > 0) ? tr.data[0] : '0;
        rw.status = (tr.rresp.size() > 0 && tr.rresp[0] == svt_axi_transaction::OKAY) ?
                    UVM_IS_OK : UVM_NOT_OK;
      end
      else begin
        rw.kind = UVM_WRITE;
        rw.data = (tr.data.size() > 0) ? tr.data[0] : '0;
        rw.status = (tr.bresp == svt_axi_transaction::OKAY) ? UVM_IS_OK : UVM_NOT_OK;
      end
    endfunction
  endclass
endpackage
