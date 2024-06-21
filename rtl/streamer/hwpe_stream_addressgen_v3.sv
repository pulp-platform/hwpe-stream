/*
 * hwpe_stream_addressgen_v3.sv
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
 * The **hwpe_stream_addressgen_v3** module is used to generate addresses to
 * load or store HWPE-Stream stream. In this version of the address generator,
 * the address is itself carried within a HWPE-Stream, making it easily stallable.
 * The address generator can be used to generate address from a
 * three-dimensional space, which can be visited with configurable strides in all
 * three dimensions.
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
 *   hwpe_stream_addressgen_v3(
 *     int base_addr,                                          // base address (byte-aligned)
 *     int d0_len,    int d1_len,    int tot_len               // d0,d1,total length (in number of transactions)
 *     int d0_stride, int d1_stride, int d2_stride,            // d0,d1,d2 strides (in bytes)
 *     int *d0_addr,  int *d1_addr,  int *d2_addr,             // d0,d1,d2 addresses (by reference)
 *     int *d0_cnt,   int *d1_cnt,   int *ov_cnt               // d0,d1,overall counters (by reference)
 *   ) {
 *     // compute current address
 *     int current_addr = 0;
 *     int done = 0;
 *     if (dim_enable & 0x1 == 0) { // 1-dimensional streaming
 *       current_addr = base_addr + *d0_addr;
 *     }
 *     else if(dim_enable & 0x2 == 0) { // 2-dimensional streaming
 *       current_addr = base_addr + *d1_addr + *d0_addr;
 *     }
 *     else { // 3-dimensional streaming
 *       current_addr = base_addr + *d2_addr + *d1_addr + *d0_addr;
 *     }
 *     // update counters and dimensional addresses
 *     if(*ov_cnt == tot_len) {
 *       done = 1;
 *     }
 *     if((*d0_cnt < d0_len) || (dim_enable & 0x1 == 0)) {
 *       *d0_addr = *d0_addr + d0_stride;
 *       *d0_cnt  = *d0_cnt + 1;
 *     }
 *     else if ((*d1_cnt < d1_len) || (dim_enable & 0x2 == 0)) {
 *       *d0_addr = 0;
 *       *d1_addr = *d1_addr + d1_stride;
 *       *d0_cnt  = 1;
 *       *d1_cnt  = *d1_cnt + 1;
 *     }
 *     else if ((*d2_cnt < d2_len) || (dim_enable & 0x4 == 0)) {
 *       *d0_addr = 0;
 *       *d1_addr = 0;
 *       *d2_addr = *d2_addr + d2_stride;
 *       *d0_cnt  = 1;
 *       *d1_cnt  = 1;
 *       *d2_cnt  = *d2_cnt + 1;
 *     }
 *     else {
 *       *d0_addr = 0;
 *       *d1_addr = 0;
 *       *d2_addr = 0;
 *       *d3_addr = *d3_addr + d3_stride;
 *       *d0_cnt  = 1;
 *       *d1_cnt  = 1;
 *       *d2_cnt  = 1;
 *     }
 *     *ov_cnt = *ov_cnt + 1;
 *     return current_addr, done;
 *   }
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hwpe_stream_addressgen_v3_params:
 * .. table:: **hwpe_stream_addressgen_v3** design-time parameters.
 *
 *   +-------------------------+------------------------------------+---------------------------------------------------------------------------------------------+
 *   | **Name**                | **Default**                        | **Description**                                                                             |
 *   +-------------------------+------------------------------------+---------------------------------------------------------------------------------------------+
 *   | *TRANS_CNT*             | 32                                 | Number of bits supported in the transaction counter, which will overflow at 2^ `TRANS_CNT`. |
 *   +-------------------------+------------------------------------+---------------------------------------------------------------------------------------------+
 *   | *CNT*                   | 32                                 | Number of bits supported in non-transaction counters, which will overflow at 2^ `CNT`.      |
 *   +-------------------------+------------------------------------+---------------------------------------------------------------------------------------------+
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hwpe_stream_addressgen_v3_ctrl:
 * .. table:: **hwpe_stream_addressgen_v3** input control signals.
 *
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | **Name**                         | **Type**             | **Description**                                                                                             |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | *base_addr*                      | `logic[31:0]`        | Byte-aligned base address of the stream in the HWPE-accessible memory.                                      |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | *tot_len*                        | `logic[31:0]`        | Total number of transactions in stream; only the `TRANS_CNT` LSB are actually used.                         |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | *d0_len*                         | `logic[31:0]`        | d0 length in number of transactions                                                                         |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | *d0_stride*                      | `logic[31:0]`        | d0 stride in bytes                                                                                          |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | *d0_len*                         | `logic[31:0]`        | d0 length in number of transactions                                                                         |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | *d1_stride*                      | `logic[31:0]`        | d1 stride in bytes                                                                                          |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | *d1_len*                         | `logic[31:0]`        | d1 length in number of transactions                                                                         |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | *d2_stride*                      | `logic[31:0]`        | d2 stride in bytes                                                                                          |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | *d2_len*                         | `logic[31:0]`        | d2 length in number of transactions                                                                         |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | *d3_stride*                      | `logic[31:0]`        | d3 stride in bytes                                                                                          |
 * *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *   | *dim_enable_1h*                  | `logic[2:0]`         | One-hot switch to enable 4-d counting (111), 3-d (011), 2-d (001), or 1-d (000).                                          |
 *   +----------------------------------+----------------------+-------------------------------------------------------------------------------------------------------------+
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hwpe_stream_addressgen_v3_flags:
 * .. table:: **hwpe_stream_addressgen_v3** output flags.
 *
 *   +-----------------+------------------+-----------------------------------------------+
 *   | **Name**        | **Type**         | **Description**                               |
 *   +-----------------+------------------+-----------------------------------------------+
 *   | *done*          | `logic`          | 1 when the address generation has finished.   |
 *   +-----------------+------------------+-----------------------------------------------+
 *
 */


