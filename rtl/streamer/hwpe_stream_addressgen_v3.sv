/*
 * hwpe_stream_addressgen_v3.sv
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

module hwpe_stream_addressgen_v3
#(
  parameter int unsigned TRANS_CNT  = 32,
  parameter int unsigned CNT        = 32  // number of bits used within the internal counter
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
  input  ctrl_addressgen_v3_t    ctrl_i,
  output flags_addressgen_v3_t   flags_o
);

  logic signed [31:0] d0_stride;
  logic signed [31:0] d1_stride;
  logic signed [31:0] d2_stride;

  logic [31:0] gen_addr_int;
  logic        done;

  logic [TRANS_CNT-1:0] overall_counter_d;
  logic [CNT-1:0]       d0_counter_d;
  logic [CNT-1:0]       d1_counter_d;
  logic [CNT-1:0]       d2_counter_d;
  logic [31:0]          d0_addr_d;
  logic [31:0]          d1_addr_d;
  logic [31:0]          d2_addr_d;
  logic [TRANS_CNT-1:0] overall_counter_q;
  logic [CNT-1:0]       d0_counter_q;
  logic [CNT-1:0]       d1_counter_q;
  logic [CNT-1:0]       d2_counter_q;
  logic [31:0]          d0_addr_q;
  logic [31:0]          d1_addr_q;
  logic [31:0]          d2_addr_q;

  logic        addr_valid_d, addr_valid_q;

  assign d0_stride   = $signed(ctrl_i.d0_stride);
  assign d1_stride   = $signed(ctrl_i.d1_stride);
  assign d2_stride   = $signed(ctrl_i.d2_stride);

  // address generation
  always_comb
  begin : address_gen_counters_comb
    d0_addr_d         = d0_addr_q;
    d1_addr_d         = d1_addr_q;
    d2_addr_d         = d2_addr_q;
    d0_counter_d      = d0_counter_q;
    d1_counter_d      = d1_counter_q;
    d2_counter_d      = d2_counter_q;
    overall_counter_d = overall_counter_q;
    addr_valid_d      = addr_valid_q;
    done = '0;
    if(addr_o.ready) begin
      if(overall_counter_q < ctrl_i.tot_len) begin
        addr_valid_d = 1'b1;
        if((d0_counter_q < ctrl_i.d0_len) || (ctrl_i.dim_enable_1h[0] == 1'b0)) begin
          d0_addr_d    = d0_addr_q + d0_stride;
          d0_counter_d = d0_counter_q + 1;
        end
        else if ((d1_counter_q < ctrl_i.d1_len) || (ctrl_i.dim_enable_1h[1] == 1'b0)) begin
          d0_addr_d    = '0;
          d1_addr_d    = d1_addr_q + d1_stride;
          d0_counter_d = 1;
          d1_counter_d = d1_counter_q + 1;
        end
        else begin
          d0_addr_d    = '0;
          d1_addr_d    = '0;
          d2_addr_d    = d2_addr_q + d2_stride;
          d0_counter_d = 1;
          d1_counter_d = 1;
          d2_counter_d = d2_counter_q + 1;
        end
        overall_counter_d = overall_counter_q + 1;
      end
      else begin
        addr_valid_d = 1'b0;
        done = 1'b1;
      end
    end
  end

  // address generation
  always_ff @(posedge clk_i or negedge rst_ni)
  begin : address_gen_counters_d0_ff
    if (~rst_ni) begin
      d0_addr_q <= '0;
    end
    else if (clear_i) begin
      d0_addr_q <= '0;
    end
    else if (presample_i) begin
      d0_addr_q <= '0;
    end
    else if (enable_i) begin
      d0_addr_q <= d0_addr_d;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni)
  begin : address_gen_counters_ff
    if (~rst_ni) begin
      d1_addr_q         <= '0;
      d2_addr_q         <= '0;
      d0_counter_q      <= '0;
      d1_counter_q      <= 1;
      d2_counter_q      <= 1;
      overall_counter_q <= '0;
      addr_valid_q      <= '0;
    end
    else if (clear_i) begin
      d1_addr_q         <= '0;
      d2_addr_q         <= '0;
      d0_counter_q      <= '0;
      d1_counter_q      <= 1;
      d2_counter_q      <= 1;
      overall_counter_q <= '0;
      addr_valid_q      <= '0;
    end
    else if(enable_i) begin
      d1_addr_q         <= d1_addr_d;
      d2_addr_q         <= d2_addr_d;
      d0_counter_q      <= d0_counter_d;
      d1_counter_q      <= d1_counter_d;
      d2_counter_q      <= d2_counter_d;
      overall_counter_q <= overall_counter_d;
      addr_valid_q      <= addr_valid_d;
    end
  end

  assign gen_addr_int = ctrl_i.base_addr + d2_addr_q + d1_addr_q + d0_addr_q;

  assign addr_o.data  = gen_addr_int;
  assign addr_o.strb  = '1;
  assign addr_o.valid = addr_valid_q;

  assign flags_o.done = done;

endmodule // hwpe_stream_addressgen_v3
