#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

SEED="${SEED:-1}"
RUN_TIME="${RUN_TIME:-1us}"
VERB="${VERB:-UVM_MEDIUM}"
TB_TOP="${TB_TOP:-top_tb}"
FILELIST="${FILELIST:-./filelist.f}"
BUILD_NAME="${BUILD_NAME:-default}"
COV="${COV:-1}"
MERGED_COV_DIR="${MERGED_COV_DIR:-sim/merged_cov.vdb}"
MERGED_COV_REPORT_DIR="${MERGED_COV_REPORT_DIR:-sim/merged_cov_report}"

directed_tests=(
  tensor_base_reg_rw_test
  tensor_base_int8_4x4_test
  tensor_base_int16_4x4_test
  tensor_base_int16_max_stress_test
  tensor_base_burst_len_test
  tensor_base_axi_ready_delay_test
  tensor_base_back_to_back_test
  tensor_base_bb_precision_switch_test
  tensor_base_write_unaligned_test
  tensor_base_irq_test
  tensor_base_ro_reg_protection_test
  tensor_base_8x8_test
  tensor_base_16x16_test
  tensor_base_32x32_test
  tensor_base_64x64_test
  tensor_base_rect_matrix_test
  tensor_base_non_aligned_size_test
  tensor_base_degenerate_dims_test
  tensor_base_bias_test
  tensor_base_relu_test
  tensor_base_bias_relu_order_test
  tensor_base_saturation_test
  tensor_base_overflow_status_test
  tensor_base_partial_k_postop_isolation_test
)

exception_tests=(
  tensor_err_illegal_matrix_size_test
  tensor_err_illegal_precision_test
  tensor_err_unaligned_base_test
  tensor_err_clear_error_recovery_test
  tensor_err_axi_read_slverr_test
  tensor_err_axi_read_bias_error_test
  tensor_err_axi_write_slverr_test
  tensor_err_axi_write_mid_row_error_test
  tensor_err_command_while_busy_test
  tensor_err_start_while_done_test
  tensor_err_burst_len_zero_test
  tensor_err_burst_len_exceed_test
  tensor_err_internal_timeout_test
  tensor_reset_during_load_test
  tensor_reset_during_compute_test
  tensor_reset_during_store_test
  tensor_soft_reset_test
  tensor_soft_reset_during_idle_test
  tensor_err_irq_on_error_test
)

random_tests=(
  tensor_base_random_legal_test
  tensor_base_random_corner_data_test
  tensor_base_random_max_stress_test
)

random_seeds=("${SEED}" "$((SEED + 1))" "$((SEED + 2))")

total=0
passed=0
failed=0

run_case() {
  local test_name="$1"
  local seed="$2"
  local extra_user_sim_opts="${3:-}"
  local run_dir="sim/run/${test_name}_seed_${seed}"
  local run_log="sim/run/${test_name}_seed_${seed}/log/run.log"
  local make_log="sim/run/${test_name}_seed_${seed}/log/make.log"
  local make_status=0
  local result="FAIL"

  total=$((total + 1))
  mkdir -p "${run_dir}/log"

  set +e
  make run \
    TESTNAME="${test_name}" \
    SEED="${seed}" \
    RUN_TIME="${RUN_TIME}" \
    VERB="${VERB}" \
    TB_TOP="${TB_TOP}" \
    FILELIST="${FILELIST}" \
    BUILD_NAME="${BUILD_NAME}" \
    COV="${COV}" \
    USER_SIM_OPTS="${extra_user_sim_opts}" >"${make_log}" 2>&1
  make_status=$?
  set -e

  if [[ -f "${run_log}" ]]; then
    if grep -Eq "UVM_TEST_RESULT[[:space:]]*:[[:space:]]*'PASSED'|\\[TEST_RESULT\\].*PASSED" "${run_log}"; then
      result="PASS"
    elif grep -Eq "UVM_TEST_RESULT[[:space:]]*:[[:space:]]*'FAILED'|\\[TEST_RESULT\\].*FAILED" "${run_log}"; then
      result="FAIL"
    elif [[ "${make_status}" -eq 0 ]]; then
      result="FAIL"
    fi
  fi

  if [[ "${make_status}" -ne 0 ]]; then
    result="FAIL"
  fi

  if [[ "${result}" == "PASS" ]]; then
    passed=$((passed + 1))
    printf '[PASS]  %s  [seed=%s]\n' "${test_name}" "${seed}"
  else
    failed=$((failed + 1))
    printf '[FAIL]  %s  [seed=%s]\n' "${test_name}" "${seed}"
  fi
}

echo "Starting regression"
echo "BUILD_NAME=${BUILD_NAME} RUN_TIME=${RUN_TIME} VERB=${VERB} TB_TOP=${TB_TOP} FILELIST=${FILELIST} COV=${COV}"

echo "== elaboration =="
make elab \
  TB_TOP="${TB_TOP}" \
  FILELIST="${FILELIST}" \
  BUILD_NAME="${BUILD_NAME}" \
  COV="${COV}"

echo "== directed_tests =="
for test_name in "${directed_tests[@]}"; do
  run_case "${test_name}" "${SEED}"
done

echo "== exception_tests =="
for test_name in "${exception_tests[@]}"; do
  run_case "${test_name}" "${SEED}"
done

echo "== random_tests =="
for test_name in "${random_tests[@]}"; do
  for seed in "${random_seeds[@]}"; do
    run_case "${test_name}" "${seed}" "+RAND_ITERS=5"
  done
done

if [[ "${total}" -eq 0 ]]; then
  pass_rate="0.00"
else
  pass_rate=$(awk -v passed="${passed}" -v total="${total}" 'BEGIN { printf "%.2f", (passed * 100.0) / total }')
fi

echo "== summary =="
printf 'total=%d passed=%d failed=%d pass_rate=%s%%\n' "${total}" "${passed}" "${failed}" "${pass_rate}"

echo "== coverage merge =="
if [[ "${COV}" != "0" ]]; then
  make merge_cov \
    BUILD_NAME="${BUILD_NAME}" \
    MERGED_COV_DIR="${MERGED_COV_DIR}" \
    MERGED_COV_REPORT_DIR="${MERGED_COV_REPORT_DIR}"
  echo "Merged coverage database: ${MERGED_COV_DIR}"
  echo "Merged coverage report: ${MERGED_COV_REPORT_DIR}"
else
  echo "Coverage disabled; skipping merge."
fi

if [[ "${failed}" -ne 0 ]]; then
  exit 1
fi
