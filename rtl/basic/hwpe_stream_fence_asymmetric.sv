/*
 * hwpe_stream_fence_aymmetric.sv
 * Arpan Suravi Prasad <prasadar@iis.ee.ethz.ch>
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
 */

/**
 * The **hwpe_stream_fence_asymmetric** module is used to synchronize the handshake between
 * `NB_STREAMS` streams.
 * This is necessary, for example, when 2 asymmetric(different datawidth) streams are produced
 * from separate TCDM accesses and have to be joined into a single, wider
 * stream.
 *
 * .. _wavedrom_hwpe_stream_fence:
 * .. wavedrom:: wavedrom/hwpe_stream_fence.json
 *   :width: 85 %
 *   :caption: Example of **hwpe_stream_fence** operation.
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hwpe_stream_fence_params:
 * .. table:: **hwpe_stream_fence** design-time parameters.
 *
 *   +------------------+-------------+---------------------------------------------+
 *   | **Name**         | **Default** | **Description**                             |
 *   +------------------+-------------+---------------------------------------------+
 *   | *NB_STREAMS*     | 2           | Number of input/output HWPE-Stream streams. |
 *   +------------------+-------------+---------------------------------------------+
 *   | *DATA_WIDTH*     | 32          | Width of the HWPE-Stream streams.           |
 *   +------------------+-------------+---------------------------------------------+
 */

import hwpe_stream_package::*;

module hwpe_stream_fence_asymmetric #(
  localparam int unsigned NB_STREAMS   = 2,
  parameter int unsigned ELEM_WIDTH_0 = 32,
  parameter int unsigned ELEM_WIDTH_1 = 32,
  parameter int unsigned DATA_WIDTH_0 = 32,
  parameter int unsigned DATA_WIDTH_1 = 32
)
(
  input  logic clk_i,
  input  logic rst_ni,
  input  logic clear_i,
  input  logic bypass_i,

  hwpe_stream_intf_stream.sink   push_0_i,
  hwpe_stream_intf_stream.sink   push_1_i,
  hwpe_stream_intf_stream.source pop_0_o,
  hwpe_stream_intf_stream.source pop_1_o
);

  logic [NB_STREAMS-1:0]     in_valid;
  logic                      out_valid;
  logic [NB_STREAMS-1:0]     fence_state_q, fence_state_d;
  logic [DATA_WIDTH_0-1:0]   data_0_d, data_0_q;
  logic [DATA_WIDTH_1-1:0]   data_1_d, data_1_q;
  logic [DATA_WIDTH_0/ELEM_WIDTH_0-1:0] strb_0_d, strb_0_q;
  logic [DATA_WIDTH_1/ELEM_WIDTH_1-1:0] strb_1_d, strb_1_q;

  logic [NB_STREAMS-1:0] in_strm_hs, out_strm_hs;

  assign in_strm_hs[0] = push_0_i.ready & push_0_i.valid;
  assign in_strm_hs[1] = push_1_i.ready & push_1_i.valid;

  assign out_strm_hs[0] = pop_0_o.ready & pop_0_o.valid;
  assign out_strm_hs[1] = pop_1_o.ready & pop_1_o.valid;

  assign in_valid[0] = push_0_i.valid;
  assign in_valid[1] = push_1_i.valid;

  // Can take element if there is nothing registered or if registered there is a handshake 
  assign push_0_i.ready = ~fence_state_q[0] || fence_state_q[0] & out_strm_hs[0];
  assign push_1_i.ready = ~fence_state_q[1] || fence_state_q[1] & out_strm_hs[1];

  assign out_valid     = &( fence_state_q | in_valid);

  assign pop_0_o.valid = bypass_i ? push_0_i.valid | fence_state_q[0] : out_valid;
  assign pop_1_o.valid = bypass_i ? push_1_i.valid | fence_state_q[1] : out_valid;

  assign pop_0_o.data = fence_state_q[0] ? data_0_q: push_0_i.data;
  assign pop_1_o.data = fence_state_q[1] ? data_1_q: push_1_i.data;

  assign pop_0_o.strb = fence_state_q[0] ? strb_0_q: push_0_i.data;
  assign pop_1_o.strb = fence_state_q[1] ? strb_1_q: push_1_i.strb;

  always_comb begin
    fence_state_d[0] = fence_state_q[0];
    data_0_d = data_0_q;
    strb_0_d = strb_0_q;
    if(in_strm_hs[0] & out_strm_hs[0]) begin 
      fence_state_d[0] = fence_state_q[0];
      data_0_d = fence_state_q[0] ? push_0_i.data : data_0_q; 
      strb_0_d = fence_state_q[0] ? push_0_i.strb : strb_0_q; 
    end else if (in_strm_hs[0] & ~out_strm_hs[0]) begin 
      fence_state_d[0] = 1'b1;
      data_0_d = push_0_i.data; 
      strb_0_d = push_0_i.strb; 
    end else if (~in_strm_hs[0] & out_strm_hs[0]) begin
      fence_state_d[0] = 1'b0;
      data_0_d = '0; 
      strb_0_d = '0; 
    end 
  end 

  always_comb begin
    fence_state_d[1] = fence_state_q[1];
    data_1_d = data_1_q;
    strb_1_d = strb_1_q;
    if(in_strm_hs[1] & out_strm_hs[1]) begin 
      fence_state_d[1] = fence_state_q[1];
      data_1_d = fence_state_q[1] ? push_1_i.data : data_1_q; 
      strb_1_d = fence_state_q[1] ? push_1_i.strb : strb_1_q; 
    end else if (in_strm_hs[1] & ~out_strm_hs[1]) begin 
      fence_state_d[1] = 1'b1;
      data_1_d = push_1_i.data; 
      strb_1_d = push_1_i.strb; 
    end else if (~in_strm_hs[1] & out_strm_hs[1]) begin
      fence_state_d[1] = 1'b0;
      data_1_d = '0; 
      strb_1_d = '0; 
    end 
  end 

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni) begin 
      data_0_q <= '0;
      data_1_q <= '0;
      strb_0_q <= '0;
      strb_1_q <= '0;
    end else if(clear_i) begin 
      data_0_q <= '0;
      data_1_q <= '0;
      strb_0_q <= '0;
      strb_1_q <= '0;
    end else begin 
      data_0_q <= data_0_d;
      data_1_q <= data_1_d;
      strb_0_q <= strb_0_d;
      strb_1_q <= strb_1_d;
    end 
  end


  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni)
      fence_state_q <= '0;
    else if(clear_i)
      fence_state_q <= '0;
    else
      fence_state_q <= fence_state_d;
  end

endmodule // hwpe_stream_fence
