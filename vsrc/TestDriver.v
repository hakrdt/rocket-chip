// See LICENSE.SiFive for license details.

`ifndef RESET_DELAY
 `define RESET_DELAY 777.7
`endif

module TestDriver;

  parameter base = 32'h80000000;

  reg clock = 1'b0;
  reg reset = 1'b1;
  integer i, fd, first, last;

  reg [7:0] mem[32'h0:32'h1000000];

  always #(`CLOCK_PERIOD/2.0) clock = ~clock;
  initial #(`RESET_DELAY) reset = 0;

  // Read input arguments and initialize
  reg verbose = 1'b0;
  wire printf_cond = verbose && !reset;
  reg [63:0] max_cycles = 0;
  reg [63:0] dump_start = 0;
  reg [63:0] trace_count = 0;
  reg [1023:0] vcdplusfile = 0;
  reg [1023:0] vcdfile = 0;
  int unsigned rand_value;
  initial
    begin
    // JRRK hacks
        $readmemh("cnvmem.mem", mem);
        for (i = base; (i < base+32'h1000000) && (1'bx === ^mem[i-base]); i=i+8)
          ;
        first = i;
        for (i = base+32'h1000000; (i >= base) && (1'bx === ^mem[i-base]); i=i-8)
          ;
        last = (i+16);
        for (i = i+1; i < last; i=i+1)
          mem[i-base] = 0;
        $display("First = %X, Last = %X", first, last-1);
        for (i = first; i < last; i=i+1)
          if (1'bx === ^mem[i-base]) mem[i-base] = 0;
        #1
        for (i = first-base; i < last-base; i=i+8)
          begin
             testHarness.SimAXIMem.AXI4RAM.mem.mem_ext.ram[(i+base-32'h80000000)/8] =
                 {mem[i+7],mem[i+6],mem[i+5],mem[i+4],mem[i+3],mem[i+2],mem[i+1],mem[i+0]};
          end
        for (i = last-base; i < 4194304-base; i=i+8)
          testHarness.SimAXIMem.AXI4RAM.mem.mem_ext.ram[(i+base-32'h80000000)/8] = 64'b0;
    
    void'($value$plusargs("max-cycles=%d", max_cycles));
    void'($value$plusargs("dump-start=%d", dump_start));
    verbose = $test$plusargs("verbose");

    // do not delete the lines below.
    // $random function needs to be called with the seed once to affect all
    // the downstream $random functions within the Chisel-generated Verilog
    // code.
    // $urandom is seeded via cmdline (+ntb_random_seed in VCS) but that
    // doesn't seed $random.
    rand_value = $urandom;
    rand_value = $random(rand_value);
    if (verbose) begin
`ifdef VCS
      $fdisplay(stderr, "testing $random %0x seed %d", rand_value, unsigned'($get_initial_random_seed));
`else
      $fdisplay(stderr, "testing $random %0x", rand_value);
`endif
    end

`ifdef DEBUG

    if ($value$plusargs("vcdplusfile=%s", vcdplusfile))
    begin
`ifdef VCS
      $vcdplusfile(vcdplusfile);
`else
      $fdisplay(stderr, "Error: +vcdplusfile is VCS-only; use +vcdfile instead");
      $fatal;
`endif
    end

    if ($value$plusargs("vcdfile=%s", vcdfile))
    begin
      $dumpfile(vcdfile);
      $dumpvars(0, testHarness);
    end
`ifdef VCS
`define VCDPLUSON $vcdpluson(0); $vcdplusmemon(0);
`define VCDPLUSCLOSE $vcdplusclose; $dumpoff;
`else
`define VCDPLUSON $dumpon;
`define VCDPLUSCLOSE $dumpoff;
`endif
`else
  // No +define+DEBUG
`define VCDPLUSON
`define VCDPLUSCLOSE

    if ($test$plusargs("vcdplusfile=") || $test$plusargs("vcdfile="))
    begin
      $fdisplay(stderr, "Error: +vcdfile or +vcdplusfile requested but compile did not have +define+DEBUG enabled");
      $fatal;
    end

`endif
  end

`ifdef TESTBENCH_IN_UVM
  // UVM library has its own way to manage end-of-simulation.
  // A UVM-based testbench will raise an objection, watch this signal until this goes 1, then drop the objection.
  reg finish_request = 1'b0;
`endif
  reg [255:0] reason = "";
  reg failure = 1'b0;
  wire success;
  integer stderr = 32'h80000002;
  always @(posedge clock)
  begin
`ifdef GATE_LEVEL
    if (verbose)
    begin
      $fdisplay(stderr, "C: %10d", trace_count);
    end
`endif
    if (trace_count == dump_start)
    begin
      `VCDPLUSON
    end

    trace_count = trace_count + 1;
    if (!reset)
    begin
      if (max_cycles > 0 && trace_count > max_cycles)
      begin
        reason = " (timeout)";
        failure = 1'b1;
      end

      if (failure)
      begin
        $fdisplay(stderr, "*** FAILED ***%s after %d simulation cycles", reason, trace_count);
        `VCDPLUSCLOSE
        $fatal;
      end

      if (success)
      begin
        if (verbose)
          $fdisplay(stderr, "Completed after %d simulation cycles", trace_count);
        `VCDPLUSCLOSE
`ifdef TESTBENCH_IN_UVM
        finish_request = 1;
`else
        $finish;
`endif
      end
    end
  end

  TestHarness testHarness(
    .clock(clock),
    .reset(reset),
    .io_success(success)
  );

endmodule
