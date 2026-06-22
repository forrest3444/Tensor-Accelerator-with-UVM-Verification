`ifndef TENSOR_ACCEL_BACK_TO_BACK_VSEQ_SV
`define TENSOR_ACCEL_BACK_TO_BACK_VSEQ_SV

class tensor_back_to_back_vseq extends base_vseq;
  `uvm_object_utils(tensor_back_to_back_vseq)

  typedef struct {
    int unsigned m_size;
    int unsigned n_size;
    int unsigned k_size;
    bit [31:0] a_base;
    bit [31:0] b_base;
    bit [31:0] c_base;
  } task_cfg_t;

  function new(string name = "tensor_back_to_back_vseq");
    super.new(name);
  endfunction

  virtual task body();
    task_cfg_t tasks[$];

    tasks.push_back('{4,  4,  4,  32'h0001_0000, 32'h0002_0000, 32'h0003_0000});
    tasks.push_back('{8,  4,  6,  32'h0001_8000, 32'h0002_8000, 32'h0003_8000});
    tasks.push_back('{3,  7,  5,  32'h0001_4000, 32'h0002_4000, 32'h0003_4000});
    tasks.push_back('{16, 8,  4,  32'h0001_c000, 32'h0002_c000, 32'h0003_c000});

    foreach (tasks[idx]) begin
      tensor_matmul_vseq matmul_seq;

      matmul_seq = tensor_matmul_vseq::type_id::create($sformatf("matmul_task_%0d",
                                                                 idx));
      matmul_seq.m_size = tasks[idx].m_size;
      matmul_seq.n_size = tasks[idx].n_size;
      matmul_seq.k_size = tasks[idx].k_size;
      matmul_seq.precision = PREC_INT8;
      matmul_seq.post_op = POST_NONE;
      matmul_seq.sat_mode = SAT_WRAP;
      matmul_seq.a_base = tasks[idx].a_base;
      matmul_seq.b_base = tasks[idx].b_base;
      matmul_seq.c_base = tasks[idx].c_base;
      matmul_seq.burst_len = 8'd8;
      matmul_seq.timeout_cycles = 500000;
      matmul_seq.poll_interval_cycles = 1000;
      matmul_seq.start(p_sequencer);

      check_cleared_status(idx);
    end
  endtask

  virtual task check_cleared_status(int unsigned task_idx);
    uvm_reg_data_t status_data;
    uvm_reg_data_t error_data;
    uvm_reg_data_t ovf_count_data;

    ral_read(reg_model.STATUS, status_data);
    ral_read(reg_model.ERROR_CODE, error_data);
    ral_read(reg_model.OVF_COUNT, ovf_count_data);

    if ((status_data[31:0] &
         (STATUS_BUSY | STATUS_DONE | STATUS_ERROR | STATUS_IRQ |
          STATUS_OVERFLOW_SEEN)) != 0) begin
      `uvm_error(get_type_name(),
                 $sformatf("Task %0d retained stale STATUS=0x%08x after clear",
                           task_idx, status_data[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end else if (cfg != null) begin
      cfg.add_seq_check_count();
    end

    if (error_data[3:0] != ERR_NO_ERROR) begin
      `uvm_error(get_type_name(),
                 $sformatf("Task %0d retained ERROR_CODE=0x%08x after clear",
                           task_idx, error_data[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end else if (cfg != null) begin
      cfg.add_seq_check_count();
    end

    if (ovf_count_data[31:0] != 32'd0) begin
      `uvm_error(get_type_name(),
                 $sformatf("Task %0d unexpected OVF_COUNT=%0d for legal non-overflow task",
                           task_idx, ovf_count_data[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end else if (cfg != null) begin
      cfg.add_seq_check_count();
    end
  endtask
endclass

`endif
