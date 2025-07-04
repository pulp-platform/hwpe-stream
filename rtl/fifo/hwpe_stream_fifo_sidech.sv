/*
 * hwpe_stream_fifo_sidech.sv
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
 * CONDITIONS OF ANY KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations under the License.
 */

import hwpe_stream_package::*;

module hwpe_stream_fifo_sidech #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned STRB_WIDTH = DATA_WIDTH/8,
  parameter int unsigned FIFO_DEPTH = 8,
  parameter int unsigned LATCH_FIFO = 0,
  parameter int unsigned SIDECH_WIDTH = 1
)
(
  input  logic                   clk_i,
  input  logic                   rst_ni,
  input  logic                   clear_i,
  
  output flags_fifo_t            flags_o,
  
  hwpe_stream_intf_stream.sink   push_i,
  hwpe_stream_intf_stream.source pop_o,

  input  logic [SIDECH_WIDTH-1:0] sidech_i,
  output logic [SIDECH_WIDTH-1:0] sidech_o
);

  // Local Parameter
  localparam ADDR_DEPTH = (FIFO_DEPTH==1) ? 1 : $clog2(FIFO_DEPTH);

  enum logic [1:0] { EMPTY, FULL, MIDDLE } cs, ns;
  // Internal Signals

  logic [ADDR_DEPTH-1:0] pop_pointer_q,  pop_pointer_d;
  logic [ADDR_DEPTH-1:0] push_pointer_q, push_pointer_d;
  logic [DATA_WIDTH+STRB_WIDTH+SIDECH_WIDTH-1:0] fifo_registers[FIFO_DEPTH-1:0];
  integer       i;

  assign flags_o.empty = (cs == EMPTY) ? 1'b1 : 1'b0;

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
        push_i.ready = 1'b1;
        pop_o.valid = 1'b0;
        case(push_i.valid)
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
        push_i.ready = 1'b1;
        pop_o.valid = 1'b1;
        case({push_i.valid,pop_o.ready})
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
        push_i.ready = 1'b0;
        pop_o.valid = 1'b1;
        case(pop_o.ready)
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
        push_i.ready = 1'b0;
        pop_o.valid = 1'b0;
        ns = EMPTY;
        pop_pointer_d = 0;
        push_pointer_d = 0;
      end
    endcase
  end

  logic [DATA_WIDTH+STRB_WIDTH+SIDECH_WIDTH-1:0] data_out_int;
  logic [DATA_WIDTH+STRB_WIDTH+SIDECH_WIDTH-1:0] data_in_int;

  generate
    if(LATCH_FIFO == 0) begin : fifo_ff_gen

      always_ff @(posedge clk_i, negedge rst_ni)
      begin
        if(rst_ni == 1'b0) begin
          for (i=0; i< FIFO_DEPTH; i++)
            fifo_registers[i] <= '0;
        end
        else if(clear_i == 1'b1) begin
          for (i=0; i< FIFO_DEPTH; i++)
            fifo_registers[i] <= '0;
        end
        else begin
          if((push_i.ready == 1'b1) && (push_i.valid == 1'b1))
            fifo_registers[push_pointer_q] <= { sidech_i, push_i.data, push_i.strb } ;
        end
      end

      assign data_out_int = fifo_registers[pop_pointer_q];

    end
    else begin : fifo_latch_gen

      assign data_in_int = { sidech_i, push_i.data, push_i.strb };

      hwpe_stream_fifo_scm #(
        .ADDR_WIDTH( ADDR_DEPTH                            ),
        .DATA_WIDTH( DATA_WIDTH + STRB_WIDTH +SIDECH_WIDTH )
      ) i_fifo_latch (
        .clk ( clk_i ),
        .rst_n       ( rst_ni                      ),
        .ReadEnable  ( 1'b1                        ),
        .ReadAddr    ( pop_pointer_d               ),
        .ReadData    ( data_out_int                ),
        .WriteEnable ( push_i.ready & push_i.valid ),
        .WriteAddr   ( push_pointer_q              ),
        .WriteData   ( data_in_int                 )
      );

    end
  endgenerate

  assign sidech_o   = (pop_o.valid == 1'b1) ? data_out_int[DATA_WIDTH+STRB_WIDTH+SIDECH_WIDTH-1:DATA_WIDTH+STRB_WIDTH] : '0;
  assign pop_o.data = (pop_o.valid == 1'b1) ? data_out_int[DATA_WIDTH+STRB_WIDTH-1:STRB_WIDTH] : '0;
  assign pop_o.strb = (pop_o.valid == 1'b1) ? data_out_int[STRB_WIDTH-1:0] : '0;

endmodule // hwpe_stream_fifo_sidech
