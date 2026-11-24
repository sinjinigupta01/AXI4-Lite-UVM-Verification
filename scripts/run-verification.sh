#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

mode=${1:-all}
case "$mode" in
  smoke|regression|all) ;;
  *) printf 'Usage: %s [smoke|regression|all]\n' "$0" >&2; exit 2 ;;
esac

image=verilator/verilator:v5.054@sha256:da7845c38c2ab84133661a1b1e2d717d028fe0bc629cc06c77bb80571e610448
uvm_revision=78c06547a2a0a29b3dc9dcafae62b75b2ff61544
mkdir -p build/logs
if [[ ! -d build/uvm/.git ]]; then
  git clone --depth 1 --branch 2020.3.1 https://github.com/accellera-official/uvm-core.git build/uvm
fi
if [[ "$(git -C build/uvm rev-parse HEAD)" != "$uvm_revision" ]]; then
  printf 'Unexpected Accellera UVM revision in build/uvm\n' >&2
  exit 1
fi

container=(docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/src" -w /src)
"${container[@]}" -e CCACHE_DIR=/src/build/ccache \
  "$image" --binary --timing --assert --coverage -j "${BUILD_JOBS:-2}" \
  --top-module tb_top --Mdir build/obj --timescale 1ns/1ps -Wno-fatal \
  +define+UVM_NO_DPI +incdir+build/uvm/src build/uvm/src/uvm_pkg.sv \
  tb/axi_lite_if.sv rtl/axi_lite_regs.sv tb/axi_lite_pkg.sv tb/tb_top.sv \
  2>&1 | tee build/logs/compile.log

run_test() {
  local test=$1 seed=$2
  local prefix="build/logs/${test}_${seed}"
  rm -f "${prefix}.dat"
  "${container[@]}" --entrypoint /src/build/obj/Vtb_top "$image" \
    "+UVM_TESTNAME=$test" "+verilator+seed+$seed" "+verilator+coverage+file+${prefix}.dat" \
    2>&1 | tee "${prefix}.log"
  grep -Eq 'UVM_ERROR[[:space:]]*:[[:space:]]*0[[:space:]]*$' "${prefix}.log"
  grep -Eq 'UVM_FATAL[[:space:]]*:[[:space:]]*0[[:space:]]*$' "${prefix}.log"
  grep -Eq '\[CHECKED\] Checked [1-9][0-9]* reads and [1-9][0-9]* writes' "${prefix}.log"
  test -s "${prefix}.dat"
}

if [[ "$mode" != regression ]]; then
  run_test axi_smoke_test 1
fi
if [[ "$mode" != smoke ]]; then
  for seed in 1 17 101; do
    run_test axi_regression_test "$seed"
  done
fi
