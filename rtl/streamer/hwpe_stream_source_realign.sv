/*
 * hwpe_stream_source_realign.sv
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
 * The **hwpe_stream_source_realign** module realigns HWPE-Streams loaded
 * in a misaligned fashion from memory. Specifically, it rotates `strb` signals
 * according to its control interface, produced along with addresses in the
 * address generator.
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hwpe_stream_source_realign_params:
 * .. table:: **hwpe_stream_source_realign** design-time parameters.
 *
 *   +-------------------+-------------+------------------------------------------------------------------------------------------------------------------------+
 *   | **Name**          | **Default** | **Description**                                                                                                        |
 *   +-------------------+-------------+------------------------------------------------------------------------------------------------------------------------+
 *   | *DECOUPLED*       | 0           | If 1, the module expects a HWPE-MemDecoupled interface instead of HWPE-Mem.                                            |
 *   +-------------------+-------------+------------------------------------------------------------------------------------------------------------------------+
 *   | *DATA_WIDTH*      | 32          | Width of input/output streams.                                                                                         |
 *   +-------------------+-------------+------------------------------------------------------------------------------------------------------------------------+
 *   | *STRB_FIFO_DEPTH* | 4           | Depth of the FIFO queue used for strobes; when full, the realigner will lower its ready signal at the input interface. |
 *   +-------------------+-------------+------------------------------------------------------------------------------------------------------------------------+
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hwpe_stream_source_realign_ctrl:
 * .. table:: **hwpe_stream_source_realign** input control signals.
 *
 *   +---------------+---------------+----------------------------------------------------------------------------------------------------+
 *   | **Name**      | **Type**      | **Description**                                                                                    |
 *   +---------------+---------------+----------------------------------------------------------------------------------------------------+
 *   | *enable*      | `logic`       | If 0, the realigner is fully clock-gated.                                                          |
 *   +---------------+---------------+----------------------------------------------------------------------------------------------------+
 *   | *strb_valid*  | `logic`       | If 1, the strobe at the `strb_i` interface is considered valid.                                    |
 *   +---------------+---------------+----------------------------------------------------------------------------------------------------+
 *   | *realign*     | `logic`       | If 1, the realigner is actively used to generate strobed HWPE-Streams. If 0, it is bypassed.       |
 *   +---------------+---------------+----------------------------------------------------------------------------------------------------+
 *   | *first*       | `logic`       | Strobe at 1 for the first packet in a line.                                                        |
 *   +---------------+---------------+----------------------------------------------------------------------------------------------------+
 *   | *last*        | `logic`       | Strobe at 1 for the last packet in a line.                                                         |
 *   +---------------+---------------+----------------------------------------------------------------------------------------------------+
 *   | *last_packet* | `logic`       | Strobe at 1 for the last packet of the transfer.                                                   |
 *   +---------------+---------------+----------------------------------------------------------------------------------------------------+
 *   | *line_length* | `logic[15:0]` | Length of a line in words, rounded by including also incomplete final words.                       |
 *   +---------------+---------------+----------------------------------------------------------------------------------------------------+
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hwpe_stream_source_realign_flags:
 * .. table:: **hwpe_stream_source_realign** output flags.
 *
 *   +-------------------+---------------+-----------------+
 *   | **Name**          | **Type**      | **Description** |
 *   +-------------------+---------------+-----------------+
 *   | *decoupled_stall* | `logic`       | Do not use.     |
 *   +-------------------+---------------+-----------------+
 *
 */

import hwpe_stream_package::*;

