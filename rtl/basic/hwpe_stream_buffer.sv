/*
 * hwpe_stream_buffer.sv
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

/**
 * .. The **hwpe_stream_buffer** implements a shallow pipeline stage of size
 * .. DATA_WIDTH for cases where a full stream FIFO is not required, i.e. when
 * .. the only important feature required is to cut forward propagation
 * .. combinational paths.
 */


module hwpe_stream_buffer
  import hwpe_stream_package::*;
#(
  parameter int unsigned DATA_WIDTH = 32
)
(
  input  logic clk_i,
  input  logic rst_ni,
  input  logic clear_i,
  input  logic test_mode_i,

  hwpe_stream_intf_stream.sink   push_i,
  hwpe_stream_intf_stream.source pop_o
);

  logic clk_gated;

  tc_clk_gating i_cg (
    .clk_o     ( clk_gated             ),
    .en_i      ( pop_o.ready | clear_i ),
    .test_en_i ( test_mode_i           ),
    .clk_i     ( clk_i                 )
  );

  always_ff @(posedge clk_gated or negedge rst_ni)
  begin
    if(~rst_ni) begin
      pop_o.data <= '0;
      pop_o.strb <= '0;
    end
    else if(clear_i) begin
      pop_o.data <= '0;
      pop_o.strb <= '0;
    end
    else begin
      pop_o.data <= push_i.data;
      pop_o.strb <= push_i.strb;
    end
  end

  always_ff @(posedge clk_gated or negedge rst_ni)
  begin
    if(~rst_ni) begin
      pop_o.valid <= 1'b0;
    end
    else if(clear_i) begin
      pop_o.valid <= 1'b0;
    end
    else begin
      pop_o.valid <= push_i.valid;
    end
  end

  assign push_i.ready = pop_o.ready;

endmodule // hwpe_stream_buffer
