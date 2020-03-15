/*
 * tb_hwpe_stream_addressgen_v2.sv
 * Francesco Conti <fconti@iis.ee.ethz.ch>
 *
 * Copyright (C) 2020 ETH Zurich, University of Bologna
 * All rights reserved.
 *
 * Unit testbench for hwpe_stream_addressgen_v2.
 */

timeunit 1ps;
timeprecision 1ps;

import hwpe_stream_package::*;

module tb_hwpe_stream_addressgen_v2;

  parameter int unsigned TRANS_CNT    = 16;
  parameter int unsigned CNT          = 10;

  // DUT signals
  logic clk_i;
  logic rst_ni;
  logic test_mode_i;
  logic enable_i;
  logic clear_i;
  ctrl_addressgen_v2_t ctrl_i;
  flags_addressgen_v2_t flags_o;

  // DUT interfaces
  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( 36 )
  ) addr_o (
    .clk ( clk_i )
  );

  // ATI timing parameters.
  localparam TCP = 1.0ns; // clock period, 1 GHz clock
  localparam TA  = 0.2ns; // application time
  localparam TT  = 0.8ns; // test time

  // Performs one entire clock cycle.
  task cycle;
    clk_i <= #(TCP/2) 0;
    clk_i <= #TCP 1;
    #TCP;
  endtask

  // The following task schedules the clock edges for the next cycle and
  // advances the simulation time to that cycles test time (localparam TT)
  // according to ATI timings.
  task cycle_start;
    clk_i <= #(TCP/2) 0;
    clk_i <= #TCP 1;
    #TT;
  endtask

  // The following task finishes a clock cycle previously started with
  // cycle_start by advancing the simulation time to the end of the cycle.
  task cycle_end;
    #(TCP-TT);
  endtask

  // DUT
  hwpe_stream_addressgen_v2 #(
    .TRANS_CNT    ( TRANS_CNT    ),
    .CNT          ( CNT          )
  ) i_dut (
    .clk_i       ( clk_i       ),
    .rst_ni      ( rst_ni      ),
    .test_mode_i ( test_mode_i ),
    .enable_i    ( enable_i    ),
    .clear_i     ( clear_i     ),
    .addr_o      ( addr_o      ),
    .ctrl_i      ( ctrl_i      ),
    .flags_o     ( flags_o     )
  );

  logic enable_rec;

  // addr_o receiver;
  tb_hwpe_stream_receiver #(
    .DATA_WIDTH ( 36  ),
    .PROB_STALL ( 0.2 ),
    .TCP        ( TCP ),
    .TA         ( TA  ),
    .TT         ( TT  )
  ) i_receiver_addr_o (
    .clk_i         ( clk_i       ),
    .force_ready_i ( 1'b0        ),
    .enable_i      ( enable_rec  ),
    .data_i        ( addr_o      )
  );

  initial
  begin : test_clock_reset_gen
    #(20*TCP);
    rst_ni <= #TA 1'b0;
    #(20*TCP);
    rst_ni <= #TA 1'b1;
    for (int i = 0; i < 10; i++)
      cycle();
    rst_ni <= #TA 1'b0;
    for (int i = 0; i < 10; i++)
      cycle();
    rst_ni <= #TA 1'b1;
    while(1) begin
      cycle();
    end
  end

  initial
  begin : test_driver
    enable_i      = '0;
    test_mode_i   = '0;
    clear_i       = '0;
    ctrl_i        = '0;
    enable_rec = 1'b0;
    // wait 80 cycles
    #(80*TCP);
    #(TCP);
    enable_rec = 1'b1;
    #(10*TCP);
    clear_i = 1'b1;
    #(TCP);
    clear_i = 1'b0;
    enable_i = 1'b1;
    ctrl_i.base_addr = 32'h80000;
    for(int i=0; i<100; i++) begin
      ctrl_i.word_length = 128;
      ctrl_i.word_stride = 4;
      ctrl_i.line_stride = -4;
      ctrl_i.line_length = 5;
      ctrl_i.feat_length = 10;
      do begin
        #(TCP);
      end while(~flags_o.done);
      #(TCP);
      clear_i = 1'b1;
      #(TCP);
      clear_i = 1'b0;
    end
    #(TCP);
  end

endmodule // tb_hwpe_stream_addressgen_v2