module hwpe_stream_source_realign #(
  parameter int unsigned DECOUPLED  = 0, // set to 1 if used with a TCDM stream that does not respect the zero-latency assumption,
                                         // e.g. it passes through a TCDM load FIFO.
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned STRB_FIFO_DEPTH = 4
)
(
  input  logic                    clk_i,
  input  logic                    rst_ni,
  input  logic                    test_mode_i,
  input  logic                    clear_i,

  input  ctrl_realign_t           ctrl_i,
  output flags_realign_t          flags_o,

  input  logic [DATA_WIDTH/8-1:0] strb_i,
  hwpe_stream_intf_stream.sink    push_i,
  hwpe_stream_intf_stream.source  pop_o
);

  logic [STRB_FIFO_DEPTH-1:0][DATA_WIDTH/8-1:0] strb_last_fifo, strb_first_fifo;
  logic [STRB_FIFO_DEPTH-1:0] last_packet_fifo;
  logic [DATA_WIDTH/8-1:0] int_strb;

  logic [$clog2(STRB_FIFO_DEPTH):0] strb_first_cnt;
  logic [$clog2(STRB_FIFO_DEPTH):0] strb_last_cnt;

  logic unsigned [$clog2(DATA_WIDTH/8):0] strb_rotate_d;
  logic unsigned [$clog2(DATA_WIDTH/8):0] strb_rotate_inv_d;
  logic [DATA_WIDTH-1:0]   stream_data_q;
  logic unsigned [$clog2(DATA_WIDTH/8):0] strb_rotate_q;
  logic unsigned [$clog2(DATA_WIDTH/8):0] strb_rotate_inv_q;

  logic unsigned [$clog2(DATA_WIDTH/8)+3:0] strb_rotate_q_shifted;
  logic unsigned [$clog2(DATA_WIDTH/8)+3:0] strb_rotate_inv_q_shifted;

  logic clk_gated;

  logic int_first;
  logic int_last;
  logic int_last_packet;

  /* clock gating */
  tc_clk_gating i_realign_gating (
    .clk_i     ( clk_i         ),
    .test_en_i ( test_mode_i   ),
    .en_i      ( ctrl_i.enable ),
    .clk_o     ( clk_gated     )
  );

  /* management of misaligned access */

  // since the source address generation could be decoupled from the received stream
  // (e.g. in case the load TCDM passes through FIFOs)
  generate
    if(DECOUPLED != 0) begin : decoupled_flags_gen

      logic [15:0] word_cnt, next_word_cnt;
      logic [15:0] line_length_m1;
      logic last_packet_q;

      assign line_length_m1 = (ctrl_i.realign == 1'b0) ? ctrl_i.line_length - 1 :
                                                         ctrl_i.line_length;

      always_comb
      begin
        next_word_cnt = word_cnt;
        if(push_i.valid & push_i.ready) begin
          next_word_cnt = word_cnt + 1;
        end
        if((push_i.valid & push_i.ready) && word_cnt == line_length_m1) begin
          next_word_cnt = '0;
        end
      end

      always_ff @(posedge clk_i or negedge rst_ni)
      begin
        if(~rst_ni) begin
          word_cnt <= '0;
        end
        else if(clear_i) begin
          word_cnt <= '0;
        end
        else begin
          word_cnt <= next_word_cnt;
        end
      end

      // misalignment flags generation
      always_comb
      begin : int_last_comb
        int_last = '1;
        if(word_cnt < line_length_m1) begin
          int_last = '0;
        end
      end
      always_comb
      begin : int_first_comb
        int_first  = '0;
        if(word_cnt == '0)
          int_first = '1;
      end

      // record strobe and release it when appropriate
      always_ff @(posedge clk_i or negedge rst_ni)
      begin
        if(~rst_ni) begin
          strb_first_fifo <= '1;
          strb_first_cnt <= '0;
        end
        else if (clear_i) begin
          strb_first_fifo <= '0;
          strb_first_cnt <= '0;
        end
        else begin
          if(ctrl_i.strb_valid & ctrl_i.first & push_i.valid & push_i.ready & int_first) begin
            strb_first_cnt <= strb_first_cnt;
            strb_first_fifo[0] <= strb_i;
            for(int i=1; i<STRB_FIFO_DEPTH; i++)
              strb_first_fifo[i] <= strb_first_fifo[i-1];
          end
          else if(ctrl_i.strb_valid & ctrl_i.first) begin
            strb_first_cnt <= strb_first_cnt + 1;
            strb_first_fifo[0] <= strb_i;
            for(int i=1; i<STRB_FIFO_DEPTH; i++)
              strb_first_fifo[i] <= strb_first_fifo[i-1];
          end
          else if(push_i.valid & push_i.ready & int_first) begin
            strb_first_cnt <= strb_first_cnt - 1;
          end
        end
      end

      always_ff @(posedge clk_i or negedge rst_ni)
      begin
        if(~rst_ni) begin
          strb_last_fifo  <= '1;
          strb_last_cnt  <= '0;
          last_packet_fifo <= '0;
        end
        else if (clear_i) begin
          strb_last_fifo  <= '1;
          strb_last_cnt  <= '0;
          last_packet_fifo <= '0;
        end
        else begin
          if(ctrl_i.strb_valid & ctrl_i.last & push_i.valid & push_i.ready & int_last) begin
            strb_last_fifo[0] <= strb_i;
            last_packet_fifo[0] <= ctrl_i.last_packet;
            for(int i=1; i<STRB_FIFO_DEPTH; i++) begin
              strb_last_fifo[i] <= strb_last_fifo[i-1];
              last_packet_fifo[i] <= last_packet_fifo[i-1];
            end
          end
          else if(ctrl_i.strb_valid & ctrl_i.last) begin
            strb_last_cnt <= strb_last_cnt + 1;
            strb_last_fifo[0] <= strb_i;
            last_packet_fifo[0] <= ctrl_i.last_packet;
            for(int i=1; i<STRB_FIFO_DEPTH; i++) begin
              strb_last_fifo[i] <= strb_last_fifo[i-1];
              last_packet_fifo[i] <= last_packet_fifo[i-1];
            end
          end
          else if(push_i.valid & push_i.ready & int_last) begin
            strb_last_cnt <= strb_last_cnt - 1;
          end
        end
      end

      always_comb
      begin
        int_strb = '1;
        int_last_packet = '0;
        if(int_first) begin
          if(ctrl_i.first & (strb_first_cnt == '0))
            int_strb = strb_i;
          else if(strb_first_cnt < 1)
            int_strb = '1; // don't care
          else
            int_strb = strb_first_fifo[strb_first_cnt-1];
        end
        else if(int_last) begin
          if(ctrl_i.last & (strb_last_cnt == '0)) begin
            int_strb = strb_i;
            int_last_packet = ctrl_i.last_packet;
          end
          else if(strb_last_cnt < 1) begin
            int_strb = '1; // don't care
            int_last_packet = '0; // don't care
          end
          else begin
            int_strb = strb_last_fifo[strb_last_cnt-1];
            int_last_packet = last_packet_fifo[strb_last_cnt-1];
          end
        end
      end

    end
    else begin : no_decoupled_flags_gen

      assign int_first = ctrl_i.first;
      assign int_last  = ctrl_i.last;
      assign int_last_packet = ctrl_i.last_packet;
      assign int_strb = strb_i;

    end
  endgenerate

  // save the strobes of the first misaligned transfer as a reference!
  // this implicitly assumes that all strobes result in a rotation - it
  // must be thus!!
  always_comb
  begin
    strb_rotate_d = '0;
    for (int i=0; i<DATA_WIDTH/8; i++)
      strb_rotate_d += ($clog2(DATA_WIDTH/8))'(int_strb[i]);
  end
  assign strb_rotate_inv_d = {($clog2(DATA_WIDTH/8)){1'b1}} - strb_rotate_d + 1;

  always_ff @(posedge clk_gated or negedge rst_ni)
  begin
    if(~rst_ni) begin
      strb_rotate_q <= '0;
      strb_rotate_inv_q <= '0;
    end
    else if (clear_i) begin
      strb_rotate_q <= '0;
      strb_rotate_inv_q <= '0;
    end
    else if (~int_last_packet & int_first) begin
      strb_rotate_q <= strb_rotate_d;
      strb_rotate_inv_q <= strb_rotate_inv_d;
    end
  end
  assign strb_rotate_q_shifted = strb_rotate_q << 3;
  assign strb_rotate_inv_q_shifted = strb_rotate_inv_q << 3;

  always_ff @(posedge clk_gated or negedge rst_ni)
  begin
    if(~rst_ni)
      stream_data_q <= '0;
    else if (clear_i)
      stream_data_q <= '0;
    // last packet is kept "forever"
    else if (~int_last_packet & push_i.valid & push_i.ready)
      stream_data_q <= push_i.data;
  end
  always_comb
  begin
    pop_o.data = push_i.data;
    if(ctrl_i.realign) begin
      if ((strb_rotate_q != '1) && (strb_rotate_q != '0))
        pop_o.data = push_i.data << strb_rotate_q_shifted | stream_data_q >> strb_rotate_inv_q_shifted;
    end
  end
  assign pop_o.valid = (~ctrl_i.realign) ? push_i.valid :
                       (int_last_packet) ? push_i.valid :
                                           push_i.valid & ~int_first & (int_last | (|int_strb));
  assign push_i.ready = (~ctrl_i.realign) ? pop_o.ready :
                        (int_last_packet) ? pop_o.ready :
                                            pop_o.ready | int_first;

  assign pop_o.strb = '1;

  assign flags_o.decoupled_stall = ($signed(strb_first_cnt) >= $signed(STRB_FIFO_DEPTH-4)) ? '1 : '0;

endmodule // hwpe_stream_source_realign
