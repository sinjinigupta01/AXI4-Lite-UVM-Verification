# AXI4-Lite UVM Verification

A SystemVerilog AXI4-Lite register peripheral and a self-checking UVM testbench.
The regression runs with Docker, Verilator 5.054, and Accellera UVM 2020.3.1.

## Register map

| Byte address | Register | Access | Reset |
| --- | --- | --- | --- |
| `0x00` | REG0 | Read/write | `0x00000000` |
| `0x04` | REG1 | Read/write | `0x00000000` |
| `0x08` | REG2 | Read/write | `0x00000000` |
| `0x0C` | REG3 | Read/write | `0x00000000` |

The slave accepts write addresses and write data independently, in either order
or in the same cycle. It allows one outstanding write and one outstanding read.
Each asserted `WSTRB` bit updates one byte. A zero strobe leaves the register
unchanged and returns `OKAY`. Misaligned or unmapped addresses return
`SLVERR`, with zero read data and no register updates. A read accepted on the
same edge as a write commits samples the old register value.

## Run the tests

With Git, Bash, and Docker on Linux, macOS, or WSL, run:

```sh
scripts/run-verification.sh smoke       # reset read, full-word write, readback
scripts/run-verification.sh regression  # extended test at seeds 1, 17, and 101
scripts/run-verification.sh             # smoke and regression
```

Compilation and test logs and per-run Verilator coverage databases are saved in
`build/logs/`. GitHub Actions uploads that directory as the `uvm-verification`
artifact. A run passes when the simulator exits successfully, the scoreboard
completes its checks, UVM reports zero errors and fatals, and the coverage
database exists. Extended tests also require every functional coverage
combination listed below.

## Verification plan

| Scenario | Check |
| --- | --- |
| Reset and register readback | Observe zero after reset. Compare reads against a byte-masked reference model. |
| Write channel independence | Exercise simultaneous, address-first, and data-first handshakes and observe which order actually occurred. |
| Byte writes | Exercise all 16 strobe masks, including no-op and full-word writes, and check the resulting data. |
| Invalid accesses | Check both read and write responses on misaligned and unmapped addresses. Check that the invalid writes leave the register model intact. |
| Backpressure | Hold off read and write response acceptance. Assertions check that valid and payloads stay stable until accepted. |
| Coverage | Require all mapped registers, both invalid-address categories on reads and writes, and all strobe masks. Cross observed response by stall for reads and observed channel order by response by stall for writes. |

The driver issues one operation at a time. The regression covers read-after-write
ordering and independent write handshakes. Concurrent read/write traffic and
reset during a transaction are outside its scope.

## Source layout

- `rtl/axi_lite_regs.sv` — register bank and AXI4-Lite channels
- `tb/axi_lite_if.sv` — interface and channel assertions
- `tb/axi_lite_pkg.sv` — transaction, sequences, driver, monitor, agent,
  scoreboard, coverage, environment, and tests
- `tb/tb_top.sv` — DUT hookup, clock, reset, and watchdog
- `scripts/run-verification.sh` — reproducible compilation and seeded runs
