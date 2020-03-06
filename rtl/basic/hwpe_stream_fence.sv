/*
 * hwpe_stream_fence.sv
 * Francesco Conti <f.conti@unibo.it>
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
 * The **hwpe_stream_fence** module is used to synchronize the handshake between
 * `NB_STREAMS` streams.
 * This is necessary, for example, when multiple 32-bit streams are produced
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

module hwpe_stream_fence #(
  parameter int unsigned NB_STREAMS = 2,
  parameter int unsigned DATA_WIDTH = 32
)
(
  input  logic clk_i,
  input  logic rst_ni,
  input  logic clear_i,
  input  logic test_mode_i,

  hwpe_stream_intf_stream.sink   push_i [NB_STREAMS-1:0],
  hwpe_stream_intf_stream.source pop_o  [NB_STREAMS-1:0]
);

  logic [NB_STREAMS-1:0] in_valid;
  logic [NB_STREAMS-1:0] in_ready;
  logic                  out_valid;
  logic [NB_STREAMS-1:0] fence_state_q, fence_state_d;
  logic [NB_STREAMS-1:0][DATA_WIDTH-1:0]   data_q;
  logic [NB_STREAMS-1:0][DATA_WIDTH/8-1:0] strb_q;

  generate
    for(genvar ii=0; ii<NB_STREAMS; ii++) begin : binding

      assign in_valid[ii] = push_i[ii].valid;

      assign push_i[ii].ready = pop_o[ii].ready & ~fence_state_q[ii];

      assign pop_o[ii].valid = out_valid;
      assign pop_o[ii].data  = fence_state_q[ii] ? data_q[ii] : push_i[ii].data;
      assign pop_o[ii].strb  = fence_state_q[ii] ? strb_q[ii] : push_i[ii].strb;

      always_ff @(posedge clk_i or negedge rst_ni)
      begin
        if(~rst_ni)
          data_q[ii] <= '0;
        else if(clear_i)
          data_q[ii] <= '0;
        else if(in_valid[ii] && ~fence_state_q[ii])
          data_q[ii] <= push_i[ii].data;
      end

      always_ff @(posedge clk_i or negedge rst_ni)
      begin
        if(~rst_ni)
          strb_q[ii] <= '0;
        else if(clear_i)
          strb_q[ii] <= '0;
        else if(in_valid[ii] && ~fence_state_q[ii])
          strb_q[ii] <= push_i[ii].strb;
      end

    end
  endgenerate

  always_comb
  begin
    fence_state_d = '0;
    out_valid = 1'b0;
    if(&(in_valid | fence_state_q))
      out_valid = 1'b1;
    else
      fence_state_d = fence_state_q | in_valid;
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
