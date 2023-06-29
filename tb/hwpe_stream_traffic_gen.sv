/*
 * hwpe_stream_traffic_gen.sv
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
 * The hwpe_stream_traffic_gen generates traffic either randomly or from a
 * memory reservoir.
 */

timeunit 1ns;
timeprecision 1ps;

import hwpe_stream_package::*;

module hwpe_stream_traffic_gen
#(
  parameter string       STIM_FILE      = "stim_file.txt",
  parameter int unsigned DATA_WIDTH     = -1,
  parameter int unsigned RESERVOIR_SIZE = 1024,
  parameter bit          RANDOM_STROBE  = 0,
  parameter real         PROB_STALL     = 0.0
)
(
  input  logic                   clk_i,
  input  logic                   rst_ni,
  input  logic                   randomize_i,
  input  logic                   force_invalid_i,
  input  logic                   force_valid_i,
  output logic                   eot_o,
  input  int                     rng_i,
  hwpe_stream_intf_stream.source pop_o
);

  logic [DATA_WIDTH-1:0] reservoir [RESERVOIR_SIZE];
  int cnt_wr, cnt_rd;

  // the reservoir is decoupled from the actual HWPE-Stream interface by using a queue (infinite-size FIFO)
  logic [DATA_WIDTH-1:0]   data_queue [$];
  logic [DATA_WIDTH/8-1:0] strb_queue [$];

  logic valid_data;

  // preload reservoir from file and zero-out counter
  initial begin
    if (STIM_FILE != "")
      $readmemh(STIM_FILE, reservoir);
  end

  // read reservoir into queue or generate random data
  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni) begin
      data_queue <= {};
      strb_queue <= {};
      cnt_wr     <= 0;
    end
    else if(randomize_i && (cnt_wr < RESERVOIR_SIZE)) begin
      data_queue.push_front($random());
      cnt_wr += 1;
      if(RANDOM_STROBE) begin
        automatic int start = $urandom_range(0, DATA_WIDTH/8-1);
        automatic int stop  = $urandom_range(0, DATA_WIDTH/8) + start;
        stop = (stop > DATA_WIDTH/8-1) ? DATA_WIDTH/8-1 : stop;
        strb_queue.push_front((1 << (stop+1)) - 1 & ~((1 << (start+1)) - 1));
      end
      else begin
        strb_queue.push_front('1);
      end
    end
    else if(cnt_wr < RESERVOIR_SIZE) begin
      data_queue.push_front(reservoir[cnt_wr]);
      strb_queue.push_front('1);
      cnt_wr += 1;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni) begin
      cnt_rd <= 0;
    end
    else begin
      if(pop_o.ready & pop_o.valid) begin
        cnt_rd <= cnt_rd + 1;
      end
    end
  end

  // generate random data validity at every new cycle when not forced valid/invalid
  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if (~rst_ni) begin
      valid_data <= '0;
    end
    else if((~force_invalid_i & ~force_valid_i) && !(rng_i < PROB_STALL*1000)) begin
      valid_data <= 1'b1;
    end
    else begin
      valid_data <= 1'b0;
    end
  end

  // write HWPE-Stream from queue
  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni) begin
      pop_o.data  <= '0;
      pop_o.valid <= '0;
      pop_o.strb  <= '0;
    end
    else begin
      // previous cycle valid but not ready --> keep valid and data
      if(pop_o.valid & ~pop_o.ready) begin
        pop_o.data  <= pop_o.data;
        pop_o.strb  <= pop_o.strb;
        pop_o.valid <= '1;
      end
      // still data in the queue
      else if (data_queue.size() > 0) begin
        if(~pop_o.valid) begin
          // previous cycle not valid, now valid --> pop from queue, set to valid
          if(~force_invalid_i & (force_valid_i | valid_data)) begin
            pop_o.data  <= data_queue.pop_back();
            pop_o.strb  <= strb_queue.pop_back();
            pop_o.valid <= '1;
          end
          // previous cycle not valid, now invalid --> pop from queue, set to valid
          else begin
            pop_o.data  <= '0;
            pop_o.strb  <= '0;
            pop_o.valid <= '0;
          end
        end
        else if(pop_o.valid & pop_o.ready) begin
          // previous cycle valid and ready, now valid --> pop from queue, set to valid
          if(~force_invalid_i & (force_valid_i | valid_data)) begin
            pop_o.data  <= data_queue.pop_back();
            pop_o.strb  <= strb_queue.pop_back();
            pop_o.valid <= '1;
          end
          // previous cycle valid and ready, now invalid --> pop from queue, set to valid
          else begin
            pop_o.data  <= '0;
            pop_o.strb  <= '0;
            pop_o.valid <= '0;
          end
        end
      end
      // no more data in queue --> set to invalid
      else if (data_queue.size() == 0) begin
        pop_o.data  <= '0;
        pop_o.strb  <= '0;
        pop_o.valid <= '0;
      end
    end
  end

  int size;
  assign size = data_queue.size();

  // end-of-transfer happens when cnt_rd==RESERVOIR_SIZE and queue is empty
  assign eot_o = (cnt_rd >= RESERVOIR_SIZE);

endmodule // hwpe_stream_traffic_gen
