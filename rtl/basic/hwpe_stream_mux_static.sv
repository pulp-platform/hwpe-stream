/* 
 * hwpe_stream_mux_static.sv
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

module hwpe_stream_mux_static
(
  input  logic                   clk_i,
  input  logic                   rst_ni,
  input  logic                   clear_i,

  input  logic                   sel_i,

  hwpe_stream_intf_stream.sink   push_0_i,
  hwpe_stream_intf_stream.sink   push_1_i,
  hwpe_stream_intf_stream.source pop_o
);

  // tcdm ports binding
  assign pop_o.valid = (sel_i) ? push_1_i.valid : push_0_i.valid;
  assign pop_o.data  = (sel_i) ? push_1_i.data  : push_0_i.data;
  assign pop_o.strb  = (sel_i) ? push_1_i.strb  : push_0_i.strb;
  assign push_0_i.ready = (sel_i) ? 1'b0      : pop_o.ready;
  assign push_1_i.ready = (sel_i) ? pop_o.ready : 1'b0;

endmodule // hwpe_stream_mux_static
