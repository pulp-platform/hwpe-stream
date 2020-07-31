/*
 * hwpe_stream_package.sv
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

package hwpe_stream_package;

  // realignment types
  parameter int unsigned HWPE_STREAM_REALIGN_SOURCE = 0;
  parameter int unsigned HWPE_STREAM_REALIGN_SINK   = 1;

  // addressgen related types
  typedef struct packed {
    logic [31:0] base_addr;
    logic [31:0] trans_size;
    logic [15:0] line_stride;
    logic [15:0] line_length;
    logic [15:0] feat_stride;
    logic [15:0] feat_length;
    logic [15:0] feat_roll;
    logic        loop_outer;
    logic        realign_type;
    logic [7:0]  line_length_remainder; // in bytes
  } ctrl_addressgen_t;

  typedef struct packed {
    logic        [31:0] base_addr;
    logic signed [31:0] word_stride;
    logic        [31:0] word_length;
    logic signed [31:0] line_stride;
    logic        [31:0] line_length;
  } ctrl_addressgen_v2_t;

  typedef struct packed {
    logic        [31:0] base_addr;
    logic        [31:0] tot_len;    // former word_length
    logic        [31:0] d0_len;     // former line_length
    logic signed [31:0] d0_stride;  // former word_stride
    logic        [31:0] d1_len;     // former block_length
    logic signed [31:0] d1_stride;  // former line_stride
    logic signed [31:0] d2_stride;  // former block_stride
    logic         [1:0] dim_enable_1h;
  } ctrl_addressgen_v3_t;

  typedef struct packed {
    logic enable;
    logic strb_valid;
    logic realign;
    logic first;
    logic last;
    logic last_packet;
    logic [15:0] line_length;
  } ctrl_realign_t;

  typedef struct packed {
    logic decoupled_stall;
  } flags_realign_t;

  typedef struct packed {
    ctrl_realign_t realign_flags;
    logic word_update;
    logic line_update;
    logic feat_update;
    logic in_progress;
  } flags_addressgen_t;

  typedef struct packed {
    logic done;
  } flags_addressgen_v2_t;

  typedef struct packed {
    logic done;
  } flags_addressgen_v3_t;

  typedef struct packed {
    logic empty;
    logic full;
    logic [7:0] push_pointer;
    logic [7:0] pop_pointer;
  } flags_fifo_t;

  // source/sink related types
  typedef struct packed {
    logic             req_start;
    ctrl_addressgen_t addressgen_ctrl;
  } ctrl_sourcesink_t;

  typedef struct packed {
    logic              ready_start;
    logic              done;
    flags_addressgen_t addressgen_flags;
  } flags_sourcesink_t;

  typedef enum {
    STREAM_IDLE, STREAM_WORKING, STREAM_DONE
  } state_sourcesink_t;

  // serialize/deserialize related types
  parameter int unsigned NB_SERDES_STREAMS_MAX = 1024;

  typedef struct packed {
    logic [$clog2(NB_SERDES_STREAMS_MAX)-1:0] first_stream;
    logic                                     clear_serdes_state;
    logic [$clog2(NB_SERDES_STREAMS_MAX)-1:0] nb_contig_m1;
  } ctrl_serdes_t;

endpackage
