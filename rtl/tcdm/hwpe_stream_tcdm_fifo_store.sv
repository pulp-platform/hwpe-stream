/*
 * hwpe_stream_tcdm_fifo_store.sv
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
 * The **hwpe_stream_tcdm_fifo_store** module implements a hardware FIFO queue for
 * HWPE-MemDecoupled store streams, used to withstand data scarcity (`req`=0) or
 * backpressure (`gnt`=0), decoupling two architectural domains.
 * This FIFO is single-clock and therefore cannot be used to cross two
 * distinct clock domains.
 * The FIFO treats a HWPE-MemDecoupled store stream as a wide HWPE-Stream where,
 * on both sides, the `data` field contains `addr`, `data`, `be` of
 * the input `tcdm_slave`; the `req` and `gnt` of the HWPE-MemDecoupled
 * interfaces are mapped on `valid` and `ready` respectively.
 * The FIFO will lower its `gnt` signal on the slave interface `tcdm_slave`
 * when it is completely full, and will lower its `req`
 * signal on the master interface `tcdm_master` when it is completely
 * empty. :numref:`_hwpe_stream_tcdm_fifo_store_mapping` shows this mapping.
 *
 * .. _hwpe_stream_tcdm_fifo_store_mapping:
 * .. figure:: img/hwpe_stream_tcdm_fifo_store.*
 *   :figwidth: 90%
 *   :width: 90%
 *   :align: center
 *
 *   Mapping of HWPE-MemDecoupled and HWPE-Stream signals inside the store FIFO.
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hwpe_stream_tcdm_fifo_store_params:
 * .. table:: **hwpe_stream_tcdm_fifo_store** design-time parameters.
 *
 *   +------------------------+--------------+--------------------------------------------------------------------------------------+
 *   | **Name**               | **Default**  | **Description**                                                                      |
 *   +------------------------+--------------+--------------------------------------------------------------------------------------+
 *   | *FIFO_DEPTH*           | 8            | Depth of the FIFO queue (multiple of 2).                                             |
 *   +------------------------+--------------+--------------------------------------------------------------------------------------+
 *   | *LATCH_FIFO*           | 0            | If 1, use latches instead of flip-flops (requires special constraints in synthesis). |
 *   +------------------------+--------------+--------------------------------------------------------------------------------------+
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hwpe_stream_tcdm_fifo_store_flags:
 * .. table:: **hwpe_stream_tcdm_fifo_store** output flags.
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

module hwpe_stream_tcdm_fifo_store #(
  parameter int unsigned FIFO_DEPTH = 8,
  parameter int unsigned LATCH_FIFO = 0
)
(
  input  logic                 clk_i,
  input  logic                 rst_ni,
  input  logic                 clear_i,

  output flags_fifo_t            flags_o,

  hwpe_stream_intf_tcdm.slave  tcdm_slave,
  hwpe_stream_intf_tcdm.master tcdm_master
);

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( 68 )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT ( 1'b1 ),
    .BYPASS_VDR_ASSERT ( 1'b1 )
`endif
  ) stream_push (
    .clk ( clk_i )
  );
  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( 68 )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT ( 1'b1 ),
    .BYPASS_VDR_ASSERT ( 1'b1 )
`endif
  ) stream_pop (
    .clk ( clk_i )
  );

  // wrap tcdm ports into a stream
  assign stream_push.data  = { tcdm_slave.be, tcdm_slave.data, tcdm_slave.add };
  assign stream_push.strb  = '1;
  assign stream_push.valid = tcdm_slave.req;
  assign tcdm_slave.gnt = stream_push.ready;

  assign { tcdm_master.be, tcdm_master.data, tcdm_master.add } = stream_pop.data;
  assign tcdm_master.req = stream_pop.valid;
  assign stream_pop.ready = tcdm_master.gnt;

  // write enable always set to write
  assign tcdm_master.wen = 1'b0;

  hwpe_stream_fifo #(
    .DATA_WIDTH ( 68         ),
    .FIFO_DEPTH ( FIFO_DEPTH ),
    .LATCH_FIFO ( LATCH_FIFO )
  ) i_fifo (
    .clk_i   ( clk_i             ),
    .rst_ni  ( rst_ni            ),
    .clear_i ( clear_i           ),
    .push_i  ( stream_push.sink  ),
    .pop_o   ( stream_pop.source ),
    .flags_o ( flags_o           )
  );

endmodule // hwpe_stream_tcdm_fifo_store
