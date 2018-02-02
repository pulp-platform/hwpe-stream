/*
 * hwpe_stream_tcdm_fifo_load.sv
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

import hwpe_stream_package::*;

module hwpe_stream_tcdm_fifo_load #(
  parameter int unsigned FIFO_DEPTH = 8,
  parameter int unsigned LATCH_FIFO = 0
)
(
  input  logic                 clk_i,
  input  logic                 rst_ni,
  input  logic                 clear_i,

  input  logic                 ready_i,
  
  hwpe_stream_intf_tcdm.slave  tcdm_slave,
  hwpe_stream_intf_tcdm.master tcdm_master
);

  logic incoming_fifo_not_full;

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( 32 )
  ) stream_outgoing_push (
    .clk ( clk_i )
  );
  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( 32 )
  ) stream_outgoing_pop (
    .clk ( clk_i )
  );

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( 32 )
  ) stream_incoming_push (
    .clk ( clk_i )
  );
  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( 32 )
  ) stream_incoming_pop (
    .clk ( clk_i )
  );

  // wrap tcdm incoming ports into a stream
  assign stream_incoming_push.data  = tcdm_master.r_data;
  assign stream_incoming_push.valid = tcdm_master.r_valid;
  always_ff @(posedge clk_i or negedge rst_ni)
  begin : incoming_fifo_not_full_ff
    if(~rst_ni) begin
      incoming_fifo_not_full <= 1'b0;
    end
    else begin
      incoming_fifo_not_full <= stream_incoming_push.ready;
    end
  end

  assign tcdm_slave.r_data  = stream_incoming_pop.data;
  assign tcdm_slave.r_valid = stream_incoming_pop.valid;
  assign stream_incoming_pop.ready = ready_i;

  hwpe_stream_fifo_earlystall #(
    .DATA_WIDTH ( 32         ),
    .FIFO_DEPTH ( FIFO_DEPTH ),
    .LATCH_FIFO ( LATCH_FIFO )
  ) i_fifo_incoming (
    .clk_i       ( clk_i                      ),
    .rst_ni      ( rst_ni                     ),
    .clear_i     ( clear_i                    ),
    .tcdm_slave  ( stream_incoming_push.sink  ),
    .tcdm_master ( stream_incoming_pop.source )
  );

  // wrap tcdm outgoing ports into a stream
  assign stream_outgoing_push.data = tcdm_slave.add;
  assign stream_outgoing_push.valid = tcdm_slave.req;
  assign tcdm_slave.gnt = stream_outgoing_push.ready;

  assign tcdm_master.add = stream_outgoing_pop.data;
  assign tcdm_master.req = stream_outgoing_pop.valid & incoming_fifo_not_full;
  assign stream_outgoing_pop.ready = tcdm_master.gnt; // if incoming_fifo_not_full=0, gnt must be 0 because req=0

  hwpe_stream_fifo #(
    .DATA_WIDTH ( 32         ),
    .FIFO_DEPTH ( FIFO_DEPTH ),
    .LATCH_FIFO ( LATCH_FIFO )
  ) i_fifo_outgoing (
    .clk_i       ( clk_i                      ),
    .rst_ni      ( rst_ni                     ),
    .clear_i     ( clear_i                    ),
    .tcdm_slave  ( stream_outgoing_push.sink  ),
    .tcdm_master ( stream_outgoing_pop.source )
  );

endmodule // hwpe_stream_tcdm_fifo_load
