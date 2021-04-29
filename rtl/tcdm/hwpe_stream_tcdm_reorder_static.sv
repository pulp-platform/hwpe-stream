/*
 * hwpe_stream_tcdm_reorder_static.sv
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
 * The **hwpe_stream_tcdm_reorder_static** block can be used to rotate the order of a
 * set of HWPE-Mem channels depending on an `order_i` input, which
 * is considered static. This is used to statically change the order of a
 * set of channels.
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hwpe_stream_tcdm_reorder_static_params:
 * .. table:: **hwpe_stream_tcdm_reorder_static** design-time parameters.
 *
 *   +------------+-------------+------------------------------+
 *   | **Name**   | **Default** | **Description**              |
 *   +------------+-------------+------------------------------+
 *   | *NB_CHAN*  | 2           | Number of HWPE-Mem channels. |
 *   +------------+-------------+------------------------------+
 */


module hwpe_stream_tcdm_reorder_static
  import hwpe_stream_package::*;
#(
  parameter int unsigned NB_CHAN = 2
)
(
  input  logic                       clk_i,
  input  logic                       rst_ni,
  input  logic                       clear_i,

  input  logic [NB_CHAN-1:0][$clog2(NB_CHAN)-1:0] order_i,

  hwpe_stream_intf_tcdm.slave        in  [NB_CHAN-1:0],
  hwpe_stream_intf_tcdm.master       out [NB_CHAN-1:0]

);

  localparam NB_IN_CHAN  = NB_CHAN;
  localparam NB_OUT_CHAN = NB_CHAN;

  logic [NB_CHAN-1:0]       in_req;
  logic [NB_CHAN-1:0][31:0] in_add;
  logic [NB_CHAN-1:0]       in_wen;
  logic [NB_CHAN-1:0][3:0]  in_be;
  logic [NB_CHAN-1:0][31:0] in_data;
  logic [NB_CHAN-1:0]       in_gnt;
  logic [NB_CHAN-1:0][31:0] in_r_data;
  logic [NB_CHAN-1:0]       in_r_valid;
  logic [NB_CHAN-1:0]       out_req;
  logic [NB_CHAN-1:0][31:0] out_add;
  logic [NB_CHAN-1:0]       out_wen;
  logic [NB_CHAN-1:0][3:0]  out_be;
  logic [NB_CHAN-1:0][31:0] out_data;
  logic [NB_CHAN-1:0]       out_gnt;
  logic [NB_CHAN-1:0][31:0] out_r_data;
  logic [NB_CHAN-1:0]       out_r_valid;

  genvar i;
  generate

    for(i=0; i<NB_CHAN; i++) begin : out_chan_gen

      // binding
      assign in_req  [i] = in[i].req  ;
      assign in_add  [i] = in[i].add  ;
      assign in_wen  [i] = in[i].wen  ;
      assign in_be   [i] = in[i].be   ;
      assign in_data [i] = in[i].data ;
      assign in[i].gnt     = in_gnt     [i];
      assign in[i].r_data  = in_r_data  [i];
      assign in[i].r_valid = in_r_valid [i];
      assign out[i].req  = out_req  [i];
      assign out[i].add  = out_add  [i];
      assign out[i].wen  = out_wen  [i];
      assign out[i].be   = out_be   [i];
      assign out[i].data = out_data [i];
      assign out_gnt     [i] = out[i].gnt    ;
      assign out_r_data  [i] = out[i].r_data ;
      assign out_r_valid [i] = out[i].r_valid;

      always_comb
      begin : mux_req_comb
        out_req   [i] = in_req   [order_i[i]];
        out_add   [i] = in_add   [order_i[i]];
        out_wen   [i] = in_wen   [order_i[i]];
        out_data  [i] = in_data  [order_i[i]];
        out_be    [i] = in_be    [order_i[i]];
      end

    end // out_chan_gen

    always_comb
    begin : mux_resp_comb
      for(int i=0; i<NB_CHAN; i++) begin
        in_r_data  [i] = '0;
        in_r_valid [i] = 1'b0;
        in_gnt     [i] = 1'b0;
      end
      for(int i=0; i<NB_CHAN; i++) begin
        in_r_data  [order_i[i]] = out_r_data  [i];
        in_r_valid [order_i[i]] = out_r_valid [i];
        in_gnt     [order_i[i]] = out_gnt     [i];
      end
    end

  endgenerate

endmodule // hwpe_stream_tcdm_reorder_static
