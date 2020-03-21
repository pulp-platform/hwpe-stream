/*
 * hwpe_stream_addressgen_v2.sv
 * Francesco Conti <f.conti@unibo.it>
 *
 * Copyright (C) 2014-2020 ETH Zurich, University of Bologna
 * Copyright and related rights are licensed under the Solderpad Hardware
 * License, Version 0.51 (the "License"); you may not use this file except in
 * compliance with the License.  You may obtain a copy of the License at
 * http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
 * or agreed to in writing, software, hardware and materials distributed under
 * this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations under the License.
 */

import hwpe_stream_package::*;

module hwpe_stream_addressgen_v2
#(
  parameter int unsigned TRANS_CNT    = 16,
  parameter int unsigned CNT          = 10 // number of bits used within the internal counter
)
(
  // global signals
  input  logic                   clk_i,
  input  logic                   rst_ni,
  input  logic                   test_mode_i,
  // local enable and clear
  input  logic                   enable_i,
  input  logic                   clear_i,
  input  logic                   presample_i,
  // generated output address
  hwpe_stream_intf_stream.source addr_o,
  // control channel
  input  ctrl_addressgen_v2_t    ctrl_i,
  output flags_addressgen_v2_t   flags_o
);

  logic        [31:0] base_addr;
  logic        [31:0] word_length_m1;
  logic        [31:0] word_length;
  logic signed [31:0] word_stride;
  logic signed [31:0] line_stride;
  logic        [31:0] line_length;

  logic        misalignment;
  logic        misalignment_first;
  logic        misalignment_last;
  logic [31:0] gen_addr_int;
  logic        done;

  logic [TRANS_CNT-1:0] overall_counter_d;
  logic [CNT-1:0]       word_counter_d;
  logic [CNT-1:0]       line_counter_d;
  logic [31:0]          word_addr_d;
  logic [31:0]          line_addr_d;
  logic [TRANS_CNT-1:0] overall_counter_q;
  logic [CNT-1:0]       word_counter_q;
  logic [CNT-1:0]       line_counter_q;
  logic [31:0]          word_addr_q;
  logic [31:0]          line_addr_q;

  logic        addr_valid_d, addr_valid_q;
  logic [35:0] addr_data;

  logic [3:0] gen_strb_int;

  assign base_addr       = ctrl_i.base_addr;
  assign word_stride     = $signed(ctrl_i.word_stride);
  assign word_length_m1  = (misalignment == 1'b0) ? ctrl_i.word_length - 1 :
                                                    ctrl_i.word_length;
  assign word_length     = (misalignment == 1'b0) ? ctrl_i.word_length :
                                                    ctrl_i.word_length + 1;
  assign line_stride     = $signed(ctrl_i.line_stride);
  assign line_length     = (misalignment == 1'b0) ? ctrl_i.line_length :
                                                    ctrl_i.line_length + 1;

  // misalignment flags generation
  always_comb
  begin : misalignment_last_flags_comb
    if(word_counter_q < line_length) begin
      misalignment_last  = '0;
    end
    else begin
      misalignment_last  = '1;
    end
  end

  always_comb
  begin : misalignment_first_flags_comb
    misalignment_first  = '0;
    if(word_counter_q == 1)
      misalignment_first  = '1;
  end

  // address generation
  always_comb
  begin : address_gen_counters_comb
    word_addr_d       = word_addr_q;
    line_addr_d       = line_addr_q;
    word_counter_d    = word_counter_q;
    line_counter_d    = line_counter_q;
    overall_counter_d = overall_counter_q;
    addr_valid_d      = addr_valid_q;
    done = '0;
    if(addr_o.ready) begin
      if(overall_counter_q < word_length) begin
        addr_valid_d = 1'b1;
        if(word_counter_q < line_length) begin
          word_addr_d    = word_addr_q + word_stride;
          word_counter_d = word_counter_q + 1;
        end
        else begin
          word_addr_d    = '0;
          line_addr_d    = line_addr_q + line_stride;
          word_counter_d = 1;
          line_counter_d = line_counter_q + 1;
        end
        /* ignore one transaction for the overall counter when there is a misalignment */
        if(~misalignment | ~misalignment_first) begin
          overall_counter_d = overall_counter_q + 1;
        end
      end
      else begin
        addr_valid_d = 1'b0;
        done = 1'b1;
      end
    end
  end

  // address generation
  always_ff @(posedge clk_i or negedge rst_ni)
  begin : address_gen_counters_word_ff
    if (~rst_ni) begin
      word_addr_q <= '0;
    end
    else if (clear_i) begin
      word_addr_q <= '0;
    end
    else if (presample_i) begin
      word_addr_q <= '0;
    end
    else if (enable_i) begin
      word_addr_q <= word_addr_d;
    end
  end
  
  always_ff @(posedge clk_i or negedge rst_ni)
  begin : address_gen_counters_ff
    if (~rst_ni) begin
      line_addr_q       <= '0;
      word_counter_q    <= '0;
      line_counter_q    <= '0;
      overall_counter_q <= '0;
      addr_valid_q      <= '0;
    end
    else if (clear_i) begin
      line_addr_q       <= '0;
      word_counter_q    <= '0;
      line_counter_q    <= '0;
      overall_counter_q <= '0;
      addr_valid_q      <= '0;
    end
    else if(enable_i) begin
      line_addr_q       <= line_addr_d;
      word_counter_q    <= word_counter_d;
      line_counter_q    <= line_counter_d;
      overall_counter_q <= overall_counter_d;
      addr_valid_q      <= addr_valid_d;
    end
  end

  assign gen_addr_int = base_addr + line_addr_q + word_addr_q;

  /* management of misaligned addresses */
  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni)
      misalignment <= 1'b0;
    else if(clear_i)
      misalignment <= 1'b0;
    else begin
      misalignment <= (base_addr   [1:0] != '0) ? 1'b1 :
                      (line_stride [1:0] != '0) ? 1'b1 : 1'b0;
    end
  end

  always_comb
  begin
    gen_strb_int = '1;
    if(misalignment) begin
      if (misalignment_first) begin
        gen_strb_int =   gen_strb_int << gen_addr_int[1:0];
      end
      if (misalignment_last) begin
        gen_strb_int = ~(gen_strb_int << gen_addr_int[1:0]);
      end
    end
  end

  assign addr_data = { 3'b0, misalignment, misalignment_first, misalignment_last, gen_addr_int[31:2] }; // data also includes flags

  assign addr_o.data  = addr_data;
  assign addr_o.strb  = gen_strb_int;
  assign addr_o.valid = addr_valid_q;

  assign flags_o.done = done;

endmodule // hwpe_stream_addressgen_v2
