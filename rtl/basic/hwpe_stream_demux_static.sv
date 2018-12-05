/* 
 * hwpe_stream_demux_static.sv
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
 *
 * The TCDM static multiplexer is used in place of the dynamic one
 * when two sets of ports are guaranteed to be used in a strictly
 * alternative fashion.
 */

import hwpe_stream_package::*;

module hwpe_stream_demux_static
#(
  parameter int unsigned NB_OUT_STREAMS = 2
)
(
  input  logic                              clk_i,
  input  logic                              rst_ni,
  input  logic                              clear_i,

  input  logic [$clog2(NB_OUT_STREAMS)-1:0] sel_i,

  hwpe_stream_intf_stream.sink   push_i,
  hwpe_stream_intf_stream.source pop_o [NB_OUT_STREAMS-1:0]
);

  logic [NB_OUT_STREAMS-1:0] out_ready;

  generate
    for(genvar i=0; i<NB_OUT_STREAMS; i++) begin : tcdm_binding

      // tcdm ports binding
      assign pop_o[i].valid = push_i.valid & (sel_i == i);
      assign pop_o[i].data  = push_i.data;
      assign pop_o[i].strb  = push_i.strb;
      assign out_ready[i] = pop_o[i].ready;

    end
  endgenerate

  assign push_i.ready = out_ready[sel_i];

endmodule // hwpe_stream_demux_static
