package axi_lite_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  typedef enum int {SAME_CYCLE, ADDRESS_FIRST, DATA_FIRST} write_order_t;

  class axi_item extends uvm_sequence_item;
    `uvm_object_utils(axi_item)
    bit write;
    bit [31:0] addr, data;
    bit [3:0] strb;
    bit [1:0] resp;
    write_order_t order;
    bit stalled;

    function new(string name = "axi_item");
      super.new(name);
    endfunction
  endclass

  class axi_driver extends uvm_driver #(axi_item);
    `uvm_component_utils(axi_driver)
    virtual axi_lite_if bus;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual axi_lite_if)::get(this, "", "bus", bus))
        `uvm_fatal("CONFIG", "Driver interface missing")
    endfunction

    task send_address(bit [31:0] address, int delay_cycles);
      repeat (delay_cycles) @(negedge bus.clk);
      bus.awaddr = address;
      bus.awvalid = 1;
      do @(posedge bus.clk); while (!bus.awready);
      @(negedge bus.clk);
      bus.awvalid = 0;
    endtask

    task send_data(bit [31:0] data, bit [3:0] strb, int delay_cycles);
      repeat (delay_cycles) @(negedge bus.clk);
      bus.wdata = data;
      bus.wstrb = strb;
      bus.wvalid = 1;
      do @(posedge bus.clk); while (!bus.wready);
      @(negedge bus.clk);
      bus.wvalid = 0;
    endtask

    task run_phase(uvm_phase phase);
      bus.awvalid = 0;
      bus.wvalid = 0;
      bus.arvalid = 0;
      bus.bready = 0;
      bus.rready = 0;
      wait (bus.rst_n);
      forever begin
        seq_item_port.get_next_item(req);
        @(negedge bus.clk);
        if (req.write) begin
          fork
            send_address(req.addr, req.order == DATA_FIRST ? 3 : 0);
            send_data(req.data, req.strb, req.order == ADDRESS_FIRST ? 3 : 0);
          join
          if (req.stalled) begin
            do @(posedge bus.clk); while (!bus.bvalid);
            repeat (2) @(negedge bus.clk);
          end
          bus.bready = 1;
          do @(posedge bus.clk); while (!bus.bvalid);
          @(negedge bus.clk);
          bus.bready = 0;
        end else begin
          bus.araddr = req.addr;
          bus.arvalid = 1;
          bus.rready = !req.stalled;
          do @(posedge bus.clk); while (!bus.arready);
          @(negedge bus.clk);
          bus.arvalid = 0;
          if (req.stalled) begin
            repeat (2) @(negedge bus.clk);
            bus.rready = 1;
          end
          do @(posedge bus.clk); while (!bus.rvalid);
          @(negedge bus.clk);
          bus.rready = 0;
        end
        seq_item_port.item_done();
      end
    endtask
  endclass

  class axi_monitor extends uvm_monitor;
    `uvm_component_utils(axi_monitor)
    virtual axi_lite_if bus;
    uvm_analysis_port #(axi_item) observed;
    axi_item pending_write, pending_read;
    bit saw_address, saw_data;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      observed = new("observed", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual axi_lite_if)::get(this, "", "bus", bus))
        `uvm_fatal("CONFIG", "Monitor interface missing")
    endfunction

    task run_phase(uvm_phase phase);
      forever begin
        @(posedge bus.clk);
        if (!bus.rst_n) begin
          pending_write = null;
          pending_read = null;
          saw_address = 0;
          saw_data = 0;
          continue;
        end

        if (bus.awvalid && bus.awready) begin
          if (pending_write == null)
            pending_write = axi_item::type_id::create("observed_write");
          pending_write.write = 1;
          pending_write.addr = bus.awaddr;
          if (saw_data)
            pending_write.order = DATA_FIRST;
          saw_address = 1;
        end
        if (bus.wvalid && bus.wready) begin
          if (pending_write == null)
            pending_write = axi_item::type_id::create("observed_write");
          pending_write.data = bus.wdata;
          pending_write.strb = bus.wstrb;
          if (saw_address && !(bus.awvalid && bus.awready))
            pending_write.order = ADDRESS_FIRST;
          saw_data = 1;
        end
        if (bus.bvalid) begin
          if (!saw_address || !saw_data)
            `uvm_fatal("PROTOCOL", "BVALID preceded accepted AW and W")
          if (bus.bready) begin
            pending_write.resp = bus.bresp;
            observed.write(pending_write);
            pending_write = null;
            saw_address = 0;
            saw_data = 0;
          end else begin
            pending_write.stalled = 1;
          end
        end

        if (bus.arvalid && bus.arready) begin
          pending_read = axi_item::type_id::create("observed_read");
          pending_read.addr = bus.araddr;
        end
        if (bus.rvalid) begin
          if (pending_read == null)
            `uvm_fatal("PROTOCOL", "RVALID preceded accepted AR")
          if (bus.rready) begin
            pending_read.data = bus.rdata;
            pending_read.resp = bus.rresp;
            observed.write(pending_read);
            pending_read = null;
          end else begin
            pending_read.stalled = 1;
          end
        end
      end
    endtask
  endclass

  class axi_agent extends uvm_agent;
    `uvm_component_utils(axi_agent)
    axi_driver driver;
    axi_monitor monitor;
    uvm_sequencer #(axi_item) sequencer;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      driver = axi_driver::type_id::create("driver", this);
      monitor = axi_monitor::type_id::create("monitor", this);
      sequencer = new("sequencer", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
  endclass

  class axi_scoreboard extends uvm_subscriber #(axi_item);
    `uvm_component_utils(axi_scoreboard)
    bit [31:0] model [4];
    int reads, writes;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void write(axi_item t);
      int index;
      bit legal;
      bit [1:0] expected_resp;
      bit [31:0] expected_data, mask;
      legal = t.addr inside {32'h0, 32'h4, 32'h8, 32'hc};
      index = int'(t.addr[3:2]);
      expected_resp = legal ? 2'b00 : 2'b10;
      if (t.resp !== expected_resp)
        `uvm_error("RESP", $sformatf("addr=%h write=%b expected=%b saw=%b",
                                    t.addr, t.write, expected_resp, t.resp))
      if (t.write) begin
        writes++;
        if (legal) begin
          mask = {{8{t.strb[3]}}, {8{t.strb[2]}}, {8{t.strb[1]}}, {8{t.strb[0]}}};
          model[index] = (model[index] & ~mask) | (t.data & mask);
        end
      end else begin
        reads++;
        expected_data = legal ? model[index] : 32'b0;
        if (t.data !== expected_data)
          `uvm_error("DATA", $sformatf("addr=%h expected=%h saw=%h",
                                      t.addr, expected_data, t.data))
      end
    endfunction
  endclass

  class axi_coverage extends uvm_subscriber #(axi_item);
    `uvm_component_utils(axi_coverage)
    int read_hits[2][2];
    int write_hits[3][2][2];
    int strobe_hits[16];
    bit [3:0] register_hits;
    bit misaligned_read, misaligned_write, unmapped_read, unmapped_write;

    covergroup reads_cg with function sample(bit error_response, bit stalled);
      response: coverpoint error_response;
      backpressure: coverpoint stalled;
      response_by_backpressure: cross response, backpressure;
    endgroup

    covergroup writes_cg with function sample(write_order_t order, bit error_response,
                                              bit stalled, bit [3:0] strb);
      channel_order: coverpoint order;
      response: coverpoint error_response;
      backpressure: coverpoint stalled;
      strobes: coverpoint strb;
      order_by_response_by_backpressure: cross channel_order, response, backpressure;
    endgroup

    function new(string name, uvm_component parent);
      super.new(name, parent);
      reads_cg = new();
      writes_cg = new();
    endfunction

    function void write(axi_item t);
      bit error_response;
      error_response = t.resp != 2'b00;
      if (!error_response)
        register_hits[t.addr[3:2]] = 1;
      if (t.write) begin
        write_hits[t.order][error_response][t.stalled]++;
        strobe_hits[t.strb]++;
        misaligned_write |= t.addr[1:0] != 0;
        unmapped_write |= t.addr >= 16;
        writes_cg.sample(t.order, error_response, t.stalled, t.strb);
      end else begin
        read_hits[error_response][t.stalled]++;
        misaligned_read |= t.addr[1:0] != 0;
        unmapped_read |= t.addr >= 16;
        reads_cg.sample(error_response, t.stalled);
      end
    endfunction

    function void check_regression();
      foreach (read_hits[response, stall])
        if (read_hits[response][stall] == 0)
          `uvm_error("COVERAGE", $sformatf("Missing read cross %0d/%0d", response, stall))
      foreach (write_hits[order, response, stall])
        if (write_hits[order][response][stall] == 0)
          `uvm_error("COVERAGE", $sformatf("Missing write cross %0d/%0d/%0d",
                                          order, response, stall))
      foreach (strobe_hits[mask])
        if (strobe_hits[mask] == 0)
          `uvm_error("COVERAGE", $sformatf("Missing strobe mask %h", mask))
      if (register_hits != 4'b1111 ||
          !(misaligned_read && misaligned_write && unmapped_read && unmapped_write))
        `uvm_error("COVERAGE", "Missing a register or an invalid address category")
      `uvm_info("COVERAGE", $sformatf("Read covergroup %.1f%%, write covergroup %.1f%%",
                                    reads_cg.get_inst_coverage(),
                                    writes_cg.get_inst_coverage()), UVM_LOW)
    endfunction
  endclass

  class axi_env extends uvm_env;
    `uvm_component_utils(axi_env)
    axi_agent agent;
    axi_scoreboard scoreboard;
    axi_coverage coverage_collector;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      agent = axi_agent::type_id::create("agent", this);
      scoreboard = axi_scoreboard::type_id::create("scoreboard", this);
      coverage_collector = axi_coverage::type_id::create("coverage_collector", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      agent.monitor.observed.connect(scoreboard.analysis_export);
      agent.monitor.observed.connect(coverage_collector.analysis_export);
    endfunction
  endclass

  class axi_sequence extends uvm_sequence #(axi_item);
    `uvm_object_utils(axi_sequence)
    bit extended_test;
    int expected_reads, expected_writes;

    function new(string name = "axi_sequence");
      super.new(name);
    endfunction

    task access_register(bit write, bit [31:0] addr, bit [31:0] data = 0,
                         bit [3:0] strb = 0, write_order_t order = SAME_CYCLE,
                         bit stall = 0);
      axi_item item;
      item = axi_item::type_id::create("request");
      start_item(item);
      item.write = write;
      item.addr = addr;
      item.data = data;
      item.strb = strb;
      item.order = order;
      item.stalled = stall;
      finish_item(item);
      if (write)
        expected_writes++;
      else
        expected_reads++;
    endtask

    task body();
      bit [31:0] address;
      access_register(0, 0);
      access_register(1, 0, 32'h1234_abcd, 4'hf);
      access_register(0, 0);
      if (!extended_test)
        return;

      for (int order = 0; order < 3; order++) begin
        for (int stall = 0; stall < 2; stall++) begin
          access_register(1, 4, 32'h1122_3344, 4'hf, write_order_t'(order), 1'(stall));
          access_register(0, 4, 0, 0, SAME_CYCLE, 1'(stall));
          access_register(1, 32'h10, '1, 4'hf, write_order_t'(order), 1'(stall));
          access_register(0, 32'h10, 0, 0, SAME_CYCLE, 1'(stall));
        end
      end
      access_register(1, 1, '1, 4'hf);
      access_register(0, 1);
      access_register(0, 0);
      for (int mask = 0; mask < 16; mask++) begin
        address = 4 * $urandom_range(3, 0);
        access_register(1, address, $urandom(), 4'(mask),
                        write_order_t'($urandom_range(2, 0)), 1'($urandom()));
        access_register(0, address, 0, 0, SAME_CYCLE, 1'($urandom()));
      end
      for (int iteration = 0; iteration < 60; iteration++) begin
        address = 4 * $urandom_range(4, 0);
        access_register(1, address, $urandom(), 4'($urandom()),
                        write_order_t'($urandom_range(2, 0)), 1'($urandom()));
        access_register(0, address, 0, 0, SAME_CYCLE, 1'($urandom()));
      end
      for (int index = 0; index < 4; index++)
        access_register(0, 4 * index);
    endtask
  endclass

  class axi_smoke_test extends uvm_test;
    `uvm_component_utils(axi_smoke_test)
    axi_env env;
    bit extended_test;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = axi_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
      axi_sequence stimulus;
      phase.raise_objection(this);
      stimulus = axi_sequence::type_id::create("stimulus");
      stimulus.extended_test = extended_test;
      stimulus.start(env.agent.sequencer);
      if (env.scoreboard.reads != stimulus.expected_reads ||
          env.scoreboard.writes != stimulus.expected_writes)
        `uvm_error("COUNT", "Scoreboard did not observe all planned responses")
      if (extended_test)
        env.coverage_collector.check_regression();
      `uvm_info("CHECKED", $sformatf("Checked %0d reads and %0d writes",
                                   env.scoreboard.reads, env.scoreboard.writes), UVM_LOW)
      phase.drop_objection(this);
    endtask
  endclass

  class axi_regression_test extends axi_smoke_test;
    `uvm_component_utils(axi_regression_test)

    function new(string name, uvm_component parent);
      super.new(name, parent);
      extended_test = 1;
    endfunction
  endclass
endpackage
