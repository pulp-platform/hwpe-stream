/*
 * hwpe_stream_tcdm_fifo.sv
 * Francesco Conti <f.conti@unibo.it>
 *
 * Copyright (C) 2014-2019 ETH Zurich, University of Bologna
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
 * The **hwpe_stream_tcdm_fifo** module implements a hardware FIFO queue for
 * HWPE-MemDecoupled streams, used to withstand data scarcity (`req`=0) or
 * backpressure (`gnt`=0), decoupling two architectural domains.
 * This FIFO is single-clock and therefore cannot be used to cross two
 * distinct clock domains.
 * The FIFO treats a HWPE-MemDecoupled stream as a combination of two
 * HWPE-Streams, one going from the `tcdm_master` to the `tcdm_slave` interface
 * carrying `addr`, `data`, `be`, `wen` (*outgoing stream*); the other from the
 * `tcdm_slave` to the `tcdm_master` interface, carrying the `r_data`
 * (*incoming stream*).
 *
 * On the slave side, the `req` and `gnt` of the HWPE-MemDecoupled interfaces
 * are mapped on `valid` and `ready` respectively in the outgoing stream.
 * Backpressure on the incoming stream (slave side) cannot be enforced by means
 * of the HWPE-MemDecoupled slave interface and thus is carried by a specific
 * input `ready_i` that must be generated outside of the TCDM FIFO, typically
 * by a **hwpe_stream_source** module (output `tcdm_fifo_ready_o`).
 * On the master side, `req` is mapped to the AND of the incoming stream `ready`
 * signal and the outgoing stream `valid` signal. `gnt` is hooked to the
 * outgoing stream `ready` signal.
 * The `r_valid` is mapped on `valid` in the incoming stream.
 * :numref:`_hwpe_stream_tcdm_fifo_load_mapping2` shows this mapping.
 *
 * .. _hwpe_stream_tcdm_fifo_load_mapping2:
 * .. figure:: img/hwpe_stream_tcdm_fifo_load.*
 *   :figwidth: 90%
 *   :width: 90%
 *   :align: center
 *
 *   Mapping of HWPE-MemDecoupled and HWPE-Stream signals inside the FIFO (loads).
 *
 * .. _hwpe_stream_tcdm_fifo_store_mapping2:
 * .. figure:: img/hwpe_stream_tcdm_fifo_store.*
 *   :figwidth: 90%
 *   :width: 90%
 *   :align: center
 *
 *   Mapping of HWPE-MemDecoupled and HWPE-Stream signals inside the FIFO (stores).
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hwpe_stream_tcdm_fifo_params:
 * .. table:: **hwpe_stream_tcdm_fifo** design-time parameters.
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
 * .. _hwpe_stream_tcdm_fifo_flags:
 * .. table:: **hwpe_stream_tcdm_fifo** output flags.
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

module hwpe_stream_tcdm_fifo #(
  parameter int unsigned FIFO_DEPTH = 8,
  parameter int unsigned LATCH_FIFO = 0
)
(
  input  logic                 clk_i,
  input  logic                 rst_ni,
  input  logic                 clear_i,

  output flags_fifo_t          flags_o,

  input  logic                 ready_i,

  hwpe_stream_intf_tcdm.slave  tcdm_slave,
  hwpe_stream_intf_tcdm.master tcdm_master
);

  flags_fifo_t flags_incoming, flags_outgoing;

  logic incoming_fifo_not_full;

  logic        tcdm_master_r_valid_d, tcdm_master_r_valid_q;
  logic [31:0] tcdm_master_r_data_d, tcdm_master_r_data_q;

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( 32+32+8+1 )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT ( 1'b1 ),
    .BYPASS_VDR_ASSERT ( 1'b1 )
`endif
  ) stream_outgoing_push (
    .clk ( clk_i )
  );
  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( 32+32+8+1 )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT ( 1'b1 ),
    .BYPASS_VDR_ASSERT ( 1'b1 )
`endif
  ) stream_outgoing_pop (
    .clk ( clk_i )
  );

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( 32 )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT ( 1'b1 ),
    .BYPASS_VDR_ASSERT ( 1'b1 )
`endif
  ) stream_incoming_push (
    .clk ( clk_i )
  );
  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( 32 )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT ( 1'b1 ),
    .BYPASS_VDR_ASSERT ( 1'b1 )
`endif
  ) stream_incoming_pop (
    .clk ( clk_i )
  );

  // wrap tcdm incoming ports into a stream
  assign stream_incoming_push.data  = tcdm_master_r_valid_d ? tcdm_master_r_data_d : tcdm_master_r_data_q;
  assign stream_incoming_push.valid = tcdm_master_r_valid_d | tcdm_master_r_valid_q;
  assign stream_incoming_push.strb = '1;

  assign incoming_fifo_not_full = stream_incoming_push.ready;

  assign tcdm_slave.r_data  = stream_incoming_pop.data;
  assign tcdm_slave.r_valid = stream_incoming_pop.valid & stream_incoming_pop.ready;
  assign stream_incoming_pop.ready = ready_i;

  // enforce protocol on incoming stream
  assign tcdm_master_r_data_d = tcdm_master.r_data;
  assign tcdm_master_r_valid_d = tcdm_master.r_valid;

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni)
      tcdm_master_r_valid_q <= 1'b0;
    else if(clear_i)
      tcdm_master_r_valid_q <= 1'b0;
    else begin
      if(tcdm_master_r_valid_d & stream_incoming_push.ready)
        tcdm_master_r_valid_q <= 1'b0;
      else if(tcdm_master_r_valid_d)
        tcdm_master_r_valid_q <= 1'b1;
      else if(tcdm_master_r_valid_q & stream_incoming_push.ready)
        tcdm_master_r_valid_q <= 1'b0;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni)
      tcdm_master_r_data_q <= '0;
    else if(clear_i)
      tcdm_master_r_data_q <= '0;
    else if(tcdm_master_r_valid_d)
        tcdm_master_r_data_q <= tcdm_master_r_data_d;
  end

  hwpe_stream_fifo #(
    .DATA_WIDTH ( 32         ),
    .FIFO_DEPTH ( FIFO_DEPTH ),
    .LATCH_FIFO ( LATCH_FIFO )
  ) i_fifo_incoming (
    .clk_i   ( clk_i                      ),
    .rst_ni  ( rst_ni                     ),
    .clear_i ( clear_i                    ),
    .flags_o ( flags_incoming             ),
    .push_i  ( stream_incoming_push.sink  ),
    .pop_o   ( stream_incoming_pop.source )
  );

  // wrap tcdm outgoing ports into a stream
  assign stream_outgoing_push.data = { tcdm_slave.add, tcdm_slave.data, tcdm_slave.be, tcdm_slave.wen };
  assign stream_outgoing_push.strb = '1;
  assign stream_outgoing_push.valid = tcdm_slave.req;
  assign tcdm_slave.gnt = stream_outgoing_push.ready;

  assign tcdm_master.add  = stream_outgoing_pop.data [32+32+4+1-1:32+4+1];
  assign tcdm_master.data = stream_outgoing_pop.data [32+4+1-1:4+1];
  assign tcdm_master.be   = stream_outgoing_pop.data [4+1-1:1];
  assign tcdm_master.wen  = stream_outgoing_pop.data [0];
  assign tcdm_master.req = stream_outgoing_pop.valid & incoming_fifo_not_full;
  assign stream_outgoing_pop.ready = tcdm_master.gnt; // if incoming_fifo_not_full=0, gnt is already 0, because req=0

  hwpe_stream_fifo #(
    .DATA_WIDTH ( 32+32+8+1  ),
    .FIFO_DEPTH ( FIFO_DEPTH ),
    .LATCH_FIFO ( LATCH_FIFO )
  ) i_fifo_outgoing (
    .clk_i   ( clk_i                      ),
    .rst_ni  ( rst_ni                     ),
    .clear_i ( clear_i                    ),
    .flags_o ( flags_outgoing             ),
    .push_i  ( stream_outgoing_push.sink  ),
    .pop_o   ( stream_outgoing_pop.source )
  );

  assign flags_o.empty = flags_incoming.empty & flags_outgoing.empty;

endmodule // hwpe_stream_tcdm_fifo
