/*
 * hwpe_stream_copy.sv
 * Luigi Ghionda <luigi.ghionda2@unibo.it>
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
 * The **hwpe_stream_copy** module is used to copy a single stream into
 * `NB_OUT_STREAMS` output streams. The *data*, *strb* and the *valid*
 * are broadcast to all outgoing streams. The *ready* is generated
 * as the AND of all *ready*\ ’s from output streams.
 *
 */

import hwpe_stream_package::*;

module hwpe_stream_copy #(
  parameter int unsigned NB_COPY_STREAMS = 2,
  parameter int unsigned DEMUXED = 0
)
(
  input  logic [$clog2(NB_COPY_STREAMS)-1:0] sel_i,

  hwpe_stream_intf_stream.sink   push_i,
  hwpe_stream_intf_stream.source pop_o  [NB_COPY_STREAMS-1:0]
);

  logic [NB_COPY_STREAMS-1:0] stream_ready;

  generate

    for(genvar ii=0; ii<NB_COPY_STREAMS; ii++) begin : stream_copy
      assign pop_o[ii].data  = push_i.data;
      assign pop_o[ii].strb  = push_i.strb;

      // copy valid is broadcast to all outgoing streams
      assign pop_o[ii].valid = push_i.valid;

      // auxiliary for ready generation
      assign stream_ready[ii] = pop_o[ii].ready;

    end

  endgenerate

  generate
    if (DEMUXED) begin : ready_demuxed
      // ready when selected copy stream is ready
      assign push_i.ready = stream_ready[sel_i];
    end
    else begin : ready_bitwise_and
      // ready only when all copy streams are ready
      assign push_i.ready = & stream_ready;
    end
  endgenerate


endmodule // hwpe_stream_copy
