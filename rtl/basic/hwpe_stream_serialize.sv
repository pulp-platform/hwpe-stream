/*
 * hwpe_stream_serialize.sv
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
 * The **hwpe_stream_serialize** module is used to merge `NB_IN_STREAMS`
 * input streams into a single stream in the time dimension, by serializing
 * packets.
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hwpe_stream_serialize_params:
 * .. table:: **hwpe_stream_serialize** design-time parameters.
 *
 *   +------------------+----------------+-------------------------------------------------------+
 *   | **Name**         | **Default**    | **Description**                                       |
 *   +------------------+----------------+-------------------------------------------------------+
 *   | *NB_IN_STREAMS*  | 2              | Number of input HWPE-Stream streams.                  |
 *   +------------------+----------------+-------------------------------------------------------+
 *   | *DATA_WIDTH*     | 32             | Width of the HWPE-Stream streams.                     |
 *   +------------------+----------------+-------------------------------------------------------+
 *   | *STRB_WIDTH*     | DATA_WIDTH / 8 | Width of the HWPE-Stream strobe signal.               |
 *   +------------------+----------------+-------------------------------------------------------+
 *   | *CONTIG_LIMIT*   | 1024           | Maximum number of contiguous packets per stream.      |
 *   +------------------+----------------+-------------------------------------------------------+
 *   | *SYNC_READY*     | 0              | If 0, each incoming stream is handshaken separately,  |
 *   |                  |                | which means that their producers must be independent. |
 *   |                  |                | If 1, the ready signal is "fenced", which means that  |
 *   |                  |                | all streams wait for the last stream to be ready to   |
 *   |                  |                | progress. This is useful, for example, when there is  |
 *   |                  |                | a single producer (e.g., `hwpe_stream_split`). Care   |
 *   |                  |                | must be taken to deadlocks, typically by inserting a  |
 *   |                  |                | decoupling FIFO.                                      |
 *   +------------------+----------------+-------------------------------------------------------+
 *
  * .. tabularcolumns:: |l|l|J|
 * .. _hwpe_stream_serialize_ctrl:
 * .. table:: **hwpe_stream_serialize** input control signals.
 *
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | **Name**                         | **Type**             | **Description**                                                                                             |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | *clear_serdes_state*             | `logic`              | If raised to 1, forces the serializer state to be reinitialized to *first_stream*                           |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | *first_stream*                   | `logic[9:0]`         | ID of the stream selected when the internal state is cleared by *clear_serdes_state*.                       |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *
 */

import hwpe_stream_package::*;

module hwpe_stream_serialize #(
  parameter int unsigned NB_IN_STREAMS = 2,
  parameter int unsigned CONTIG_LIMIT = 1024,
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned STRB_WIDTH = DATA_WIDTH/8,
  parameter logic        SYNC_READY = 1'b0
)
(
  input  logic                   clk_i,
  input  logic                   rst_ni,
  input  logic                   clear_i,

  input  ctrl_serdes_t           ctrl_i,
  hwpe_stream_intf_stream.sink   push_i [NB_IN_STREAMS-1:0],
  hwpe_stream_intf_stream.source pop_o
);

  logic [$clog2(NB_IN_STREAMS)-1:0] stream_cnt_d, stream_cnt_q;
  logic [$clog2(CONTIG_LIMIT)-1:0]  contig_cnt_d, contig_cnt_q;
  logic stream_cnt_en;

  // boilerplate for SystemVerilog compliance
  logic [NB_IN_STREAMS-1:0][DATA_WIDTH-1:0]   push_data;
  logic [NB_IN_STREAMS-1:0]                   push_valid;
  logic [NB_IN_STREAMS-1:0][STRB_WIDTH-1:0] push_strb;
  logic [NB_IN_STREAMS-1:0]                   push_ready;

  generate
    for(genvar ii=0; ii<NB_IN_STREAMS; ii++) begin : stream_binding

      assign push_data [ii]   = push_i[ii].data;
      assign push_strb [ii]   = push_i[ii].strb;
      assign push_valid[ii]   = push_i[ii].valid;
      assign push_i[ii].ready = push_ready[ii];

    end
  endgenerate

  // stream serialization
  assign pop_o.data  = push_data [stream_cnt_q];
  assign pop_o.valid = push_valid[stream_cnt_q];
  assign pop_o.strb  = push_strb [stream_cnt_q];

  if(SYNC_READY) begin : sync_ready_gen
    for(genvar ii=0; ii<NB_IN_STREAMS; ii++) begin : sync_ready_loop_gen
      assign push_ready[ii] = (stream_cnt_q == NB_IN_STREAMS-1) ? stream_cnt_en & pop_o.ready : 1'b0;
    end
  end
  else begin : no_sync_ready_gen
    always_comb
    begin
      push_ready = '0;
      push_ready[stream_cnt_q] = pop_o.ready;
    end
  end

  // stream counters
  always_ff @(posedge clk_i or negedge rst_ni)
  begin : stream_counter_ff
    if(~rst_ni) begin
      stream_cnt_q <= '0;
    end
    else if(clear_i) begin
      stream_cnt_q <= '0;
    end
    else if(stream_cnt_en & pop_o.valid & pop_o.ready) begin
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
      if(stream_cnt_q < NB_IN_STREAMS-1) begin
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
    else if(pop_o.valid & pop_o.ready) begin
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

  assign stream_cnt_en = contig_cnt_q < ctrl_i.nb_contig_m1 ? 1'b0 : 1'b1;

endmodule // hwpe_stream_serialize
