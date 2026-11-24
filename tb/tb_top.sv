module tb_top;
  timeunit 1ns;
  timeprecision 1ps;
  import uvm_pkg::*;
  import axi_lite_pkg::*;

  bit clk;
  always #5 clk = ~clk;
  axi_lite_if bus(clk);

  axi_lite_regs dut (
    .clk, .rst_n(bus.rst_n),
    .awaddr(bus.awaddr), .awvalid(bus.awvalid), .awready(bus.awready),
    .wdata(bus.wdata), .wstrb(bus.wstrb), .wvalid(bus.wvalid), .wready(bus.wready),
    .bresp(bus.bresp), .bvalid(bus.bvalid), .bready(bus.bready),
    .araddr(bus.araddr), .arvalid(bus.arvalid), .arready(bus.arready),
    .rdata(bus.rdata), .rresp(bus.rresp), .rvalid(bus.rvalid), .rready(bus.rready)
  );

  initial begin
    bus.rst_n = 0;
    repeat (3) @(negedge clk);
    bus.rst_n = 1;
  end

  initial begin
    uvm_config_db#(virtual axi_lite_if)::set(null, "*", "bus", bus);
    run_test();
  end

  initial begin
    #100us;
    $fatal(1, "Simulation watchdog expired");
  end
endmodule
