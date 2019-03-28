/*
 * hwpe_stream_sink_realign.sv
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
 * The **hwpe_stream_sink_realign** module realigns HWPE-Streams to prepare
 * them for storage in memory. Specifically, it rotates `strb` signals
 * according to its control interface, produced along with addresses in the
 * address generator.
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hwpe_stream_sink_realign_params:
 * .. table:: **hwpe_stream_sink_realign** design-time parameters.
 *
 *   +-------------------+-------------+--------------------------------------------------------------------------------------------------------------------------+
 *   | **Name**          | **Default** | **Description**                                                                                                          |
 *   +-------------------+-------------+--------------------------------------------------------------------------------------------------------------------------+
 *   | *DATA_WIDTH*      | 32          | Width of input/output streams.                                                                                           |
 *   +-------------------+-------------+--------------------------------------------------------------------------------------------------------------------------+
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hwpe_stream_sink_realign_ctrl:
 * .. table:: **hwpe_stream_sink_realign** input control signals.
 *
 *   +---------------+---------------+----------------------------------------------------------------------------------------------------+
 *   | **Name**      | **Type**      | **Description**                                                                                    |
 *   +---------------+---------------+----------------------------------------------------------------------------------------------------+
 *   | *enable*      | `logic`       | Unused.                                                                                            |
 *   +---------------+---------------+----------------------------------------------------------------------------------------------------+
 *   | *strb_valid*  | `logic`       | Unused.                                                                                            |
 *   +---------------+---------------+----------------------------------------------------------------------------------------------------+
 *   | *realign*     | `logic`       | If 1, the realigner is actively used to generate strobed HWPE-Streams. If 0, it is bypassed.       |
 *   +---------------+---------------+----------------------------------------------------------------------------------------------------+
 *   | *first*       | `logic`       | Strobe at 1 for the first packet in a line.                                                        |
 *   +---------------+---------------+----------------------------------------------------------------------------------------------------+
 *   | *last*        | `logic`       | Strobe at 1 for the last packet in a line.                                                         |
 *   +---------------+---------------+----------------------------------------------------------------------------------------------------+
 *   | *last_packet* | `logic`       | Strobe at 1 for the last packet of the transfer.                                                   |
 *   +---------------+---------------+----------------------------------------------------------------------------------------------------+
 *   | *line_length* | `logic[15:0]` | Unused.                                                                                            |
 *   +---------------+---------------+----------------------------------------------------------------------------------------------------+
 *
 */

import hwpe_stream_package::*;

