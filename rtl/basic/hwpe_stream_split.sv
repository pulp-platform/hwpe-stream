/*
 * hwpe_stream_split.sv
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
 * The **hwpe_stream_split** module is used to split a single stream into
 * `NB_OUT_STREAMS`, 32-bit output streams. The *data* and *strb* channel
 * from the input stream is split in ordered output streams, and the
 * *valid* is broadcast to all outgoing streams. The *ready* is generated
 * as the AND of all *ready*\ ’s from output streams.
 *
 * A typical use of this module is to take a multiple-of-32-bit stream
 * coming from within the HWPE and split it into multiple 32-bit streams
 * that feed a TCDM store interface.
 *
 * The following shows an example of the **hwpe_stream_split** operation:
 *
 * .. _wavedrom_hwpe_stream_split:
 * .. wavedrom:: wavedrom/hwpe_stream_split.json
 *   :width: 85 %
 *   :caption: Example of **hwpe_stream_split** operation.
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hwpe_stream_split_params:
 * .. table:: **hwpe_stream_split** design-time parameters.
 *
 *   +------------------+-------------+---------------------------------------------+
 *   | **Name**         | **Default** | **Description**                             |
 *   +------------------+-------------+---------------------------------------------+
 *   | *NB_OUT_STREAMS* | 2           | Number of output HWPE-Stream streams.       |
 *   +------------------+-------------+---------------------------------------------+
 *   | *DATA_WIDTH_IN*  | 128         | Width of the input HWPE-Stream stream.      |
 *   +------------------+-------------+---------------------------------------------+
 */

import hwpe_stream_package::*;

module hwpe_stream_split #(
  parameter int unsigned NB_OUT_STREAMS = 2,
  parameter int unsigned DATA_WIDTH_IN = 128
)
(
  input  logic                   clk_i,
  input  logic                   rst_ni,
  input  logic                   clear_i,

  hwpe_stream_intf_stream.sink   push_i,
  hwpe_stream_intf_stream.source pop_o [NB_OUT_STREAMS-1:0]
);

  parameter int unsigned DATA_WIDTH_OUT = DATA_WIDTH_IN/NB_OUT_STREAMS;
  parameter int unsigned STRB_WIDTH_OUT = DATA_WIDTH_OUT/8;

  logic [NB_OUT_STREAMS-1:0] stream_ready;

  generate

    for(genvar ii=0; ii<NB_OUT_STREAMS; ii++) begin : stream_binding

      // split data is bound in order
      assign pop_o[ii].data  = push_i.data [(ii+1)*DATA_WIDTH_OUT-1:ii*DATA_WIDTH_OUT];
      assign pop_o[ii].strb  = push_i.strb [(ii+1)*STRB_WIDTH_OUT-1:ii*STRB_WIDTH_OUT];

      // split valid is broadcast to all outgoing streams
      assign pop_o[ii].valid = push_i.valid;

      // auxiliary for ready generation
      assign stream_ready[ii] = pop_o[ii].ready;

    end

  endgenerate

  // ready only when all diverging streams are ready
  assign push_i.ready = & stream_ready;

endmodule // hwpe_stream_split
