interface axi_lite_if(input logic clk);
  logic rst_n;
  logic [31:0] awaddr, wdata, araddr, rdata;
  logic [3:0] wstrb;
  logic [1:0] bresp, rresp;
  logic awvalid, awready, wvalid, wready, bvalid, bready;
  logic arvalid, arready, rvalid, rready;

  assert property (@(posedge clk) disable iff (!rst_n)
    bvalid && !bready |=> bvalid && $stable(bresp));
  assert property (@(posedge clk) disable iff (!rst_n)
    rvalid && !rready |=> rvalid && $stable({rresp, rdata}));
  assert property (@(posedge clk) disable iff (!rst_n)
    awvalid && !awready |=> awvalid && $stable(awaddr));
  assert property (@(posedge clk) disable iff (!rst_n)
    wvalid && !wready |=> wvalid && $stable({wdata, wstrb}));
  assert property (@(posedge clk) disable iff (!rst_n)
    arvalid && !arready |=> arvalid && $stable(araddr));
endinterface
