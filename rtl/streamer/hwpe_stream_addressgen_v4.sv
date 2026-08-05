/*
 * hwpe_stream_addressgen_v4.sv
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
 * The **hwpe_stream_addressgen_v4** module is used to generate addresses to
 * load or store HWPE-Stream stream. In this version of the address generator,
 * the address is itself carried within a HWPE-Stream, making it easily stallable.
 * The address generator can be used to generate address from a
 * five-dimensional space, which can be visited with configurable strides in all
 * five dimensions.
 *
 * The multiple loop functionality is partially overlapped by the functionality
 * provided by the microcode processor `hwce_ctrl_ucode` that can be embedded
 * in HWPEs. The latter is much more flexible and smaller, but less fast.
 *
 * One iteration is performed per each cycle when `enable_i` is 1 and the output
 * `addr_o` stream is ready. `presample_i` should be 1 in the first cycle in which
 * the address generator can start generating addresses, and no further.
 * The following piece of pseudo-C code resumes the basic functionality provided by
 * the address generator.
 *
 * .. code-block:: C
 *
 *   hwpe_stream_addressgen_v4(
 *     int base_addr,                                                          // base address (byte-aligned)
 *     int d0_len,    int d1_len,    int d2_len,    int d3_len,   int tot_len, // d0..d3,total length (in number of transactions)
 *     int d0_stride, int d1_stride, int d2_stride, int d3_stride, int d4_stride, // d0..d4 strides (in bytes)
 *     int *d0_addr,  int *d1_addr,  int *d2_addr,  int *d3_addr,  int *d4_addr,  // d0..d4 addresses (by reference)
 *     int *d0_cnt,   int *d1_cnt,   int *d2_cnt,   int *d3_cnt,   int *ov_cnt    // d0..d3,overall counters (by reference)
 *   ) {
 *     // A dimension counts dN_cnt from 1 to len_eff(N), so its index is dN_cnt-1
 *     // running up and len_eff(N)-dN_cnt running down. It is at its last index when:
 *     at_top(N)    = down(N) ? (*dN_cnt == 1) : (*dN_cnt == len_eff(N));
 *     // A second length, switched by an outer dimension only: bits at or below N are
 *     // masked off, which also keeps at_top -> len_eff -> at_top acyclic. tot_len has
 *     // to account for the shortened sweeps and for the skipped elements.
 *     len_eff(N)   = (dN_len_last_1h & at_top & ~((2 << N)-1)) ? dN_len_last : dN_len;
 *     // A second stride, switched by any dimension. A second address stepped next to
 *     // the first always holds idx*dN_stride_last, so no multiplier is needed.
 *     use_last(N)  = (dN_last_1h & at_top) != 0;
 *     addr(N)      = use_last(N) ? *dN_addr_last : *dN_addr;
 *     step(N)      = down(N) ? -dN_stride      : dN_stride;
 *     step_last(N) = down(N) ? -dN_stride_last : dN_stride_last;
 *     advance(N) { *dN_addr += step(N); *dN_addr_last += step_last(N); *dN_cnt += 1; }
 *     restart(N) { // the dimension directly above N moved
 *       down(N)       = alternate_1h[N] ? !down(N) : 0;
 *       *dN_addr      = alt_skip_1h[N] ? *dN_addr      - step(N)      // skip the repeat
 *                     : down(N)        ? *dN_addr                     // resume from the top
 *                     :                  0;                           // restart at the bottom
 *       *dN_addr_last = alt_skip_1h[N] ? *dN_addr_last - step_last(N)
 *                     : down(N)        ? *dN_addr_last
 *                     :                  0;
 *       *dN_cnt       = alt_skip_1h[N] ? 2 : 1;
 *     }
 *     reset(N)   { down(N) = 0; *dN_addr = 0; *dN_addr_last = 0; *dN_cnt = 1; }
 *     // compute current address
 *     int current_addr = 0;
 *     int done = 0;
 *     if (dim_enable_1h & 0x1 == 0) { // 1-dimensional streaming
 *       current_addr = base_addr + addr(0);
 *     }
 *     else if(dim_enable_1h & 0x2 == 0) { // 2-dimensional streaming
 *       current_addr = base_addr + addr(1) + addr(0);
 *     }
 *     else if(dim_enable_1h & 0x4 == 0) { // 3-dimensional streaming
 *       current_addr = base_addr + addr(2) + addr(1) + addr(0);
 *     }
 *     else if(dim_enable_1h & 0x8 == 0) { // 4-dimensional streaming
 *       current_addr = base_addr + addr(3) + addr(2) + addr(1) + addr(0);
 *     }
 *     else { // 5-dimensional streaming
 *       current_addr = base_addr + *d4_addr + addr(3) + addr(2) + addr(1) + addr(0);
 *     }
 *     // update counters and dimensional addresses
 *     if(*ov_cnt == tot_len) {
 *       done = 1;
 *     }
 *     if((*d0_cnt < len_eff(0)) || (dim_enable_1h & 0x1 == 0)) {
 *       advance(0);
 *     }
 *     else if ((*d1_cnt < len_eff(1)) || (dim_enable_1h & 0x2 == 0)) {
 *       restart(0); advance(1);
 *     }
 *     else if ((*d2_cnt < len_eff(2)) || (dim_enable_1h & 0x4 == 0)) {
 *       reset(0); restart(1); advance(2);
 *     }
 *     else if ((*d3_cnt < len_eff(3)) || (dim_enable_1h & 0x8 == 0)) {
 *       reset(0); reset(1); restart(2); advance(3);
 *     }
 *     else {
 *       reset(0); reset(1); reset(2); restart(3);
 *       *d4_addr = *d4_addr + d4_stride;
 *     }
 *     *ov_cnt = *ov_cnt + 1;
 *     return current_addr, done;
 *   }
 *
 * With a parameter bit clear the matching control fields are ignored, so every
 * extension is off by default and a zero-initialised control struct keeps working.
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hwpe_stream_addressgen_v4_params:
 * .. table:: **hwpe_stream_addressgen_v4** design-time parameters.
 *
 *   +-------------------------+------------------------------------+---------------------------------------------------------------------------------------------+
 *   | **Name**                | **Default**                        | **Description**                                                                             |
 *   +-------------------------+------------------------------------+---------------------------------------------------------------------------------------------+
 *   | *TRANS_CNT*             | 32                                 | Number of bits supported in the transaction counter, which will overflow at 2^ `TRANS_CNT`. |
 *   +-------------------------+------------------------------------+---------------------------------------------------------------------------------------------+
 *   | *CNT*                   | 32                                 | Number of bits supported in non-transaction counters, which will overflow at 2^ `CNT`.      |
 *   +-------------------------+------------------------------------+---------------------------------------------------------------------------------------------+
 *   | *DIM_ENABLE_1H*         | 4'b1111                            | Bit N: dimension N may be bounded. 0 makes it free-run whatever the control says.            |
 *   +-------------------------+------------------------------------+---------------------------------------------------------------------------------------------+
 *   | *STRIDE_LAST_1H*        | 4'b0000                            | Bit N: give dimension N a second stride, used at the last index of another one.             |
 *   +-------------------------+------------------------------------+---------------------------------------------------------------------------------------------+
 *   | *LEN_LAST_1H*           | 4'b0000                            | Bit N: give dimension N a second length, used at the last index of an outer one.            |
 *   +-------------------------+------------------------------------+---------------------------------------------------------------------------------------------+
 *   | *ALTERNATE_1H*          | 4'b0000                            | Bit N: let dimension N sweep up and down instead of always up.                              |
 *   +-------------------------+------------------------------------+---------------------------------------------------------------------------------------------+
 *   | *ALT_SKIP_1H*           | 4'b0000                            | Bit N: let dimension N skip the shared element. Bits outside `ALTERNATE_1H` do nothing.     |
 *   +-------------------------+------------------------------------+---------------------------------------------------------------------------------------------+
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hwpe_stream_addressgen_v4_ctrl:
 * .. table:: **hwpe_stream_addressgen_v4** input control signals.
 *
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | **Name**                         | **Type**             | **Description**                                                                                             |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | *base_addr*                      | `logic[31:0]`        | Byte-aligned base address of the stream in the HWPE-accessible memory.                                      |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | *tot_len*                        | `logic[31:0]`        | Total number of transactions in stream; only the `TRANS_CNT` LSB are actually used.                         |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | *dN_len*                         | `logic[31:0]`        | dN length in number of transactions (N = 0..3)                                                              |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | *dN_stride*                      | `logic[31:0]`        | dN stride in bytes (N = 0..3)                                                                               |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | *d4_stride*                      | `logic[31:0]`        | d4 stride in bytes                                                                                          |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | *dim_enable_1h*                  | `logic[3:0]`         | One-hot switch to enable 5-d counting (1111), 4-d (0111), 3-d (0011), 2-d (0001), or 1-d (0000).            |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | *dN_stride_last*                 | `logic[31:0]`        | Second stride of dimension N, in bytes (N = 0..3).                                                          |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | *dN_last_1h*                     | `logic[3:0]`         | Bit j: use `dN_stride_last` while dimension j is at its last index. 0 turns it off.                         |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | *dN_len_last*                    | `logic[31:0]`        | Second length of dimension N, in transactions (N = 0..3).                                                   |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | *dN_len_last_1h*                 | `logic[3:0]`         | Bit j: use `dN_len_last` while dimension j is at its last index. Bits at or below N do nothing.             |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | *alternate_1h*                   | `logic[3:0]`         | Bit N: dimension N turns around every time dimension N+1 moves.                                             |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | *alt_skip_1h*                    | `logic[3:0]`         | Bit N: with `alternate_1h[N]`, skip the element shared with the previous sweep.                             |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hwpe_stream_addressgen_v4_flags:
 * .. table:: **hwpe_stream_addressgen_v4** output flags.
 *
 *   +-----------------+------------------+-----------------------------------------------+
 *   | **Name**        | **Type**         | **Description**                               |
 *   +-----------------+------------------+-----------------------------------------------+
 *   | *done*          | `logic`          | 1 when the address generation has finished.   |
 *   +-----------------+------------------+-----------------------------------------------+
 *
 */


