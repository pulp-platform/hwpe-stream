/*
 * hwpe_stream_fifo_passthrough.sv
 * Francesco Conti <f.conti@unibo.it>
 *
 * Copyright (C) 2024 ETH Zurich, University of Bologna
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

module hwpe_stream_fifo_passthrough #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned FIFO_DEPTH = 8,
  parameter int unsigned LATCH_FIFO = 0,
  parameter int unsigned LATCH_FIFO_TEST_WRAP = 0
)
(
  input  logic                   clk_i,
  input  logic                   rst_ni,
  input  logic                   clear_i,

  output flags_fifo_t            flags_o,

  hwpe_stream_intf_stream.sink   push_i,
  hwpe_stream_intf_stream.source pop_o
);

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( DATA_WIDTH )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT ( 1'b1 ),
    .BYPASS_VDR_ASSERT ( 1'b1 )
`endif
  ) push (
    .clk ( clk_i )
  );

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( DATA_WIDTH )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT ( 1'b1 ),
    .BYPASS_VDR_ASSERT ( 1'b1 )
`endif
  ) pop (
    .clk ( clk_i )
  );

  logic passthrough;
  assign passthrough = push_i.valid & flags_o.empty;

  assign push.valid   = push_i.valid & ~passthrough;
  assign push.data    = push_i.data;
  assign push.strb    = push_i.strb;
  assign push_i.ready = passthrough ? pop_o.ready  : push.ready;

  assign pop_o.valid  = passthrough ? push_i.valid : pop.valid;
  assign pop_o.data   = passthrough ? push_i.data  : pop.data;
  assign pop_o.strb   = passthrough ? push_i.strb  : pop.strb;
  assign pop.ready    = pop_o.ready & ~passthrough;

  hwpe_stream_fifo #(
    .DATA_WIDTH           ( DATA_WIDTH           ),
    .FIFO_DEPTH           ( FIFO_DEPTH           ),
    .LATCH_FIFO           ( LATCH_FIFO           ),
    .LATCH_FIFO_TEST_WRAP ( LATCH_FIFO_TEST_WRAP )
  ) i_fifo (
    .clk_i   ( clk_i   ),
    .rst_ni  ( rst_ni  ),
    .clear_i ( clear_i ),
    .flags_o ( flags_o ),
    .push_i  ( push    ),
    .pop_o   ( pop     )
  );

endmodule // hwpe_stream_fifo_passthrough
