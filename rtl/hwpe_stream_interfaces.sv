/*
 * hwpe_stream_interfaces.sv
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

interface hwpe_stream_intf_tcdm (
  input logic clk
);

  logic        req;
  logic        gnt;
  logic [31:0] add;
  logic        wen;
  logic [3:0]  be;
  logic [31:0] data;
  logic [31:0] r_data;
  logic        r_valid;

  modport master (
    output req, add, wen, be, data,
    input  gnt, r_data, r_valid
  );
  modport slave (
    input  req, add, wen, be, data,
    output gnt, r_data, r_valid
  );
  modport monitor (
    input  req, add, wen, be, data, gnt, r_data, r_valid
  );

endinterface // hwpe_stream_intf_tcdm

interface hwpe_stream_intf_stream (
  input logic clk
);
  parameter int unsigned DATA_WIDTH = -1;

  logic                    valid;
  logic                    ready;
  logic [DATA_WIDTH-1:0]   data;
  logic [DATA_WIDTH/8-1:0] strb;

  modport source (
    output valid, data, strb,
    input  ready
  );
  modport sink (
    input  valid, data, strb,
    output ready
  );
  modport monitor (
    input  valid, data, strb, ready
  );

`ifndef SYNTHESIS
  property hwpe_stream_value_change_rule;
    @(posedge clk)
    ($past(valid) == 1'b1 & ~($past(valid) & $past(ready))) |-> (data == $past(data)) && (strb == $past(strb));
  endproperty;

  property hwpe_stream_valid_deassert_rule;
    @(posedge clk)
    ($past(valid) & ~valid) |-> $past(valid) & $past(ready);
  endproperty;

  hwpe_stream_value_change_assert:   assert property(hwpe_stream_value_change_rule)
    else $fatal("ASSERTION FAILURE hwpe_stream_value_change_assert", 1);

  hwpe_stream_valid_deassert_assert: assert property(hwpe_stream_valid_deassert_rule)
    else $fatal("ASSERTION FAILURE hwpe_stream_valid_deassert_assert", 1);
`endif

endinterface // hwpe_stream_intf_stream
