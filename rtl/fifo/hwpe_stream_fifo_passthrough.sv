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
 *

/**
 * The **hwpe_stream_fifo_passthrough** module implements a hardware FIFO
 * queue for HWPE-Stream streams, used to withstand data scarcity (`valid`=0) or
 * backpressure (`ready`=0), decoupling two architectural domains.
 * This FIFO is single-clock and therefore cannot be used to cross two
 * distinct clock domains.
 * The FIFO will lower its `ready` signal on the input stream `push_i`
 * interface when it is completely full, and will lower its `valid`
 * signal on the output stream `pop_o` interface when it is completely
 * empty.
 * The passthrough FIFO allows for transactions to fall through the FIFO
 * queue (with 0 latency) if there are no stalls. This has the advantage to
 * minimize latency, at the cost of not cutting combinational paths.
 * The alternative is the regular FIFO **hwpe_stream_fifo**.
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hwpe_stream_fifo_params:
 * .. table:: **hwpe_stream_fifo** design-time parameters.
 *
 *   +------------------------+--------------+--------------------------------------------------------------------------------------+
 *   | **Name**               | **Default**  | **Description**                                                                      |
 *   +------------------------+--------------+--------------------------------------------------------------------------------------+
 *   | *DATA_WIDTH*           | 32           | Width of the HWPE-Streams (typically multiple of 32, but this module does not care). |
 *   +------------------------+--------------+--------------------------------------------------------------------------------------+
 *   | *FIFO_DEPTH*           | 8            | Depth of the FIFO queue (multiple of 2).                                             |
 *   +------------------------+--------------+--------------------------------------------------------------------------------------+
 *   | *LATCH_FIFO*           | 0            | If 1, use latches instead of flip-flops (requires special constraints in synthesis). |
 *   +------------------------+--------------+--------------------------------------------------------------------------------------+
 *   | *LATCH_FIFO_TEST_WRAP* | 0            | If 1 and *LATCH_FIFO* is 1, wrap latches with BIST wrappers.                         |
 *   +------------------------+--------------+--------------------------------------------------------------------------------------+
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hwpe_stream_fifo_flags:
 * .. table:: **hwpe_stream_fifo** output flags.
 *
 *   +----------------+--------------+-----------------------------------+
 *   | **Name**       | **Type**     | **Description**                   |
 *   +----------------+--------------+-----------------------------------+
 *   | *empty*        | `logic`      | 1 if the FIFO is currently empty. |
 *   +----------------+--------------+-----------------------------------+
 *   | *full*         | `logic`      | 1 if the FIFO is currently full.  |
 *   +----------------+--------------+-----------------------------------+
 *   | *push_pointer* | `logic[7:0]` | Unused.                           |
 *   +----------------+--------------+-----------------------------------+
 *   | *pop_pointer*  | `logic[7:0]` | Unused.                           |
 *   +----------------+--------------+-----------------------------------+
 *
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
