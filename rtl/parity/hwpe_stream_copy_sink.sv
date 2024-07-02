/*
 * hwpe_stream_copy_sink.sv
 * Maurus Item <itemm@student.ethz.ch>
 *
 * Copyright (C) 2024-2024 ETH Zurich, University of Bologna
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
 * The **hwpe_stream_copy_sink** module is used to monitor an input normal
 * stream `original_i` and compare it with a copy stream `copy_i`.
 * Together with hwpe_stream_copy_source this allows for low area fault detection
 * on HWPE streams by building a copy network that matches the original network.
 *
 * How "deep" the copy is can be set with the parameter COPY_TYPE.
 * COPY_TYPE MUST match on connected sinks and sources!
 *
 * The available options are:
 * - COPY:      Fully copy of everything.
 *              DATA_WIDTH_COPY = DATA_WIDTH_ORIGINAL
 *              STRB_WIDTH_COPY = STRB_WIDTH_ORIGINAL
 * - PARITY:    Reduction on the data width with parity per bit.
 *              DATA_WIDTH_COPY = STRB_WIDTH_ORIGINAL <--- Notice it is STRB here!
 *              STRB_WIDTH_COPY = STRB_WIDTH_ORIGINAL
 * - STRB_ONLY: No data information.
 *              DATA_WIDTH_COPY = 1
 *              STRB_WIDTH_COPY = STRB_WIDTH_ORIGINAL
 * - ZERO:      No data or strobe information.
 *              DATA_WIDTH_COPY = 1
 *              STRB_WIDTH_COPY = 1
 */


import hwpe_stream_package::*;

module hwpe_stream_copy_sink #(
  parameter hwpe_stream_package::hwpe_copy_t  COPY_TYPE = COPY,
  parameter                     int unsigned DATA_WIDTH = 32,           // Data width before any modifications
  parameter                     int unsigned STRB_WIDTH = DATA_WIDTH/8, // Strobe width before any modifications
  parameter                            logic  DONT_CARE = 1             // Signal to use for don't care assignments
) (
  input logic                     clk_i,
  input logic                     rst_ni,
  hwpe_stream_intf_stream.monitor original_i,
  hwpe_stream_intf_stream.sink    copy_i,
  output logic                    fault_o
);

  logic fault, data_fault, strobe_fault, valid_fault;

  // Assign handshake directly
  assign copy_i.ready = original_i.ready;
  assign valid_fault = copy_i.valid != original_i.valid;

  // Assign strobe and data based on type
  if (COPY_TYPE == COPY) begin
    assign data_fault   = copy_i.data != original_i.data;
    assign strobe_fault = copy_i.strb != original_i.strb;
  end
  else if (COPY_TYPE == PARITY) begin
    // Compute parity localy for compare
    logic [STRB_WIDTH-1:0] local_parity_data;
    for (genvar i = 0; i < STRB_WIDTH; i++) begin
      assign local_parity_data[i] = ^original_i.data[i * DATA_WIDTH/STRB_WIDTH +: DATA_WIDTH/STRB_WIDTH];
    end

    assign data_fault   = copy_i.data != local_parity_data;
    assign strobe_fault = copy_i.strb != original_i.strb;
  end
  else if (COPY_TYPE == STRB_ONLY) begin
    assign data_fault   = 1'b0;
    assign strobe_fault = copy_i.strb != original_i.strb;
  end
  else if (COPY_TYPE == ZERO) begin
    assign data_fault   = 1'b0;
    assign strobe_fault = 1'b0;
  end
  else begin
    $fatal(1, "Unsupported COPY_TYPE in hwpe_stream_copy_sink!\n");
  end

  assign fault = data_fault | strobe_fault | valid_fault;

  // Register on fault detected to not make critical path longer
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      fault_o <= '0;
    end else begin
      fault_o <= fault;
    end
  end

endmodule : hwpe_stream_copy_sink
