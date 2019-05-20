/*
 * hwpe_stream_addressgen.sv
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
 * The **hwpe_stream_addressgen** module is used to generate addresses to
 * load or store HWPE-Stream streams, as well as the related byte enable
 * strobes (`gen_addr_o` and `gen_strb_o` respectively).
 * The address generator can be used to generate address from a
 * three-dimensional space of “words”, “lines” and “features”. Lines and
 * features can be separated by a certain stride, and a roll parameter can
 * be used to reuse the same offsets multiple times.
 *
 * The multiple loop functionality is partially overlapped by the functionality
 * provided by the microcode processor `hwce_ctrl_ucode` that can be embedded
 * in HWPEs. The latter is much more flexible and smaller, but less fast.
 * When using a single loop in the address generator, the HWPE designer should
 * statically set `line_stride` =0, `feat_length` =1, `feat_stride` =0.
 *
 * The address generation loop considers three-dimensional vectors, where
 * the three dimensions are called *packet*, *line* and *features* from the
 * innermost to the outermost.
 * One iteration is performed per each cycle when `enable_i` is 1.
 * Feature loops can behave in two different fashions, modeled after the
 * behavior of input/output features in CNNs.
 * The following piece of code resumes the basic functionality provided by
 * the address generator, discarding more complex situations where the
 * address is misaligned (resulting in one more transaction, introduced
 * automatically).
 *
 * .. code-block:: C
 *
 *   int word_addr=0, line_addr=0, feat_addr=0;
 *   int trans_idx=0;
 *   while(trans_idx < trans_size) {
 *     if(!enable)
 *       continue;
 *     for(int feat_idx=0; feat_idx<feat_roll; feat_idx++) { // feature loop
 *       for(int line_idx=0; line_idx<feat_length; line_idx++) { // line loop
 *         for(int word_idx=0; word_idx<line_length; word_idx++) { // word loop
 *           gen_addr = base_addr + feat_addr + line_addr + word_idx * STEP;
 *         }
 *         line_addr += line_stride;
 *       }
 *       if((loop_outer) && (feat_idx == feat_roll-1)) {
 *         feat_addr += feat_stride;
 *         feat_idx  = 0;
 *       }
 *       else if ((!loop_outer) && (feat_idx < feat_roll-1)){
 *         feat_addr += feat_stride;
 *       }
 *       else if ((!loop_outer) && (feat_idx == feat_roll-1)){
 *         feat_addr = 0;
 *         feat_idx  = 0;
 *       }
 *     }
 *   }
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hwpe_stream_addressgen_params:
 * .. table:: **hwpe_stream_addressgen** design-time parameters.
 *
 *   +-------------------------+------------------------------------+---------------------------------------------------------------------------------------------+
 *   | **Name**                | **Default**                        | **Description**                                                                             |
 *   +-------------------------+------------------------------------+---------------------------------------------------------------------------------------------+
 *   | *REALIGN_TYPE*          | HWPE_STREAM_REALIGN_SOURCE         | Type of realignment, can be set to HWPE_STREAM_REALIGN{SOURCE,SINK}.                        |
 *   +-------------------------+------------------------------------+---------------------------------------------------------------------------------------------+
 *   | *STEP*                  | 4                                  | Step of address generation (untested with != 4).                                            |
 *   +-------------------------+------------------------------------+---------------------------------------------------------------------------------------------+
 *   | *TRANS_CNT*             | 16                                 | Number of bits supported in the transaction counter, which will overflow at 2^ `TRANS_CNT`. |
 *   +-------------------------+------------------------------------+---------------------------------------------------------------------------------------------+
 *   | *CNT*                   | 10                                 | Number of bits supported in non-transaction counters, which will overflow at 2^ `CNT`.      |
 *   +-------------------------+------------------------------------+---------------------------------------------------------------------------------------------+
 *   | *DELAY_FLAGS*           | 0                                  | If 1, delay the production of flags by one cycle.                                           |
 *   +-------------------------+------------------------------------+---------------------------------------------------------------------------------------------+
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hwpe_stream_addressgen_ctrl:
 * .. table:: **hwpe_stream_addressgen** input control signals.
 *
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | **Name**                         | **Type**             | **Description**                                                                                             |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | *base_addr*                      | `logic[31:0]`        | Byte-aligned base address of the stream in the HWPE-accessible memory.                                      |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | *trans_size*                     | `logic[31:0]`        | Total size of transaction; only the `TRANS_CNT` LSB are actually used.                                      |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | *line_stride*                    | `logic[15:0]`        | Distance between two adjacent lines in bytes.                                                               |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | *line_length*                    | `logic[15:0]`        | Length of a line in words, rounded by including also incomplete final words.                                |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | *feat_stride*                    | `logic[15:0]`        | Distance between two adjacent features in bytes.                                                            |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | *feat_length*                    | `logic[15:0]`        | Length of a feature in number of lines.                                                                     |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | *loop_outer*                     | `logic`              | Whether this corresponds to an outer or inner feature loop.                                                 |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | *feat_roll*                      | `logic[15:0]`        | After this number of features, depending on *loop_outer*, feature index will be rolled back or incremented. |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | *realign_type*                   | `logic`              | Unused.                                                                                                     |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | *line_length_remainder*          | `logic[7:0]`         | Unused.                                                                                                     |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hwpe_stream_addressgen_flags:
 * .. table:: **hwpe_stream_addressgen** output flags.
 *
 *   +-----------------+------------------+----------------------------------------------------------------------------------------------+
 *   | **Name**        | **Type**         | **Description**                                                                              |
 *   +-----------------+------------------+----------------------------------------------------------------------------------------------+
 *   | *realign_flags* | `ctrl_realign_t` | Control signals to be used for realignment by **hwpe_stream_{source,sink}_realign** modules. |
 *   +-----------------+------------------+----------------------------------------------------------------------------------------------+
 *   | *word_update*   | `logic`          | 1 when the word loop has been updated.                                                       |
 *   +-----------------+------------------+----------------------------------------------------------------------------------------------+
 *   | *line_update*   | `logic`          | 1 when the line loop has been updated.                                                       |
 *   +-----------------+------------------+----------------------------------------------------------------------------------------------+
 *   | *feat_update*   | `logic`          | 1 when the feature loop has been updated.                                                    |
 *   +-----------------+------------------+----------------------------------------------------------------------------------------------+
 *   | *in_progress*   | `logic`          | 1 when the address generation has progressed.                                                |
 *   +-----------------+------------------+----------------------------------------------------------------------------------------------+
 *
 */

