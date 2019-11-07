/*
 * hwpe_stream_streamer_queue.sv
 * Francesco Conti <f.conti@unibo.it>
 *
 * Copyright (C) 2019 ETH Zurich, University of Bologna
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

module hwpe_stream_streamer_queue
(
  input logic clk_i,
  input logic rst_ni,
  input logic test_mode_i,
  input logic clear_i,

  // controller side
  input  ctrl_sourcesink_t   controller_ctrl_i,
  output flags_sourcesink_t  controller_flags_o,

  // streamer side
  output ctrl_sourcesink_t   streamer_ctrl_o,
  input  flags_sourcesink_t  streamer_flags_i
);

  logic [31:0] base_addr, base_addr_q;
  logic [31:0] trans_size, trans_size_q;

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni) begin
      base_addr_q  <= '0;
      trans_size_q <= '0;
    end
    else if(clear_i) begin
      base_addr_q  <= '0;
      trans_size_q <= '0;
    end
    else if(controller_ctrl_i.req_start) begin
      base_addr_q  <= controller_ctrl_i.addressgen_ctrl.base_addr;
      trans_size_q <= controller_ctrl_i.addressgen_ctrl.trans_size;
    end
  end

  always_comb
  begin
    streamer_ctrl_o = controller_ctrl_i;
    streamer_ctrl_o.addressgen_ctrl.base_addr   = controller_ctrl_i.req_start ? controller_ctrl_i.addressgen_ctrl.base_addr   : base_addr_q;
    streamer_ctrl_o.addressgen_ctrl.trans_size  = controller_ctrl_i.req_start ? controller_ctrl_i.addressgen_ctrl.trans_size  : trans_size_q;
    streamer_ctrl_o.addressgen_ctrl.line_length = controller_ctrl_i.req_start ? controller_ctrl_i.addressgen_ctrl.line_length : trans_size_q[15:0];
  end

  assign controller_flags_o = streamer_flags_i;

endmodule // hwpe_stream_streamer_queue
