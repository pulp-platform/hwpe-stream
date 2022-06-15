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
#(
  parameter int unsigned FIFO_DEPTH = 2
)
(
  input logic clk_i,
  input logic rst_ni,
  input logic test_mode_i,
  input logic clear_i,

  // controller side
  input  ctrl_sourcesink_t   controller_ctrl_i,
  input  logic               controller_ctrl_valid_i,
  output logic               controller_ctrl_ready_o,
  output flags_sourcesink_t  controller_flags_o,
  output logic               controller_flags_valid_o,
  input  logic               controller_flags_ready_i,

  // streamer side
  output ctrl_sourcesink_t   streamer_ctrl_o,
  output logic               streamer_ctrl_valid_o,
  input  logic               streamer_ctrl_ready_i,
  input  flags_sourcesink_t  streamer_flags_i,
  input  logic               streamer_flags_valid_i,
  output logic               streamer_flags_ready_o
);

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( $bits(ctrl_sourcesink_t) )
  ) ctrl_push (
    .clk ( clk_i )
  );

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( $bits(ctrl_sourcesink_t) )
  ) ctrl_pop (
    .clk ( clk_i )
  );

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( $bits(flags_sourcesink_t) )
  ) flags_push (
    .clk ( clk_i )
  );

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( $bits(flags_sourcesink_t) )
  ) flags_pop (
    .clk ( clk_i )
  );

  hwpe_stream_fifo #(
    .DATA_WIDTH ( $bits(ctrl_sourcesink_t) ),
    .FIFO_DEPTH ( FIFO_DEPTH               )
  ) i_ctrl_fifo (
    .clk_i   ( clk_i     ),
    .rst_ni  ( rst_ni    ),
    .clear_i ( clear_i   ),
    .flags_o (           ),
    .push_i  ( ctrl_push ),
    .pop_o   ( ctrl_pop  )
  );
  assign ctrl_push.valid = controller_ctrl_valid_i;
  assign ctrl_push.data  = controller_ctrl_i;
  assign ctrl_push.strb  = '1;
  assign streamer_ctrl_valid_o = ctrl_pop.valid;
  assign streamer_ctrl_o  = ctrl_pop.data;
  assign ctrl_pop.ready = streamer_ctrl_ready_i;

  hwpe_stream_fifo #(
    .DATA_WIDTH ( $bits(flags_sourcesink_t) ),
    .FIFO_DEPTH ( FIFO_DEPTH                )
  ) i_flags_fifo (
    .clk_i   ( clk_i      ),
    .rst_ni  ( rst_ni     ),
    .clear_i ( clear_i    ),
    .flags_o (            ),
    .push_i  ( flags_push ),
    .pop_o   ( flags_pop  )
  );
  assign flags_push.valid = streamer_flags_valid_i;
  assign flags_push.data  = streamer_flags_i;
  assign flags_push.strb  = '1;
  assign controller_flags_valid_o = flags_pop.valid;
  assign controller_flags_o       = flags_pop.data;
  assign flags_pop.ready = controller_flags_ready_i;

endmodule // hwpe_stream_streamer_queue
