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
    parameter int unsigned DELAY_REQ  = 1,
    parameter int unsigned DELAY_RESP = 1
)
(
  input  logic clk_i,
  input  logic rst_ni,
  input  logic delay_i,

  hwpe_stream_intf_stream.sink   push_i,
  hwpe_stream_intf_stream.source pop_o
);

localparam int unsigned MAX_DELAY = DELAY_REQ > DELAY_RESP ? DELAY_REQ : DELAY_RESP;

hwpe_stream_intf_stream #(
    .DATA_WIDTH ( DATA_WIDTH )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT( 1'b1  ),
    .BYPASS_VDR_ASSERT( 1'b1  )
`endif
) delayed [MAX_DELAY:0] (
    .clk ( clk_i )
);

// Request
logic delay_req;

assign delay_req = (DELAY_REQ > 0) && delay_i;

assign delayed[0].valid = push_i.valid;
assign delayed[0].data  = push_i.data;
assign delayed[0].strb  = push_i.strb;

for (genvar ii = 1; ii <= MAX_DELAY; ii++) begin : gen_req
    if (ii > DELAY_REQ) begin : gen_tieoffs
        assign delayed[ii].valid = '0;
        assign delayed[ii].data  = '0;
        assign delayed[ii].strb  = '0;
    end else begin : gen_delay
        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni) begin
                delayed[ii].valid <= '0;
                delayed[ii].data  <= '0;
                delayed[ii].strb  <= '0;
            end else begin
                delayed[ii].valid <= delayed[ii-1].valid;
                delayed[ii].data  <= delayed[ii-1].data;
                delayed[ii].strb  <= delayed[ii-1].strb;
            end
        end
    end
end

assign pop_o.valid = delay_req ? delayed[DELAY_REQ].valid : push_i.valid;
assign pop_o.data  = delay_req ? delayed[DELAY_REQ].data  : push_i.data;
assign pop_o.strb  = delay_req ? delayed[DELAY_REQ].strb  : push_i.strb;

// Response
logic delay_resp;

assign delay_resp = (DELAY_RESP > 0) && delay_i;

assign delayed[0].ready = pop_o.ready;

for (genvar ii = 1; ii <= MAX_DELAY; ii++) begin : gen_resp
    if (ii > DELAY_RESP) begin : gen_tieoffs
        assign delayed[ii].ready = '0;
    end else begin : gen_delay
        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni) begin
                delayed[ii].ready <= '0;
            end else begin
                delayed[ii].ready <= delayed[ii-1].ready;
            end
        end
    end
end

assign push_i.ready = delay_resp ? delayed[DELAY_RESP].ready : pop_o.ready;
endmodule
