/* 
 * tb_hwpe_stream_source_realign_decoupled.sv
 * Francesco Conti <fconti@iis.ee.ethz.ch>
 *
 * Copyright (C) 2014-2018 ETH Zurich, University of Bologna
 * Copyright and related rights are licensed under the Solderpad Hardware
 * License, Version 0.51 (the "License"); you may not use this file except in
 * compliance with the License.  You may obtain a copy of the License at
 * http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
 * or agreed to in writing, software, hardware and materials distributed under
 * this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations under the License.
 *
 * This is a unit test for the hwpe stream sink realign module
 */

timeunit 1ns;
timeprecision 1ps;

import hwpe_stream_package::*;

module tb_hwpe_stream_source_realign_decoupled;

  // parameters
  parameter PROB_STALL_SOURCE = 0.05;
  parameter PROB_STALL_SINK   = 0.05;
  parameter DS = 32;
  parameter DECOUPLED = 1;
  parameter STRB_FIFO_DEPTH = 64;

  parameter LENGTH = 1;

  // global signals
  logic clk_i  = '0;
  logic rst_ni = '1;
  logic test_mode_i = '0;

  logic randomize = '0;
  logic enable = '0;
  logic enable_reservoir = '0;
  ctrl_realign_t ctrl, delayed_ctrl;
  flags_realign_t flags;
  logic [DS/8-1:0] strb;
  logic force_invalid;
  logic force_valid;
  logic real_last;
  logic real_last_out;

  int unsigned rotation = 0;
  logic new_rotation;
  int unsigned verif_ctr_in;
  int unsigned verif_ctr_out;
  logic [DS*DS-1:0] verif_vector_in;
  logic [DS*DS-1:0] verif_vector_out;
  logic [DS*DS-1:0] next_verif_vector_in;
  logic [DS*DS-1:0] next_verif_vector_out;
  
  logic[DS/8-1:0] gen_strb;

  logic clk_delayed, clk_assert;
  
  hwpe_stream_intf_stream #(
    .DATA_WIDTH(DS)
  ) in (
    .clk ( clk_i )
  );
  hwpe_stream_intf_stream #(
    .DATA_WIDTH(DS)
  ) fifo (
    .clk ( clk_i )
  );
  hwpe_stream_intf_stream #(
    .DATA_WIDTH(DS)
  ) out (
    .clk ( clk_i )
  );

  // ATI timing parameters.
  localparam TCP = 1.0ns; // clock period, 1 GHz clock
  localparam TA  = 0.1ns; // application time
  localparam TT  = 0.9ns; // test time

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

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni)
      delayed_ctrl <= '0;
    else
      delayed_ctrl <= ctrl;
  end

  tb_hwpe_stream_reservoir #(
    .REALIGN_TYPE ( HWPE_STREAM_REALIGN_SOURCE ),
    .DATA_WIDTH   ( DS                         ),
    .PROB_STALL   ( PROB_STALL_SOURCE          ),
    .TCP          ( TCP                        ),
    .TA           ( TA                         ),
    .TT           ( TT                         )
  ) i_reservoir (
    .clk_i           ( clk_i                                      ),
    .randomize_i     ( randomize                                  ),
    .rotation_i      ( rotation                                   ),
    .new_rotation_i  ( new_rotation                               ),
    .force_invalid_i ( force_invalid                              ),
    .force_valid_i   ( force_valid                                ),
    .enable_i        ( enable & (enable_reservoir | ctrl.realign) ),
    .data_o          ( in                                         )
  );

  hwpe_stream_source_realign #(
    .DATA_WIDTH      ( DS              ),
    .DECOUPLED       ( DECOUPLED       ),
    .STRB_FIFO_DEPTH ( STRB_FIFO_DEPTH )
  ) i_source_realign (
    .clk_i       ( clk_i        ),
    .rst_ni      ( rst_ni       ),
    .clear_i     ( 1'b0         ),
    .test_mode_i ( 1'b0         ),
    .ctrl_i      ( delayed_ctrl ),
    .flags_o     ( flags        ),
    .strb_i      ( gen_strb     ),
    .push_i      ( in           ),
    .pop_o       ( out          )
  );

  tb_hwpe_stream_receiver #(
    .DATA_WIDTH ( DS              ),
    .PROB_STALL ( PROB_STALL_SINK ),
    .TCP        ( TCP             ),
    .TA         ( TA              ),
    .TT         ( TT              )
  ) i_receiver (
    .clk_i         ( clk_i  ),
    .force_ready_i ( 1'b0   ),
    .enable_i      ( enable ),
    .data_i        ( out    )
  );

  initial begin
    #(20*TCP);

    force_invalid <= #TA '1;
    force_valid   <= #TA '0;

    // Reset phase.
    rst_ni <= #TA 1'b0;
    #(20*TCP);
    rst_ni <= #TA 1'b1;

    for (int i = 0; i < 10; i++)
      cycle();
    rst_ni <= #TA 1'b0;
    for (int i = 0; i < 10; i++)
      cycle();
    rst_ni <= #TA 1'b1;

    randomize <= #TA 1'b1;
    cycle();
    randomize <= #TA 1'b0;

    force_invalid <= #TA '0;
    force_valid   <= #TA '0;
    enable_reservoir <= #TA 1'b1;

    cycle();
    cycle();
    enable <= 1'b1;

    while(1) begin
      cycle();
    end

  end

  int counter = 0;
  int unsigned length   = 1;
  logic last_flag;

  int rotation_queue[$];
  int length_queue[$];
  int in_length_queue[$];
  logic [DS/8-1:0] strb_queue[$];

  always
  begin
    if(~rst_ni) begin
      while(rotation_queue.size() > 0)
        rotation_queue.delete(0);
      while(length_queue.size() > 0)
        length_queue.delete(0);
    end
    if(rotation_queue.size() < 16) begin
      rotation_queue.push_front($urandom_range(0, DS/8-1));
      length_queue.push_front(LENGTH);
    end
    #(TCP);
  end

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni) begin
      counter <= 0;
      ctrl <= '0;
      gen_strb <= '0;
      while(strb_queue.size() > 0)
        strb_queue.delete(0);
      while(in_length_queue.size() > 0)
        in_length_queue.delete(0);
    end
    else begin
      automatic int rotation = rotation_queue.pop_back();
      automatic int length = length_queue.pop_back();
      ctrl.enable <= 1'b1;
      if((counter == 0) && (rotation_queue.size() > 0) && flags.decoupled_stall == '0) begin
        ctrl.first       <= 1'b1;
        ctrl.last        <= 1'b0;
        ctrl.strb_valid  <= 1'b1;
        ctrl.line_length <= length;
        if(rotation != 0) begin
          ctrl.realign <= 1'b1;
          gen_strb <= '1 << rotation;
          strb_queue.push_front('1 << rotation);
          in_length_queue.push_front(length+1);
        end
        else begin
          ctrl.realign <= 1'b1;
          gen_strb <= '1;
          strb_queue.push_front('1);
          in_length_queue.push_front(length+1);
        end
        counter <= counter + 1;
      end
      else if(counter > 0 && counter < ctrl.line_length-1) begin
        counter <= counter + 1;
        ctrl.first       <= 1'b0;
        ctrl.last        <= 1'b0;
        ctrl.strb_valid  <= 1'b0;
      end
      else if(counter > 0 && counter == ctrl.line_length-1) begin
        counter <= 0;
        ctrl.first       <= 1'b0;
        ctrl.last        <= 1'b1;
        ctrl.strb_valid  <= 1'b1;
      end
      else begin
        counter <= 0;
        ctrl.first       <= 1'b0;
        ctrl.last        <= 1'b0;
        ctrl.strb_valid  <= 1'b0;
      end
    end
  end

  int in_counter;
  int in_length;
  logic [DS/8-1:0] in_strb;
  logic in_first;
  logic in_last;
  logic in_strb_valid;
  logic in_realign;
  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni) begin
      in_counter <= 0;
    end
    else begin
      if(in.valid & in.ready) begin
        if(in_counter == in_length-1) begin
          in_counter <= 0;
        end
        else begin
          in_counter <= in_counter + 1;
        end
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni) begin
      in_length <= '0;
      in_strb <= '1;
    end
    else begin
      if(in_length == '0) begin
        if(in_length_queue.size() > 0) begin
          in_length <= in_length_queue.pop_back();
          in_strb <= strb_queue.pop_back();
        end
      end
      if(in.valid & in.ready & in_counter == in_length-1) begin
        in_length <= in_length_queue.pop_back();
        in_strb <= strb_queue.pop_back();
      end
    end
  end

  assign in_first = (in_counter == 0) & in.valid & in.ready;
  assign in_last = (in_counter == in_length-1) & in.valid & in.ready;
  assign in_strb_valid = in_first | in_last;
  assign in_realign = in_length > LENGTH ? 1'b1 : 1'b0;
  assign real_last = (in_counter == in_length-1) & in.valid & in.ready;
  assign real_last_out = enable & i_source_realign.int_last & out.valid & out.ready;

  int unsigned strb_popcount;
  always_comb
  begin
    strb_popcount = 0;
    for(int i=0; i<DS/8; i++)
      strb_popcount += (in_strb[i] == 1'b1) ? 1 : 0;
  end

  logic [DS/8-1:0] save_strb;
  always_ff @(posedge clk_i)
  begin
    if(~enable) begin
      save_strb <= '0;
    end
    else if(in.valid & in.ready) begin
      if(in_first) begin
        save_strb <= ~in_strb;
      end
    end
  end


  logic [DS*DS-1:0] in_data_queue  [$];
  logic [DS*DS-1:0] out_data_queue [$];

  // sample monitored streams
  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni) begin
      while(in_data_queue.size() > 0)
        in_data_queue.delete(0);
      while(out_data_queue.size() > 0)
        out_data_queue.delete(0);
    end
    else begin
      if(in.valid & in.ready & real_last) begin
        in_data_queue.push_front(next_verif_vector_in);
      end
      if(out.valid & out.ready & real_last_out) begin
        out_data_queue.push_front(next_verif_vector_out);
      end
    end
  end

  int first_bit;

  always_comb
  begin
    first_bit = 0;
    next_verif_vector_in = verif_vector_in;
    if(in_first & in_realign) begin
      for(int i=0; i<DS/8; i++) begin
        if(in_strb[i] == 1'b1) begin
          first_bit = i*8;
          break;
        end
      end
      for(int i=0; i<DS*DS; i++)
        if ((i>=0) && (i<strb_popcount*8))
          next_verif_vector_in[i] = in.data[first_bit+i];
    end
    else if(in_last & in_realign) begin
      for(int i=0; i<DS*DS; i++)
        if ((i>=verif_ctr_in) && (i<verif_ctr_in+DS))
          next_verif_vector_in[i] = in.data[i-verif_ctr_in] & save_strb[(i-verif_ctr_in)/8];
    end
    else begin
      for(int i=0; i<DS*DS; i++)
        if ((i>=verif_ctr_in) && (i<verif_ctr_in+DS))
          next_verif_vector_in[i] = in.data[i-verif_ctr_in]; // assume "fully strobed" stream
    end
  end

  always_ff @(posedge clk_i)
  begin
    if(~enable | real_last) begin
      verif_vector_in <= '0;
      verif_ctr_in <= 0;
    end
    else if(in.valid & in.ready) begin
      if(in_first) begin
        verif_ctr_in <= verif_ctr_in + (DS-first_bit);
        verif_vector_in <= next_verif_vector_in;
      end
      else if(real_last) begin
        verif_ctr_in <= 0;
        verif_vector_in <= '0;
      end
      else begin
        verif_ctr_in <= verif_ctr_in + DS;
        verif_vector_in <= next_verif_vector_in;
      end
    end
  end

  always_comb
  begin
    next_verif_vector_out = verif_vector_out;
    for(int i=0; i<DS*DS; i++)
      if ((i>=verif_ctr_out) && (i<verif_ctr_out+DS))
        next_verif_vector_out[i] = out.data[i-verif_ctr_out];
  end
  always_ff @(posedge clk_i)
  begin
    if(~enable) begin
      verif_vector_out <= '0;
      verif_ctr_out <= 0;
    end
    else if(real_last_out) begin
      verif_ctr_out <= 0;
      verif_vector_out <= '0;
    end
    else if(out.valid & out.ready) begin
      verif_ctr_out <= verif_ctr_out + DS;
      verif_vector_out <= next_verif_vector_out;
    end
  end

  always @(clk_i)
  begin
    clk_delayed <= #(TT) clk_i;
  end
  
  always @(clk_i)
  begin
    clk_assert <= #(TA) clk_i;
  end

  logic check_valid, check_data;
  always_ff @(posedge clk_delayed)
  begin
    check_valid = '0;
    check_data = '0;
    if(in_data_queue.size() > 1 && out_data_queue.size() > 1) begin
      automatic logic [DS*DS-1:0] in_pop  = in_data_queue.pop_back();
      automatic logic [DS*DS-1:0] out_pop = out_data_queue.pop_back();
      check_valid = '1;
      if (in_pop == out_pop) begin
        check_data = '1;
        $display("%0x == %0x\n", in_pop, out_pop);
      end
      else
        $display("%0x != %0x\n", in_pop, out_pop);
    end
  end

  property check_data_assert;
    @(posedge clk_assert)
    (check_valid == 1'b1) |-> check_data == 1'b1;
  endproperty;

  DATA_WRONG: assert property(check_data_assert)
  else $fatal("ASSERTION FAILURE: DATA_WRONG", 1);

endmodule
