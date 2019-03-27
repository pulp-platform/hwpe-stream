/*
 * hwpe_stream_fifo_ctrl.sv
 * Francesco Conti <f.conti@unibo.it>
 * Igor Loi <igor.loi@unibo.it>
 *
 * Copyright (C) 2014-2018 ETH Zurich, University of Bologna
 * Copyright and related rights are licensed under the Solderpad Hardware
 * License, Version 0.51 (the "License"); you may not use this file except in
 * compliance with the License.  You may obtain a copy of the License at
 * http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
 * or agreed to in writing, software, hardware and materials distributed under
 * this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND, either express or implied. See tdhe License for the
 * specific language governing permissions and limitations under the License.
 */

/**
 * The **hwpe_stream_fifo_ctrl** module implements a hardware FIFO queue
 * similar to that implemented by **hwpe_stream_fifo**, but without any actual
 * interface handshake forced on HWPE-Streams. Instead, it will push
 * its "virtual" handshake on the `push_valid_i`/`push_ready_o` and
 * `pop_valid_o`/`pop_ready_i` signals.
 * It can be used to operate multiple big FIFO queues (e.g. with latches)
 * in a synchronized fashion without breaking the HWPE-Stream protocol.
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hwpe_stream_fifo_ctrl_params:
 * .. table:: **hwpe_stream_fifo_ctrl** design-time parameters.
 *
 *   +--------------+--------------+------------------------------------------+
 *   | **Name**     | **Default**  | **Description**                          |
 *   +--------------+--------------+------------------------------------------+
 *   | *FIFO_DEPTH* | 8            | Depth of the FIFO queue (multiple of 2). |
 *   +--------------+--------------+------------------------------------------+
 */

import hwpe_stream_package::*;

module hwpe_stream_fifo_ctrl #(
  parameter int unsigned FIFO_DEPTH = 8
)
(
  input  logic                  clk_i,
  input  logic                  rst_ni,
  input  logic                  clear_i,

  output flags_fifo_t           flags_o,

  input  logic                  push_valid_i,
  output logic                  push_ready_o,

  output logic                  pop_valid_o,
  input  logic                  pop_ready_i
);

  // Local Parameter
  localparam ADDR_DEPTH = (FIFO_DEPTH==1) ? 1 : $clog2(FIFO_DEPTH);

  enum logic [1:0] { EMPTY, FULL, MIDDLE } cs, ns;
  // Internal Signals

  logic [ADDR_DEPTH-1:0] pop_pointer_q,  pop_pointer_d;
  logic [ADDR_DEPTH-1:0] push_pointer_q, push_pointer_d;
  integer       i;

  assign flags_o.empty = (cs == EMPTY) ? 1'b1 : 1'b0;
  assign flags_o.full = (cs == FULL) ? 1'b1 : 1'b0;
  assign flags_o.push_pointer = push_pointer_q;
  assign flags_o.pop_pointer  = pop_pointer_q;

  // state update
  always_ff @(posedge clk_i, negedge rst_ni)
  begin
    if(rst_ni == 1'b0) begin
      cs             <= EMPTY;
      pop_pointer_q  <= {ADDR_DEPTH {1'b0}};
      push_pointer_q <= {ADDR_DEPTH {1'b0}};
    end
    else if(clear_i == 1'b1) begin
      cs             <= EMPTY;
      pop_pointer_q  <= {ADDR_DEPTH {1'b0}};
      push_pointer_q <= {ADDR_DEPTH {1'b0}};
    end
    else begin
      cs             <= ns;
      pop_pointer_q  <= pop_pointer_d;
      push_pointer_q <= push_pointer_d;
    end
  end

  // Compute Next State
  always_comb
  begin
    case(cs)
      EMPTY: begin
        push_ready_o = 1'b1;
        pop_valid_o = 1'b0;
        case(push_valid_i)
          1'b0 : begin
            ns = EMPTY;
            push_pointer_d = push_pointer_q;
            pop_pointer_d  = pop_pointer_q;
          end
          1'b1 : begin
            ns = MIDDLE;
            push_pointer_d = push_pointer_q + 1'b1;
            pop_pointer_d  = pop_pointer_q;
          end
        endcase
      end
      MIDDLE: begin
        push_ready_o = 1'b1;
        pop_valid_o = 1'b1;
        case({push_valid_i,pop_ready_i})
          2'b01 : begin
            if((pop_pointer_q == push_pointer_q -1 ) || ((pop_pointer_q == FIFO_DEPTH-1) && (push_pointer_q == 0) ))
              ns = EMPTY;
            else
              ns = MIDDLE;
            push_pointer_d = push_pointer_q;
            if(pop_pointer_q == FIFO_DEPTH-1)
              pop_pointer_d  = 0;
            else
              pop_pointer_d  = pop_pointer_q + 1'b1;
          end
          2'b00 : begin
            ns = MIDDLE;
            push_pointer_d = push_pointer_q;
            pop_pointer_d  = pop_pointer_q;
          end
          2'b11 : begin
            ns = MIDDLE;
            if(push_pointer_q == FIFO_DEPTH-1)
              push_pointer_d = 0;
            else
              push_pointer_d = push_pointer_q + 1'b1;

            if(pop_pointer_q == FIFO_DEPTH-1)
              pop_pointer_d  = 0;
            else
              pop_pointer_d  = pop_pointer_q  + 1'b1;
          end
          2'b10 : begin
            if(( push_pointer_q == pop_pointer_q - 1) || ( (push_pointer_q == FIFO_DEPTH-1) && (pop_pointer_q == 0) ))
              ns = FULL;
            else
              ns = MIDDLE;
            if(push_pointer_q == FIFO_DEPTH - 1)
              push_pointer_d = 0;
            else
              push_pointer_d = push_pointer_q + 1'b1;
            pop_pointer_d  = pop_pointer_q;
          end
        endcase
      end
      FULL : begin
        push_ready_o = 1'b0;
        pop_valid_o = 1'b1;
        case(pop_ready_i)
          1'b1 : begin
            ns = MIDDLE;
            push_pointer_d = push_pointer_q;
            if(pop_pointer_q == FIFO_DEPTH-1)
              pop_pointer_d  = 0;
            else
              pop_pointer_d  = pop_pointer_q  + 1'b1;
          end
          1'b0 : begin
            ns = FULL;
            push_pointer_d = push_pointer_q;
            pop_pointer_d  = pop_pointer_q;
          end
        endcase
      end
      default : begin
        push_ready_o = 1'b0;
        pop_valid_o = 1'b0;
        ns = EMPTY;
        pop_pointer_d = 0;
        push_pointer_d = 0;
      end
    endcase
  end

endmodule // hwpe_stream_fifo_ctrl