import hwpe_stream_package::*;

module hwpe_stream_addressgen
#(
  parameter int unsigned REALIGN_TYPE = HWPE_STREAM_REALIGN_SOURCE,
  parameter int unsigned DECOUPLED    = 0,
  parameter int unsigned STEP         = 4,
  parameter int unsigned TRANS_CNT    = 16,
  parameter int unsigned CNT          = 10, // number of bits used within the internal counter
  parameter int unsigned DELAY_FLAGS  = 0
)
(
  // global signals
  input  logic                clk_i,
  input  logic                rst_ni,
  input  logic                test_mode_i,
  // local enable and clear
  input  logic                enable_i,
  input  logic                clear_i,
  // generated output address
  output logic [31:0]         gen_addr_o,
  output logic [STEP-1:0]     gen_strb_o,
  // control channel
  input  ctrl_addressgen_t    ctrl_i,
  output flags_addressgen_t   flags_o
);

  logic        [31:0] base_addr;
  logic        [31:0] trans_size_m2;
  logic signed [15:0] line_stride;
  logic        [15:0] line_length_m1;
  logic signed [15:0] feat_stride;
  logic        [15:0] feat_length_m1;
  logic        [15:0] feat_roll_m1;

  logic        misalignment;
  logic        misalignment_first;
  logic        misalignment_last;
  logic [31:0] gen_addr_int;
  logic        enable_int /*verilator clock_enable*/;
  logic        last_packet;

  logic [TRANS_CNT-1:0] overall_counter;
  logic [CNT-1:0] word_counter;
  logic [CNT-1:0] line_counter;
  logic [CNT-1:0] feat_counter;
  logic [31:0]    word_addr;
  logic [31:0]    line_addr;
  logic [31:0]    feat_addr;

  logic [STEP-1:0] gen_strb_int;
  logic [STEP-1:0] gen_strb_r;

  flags_addressgen_t flags, flags_nb;

  assign base_addr      = ctrl_i.base_addr;
  assign trans_size_m2  = (misalignment == 1'b0) ? ctrl_i.trans_size - 2 :
                                                   ctrl_i.trans_size - 1;
  assign line_stride    = ctrl_i.line_stride;
  assign line_length_m1 = (misalignment == 1'b0) ? ctrl_i.line_length - 1 :
                                                   ctrl_i.line_length;
  assign feat_stride    = ctrl_i.feat_stride;
  assign feat_length_m1 = ctrl_i.feat_length - 1;
  assign feat_roll_m1   = ctrl_i.feat_roll - 1;

  generate
    if(REALIGN_TYPE == HWPE_STREAM_REALIGN_SINK) begin : last_packet_sink_gen
      assign last_packet = (misalignment==1'b1 && overall_counter == trans_size_m2) ? 1'b1 : 1'b0;
    end // last_packet_sink_gen
    else begin : last_packet_source_gen
      assign last_packet = 1'b0;
    end // last_packet_source_gen
  endgenerate

  assign enable_int = enable_i | last_packet;

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni)
      flags_nb.realign_flags.last_packet <= '0;
    else if(clear_i)
      flags_nb.realign_flags.last_packet <= '0;
    else if(enable_int)
      flags_nb.realign_flags.last_packet <= (misalignment==1'b1 && overall_counter == trans_size_m2) ? 1'b1 : 1'b0;
  end

  // flags generation
  always_comb
  begin
    if(enable_int == 1'b1) begin
      if(word_counter < line_length_m1) begin
        flags_nb.word_update = 1'b1;
        flags_nb.line_update = 1'b0;
        flags_nb.feat_update = 1'b0;
      end
      else if(line_counter < feat_length_m1) begin
        flags_nb.word_update = 1'b1;
        flags_nb.line_update = 1'b1;
        flags_nb.feat_update = 1'b0;
      end
      else begin
        flags_nb.word_update = 1'b1;
        flags_nb.line_update = 1'b1;
        flags_nb.feat_update = 1'b1;
      end
    end
    else begin
      flags_nb.word_update = 1'b0;
      flags_nb.line_update = 1'b0;
      flags_nb.feat_update = 1'b0;
    end
  end

  // misalignment flags generation
  always_comb
  begin : misalignment_last_flags_comb
    if(word_counter < line_length_m1) begin
      misalignment_last  = '0;
    end
    else begin
      misalignment_last  = '1;
    end
  end
  always_comb
  begin : misalignment_first_flags_comb
    misalignment_first  = '0;
    if(word_counter == '0)
      misalignment_first  = '1;
  end

  // address generation
  always_ff @(posedge clk_i or negedge rst_ni)
  begin : address_gen_counters_proc
    if (rst_ni==1'b0) begin
      word_addr    <= '0;
      line_addr    <= '0;
      feat_addr    <= '0;
      word_counter    <= '0;
      line_counter    <= '0;
      feat_counter    <= '0;
      overall_counter <= '0;
    end
    else if (clear_i == 1'b1) begin
      word_addr    <= '0;
      line_addr    <= '0;
      feat_addr    <= '0;
      word_counter    <= '0;
      line_counter    <= '0;
      feat_counter    <= '0;
      overall_counter <= '0;
    end
    else begin
      if(enable_int == 1'b0) begin
        word_addr    <= word_addr;
        line_addr    <= line_addr;
        feat_addr    <= feat_addr;
        word_counter    <= word_counter;
        line_counter    <= line_counter;
        feat_counter    <= feat_counter;
        overall_counter <= overall_counter;
      end
      else begin
        if(word_counter < line_length_m1) begin
          word_addr <= word_addr + STEP;
          line_addr <= line_addr;
          feat_addr <= feat_addr;
          word_counter <= word_counter + 1;
          line_counter <= line_counter;
          feat_counter <= feat_counter;
        end
        else if(line_counter < feat_length_m1) begin
          word_addr <= '0;
          line_addr <= line_addr + {{16{line_stride[15]}}, line_stride};
          feat_addr <= feat_addr;
          word_counter <= '0;
          line_counter <= line_counter + 1;
          feat_counter <= feat_counter;
        end
        /* in outer loops, update feat_addr and reset feat_counter when feat_counter == feat_roll_m1 */
        else if((ctrl_i.loop_outer == 1'b1) && ((feat_counter == feat_roll_m1) || (ctrl_i.feat_roll == '0))) begin
          word_addr <= '0;
          line_addr <= '0;
          feat_addr <= feat_addr + {{16{feat_stride[15]}}, feat_stride};
          word_counter <= '0;
          line_counter <= '0;
          feat_counter <= '0;
        end
        /* in outer loops, update feat_counter when feat_counter != feat_roll_m1 */
        else if((ctrl_i.loop_outer == 1'b1) && ((feat_counter < feat_roll_m1) || (ctrl_i.feat_roll == '0))) begin
          word_addr <= '0;
          line_addr <= '0;
          feat_addr <= feat_addr;
          word_counter <= '0;
          line_counter <= '0;
          feat_counter <= feat_counter + 1;
        end
        /* in inner loops, update feat_addr and feat_counter when feat_counter != feat_roll_m1 */
        else if((ctrl_i.loop_outer == 1'b0) && ((feat_counter < feat_roll_m1) || (ctrl_i.feat_roll == '0))) begin
          word_addr <= '0;
          line_addr <= '0;
          feat_addr <= feat_addr + {{16{feat_stride[15]}}, feat_stride};
          word_counter <= '0;
          line_counter <= '0;
          feat_counter <= feat_counter + 1;
        end
        else begin
          word_addr <= '0;
          line_addr <= '0;
          feat_addr <= '0;
          word_counter <= '0;
          line_counter <= '0;
          feat_counter <= '0;
        end
        /* ignore one transaction for the overall counter when there is a misalignment */
        if(~misalignment | ~misalignment_first)
          overall_counter <= overall_counter + 1;
      end
    end
  end

  logic trans_size_m2_is_ffff;
  assign trans_size_m2_is_ffff = (trans_size_m2 == '1) ? 1'b1 : 1'b0;

  logic overall_counter_is_0;
  assign overall_counter_is_0 = (overall_counter == '0) ? 1'b1 : 1'b0;

  generate
    if((DECOUPLED == 0) && (REALIGN_TYPE == HWPE_STREAM_REALIGN_SOURCE)) begin
      always_ff @(posedge clk_i or negedge rst_ni)
      begin
        if (rst_ni==1'b0)
          flags_nb.in_progress <= 1'b1;
        else if (clear_i==1'b1)
          flags_nb.in_progress <= 1'b1;
        else
          if(trans_size_m2 == '1)
            flags_nb.in_progress <= 1'b0;
          else if (overall_counter < trans_size_m2)
            flags_nb.in_progress <= 1'b1;
          else if ((overall_counter == trans_size_m2) && (enable_int == 1'b0))
            flags_nb.in_progress <= 1'b1;
          else
            flags_nb.in_progress <= 1'b0;
      end
    end
    else begin
      always_ff @(posedge clk_i or negedge rst_ni)
      begin
        if (rst_ni==1'b0)
          flags_nb.in_progress <= 1'b1;
        else if (clear_i==1'b1)
          flags_nb.in_progress <= 1'b1;
        else
          if(trans_size_m2_is_ffff)
            flags_nb.in_progress <= overall_counter_is_0;
          else if (overall_counter < trans_size_m2)
            flags_nb.in_progress <= 1'b1;
          else if ((overall_counter == trans_size_m2) && (enable_int == 1'b0))
            flags_nb.in_progress <= 1'b1;
          else
            flags_nb.in_progress <= 1'b0;
      end
    end
  endgenerate

  assign gen_addr_int = base_addr + feat_addr + line_addr + word_addr;

  /* management of misaligned addresses */
  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni)
      misalignment <= 1'b0;
    else if(clear_i)
      misalignment <= 1'b0;
    else begin
      misalignment <= (base_addr   [1:0] != '0) ? 1'b1 :
                      (line_stride [1:0] != '0) ? 1'b1 :
                      (feat_stride [1:0] != '0) ? 1'b1 : 1'b0;
    end
  end

  assign gen_addr_o = { gen_addr_int[31:2] , 2'b0 };

  always_comb
  begin
    gen_strb_int = '1;
    if(misalignment) begin
      if (misalignment_first) begin
        gen_strb_int =   gen_strb_int << gen_addr_int[1:0];
      end
      if (misalignment_last) begin
        gen_strb_int = ~(gen_strb_int << gen_addr_int[1:0]);
      end
    end
  end

  always_comb
  begin
    flags = flags_nb;
    flags.realign_flags.enable  = misalignment;
    flags.realign_flags.realign = misalignment;
    flags.realign_flags.first   = misalignment_first;
    flags.realign_flags.last    = misalignment_last;
    flags.realign_flags.line_length = ctrl_i.line_length;
    flags.realign_flags.strb_valid = '1;
  end

  generate

    // auxiliary variable used to avoid conflicts between always_ff & assign
    flags_addressgen_t aux;

    logic strb_valid_r0, strb_valid_r1;
    always_ff @(posedge clk_i or negedge rst_ni)
    begin
      if(~rst_ni) begin
        strb_valid_r0 <= '0;
        strb_valid_r1 <= '0;
      end
      else if(clear_i) begin
        strb_valid_r0 <= '0;
        strb_valid_r1 <= '0;
      end
      else begin
        strb_valid_r0 <= enable_int;
        strb_valid_r1 <= strb_valid_r0;
      end
    end

    assign flags_o.word_update = aux.word_update;
    assign flags_o.line_update = aux.line_update;
    assign flags_o.feat_update = aux.feat_update;
    assign flags_o.in_progress = aux.in_progress;

    if(DELAY_FLAGS != 0) begin : delay_flags_gen

      // this is required to align the flags with the TCDM response phase
      // in some accelerators (it can be disabled, or done externally)
      always_ff @(posedge clk_i or negedge rst_ni)
      begin
        if(~rst_ni) begin
          aux <= '0;
          gen_strb_r <= '0;
        end
        else if(clear_i) begin
          aux <= '0;
          gen_strb_r <= '0;
        end
        else begin
          aux <= flags;
          gen_strb_r <= gen_strb_int;
        end
      end
      if(REALIGN_TYPE == HWPE_STREAM_REALIGN_SOURCE) begin
        always_comb
        begin
          flags_o.realign_flags = aux.realign_flags;
          flags_o.realign_flags.strb_valid = strb_valid_r0 & (aux.realign_flags.first | aux.realign_flags.last);
        end
        assign gen_strb_o = gen_strb_r;
      end
      else begin
        always_comb
        begin
          flags_o.realign_flags = flags.realign_flags;
          flags_o.realign_flags.strb_valid = enable_int & (flags.realign_flags.first | flags.realign_flags.last);
        end
        assign gen_strb_o = gen_strb_int;
      end

    end
    else begin : no_delay_flags_gen

      assign aux = flags;
      assign gen_strb_r = gen_strb_int;

      always_comb
      begin
        flags_o.realign_flags = flags.realign_flags;
        flags_o.realign_flags.strb_valid = enable_int & (flags.realign_flags.first | flags.realign_flags.last);
      end
      assign gen_strb_o = gen_strb_int;

    end
  endgenerate

endmodule // hwpe_stream_addressgen