import hwpe_stream_package::*;

module hwpe_stream_addressgen_v4
#(
  parameter int unsigned TRANS_CNT  = 32,
  parameter int unsigned CNT        = 32,    // number of bits used within the internal counter
  parameter bit [3:0] DIM_ENABLE_1H  = 4'b1111, // Number of dimensions enabled on HW side
  parameter bit [3:0] STRIDE_LAST_1H = 4'b0000, // Dimensions that get a second stride
  parameter bit [3:0] LEN_LAST_1H    = 4'b0000, // Dimensions that get a second length
  parameter bit [3:0] ALTERNATE_1H   = 4'b0000, // Dimensions that can sweep up and down
  parameter bit [3:0] ALT_SKIP_1H    = 4'b0000  // Of those, the ones that can skip the shared element
)
(
  // global signals
  input  logic                   clk_i,
  input  logic                   rst_ni,
  // local enable and clear
  input  logic                   enable_i,
  input  logic                   clear_i,
  input  logic                   presample_i,
  // generated output address
  hwpe_stream_intf_stream.source addr_o,
  // control channel
  input  ctrl_addressgen_v4_t    ctrl_i,
  output flags_addressgen_v4_t   flags_o
);

  logic signed [31:0] d0_stride;
  logic signed [31:0] d1_stride;
  logic signed [31:0] d2_stride;
  logic signed [31:0] d3_stride;
  logic signed [31:0] d4_stride;

  // second stride, used at the last index of the dimensions picked by dN_last_1h
  logic signed [31:0] d0_stride_last;
  logic signed [31:0] d1_stride_last;
  logic signed [31:0] d2_stride_last;
  logic signed [31:0] d3_stride_last;

  // increment of a dimension mid-sweep, negative while it runs downwards
  logic signed [31:0] d0_step,      d1_step,      d2_step,      d3_step;
  logic signed [31:0] d0_step_last, d1_step_last, d2_step_last, d3_step_last;

  // where a dimension restarts from when the dimension above it moves
  logic [31:0]    d0_roll_addr,      d1_roll_addr,      d2_roll_addr,      d3_roll_addr;
  logic [31:0]    d0_roll_addr_last, d1_roll_addr_last, d2_roll_addr_last, d3_roll_addr_last;
  logic [CNT-1:0] d0_roll_counter,   d1_roll_counter,   d2_roll_counter,   d3_roll_counter;

  // length in force for this sweep
  logic [31:0] d0_len_eff, d1_len_eff, d2_len_eff, d3_len_eff;

  // one bit per dimension, like dim_enable_1h
  logic [3:0] alternate;    // dimension may sweep up and down
  logic [3:0] alt_skip;     // and may skip the shared element
  logic [3:0] down;         // sweep direction, 0 where the dimension only runs up
  logic [3:0] down_next;    // the sweep after the next restart runs downwards
  logic [3:0] at_top;       // dimension sits at its last index
  logic [3:0] use_last;     // dimension uses its second stride
  logic [3:0] use_len_last; // dimension uses its second length

  logic [31:0] gen_addr_int;
  logic        done;

  logic [TRANS_CNT-1:0] overall_counter_d;
  logic [CNT-1:0]       d0_counter_d;
  logic [CNT-1:0]       d1_counter_d;
  logic [CNT-1:0]       d2_counter_d;
  logic [CNT-1:0]       d3_counter_d;
  logic [CNT-1:0]       d4_counter_d;
  logic [31:0]          d0_addr_d;
  logic [31:0]          d1_addr_d;
  logic [31:0]          d2_addr_d;
  logic [31:0]          d3_addr_d;
  logic [31:0]          d4_addr_d;
  logic [31:0]          d0_addr_last_d;
  logic [31:0]          d1_addr_last_d;
  logic [31:0]          d2_addr_last_d;
  logic [31:0]          d3_addr_last_d;
  logic [3:0]           down_d;
  logic [TRANS_CNT-1:0] overall_counter_q;
  logic [CNT-1:0]       d0_counter_q;
  logic [CNT-1:0]       d1_counter_q;
  logic [CNT-1:0]       d2_counter_q;
  logic [CNT-1:0]       d3_counter_q;
  logic [CNT-1:0]       d4_counter_q;
  logic [31:0]          d0_addr_q;
  logic [31:0]          d1_addr_q;
  logic [31:0]          d2_addr_q;
  logic [31:0]          d3_addr_q;
  logic [31:0]          d4_addr_q;
  logic [31:0]          d0_addr_last_q;
  logic [31:0]          d1_addr_last_q;
  logic [31:0]          d2_addr_last_q;
  logic [31:0]          d3_addr_last_q;
  logic [3:0]           down_q;

  logic        addr_valid_d, addr_valid_q;

  assign d0_stride = $signed(ctrl_i.d0_stride);
  assign d1_stride = $signed(ctrl_i.d1_stride);
  assign d2_stride = $signed(ctrl_i.d2_stride);
  assign d3_stride = $signed(ctrl_i.d3_stride);
  assign d4_stride = $signed(ctrl_i.d4_stride);

  // A feature that was not built is not driven: the control field is ignored and the
  // logic behind it disappears.
  assign d0_stride_last = STRIDE_LAST_1H[0] ? $signed(ctrl_i.d0_stride_last) : '0;
  assign d1_stride_last = STRIDE_LAST_1H[1] ? $signed(ctrl_i.d1_stride_last) : '0;
  assign d2_stride_last = STRIDE_LAST_1H[2] ? $signed(ctrl_i.d2_stride_last) : '0;
  assign d3_stride_last = STRIDE_LAST_1H[3] ? $signed(ctrl_i.d3_stride_last) : '0;

  // A dimension may sweep both ways, and may skip the element shared with the sweep
  // that just ended, only where both the parameter and the control bit say so. The
  // direction is read through the parameter, not straight out of the flop, so a
  // dimension not built to sweep both ways has no negate-and-mux in front of its
  // stride and leaves down_q driving nothing but itself.
  assign alternate = ALTERNATE_1H & ctrl_i.alternate_1h;
  assign alt_skip  = ALT_SKIP_1H  & ctrl_i.alt_skip_1h & alternate;
  assign down      = ALTERNATE_1H & down_q;
  assign down_next = alternate & ~down;

  // Only a dimension outside N may switch the length of N: an inner one runs a whole
  // sweep per step of N, so "inner at its last index" does not identify a step of N.
  // Masking self and inner also breaks the at_top -> len_eff -> at_top path, so no
  // control field value can make a combinational loop.
  assign use_len_last[0] = LEN_LAST_1H[0] & (|(at_top & ctrl_i.d0_len_last_1h & 4'b1110));
  assign use_len_last[1] = LEN_LAST_1H[1] & (|(at_top & ctrl_i.d1_len_last_1h & 4'b1100));
  assign use_len_last[2] = LEN_LAST_1H[2] & (|(at_top & ctrl_i.d2_len_last_1h & 4'b1000));
  assign use_len_last[3] = LEN_LAST_1H[3] & (|(at_top & ctrl_i.d3_len_last_1h & 4'b0000));

  assign d0_len_eff = use_len_last[0] ? ctrl_i.d0_len_last : ctrl_i.d0_len;
  assign d1_len_eff = use_len_last[1] ? ctrl_i.d1_len_last : ctrl_i.d1_len;
  assign d2_len_eff = use_len_last[2] ? ctrl_i.d2_len_last : ctrl_i.d2_len;
  assign d3_len_eff = use_len_last[3] ? ctrl_i.d3_len_last : ctrl_i.d3_len;

  // A dimension is at its last index at the end of an upward sweep and at the start
  // of a downward one. down is 0 unless the dimension may sweep both ways.
  assign at_top[0] = down[0] ? (d0_counter_q == 1) : (d0_counter_q == d0_len_eff);
  assign at_top[1] = down[1] ? (d1_counter_q == 1) : (d1_counter_q == d1_len_eff);
  assign at_top[2] = down[2] ? (d2_counter_q == 1) : (d2_counter_q == d2_len_eff);
  assign at_top[3] = down[3] ? (d3_counter_q == 1) : (d3_counter_q == d3_len_eff);

  assign use_last[0] = STRIDE_LAST_1H[0] & (|(at_top & ctrl_i.d0_last_1h));
  assign use_last[1] = STRIDE_LAST_1H[1] & (|(at_top & ctrl_i.d1_last_1h));
  assign use_last[2] = STRIDE_LAST_1H[2] & (|(at_top & ctrl_i.d2_last_1h));
  assign use_last[3] = STRIDE_LAST_1H[3] & (|(at_top & ctrl_i.d3_last_1h));

  assign d0_step = down[0] ? -d0_stride : d0_stride;
  assign d1_step = down[1] ? -d1_stride : d1_stride;
  assign d2_step = down[2] ? -d2_stride : d2_stride;
  assign d3_step = down[3] ? -d3_stride : d3_stride;

  assign d0_step_last = down[0] ? -d0_stride_last : d0_stride_last;
  assign d1_step_last = down[1] ? -d1_stride_last : d1_stride_last;
  assign d2_step_last = down[2] ? -d2_stride_last : d2_stride_last;
  assign d3_step_last = down[3] ? -d3_stride_last : d3_stride_last;

  // Skipping steps off the shared element, in the direction the sweep just came from;
  // otherwise a downward sweep resumes from the top it has just reached and an upward
  // one restarts at 0. All three collapse to 0 when alternate is off.
  assign d0_roll_addr = alt_skip [0] ? d0_addr_q - d0_step
                      : down_next[0] ? d0_addr_q
                      :                '0;
  assign d1_roll_addr = alt_skip [1] ? d1_addr_q - d1_step
                      : down_next[1] ? d1_addr_q
                      :                '0;
  assign d2_roll_addr = alt_skip [2] ? d2_addr_q - d2_step
                      : down_next[2] ? d2_addr_q
                      :                '0;
  assign d3_roll_addr = alt_skip [3] ? d3_addr_q - d3_step
                      : down_next[3] ? d3_addr_q
                      :                '0;

  assign d0_roll_addr_last = alt_skip [0] ? d0_addr_last_q - d0_step_last
                           : down_next[0] ? d0_addr_last_q
                           :                '0;
  assign d1_roll_addr_last = alt_skip [1] ? d1_addr_last_q - d1_step_last
                           : down_next[1] ? d1_addr_last_q
                           :                '0;
  assign d2_roll_addr_last = alt_skip [2] ? d2_addr_last_q - d2_step_last
                           : down_next[2] ? d2_addr_last_q
                           :                '0;
  assign d3_roll_addr_last = alt_skip [3] ? d3_addr_last_q - d3_step_last
                           : down_next[3] ? d3_addr_last_q
                           :                '0;

  assign d0_roll_counter = alt_skip[0] ? 2 : 1;
  assign d1_roll_counter = alt_skip[1] ? 2 : 1;
  assign d2_roll_counter = alt_skip[2] ? 2 : 1;
  assign d3_roll_counter = alt_skip[3] ? 2 : 1;

  // address generation
  always_comb
  begin : address_gen_counters_comb
    d0_addr_d         = d0_addr_q;
    d1_addr_d         = d1_addr_q;
    d2_addr_d         = d2_addr_q;
    d3_addr_d         = d3_addr_q;
    d4_addr_d         = d4_addr_q;
    d0_addr_last_d    = d0_addr_last_q;
    d1_addr_last_d    = d1_addr_last_q;
    d2_addr_last_d    = d2_addr_last_q;
    d3_addr_last_d    = d3_addr_last_q;
    d0_counter_d      = d0_counter_q;
    d1_counter_d      = d1_counter_q;
    d2_counter_d      = d2_counter_q;
    d3_counter_d      = d3_counter_q;
    d4_counter_d      = d4_counter_q;
    down_d            = down_q;
    overall_counter_d = overall_counter_q;
    addr_valid_d      = addr_valid_q;
    done = '0;
    if(addr_o.ready) begin
      if(overall_counter_q < ctrl_i.tot_len) begin
        addr_valid_d = 1'b1;
        if((d0_counter_q < d0_len_eff) || (ctrl_i.dim_enable_1h[0] == 1'b0) || (DIM_ENABLE_1H[0] == 1'b0)) begin
          d0_addr_d      = d0_addr_q      + d0_step;
          d0_addr_last_d = d0_addr_last_q + d0_step_last;
          d0_counter_d = d0_counter_q + 1;
        end
        else if ((d1_counter_q < d1_len_eff) || (ctrl_i.dim_enable_1h[1] == 1'b0) || (DIM_ENABLE_1H[1] == 1'b0)) begin
          d0_addr_d      = d0_roll_addr;
          d0_addr_last_d = d0_roll_addr_last;
          down_d[0]      = down_next[0];
          d1_addr_d      = d1_addr_q      + d1_step;
          d1_addr_last_d = d1_addr_last_q + d1_step_last;
          d0_counter_d = d0_roll_counter;
          d1_counter_d = d1_counter_q + 1;
        end
        else if ((d2_counter_q < d2_len_eff) || (ctrl_i.dim_enable_1h[2] == 1'b0) || (DIM_ENABLE_1H[2] == 1'b0)) begin
          d0_addr_d      = '0;
          d0_addr_last_d = '0;
          down_d[0]      = 1'b0;
          d1_addr_d      = d1_roll_addr;
          d1_addr_last_d = d1_roll_addr_last;
          down_d[1]      = down_next[1];
          d2_addr_d      = d2_addr_q      + d2_step;
          d2_addr_last_d = d2_addr_last_q + d2_step_last;
          d0_counter_d = 1;
          d1_counter_d = d1_roll_counter;
          d2_counter_d = d2_counter_q + 1;
        end
        else if ((d3_counter_q < d3_len_eff) || (ctrl_i.dim_enable_1h[3] == 1'b0) || (DIM_ENABLE_1H[3] == 1'b0)) begin
          d0_addr_d      = '0;
          d0_addr_last_d = '0;
          down_d[0]      = 1'b0;
          d1_addr_d      = '0;
          d1_addr_last_d = '0;
          down_d[1]      = 1'b0;
          d2_addr_d      = d2_roll_addr;
          d2_addr_last_d = d2_roll_addr_last;
          down_d[2]      = down_next[2];
          d3_addr_d      = d3_addr_q      + d3_step;
          d3_addr_last_d = d3_addr_last_q + d3_step_last;
          d0_counter_d = 1;
          d1_counter_d = 1;
          d2_counter_d = d2_roll_counter;
          d3_counter_d = d3_counter_q + 1;
        end
        else begin
          d0_addr_d      = '0;
          d0_addr_last_d = '0;
          down_d[0]      = 1'b0;
          d1_addr_d      = '0;
          d1_addr_last_d = '0;
          down_d[1]      = 1'b0;
          d2_addr_d      = '0;
          d2_addr_last_d = '0;
          down_d[2]      = 1'b0;
          d3_addr_d      = d3_roll_addr;
          d3_addr_last_d = d3_roll_addr_last;
          down_d[3]      = down_next[3];
          d4_addr_d      = d4_addr_q + d4_stride;
          d0_counter_d = 1;
          d1_counter_d = 1;
          d2_counter_d = 1;
          d3_counter_d = d3_roll_counter;
          d4_counter_d = d4_counter_q + 1;
        end
        overall_counter_d = overall_counter_q + 1;
      end
      else begin
        addr_valid_d = 1'b0;
        done = 1'b1;
      end
    end
  end

  // address generation
  always_ff @(posedge clk_i or negedge rst_ni)
  begin : address_gen_counters_d0_ff
    if (~rst_ni) begin
      d0_addr_q      <= '0;
      d0_addr_last_q <= '0;
    end
    else if (clear_i) begin
      d0_addr_q      <= '0;
      d0_addr_last_q <= '0;
    end
    else if (presample_i) begin
      d0_addr_q      <= '0;
      d0_addr_last_q <= '0;
    end
    else if (enable_i) begin
      d0_addr_q      <= d0_addr_d;
      d0_addr_last_q <= d0_addr_last_d;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni)
  begin : address_gen_counters_ff
    if (~rst_ni) begin
      d1_addr_q         <= '0;
      d2_addr_q         <= '0;
      d3_addr_q         <= '0;
      d4_addr_q         <= '0;
      d1_addr_last_q    <= '0;
      d2_addr_last_q    <= '0;
      d3_addr_last_q    <= '0;
      down_q            <= '0;
      d0_counter_q      <= '0;
      d1_counter_q      <= 1;
      d2_counter_q      <= 1;
      d3_counter_q      <= 1;
      d4_counter_q      <= 1;
      overall_counter_q <= '0;
      addr_valid_q      <= '0;
    end
    else if (clear_i) begin
      d1_addr_q         <= '0;
      d2_addr_q         <= '0;
      d3_addr_q         <= '0;
      d4_addr_q         <= '0;
      d1_addr_last_q    <= '0;
      d2_addr_last_q    <= '0;
      d3_addr_last_q    <= '0;
      down_q            <= '0;
      d0_counter_q      <= '0;
      d1_counter_q      <= 1;
      d2_counter_q      <= 1;
      d3_counter_q      <= 1;
      d4_counter_q      <= 1;
      overall_counter_q <= '0;
      addr_valid_q      <= '0;
    end
    else if(enable_i) begin
      d1_addr_q         <= d1_addr_d;
      d2_addr_q         <= d2_addr_d;
      d3_addr_q         <= d3_addr_d;
      d4_addr_q         <= d4_addr_d;
      d1_addr_last_q    <= d1_addr_last_d;
      d2_addr_last_q    <= d2_addr_last_d;
      d3_addr_last_q    <= d3_addr_last_d;
      down_q            <= down_d;
      d0_counter_q      <= d0_counter_d;
      d1_counter_q      <= d1_counter_d;
      d2_counter_q      <= d2_counter_d;
      d3_counter_q      <= d3_counter_d;
      d4_counter_q      <= d4_counter_d;
      overall_counter_q <= overall_counter_d;
      addr_valid_q      <= addr_valid_d;
    end
  end

  assign gen_addr_int = ctrl_i.base_addr + d4_addr_q +
                        (use_last[3] ? d3_addr_last_q : d3_addr_q) +
                        (use_last[2] ? d2_addr_last_q : d2_addr_q) +
                        (use_last[1] ? d1_addr_last_q : d1_addr_q) +
                        (use_last[0] ? d0_addr_last_q : d0_addr_q);

  assign addr_o.data  = gen_addr_int;
  assign addr_o.strb  = '1;
  assign addr_o.valid = addr_valid_q;

  assign flags_o.done = done;

endmodule // hwpe_stream_addressgen_v4