import hwpe_stream_package::*;

module hwpe_stream_addressgen_v3
#(
  parameter int unsigned TRANS_CNT  = 32,
  parameter int unsigned CNT        = 32  // number of bits used within the internal counter
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
  input  ctrl_addressgen_v3_t    ctrl_i,
  output flags_addressgen_v3_t   flags_o
);

  logic signed [31:0] d0_stride;
  logic signed [31:0] d1_stride;
  logic signed [31:0] d2_stride;
  logic signed [31:0] d3_stride;

  logic [31:0] gen_addr_int;
  logic        done;

  logic [TRANS_CNT-1:0] overall_counter_d;
  logic [CNT-1:0]       d0_counter_d;
  logic [CNT-1:0]       d1_counter_d;
  logic [CNT-1:0]       d2_counter_d;
  logic [CNT-1:0]       d3_counter_d;
  logic [31:0]          d0_addr_d;
  logic [31:0]          d1_addr_d;
  logic [31:0]          d2_addr_d;
  logic [31:0]          d3_addr_d;
  logic [TRANS_CNT-1:0] overall_counter_q;
  logic [CNT-1:0]       d0_counter_q;
  logic [CNT-1:0]       d1_counter_q;
  logic [CNT-1:0]       d2_counter_q;
  logic [CNT-1:0]       d3_counter_q;
  logic [31:0]          d0_addr_q;
  logic [31:0]          d1_addr_q;
  logic [31:0]          d2_addr_q;
  logic [31:0]          d3_addr_q;

  logic        addr_valid_d, addr_valid_q;

  assign d0_stride   = $signed(ctrl_i.d0_stride);
  assign d1_stride   = $signed(ctrl_i.d1_stride);
  assign d2_stride   = $signed(ctrl_i.d2_stride);
  assign d3_stride   = $signed(ctrl_i.d3_stride);

  // address generation
  always_comb
  begin : address_gen_counters_comb
    d0_addr_d         = d0_addr_q;
    d1_addr_d         = d1_addr_q;
    d2_addr_d         = d2_addr_q;
    d3_addr_d         = d3_addr_q;
    d0_counter_d      = d0_counter_q;
    d1_counter_d      = d1_counter_q;
    d2_counter_d      = d2_counter_q;
    d3_counter_d      = d3_counter_q;
    overall_counter_d = overall_counter_q;
    addr_valid_d      = addr_valid_q;
    done = '0;
    if(addr_o.ready) begin
      if(overall_counter_q < ctrl_i.tot_len) begin
        addr_valid_d = 1'b1;
        if((d0_counter_q < ctrl_i.d0_len) || (ctrl_i.dim_enable_1h[0] == 1'b0)) begin
          d0_addr_d    = d0_addr_q + d0_stride;
          d0_counter_d = d0_counter_q + 1;
        end
        else if ((d1_counter_q < ctrl_i.d1_len) || (ctrl_i.dim_enable_1h[1] == 1'b0)) begin
          d0_addr_d    = '0;
          d1_addr_d    = d1_addr_q + d1_stride;
          d0_counter_d = 1;
          d1_counter_d = d1_counter_q + 1;
        end
        else if ((d2_counter_q < ctrl_i.d2_len) || (ctrl_i.dim_enable_1h[2] == 1'b0)) begin
          d0_addr_d    = '0;
          d1_addr_d    = '0;
          d2_addr_d    = d2_addr_q + d2_stride;
          d0_counter_d = 1;
          d1_counter_d = 1;
          d2_counter_d = d2_counter_q + 1;
        end
        else begin
          d0_addr_d    = '0;
          d1_addr_d    = '0;
          d2_addr_d    = '0;
          d3_addr_d    = d3_addr_q + d3_stride;
          d0_counter_d = 1;
          d1_counter_d = 1;
          d2_counter_d = 1;
          d3_counter_d = d3_counter_q + 1;
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
      d0_addr_q <= '0;
    end
    else if (clear_i) begin
      d0_addr_q <= '0;
    end
    else if (presample_i) begin
      d0_addr_q <= '0;
    end
    else if (enable_i) begin
      d0_addr_q <= d0_addr_d;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni)
  begin : address_gen_counters_ff
    if (~rst_ni) begin
      d1_addr_q         <= '0;
      d2_addr_q         <= '0;
      d3_addr_q         <= '0;
      d0_counter_q      <= '0;
      d1_counter_q      <= 1;
      d2_counter_q      <= 1;
      d3_counter_q      <= 1;
      overall_counter_q <= '0;
      addr_valid_q      <= '0;
    end
    else if (clear_i) begin
      d1_addr_q         <= '0;
      d2_addr_q         <= '0;
      d3_addr_q         <= '0;
      d0_counter_q      <= '0;
      d1_counter_q      <= 1;
      d2_counter_q      <= 1;
      d3_counter_q      <= 1;
      overall_counter_q <= '0;
      addr_valid_q      <= '0;
    end
    else if(enable_i) begin
      d1_addr_q         <= d1_addr_d;
      d2_addr_q         <= d2_addr_d;
      d3_addr_q         <= d3_addr_d;
      d0_counter_q      <= d0_counter_d;
      d1_counter_q      <= d1_counter_d;
      d2_counter_q      <= d2_counter_d;
      d3_counter_q      <= d3_counter_d;
      overall_counter_q <= overall_counter_d;
      addr_valid_q      <= addr_valid_d;
    end
  end

  assign gen_addr_int = ctrl_i.base_addr + d3_addr_q + d2_addr_q + d1_addr_q + d0_addr_q;

  assign addr_o.data  = gen_addr_int;
  assign addr_o.strb  = '1;
  assign addr_o.valid = addr_valid_q;

  assign flags_o.done = done;

endmodule // hwpe_stream_addressgen_v3
