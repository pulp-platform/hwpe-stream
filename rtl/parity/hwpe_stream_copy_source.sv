/*
 * hwpe_stream_copy_source.sv
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
 * The **hwpe_stream_copy_source** module is used to monitor an input normal
 * stream `original_i` and copy it to an output stream `copy_o`.
 * Together with hwpe_stream_copy_sink this allows for low area fault detection on
 * HWPE streams by building a copy network that matches the original network.
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

module hwpe_stream_copy_source #(
  parameter hwpe_stream_package::hwpe_copy_t  COPY_TYPE = COPY,
  parameter                     int unsigned DATA_WIDTH = 32,           // Data width before any modifications
  parameter                     int unsigned STRB_WIDTH = DATA_WIDTH/8, // Strobe width before any modifications
  parameter                            logic  DONT_CARE = 1             // Signal to use for don't care assignments
) (
  input logic                     clk_i,
  input logic                     rst_ni,
  hwpe_stream_intf_stream.monitor original_i,
  hwpe_stream_intf_stream.source  copy_o,
  output logic                    fault_o
);
  logic ready_fault;

  // Assign handshake directly
  assign copy_o.valid = original_i.valid;
  assign ready_fault = original_i.ready != copy_o.ready;

  // Assign strobe and data based on type
  if (COPY_TYPE == COPY) begin
    assign copy_o.data = original_i.data;
    assign copy_o.strb = original_i.strb;
  end
  else if (COPY_TYPE == PARITY) begin
    for (genvar i = 0; i < STRB_WIDTH ; i++) begin
      assign copy_o.data[i]  = ^original_i.data[i * DATA_WIDTH/STRB_WIDTH +: DATA_WIDTH/STRB_WIDTH];
    end
    assign copy_o.strb = original_i.strb;
  end
  else if (COPY_TYPE == STRB_ONLY) begin
    assign copy_o.data = DONT_CARE;
    assign copy_o.strb = original_i.strb;
  end
  else if (COPY_TYPE == ZERO) begin
    assign copy_o.data = DONT_CARE;
    assign copy_o.strb = DONT_CARE;
  end
  else begin
        $fatal(1, "Unsupported COPY_TYPE in hwpe_stream_copy_source!\n");
  end

  // Register on fault detected to not make critical path longer
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      fault_o <= '0;
    end
    else begin
      fault_o <= ready_fault;
    end
  end

endmodule : hwpe_stream_copy_source
