/*
 * hwpe_stream_dynamic_delay.sv
 * Riccardo Tedeschi <riccardo.tedeschi6@unibo.it>
 *
 * Copyright (C) 2014-2025 ETH Zurich, University of Bologna
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

module hwpe_stream_delay_assign #(
    parameter int unsigned DATA_WIDTH = 1,
    parameter bit          DELAY_REQ = 1,
    parameter bit          DELAY_RESP
)
(
  input  logic clk_i,
  input  logic rst_ni,
  input  logic delay_i,

  hwpe_stream_intf_stream.sink   push_i,
  hwpe_stream_intf_stream.source pop_o
);

hwpe_stream_intf_stream #(
    .DATA_WIDTH ( DATA_WIDTH )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT( 1'b1  ),
    .BYPASS_VDR_ASSERT( 1'b1  )
`endif
) delayed (
    .clk ( clk_i )
);

if (DELAY_REQ) begin : gen_delay_req
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            delayed.valid <= '0;
            delayed.data  <= '0;
            delayed.strb  <= '0;
        end else begin
            delayed.valid <= push_i.valid;
            delayed.data  <= push_i.data;
            delayed.strb  <= push_i.strb;
        end
    end
    assign pop_o.valid = delay_i ? delayed.valid : push_i.valid;
    assign pop_o.data  = delay_i ? delayed.data  : push_i.data;
    assign pop_o.strb  = delay_i ? delayed.strb  : push_i.strb;
end else begin : gen_null_delay_req
    assign pop_o.valid = push_i.valid;
    assign pop_o.data  = push_i.data;
    assign pop_o.strb  = push_i.strb;
end

if (DELAY_RESP) begin : gen_delay_resp
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            delayed.ready <= '0;
        end else begin
            delayed.ready <= pop_o.ready;
        end
    end
    assign push_i.ready = delay_i ? delayed.ready : pop_o.ready;
end else begin : gen_null_delay_resp
    assign push_i.ready = pop_o.ready;
end
endmodule
