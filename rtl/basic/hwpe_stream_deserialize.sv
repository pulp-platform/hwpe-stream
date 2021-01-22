/*
 * hwpe_stream_deserialize.sv
 * Francesco Conti <f.conti@unibo.it>
 *
 * Copyright (C) 2014-2020 ETH Zurich, University of Bologna
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
 * The **hwpe_stream_deserialize** module is used to split an input stream
 * into *NB_OUT_STREAMS* streams in the time dimension, by deserializing
 * packets. Note that the output streams are not synchronized with one another.
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hwpe_stream_deserialize_params:
 * .. table:: **hwpe_stream_deserialize** design-time parameters.
 *
 *   +------------------+-------------+---------------------------------------------+
 *   | **Name**         | **Default** | **Description**                             |
 *   +------------------+-------------+---------------------------------------------+
 *   | *NB_OUT_STREAMS* | 2           | Number of output HWPE-Stream streams.       |
 *   +------------------+-------------+---------------------------------------------+
 *   | *DATA_WIDTH*     | 32          | Width of the HWPE-Stream streams.           |
 *   +------------------+-------------+---------------------------------------------+
 *
  * .. tabularcolumns:: |l|l|J|
 * .. _hwpe_stream_deserialize_ctrl:
 * .. table:: **hwpe_stream_deserialize** input control signals.
 *
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | **Name**                         | **Type**             | **Description**                                                                                             |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | *clear_serdes_state*             | `logic`              | If raised to 1, forces the deserializer state to be reinitialized to *first_stream*                         |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | *first_stream*                   | `logic[9:0]`         | ID of the stream selected when the internal state is cleared by *clear_serdes_state*.                       |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *
 */

import hwpe_stream_package::*;

module hwpe_stream_deserialize #(
  parameter int unsigned NB_OUT_STREAMS = 2,
  parameter int unsigned CONTIG_LIMIT = 1024,
  parameter int unsigned DATA_WIDTH = 32
)
(
  input  logic                   clk_i,
  input  logic                   rst_ni,
  input  logic                   clear_i,

  input  ctrl_serdes_t           ctrl_i,
  hwpe_stream_intf_stream.sink   push_i,
  hwpe_stream_intf_stream.source pop_o[NB_OUT_STREAMS-1:0]
);

  logic [$clog2(NB_OUT_STREAMS)-1:0] stream_cnt_d, stream_cnt_q;
  logic [$clog2(CONTIG_LIMIT)-1:0]   contig_cnt_d, contig_cnt_q;
  logic stream_cnt_en;
  logic [NB_OUT_STREAMS-1:0]         pop_ready;

  // stream serialization
  generate
    for(genvar ii=0; ii<NB_OUT_STREAMS; ii++) begin : stream_binding

      assign pop_o[ii].data  = push_i.data;
      assign pop_o[ii].strb  = push_i.strb;
      assign pop_o[ii].valid = (stream_cnt_q == ii) ? push_i.valid : '0;
      assign pop_ready[ii] = pop_o[ii].ready;

    end
  endgenerate

  assign push_i.ready = pop_ready[stream_cnt_q];

  // stream counters
  always_ff @(posedge clk_i or negedge rst_ni)
  begin : stream_counter_ff
    if(~rst_ni) begin
      stream_cnt_q <= '0;
    end
    else if(clear_i) begin
      stream_cnt_q <= '0;
    end
    else if(stream_cnt_en) begin
      stream_cnt_q <= stream_cnt_d;
    end
  end

  always_comb
  begin : stream_counter_comb
    stream_cnt_d = stream_cnt_q;
    if(ctrl_i.clear_serdes_state) begin
      stream_cnt_d = ctrl_i.first_stream;
    end
    else begin
      if(stream_cnt_q < NB_OUT_STREAMS-1) begin
        stream_cnt_d = stream_cnt_q + 1;
      end
      else begin
        stream_cnt_d = '0;
      end
    end
  end

  // contiguous counters
  always_ff @(posedge clk_i or negedge rst_ni)
  begin : contig_counter_ff
    if(~rst_ni) begin
      contig_cnt_q <= '0;
    end
    else if(clear_i) begin
      contig_cnt_q <= '0;
    end
    else if(push_i.valid & push_i.ready) begin
      contig_cnt_q <= contig_cnt_d;
    end
  end

  always_comb
  begin : contig_counter_comb
    contig_cnt_d = '0;
    if(contig_cnt_q < ctrl_i.nb_contig_m1) begin
      contig_cnt_d = contig_cnt_q + 1;
    end
    else begin
      contig_cnt_d = '0;
    end
  end

  assign stream_cnt_en = contig_cnt_q < ctrl_i.nb_contig_m1 ? 1'b0 : push_i.valid & push_i.ready;

endmodule // hwpe_stream_deserialize
