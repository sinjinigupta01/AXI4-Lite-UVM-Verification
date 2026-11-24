module axi_lite_regs (
  input  logic        clk, rst_n,
  input  logic [31:0] awaddr, wdata, araddr,
  input  logic [3:0]  wstrb,
  input  logic        awvalid, wvalid, arvalid, bready, rready,
  output logic        awready, wready, arready, bvalid, rvalid,
  output logic [1:0]  bresp, rresp,
  output logic [31:0] rdata
);
  logic [31:0] registers [4];
  logic have_address, have_data;
  logic [31:0] address_buffer, data_buffer;
  logic [3:0] strobe_buffer;

  function automatic logic mapped(input logic [31:0] addr);
    return addr < 32'd16 && addr[1:0] == 2'b00;
  endfunction

  assign awready = rst_n && !have_address && !bvalid;
  assign wready = rst_n && !have_data && !bvalid;
  assign arready = rst_n && !rvalid;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      registers <= '{default: '0};
      have_address <= 0;
      have_data <= 0;
      address_buffer <= 0;
      data_buffer <= 0;
      strobe_buffer <= 0;
      bvalid <= 0;
      rvalid <= 0;
      bresp <= 0;
      rresp <= 0;
      rdata <= 0;
    end else begin
      if (awvalid && awready) begin
        have_address <= 1;
        address_buffer <= awaddr;
      end
      if (wvalid && wready) begin
        have_data <= 1;
        data_buffer <= wdata;
        strobe_buffer <= wstrb;
      end
      if (bvalid && bready)
        bvalid <= 0;
      if (have_address && have_data) begin
        have_address <= 0;
        have_data <= 0;
        bvalid <= 1;
        bresp <= mapped(address_buffer) ? 2'b00 : 2'b10;
        if (mapped(address_buffer))
          for (int lane = 0; lane < 4; lane++)
            if (strobe_buffer[lane])
              registers[address_buffer[3:2]][8*lane +: 8] <= data_buffer[8*lane +: 8];
      end

      if (rvalid && rready)
        rvalid <= 0;
      if (arvalid && arready) begin
        rvalid <= 1;
        rresp <= mapped(araddr) ? 2'b00 : 2'b10;
        rdata <= mapped(araddr) ? registers[araddr[3:2]] : 32'b0;
      end
    end
  end
endmodule