module hwpe_stream_sink_realign #(
  parameter int unsigned DATA_WIDTH = 32
)
(
  input  logic                    clk_i,
  input  logic                    rst_ni,
  input  logic                    clear_i,
  input  logic                    test_mode_i,

  input  ctrl_realign_t           ctrl_i,

  input  logic [DATA_WIDTH/8-1:0] strb_i,
  hwpe_stream_intf_stream.sink    push_i,
  hwpe_stream_intf_stream.source  pop_o
);

  logic [DATA_WIDTH/8-1:0] strb_q;
  logic unsigned [$clog2(DATA_WIDTH/8):0] strb_rotate_inv_d;
  logic unsigned [$clog2(DATA_WIDTH/8):0] strb_rotate_inv_q;
  logic unsigned [$clog2(DATA_WIDTH/8):0] strb_rotate_d;
  logic unsigned [$clog2(DATA_WIDTH/8):0] strb_rotate_q;
  logic unsigned [$clog2(DATA_WIDTH/8)+3:0] strb_rotate_d_shifted;
  logic unsigned [$clog2(DATA_WIDTH/8)+3:0] strb_rotate_q_shifted;
  logic unsigned [$clog2(DATA_WIDTH/8)+3:0] strb_rotate_inv_shifted;
  logic [DATA_WIDTH-1:0]   stream_data_q;
  logic [DATA_WIDTH/8-1:0] stream_strb_q;
  logic [DATA_WIDTH/8-1:0] stream_strb_latest_q;

  logic [DATA_WIDTH-1:0] int_data;
  logic [DATA_WIDTH-1:0] int_data_q;
  logic [DATA_WIDTH/8-1:0] int_strb;
  logic [DATA_WIDTH/8-1:0] int_strb_q;
  logic int_valid;
  logic int_valid_q;
  logic int_ready;

  logic first_state, first_sticky;

  /* stick the value of ctrl_i.first in first_sticky until pop_o.ready */
  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni)
      first_state <= '0;
    else if(clear_i)
      first_state <= '0;
    else if(ctrl_i.first & ~push_i.ready)
      first_state <= 1'b1;
    else if (push_i.ready)
      first_state <= 1'b0;
  end
  assign first_sticky = ~ctrl_i.last_packet & ctrl_i.first | first_state;

  /* management of misaligned accesses */
  assign int_valid = (~ctrl_i.realign)    ? push_i.valid :
                     (ctrl_i.last_packet) ? 1'b0 :
                                            (push_i.valid | ctrl_i.last) & |strb_i;
  assign push_i.ready = (~ctrl_i.realign) ? int_ready :
                                            int_ready & ~ctrl_i.last;

  // save the strobes of the first misaligned transfer as a reference!
  // this implicitly assumes that all strobes result in a rotation - it
  // must be thus!!
  always_comb
  begin
    strb_rotate_inv_d = '0;
    if(ctrl_i.first) begin
      for (int i=0; i<DATA_WIDTH/8; i++)
        strb_rotate_inv_d += ($clog2(DATA_WIDTH/8))'(strb_i[i]);
    end
    else begin
      for (int i=0; i<DATA_WIDTH/8; i++)
        strb_rotate_inv_d += ($clog2(DATA_WIDTH/8))'(strb_q[i]);
    end
  end
  assign strb_rotate_d = {($clog2(DATA_WIDTH/8)){1'b1}} - strb_rotate_inv_d + 1;
  assign strb_rotate_d_shifted   = strb_rotate_d << 3;
  assign strb_rotate_q_shifted   = strb_rotate_q << 3;
  assign strb_rotate_inv_shifted = strb_rotate_inv_q << 3;

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni)
      stream_strb_q <= '0;
    else if (clear_i)
      stream_strb_q <= '0;
    else if (push_i.valid & push_i.ready & ctrl_i.first) begin
      stream_strb_q <= push_i.strb;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni)
      stream_strb_latest_q <= '0;
    else if (clear_i)
      stream_strb_latest_q <= '0;
    else if (push_i.valid & push_i.ready) begin
      stream_strb_latest_q <= push_i.strb;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni)
      strb_q <= '0;
    else if (clear_i)
      strb_q <= '0;
    else if (ctrl_i.first) begin
      strb_q <= strb_i;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni) begin
      strb_rotate_q     <= '0;
      strb_rotate_inv_q <= '0;
    end
    else if (clear_i) begin
      strb_rotate_q     <= '0;
      strb_rotate_inv_q <= '0;
    end
    else if (ctrl_i.first) begin
      strb_rotate_q     <= strb_rotate_d;
      strb_rotate_inv_q <= strb_rotate_inv_d;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni)
      stream_data_q <= '0;
    else if (clear_i)
      stream_data_q <= '0;
    else if (push_i.valid & push_i.ready) begin
      stream_data_q <= push_i.data;
    end
  end

  always_comb
  begin
    int_data = push_i.data;
    int_strb = push_i.strb;
    if(ctrl_i.realign) begin
      if(first_sticky) begin
        int_data =  push_i.data << strb_rotate_d_shifted;
        int_strb = (push_i.strb << strb_rotate_d) & strb_i;
      end
      else begin
        int_data =  (push_i.data << strb_rotate_q_shifted) | (stream_data_q >> strb_rotate_inv_shifted);
        if(ctrl_i.last)
          int_strb = ((stream_strb_q & stream_strb_latest_q) >> strb_rotate_inv_q);
        else
          int_strb = ((push_i.strb << strb_rotate_q) & strb_q | (stream_strb_q >> strb_rotate_inv_q));
      end
    end
  end

  /* ensure that the stream follows the correct protocol */
  assign int_ready = pop_o.ready;

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni) begin
      int_data_q <= '0;
      int_strb_q <= '0;
      int_valid_q <= '0;
    end
    else if(clear_i) begin
      int_data_q <= '0;
      int_strb_q <= '0;
      int_valid_q <= '0;
    end
    else if(int_valid) begin
      int_data_q <= int_data;
      int_strb_q <= int_strb;
      int_valid_q <= ~int_ready;
    end
    else if(int_ready) begin
      int_valid_q <= 1'b0;
    end
  end
  assign pop_o.data = int_valid ? int_data : int_data_q;
  assign pop_o.strb = (int_valid | ctrl_i.last) ? int_strb : int_strb_q;
  assign pop_o.valid = int_valid | int_valid_q;

endmodule // hwpe_stream_sink_realign
