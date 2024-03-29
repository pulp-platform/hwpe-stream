/*
 * hwpe_stream_traffic_recv.sv
 * Francesco Conti <f.conti@unibo.it>
 *
 * Copyright (C) 2014-2023 ETH Zurich, University of Bologna
 * Copyright and related rights are licensed under the Solderpad Hardware
 * License, Version 0.51 (the "License"); you may not use this file except in
 * compliance with the License.  You may obtain a copy of the License at
 * http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
 * or agreed to in writing, software, hardware and materials distributed under
 * this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations under the License.
 *
 * The hwpe_stream_traffic_recv receives and optionally checks traffic.
 */

timeunit 1ns;
timeprecision 1ps;

module tb_hwpe_stream_receiver
#(
  parameter DATA_WIDTH     = -1,
  parameter PROB_STALL     = 0.0,
  parameter TCP            = 1.0ns, // clock period, 1GHz clock
  parameter TA             = 0.2ns, // application time
  parameter TT             = 0.8ns  // test time
)
(
  input  logic                 clk_i,
  input  logic                 force_ready_i,
  input  logic                 enable_i,
  hwpe_stream_intf_stream.sink push
);

  logic push_ready;

  always_ff @(posedge clk_i)
  begin
    if (force_ready_i)
      push_ready <= 1'b1;
    else if(enable_i) begin
      if ((push.valid == 1'b1) || (push.ready == 1'b0)) begin
        if ($urandom_range(0, 1000) < PROB_STALL*1000)
          push.ready <= 1'b0;
        else
          push.ready <= 1'b1;
      end
    end
    else begin
      push_ready <= 1'b0;
    end
  end

  assign push.ready = push_ready;

endmodule // tb_hwpe_stream_reservoir
