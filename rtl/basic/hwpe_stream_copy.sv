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
  parameter int unsigned NB_IN_STREAMS   = 1,
  parameter int unsigned NB_COPY_STREAMS = 2
)
(
  hwpe_stream_intf_stream.sink   push_i [NB_IN_STREAMS-1:0],
  hwpe_stream_intf_stream.source pop_o  [NB_COPY_STREAMS*NB_IN_STREAMS-1:0]
);

  logic [NB_IN_STREAMS-1:0][NB_COPY_STREAMS-1:0] stream_ready;

  generate

    for(genvar ii=0; ii<NB_COPY_STREAMS; ii++) begin : stream_copy
      for(genvar jj=0; jj<NB_IN_STREAMS; jj++) begin
        localparam ii_jj = ii*NB_IN_STREAMS+jj;

        assign pop_o[ii_jj].data  = push_i[jj].data;
        assign pop_o[ii_jj].strb  = push_i[jj].strb;
        assign pop_o[ii_jj].valid = push_i[jj].valid;

        // auxiliary for ready generation
        assign stream_ready[jj][ii] = pop_o[ii_jj].ready;

      end
    end

  endgenerate

  for(genvar jj=0; jj<NB_IN_STREAMS; jj++) begin : ready_assign
    // ready only when all copy streams are ready
    assign push_i[jj].ready = & stream_ready[jj];
  end

endmodule // hwpe_stream_copy
