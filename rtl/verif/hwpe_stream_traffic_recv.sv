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

module hwpe_stream_traffic_recv
#(
  parameter string       STIM_FILE      = "",
  parameter int unsigned DATA_WIDTH     = -1,
  parameter int unsigned RESERVOIR_SIZE = 1024,
  parameter bit          CHECK          = 0,
  parameter real PROB_STALL             = 0.0
)
(
  input  logic                 clk_i,
  input  logic                 rst_ni,
  input  logic                 force_unready_i,
  input  logic                 force_ready_i,
  input  logic                 enable_i,
  output logic                 eot_o,
  input  int                   rng_i,
  hwpe_stream_intf_stream.sink push_i
);

  logic [DATA_WIDTH-1:0] reservoir [RESERVOIR_SIZE];
  int cnt;

  // preload reservoir from file and zero-out counter
  initial begin
    if (STIM_FILE != "")
      $readmemh(STIM_FILE, reservoir);
  end

  // read reservoir into queue or generate random data
  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni) begin
      cnt = 0;
    end
    if(push_i.valid & push_i.ready) begin
      if(CHECK == 1'b1 && cnt < RESERVOIR_SIZE) begin
        if(push_i.data !== reservoir[cnt]) begin
          $display("ERROR: data mismatch expected = 0x%x, actual = 0x%x\n", reservoir[cnt], push_i.data);
          $finish;
        end
      end
      cnt += 1;
    end
  end

  logic push_ready;
  assign push_i.ready = push_ready;

  // receive traffic with random or forced ready
  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if (~rst_ni) begin
      push_ready <= 1'b0;
    end
    else if(enable_i) begin
      if (force_unready_i) begin
        push_ready <= 1'b0;
      end
      else if (force_ready_i) begin
        push_ready <= cnt < RESERVOIR_SIZE ? 1'b1 : 1'b0;
      end
      else if (push_i.valid | ~push_ready) begin
        if (rng_i < PROB_STALL*1000)
          push_ready <= 1'b0;
        else
          push_ready <= cnt < RESERVOIR_SIZE ? 1'b1 : 1'b0;
      end
    end
    else begin
      push_ready <= 1'b0;
    end
  end

  // end-of-transfer happens when cnt==RESERVOIR_SIZE
  assign eot_o = (cnt >= RESERVOIR_SIZE);

endmodule // hwpe_stream_traffic_recv
