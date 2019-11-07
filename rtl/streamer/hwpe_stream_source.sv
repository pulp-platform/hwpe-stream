/*
 * hwpe_stream_source.sv
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
 * The **hwpe_stream_source** module is the high-level source streamer
 * performing a series of loads on a HWPE-Mem or HWPE-MemDecoupled interface
 * and producing a HWPE-Stream data stream to feed a HWPE engine/datapath.
 * The source streamer is a composite module that makes use of many other
 * fundamental IPs. Its architecture is shown in :numfig: `_hwpe_stream_source_archi`.
 *
 * .. _hwpe_stream_source_archi:
 * .. figure:: img/hwpe_stream_source_archi.*
 *   :figwidth: 90%
 *   :width: 90%
 *   :align: center
 *
 *   Architecture of the source streamer.
 *
 * Fundamentally, a source streamer acts as a specialized DMA engine acting
 * out a predefined pattern from an **hwpe_stream_addressgen** to perform
 * a burst of loads via a HWPE-Mem interface, producing a HWPE-Stream
 * data stream from the HWPE-Mem `r_data` field.
 *
 * Depending on the `DECOUPLED` parameter, the streamer supports delayed
 * accesses using a HWPE-MemDecoupled interface.
 * The source streamer does not include any TCDM FIFO inside on its own;
 * rather, it provides a specific `tcdm_fifo_ready_o`
 * output signal that can be hooked to an external **hwpe_stream_tcdm_fifo_load**.
 * `tcdm_fifo_ready_o` provides a backpressure mechanism from the source
 * streamer to the TCDM FIFO (this is unnecessary in the case of TCDM FIFOs for
 * store).
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hwpe_stream_source_params:
 * .. table:: **hwpe_stream_source** design-time parameters.
 *
 *   +-------------------+-------------+------------------------------------------------------------------------------------------------------------------------+
 *   | **Name**          | **Default** | **Description**                                                                                                        |
 *   +-------------------+-------------+------------------------------------------------------------------------------------------------------------------------+
 *   | *DECOUPLED*       | 0           | If 1, the module expects a HWPE-MemDecoupled interface instead of HWPE-Mem.                                            |
 *   +-------------------+-------------+------------------------------------------------------------------------------------------------------------------------+
 *   | *DATA_WIDTH*      | 32          | Width of input/output streams (multiple of 32).                                                                        |
 *   +-------------------+-------------+------------------------------------------------------------------------------------------------------------------------+
 *   | *LATCH_FIFO*      | 0           | If 1, use latches instead of flip-flops (requires special constraints in synthesis).                                   |
 *   +-------------------+-------------+------------------------------------------------------------------------------------------------------------------------+
 *   | *TRANS_CNT*       | 16          | Number of bits supported in the transaction counter of the address generator, which will overflow at 2^ `TRANS_CNT`.   |
 *   +-------------------+-------------+------------------------------------------------------------------------------------------------------------------------+
 *   | *REALIGNABLE*     | 1           | If set to 0, the source will not support non-word-aligned HWPE-Mem accesses.                                           |
 *   +-------------------+-------------+------------------------------------------------------------------------------------------------------------------------+
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hwpe_stream_source_ctrl:
 * .. table:: **hwpe_stream_source** input control signals.
 *
 *   +-------------------+---------------------+-------------------------------------------------------------------------+
 *   | **Name**          | **Type**            | **Description**                                                         |
 *   +-------------------+---------------------+-------------------------------------------------------------------------+
 *   | *req_start*       | `logic`             | When 1, the source streamer operation is started if it is ready.        |
 *   +-------------------+---------------------+-------------------------------------------------------------------------+
 *   | *addressgen_ctrl* | `ctrl_addressgen_t` | Configuration of the address generator (see **hwpe_stream_addresgen**). |
 *   +-------------------+---------------------+-------------------------------------------------------------------------+
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hwpe_stream_source_flags:
 * .. table:: **hwpe_stream_source** output flags.
 *
 *   +--------------------+----------------------+----------------------------------------------------------+
 *   | **Name**           | **Type**             | **Description**                                          |
 *   +--------------------+----------------------+----------------------------------------------------------+
 *   | *ready_start*      | `logic`              | 1 when the source streamer is ready to start operation.  |
 *   +--------------------+----------------------+----------------------------------------------------------+
 *   | *done*             | `logic`              | 1 for one cycle when the streamer ends operation.        |
 *   +--------------------+----------------------+----------------------------------------------------------+
 *   | *addressgen_flags* | `flags_addressgen_t` | Address generator flags (see **hwpe_stream_addresgen**). |
 *   +--------------------+----------------------+----------------------------------------------------------+
 *   | *ready_fifo*       | `logic`              | Unused.                                                  |
 *   +--------------------+----------------------+----------------------------------------------------------+
 *
 */

import hwpe_stream_package::*;

module hwpe_stream_source
#(
  // Stream interface params
  parameter int unsigned DATA_WIDTH    = 32,
  parameter int unsigned NB_TCDM_PORTS = DATA_WIDTH/32,
  parameter int unsigned DECOUPLED     = 0,
  parameter int unsigned LATCH_FIFO    = 0,
  parameter int unsigned REALIGNABLE   = 1,
  parameter int unsigned TRANS_CNT     = 16
)
(
  input logic clk_i,
  input logic rst_ni,
  input logic test_mode_i,
  input logic clear_i,

  hwpe_stream_intf_tcdm.master     tcdm [NB_TCDM_PORTS-1:0],
  hwpe_stream_intf_stream.source   stream,
  output logic [NB_TCDM_PORTS-1:0] tcdm_fifo_ready_o, // leave unconnected if DECOUPLED = 0

  // control plane
  input  ctrl_sourcesink_t   ctrl_i,
  output flags_sourcesink_t  flags_o
);

  state_sourcesink_t cs, ns;

  logic done;
  logic address_gen_en;
  logic address_gen_clr;

  logic [31:0]                gen_addr;
  logic [NB_TCDM_PORTS*4-1:0] gen_strb;

  logic tcdm_int_req;
  logic tcdm_int_gnt;
  logic [NB_TCDM_PORTS-1:0] tcdm_split_gnt;

  logic [TRANS_CNT-1:0] overall_cnt_q, overall_cnt_d;
  logic overall_none;

  logic [NB_TCDM_PORTS-1:0] fence_hs;
  logic kill_req;

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( 32 )
  ) split_streams [NB_TCDM_PORTS-1:0] (
    .clk ( clk_i )
  );

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( 32 )
  ) fenced_streams [NB_TCDM_PORTS-1:0] (
    .clk ( clk_i )
  );

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( DATA_WIDTH )
  ) misaligned_stream (
    .clk ( clk_i )
  );

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( DATA_WIDTH )
  ) misaligned_fifo_stream (
    .clk ( clk_i )
  );

  hwpe_stream_merge #(
    .DATA_WIDTH_IN ( 32            ),
    .NB_IN_STREAMS ( NB_TCDM_PORTS )
  ) i_stream_merge (
    .clk_i    ( clk_i              ),
    .rst_ni   ( rst_ni             ),
    .clear_i  ( clear_i            ),
    .push_i   ( fenced_streams     ),
    .pop_o    ( misaligned_stream  )
  );

  // generate addresses
  hwpe_stream_addressgen #(
    .STEP         ( NB_TCDM_PORTS*4            ),
    .TRANS_CNT    ( TRANS_CNT                  ),
    .REALIGN_TYPE ( HWPE_STREAM_REALIGN_SOURCE ),
    .DECOUPLED    ( DECOUPLED                  )
  ) i_addressgen (
    .clk_i          ( clk_i                    ),
    .rst_ni         ( rst_ni                   ),
    .test_mode_i    ( test_mode_i              ),
    .enable_i       ( address_gen_en           ),
    .clear_i        ( address_gen_clr          ),
    .gen_addr_o     ( gen_addr                 ),
    .gen_strb_o     ( gen_strb                 ),
    .ctrl_i         ( ctrl_i.addressgen_ctrl   ),
    .flags_o        ( flags_o.addressgen_flags )
  );

  // realign the merged stream
  generate
    if (REALIGNABLE) begin : realign_gen
      hwpe_stream_source_realign #(
        .DECOUPLED  ( DECOUPLED  ),
        .DATA_WIDTH ( DATA_WIDTH )
      ) i_realign (
        .clk_i      ( clk_i                                  ),
        .rst_ni     ( rst_ni                                 ),
        .test_mode_i( test_mode_i                            ),
        .clear_i    ( clear_i                                ),
        .ctrl_i     ( flags_o.addressgen_flags.realign_flags ),
        .flags_o    (                                        ),
        .strb_i     ( gen_strb                               ),
        .push_i     ( misaligned_fifo_stream                 ),
        .pop_o      ( stream                                 )
      );
    end
    else begin : no_realign_gen
      hwpe_stream_assign i_no_realign (
        .push_i ( misaligned_fifo_stream ),
        .pop_o  ( stream                 )
      );
    end
  endgenerate

  // tcdm ports binding
  generate

    if(DECOUPLED != 0) begin : fence_gen

      hwpe_stream_fifo #(
        .DATA_WIDTH ( DATA_WIDTH ),
        .FIFO_DEPTH ( 2          ),
        .LATCH_FIFO ( LATCH_FIFO )
      ) i_misaligned_fifo (
        .clk_i   ( clk_i                  ),
        .rst_ni  ( rst_ni                 ),
        .clear_i ( clear_i                ),
        .flags_o (                        ),
        .push_i  ( misaligned_stream      ),
        .pop_o   ( misaligned_fifo_stream )
      );

      hwpe_stream_fence #(
        .NB_STREAMS ( NB_TCDM_PORTS ),
        .DATA_WIDTH ( 32            )
      ) i_fence (
        .clk_i       ( clk_i          ),
        .rst_ni      ( rst_ni         ),
        .clear_i     ( clear_i        ),
        .test_mode_i ( test_mode_i    ),
        .push_i      ( split_streams  ),
        .pop_o       ( fenced_streams )
      );

      always_ff @(posedge clk_i or negedge rst_ni)
      begin
        if (~rst_ni)
          fence_hs <= '0;
        else if (clear_i)
          fence_hs <= '0;
        else for(int i=0; i<NB_TCDM_PORTS; i++) begin
          if (tcdm_int_req & tcdm_int_gnt)
            fence_hs[i] <= '0;
          else if (tcdm_int_req & ~tcdm_int_gnt)
            fence_hs[i] <= fence_hs[i] | tcdm_int_req & tcdm_split_gnt[i];
        end
      end

    end
    else begin : no_fence_gen

      assign fence_hs = '0;

      for(genvar ii=0; ii<NB_TCDM_PORTS; ii++) begin : no_fence_binding
        assign fenced_streams[ii].valid = split_streams[ii].valid;
        assign fenced_streams[ii].data  = split_streams[ii].data;
        assign fenced_streams[ii].strb  = split_streams[ii].strb;
        assign split_streams[ii].ready = fenced_streams[ii].ready;
      end

      assign misaligned_fifo_stream.valid = misaligned_stream.valid;
      assign misaligned_fifo_stream.data  = misaligned_stream.data;
      assign misaligned_fifo_stream.strb  = misaligned_stream.strb;
      assign misaligned_stream.ready = misaligned_fifo_stream.ready;

    end

    for(genvar ii=0; ii<NB_TCDM_PORTS; ii++) begin: tcdm_binding
      logic        stream_valid_d, stream_valid_q;
      logic [31:0] stream_data_d,  stream_data_q;

      assign tcdm_fifo_ready_o[ii] = split_streams[ii].ready;
      assign tcdm[ii].req  = tcdm_int_req & ~fence_hs[ii] & ~kill_req;
      assign tcdm[ii].add  = gen_addr + ii*4;
      assign tcdm[ii].wen  = 1'b1;
      assign tcdm[ii].be   = 4'h0;
      assign tcdm[ii].data = '0;
      assign tcdm_split_gnt[ii] = tcdm[ii].gnt | fence_hs[ii];
      assign split_streams[ii].strb  = '1;
      assign split_streams[ii].data  = stream_valid_d ? stream_data_d : stream_data_q;
      assign split_streams[ii].valid = stream_valid_d | stream_valid_q;

      assign stream_data_d  = tcdm[ii].r_data;
      assign stream_valid_d = tcdm[ii].r_valid;

      always_ff @(posedge clk_i or negedge rst_ni)
      begin
        if(~rst_ni)
          stream_valid_q <= 1'b0;
        else if(clear_i)
          stream_valid_q <= 1'b0;
        else begin
          if(stream_valid_d & split_streams[ii].ready)
            stream_valid_q <= 1'b0;
          else if(stream_valid_d)
            stream_valid_q <= 1'b1;
          else if(stream_valid_q & split_streams[ii].ready)
            stream_valid_q <= 1'b0;
        end
      end

      always_ff @(posedge clk_i or negedge rst_ni)
      begin
        if(~rst_ni)
          stream_data_q <= '0;
        else if(clear_i)
          stream_data_q <= '0;
        else if(stream_valid_d)
            stream_data_q <= stream_data_d;
      end

    end
  endgenerate

  always_comb
  begin
    tcdm_int_gnt = 1'b1;
    for(int i=0; i<NB_TCDM_PORTS; i++)
      tcdm_int_gnt &= tcdm_split_gnt[i];
  end

  // finite-state machine
  always_ff @(posedge clk_i, negedge rst_ni)
  begin : fsm_seq
    if(rst_ni == 1'b0) begin
      cs <= STREAM_IDLE;
    end
    else if(clear_i == 1'b1) begin
      cs <= STREAM_IDLE;
    end
    else begin
      cs <= ns;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni)
  begin : done_source_ff
    if(~rst_ni)
      flags_o.done <= 1'b0;
    else if(clear_i)
      flags_o.done <= 1'b0;
    else
      flags_o.done <= done;
  end

  generate

    if(DECOUPLED != 0) begin : decoupled_ctrl_gen

      logic [TRANS_CNT-1:0] request_cnt_q, request_cnt_d;

      // this is necessary to "kill" a final request that may be issued after all the legitimate
      // ones are already going through the network (may happen consequently to fencing constraints)
      always_ff @(posedge clk_i or negedge rst_ni)
      begin
        if(~rst_ni) begin
          kill_req <= '0;
        end
        else if (clear_i) begin
          kill_req <= '0;
        end
        else begin
          if(cs == STREAM_IDLE)
            kill_req <= '0;
          else if(flags_o.addressgen_flags.realign_flags.enable==1'b1 && (tcdm_int_req & tcdm_int_gnt) && request_cnt_q == ctrl_i.addressgen_ctrl.trans_size) begin
            kill_req <= '1;
          end
          else if(flags_o.addressgen_flags.realign_flags.enable==1'b0 && (tcdm_int_req & tcdm_int_gnt) && request_cnt_q == ctrl_i.addressgen_ctrl.trans_size-1) begin
            kill_req <= '1;
          end
        end
      end

      always_comb
      begin : fsm_comb
        tcdm_int_req  = 1'b0;
        flags_o.ready_start = 1'b0;
        done = 1'b0;
        ns = cs;
        address_gen_en  = 1'b0;
        address_gen_clr = clear_i;
        case(cs)
          STREAM_IDLE: begin
            flags_o.ready_start = 1'b1;
            if(ctrl_i.req_start) begin
              ns = STREAM_WORKING;
            end
            else begin
              ns = STREAM_IDLE;
            end
            address_gen_en = 1'b0;
          end
          STREAM_WORKING: begin
            if(stream.ready) begin
              tcdm_int_req = 1'b1;
              if(tcdm_int_gnt)
                address_gen_en = 1'b1;
              else
                address_gen_en = 1'b0;
            end
            else begin
              tcdm_int_req = 1'b0;
              address_gen_en = 1'b0;
            end
            if(tcdm_int_req & tcdm_int_gnt) begin
              if(flags_o.addressgen_flags.in_progress == 1'b1) begin
                ns = STREAM_WORKING;
              end
              else if(overall_none == 1'b1 || overall_cnt_q != '0) begin
                ns = STREAM_DONE;
                address_gen_en = 1'b0;
              end
            end
            else begin
              ns = STREAM_WORKING;
            end
          end
          STREAM_DONE: begin
            ns = STREAM_DONE;
            if(overall_none == 1'b0 && overall_cnt_q == '0) begin
              ns = STREAM_IDLE;
              done = 1'b1;
              address_gen_clr = 1'b1;
            end
            address_gen_en = 1'b0;
          end
          default: begin
            ns = STREAM_IDLE;
            address_gen_en = 1'b0;
          end
        endcase
      end

      always_comb
      begin
        overall_cnt_d = overall_cnt_q;
        if(cs == STREAM_IDLE)
          overall_cnt_d = '0;
        else if(stream.valid & stream.ready) begin
          overall_cnt_d = overall_cnt_q + 1;
        end
        if((stream.valid & stream.ready) && overall_cnt_q == ctrl_i.addressgen_ctrl.trans_size-1) begin
          overall_cnt_d = '0;
        end
      end

      always_ff @(posedge clk_i or negedge rst_ni)
      begin
        if(~rst_ni) begin
          overall_cnt_q <= '0;
        end
        else if(clear_i) begin
          overall_cnt_q <= '0;
        end
        else begin
          overall_cnt_q <= overall_cnt_d;
        end
      end

      always_ff @(posedge clk_i or negedge rst_ni)
      begin
        if(~rst_ni) begin
          overall_none <= 1'b1;
        end
        else if(clear_i) begin
          overall_none <= 1'b1;
        end
        else if(cs == STREAM_IDLE) begin
          overall_none <= 1'b1;
        end
        else if(stream.valid & stream.ready) begin
          overall_none <= 1'b0;
        end
      end

      always_comb
      begin
        request_cnt_d = request_cnt_q;
        if(cs == STREAM_IDLE)
          request_cnt_d = '0;
        else if(tcdm_int_req & tcdm_int_gnt) begin
          request_cnt_d = request_cnt_q + 1;
        end
      end

      always_ff @(posedge clk_i or negedge rst_ni)
      begin
        if(~rst_ni) begin
          request_cnt_q <= '0;
        end
        else if(clear_i) begin
          request_cnt_q <= '0;
        end
        else begin
          request_cnt_q <= request_cnt_d;
        end
      end

    end
    else begin : no_decoupled_ctrl_gen

      assign kill_req = 1'b0;

      always_comb
      begin : fsm_comb
        tcdm_int_req  = 1'b0;
        flags_o.ready_start = 1'b0;
        done = 1'b0;
        ns         = cs;
        address_gen_en  = 1'b0;
        address_gen_clr = clear_i;
        case(cs)
          STREAM_IDLE: begin
            flags_o.ready_start = 1'b1;
            if(ctrl_i.req_start) begin
              ns = STREAM_WORKING;
            end
            else begin
              ns = STREAM_IDLE;
            end
            address_gen_en = 1'b0;
          end
          STREAM_WORKING: begin
            if(stream.ready) begin
              tcdm_int_req = 1'b1;
              if(tcdm_int_gnt)
                address_gen_en = 1'b1;
              else
                address_gen_en = 1'b0;
            end
            else begin
              tcdm_int_req = 1'b0;
              address_gen_en = 1'b0;
            end
            if(tcdm_int_gnt) begin
              if(flags_o.addressgen_flags.in_progress == 1'b1) begin
                ns = STREAM_WORKING;
              end
              else begin
                done = 1'b1;
                ns   = STREAM_IDLE;
                address_gen_clr = 1'b1;
              end
            end
            else begin
              ns = STREAM_WORKING;
            end
          end//~SOURCE
          default: begin
            ns = STREAM_IDLE;
            address_gen_en = 1'b0;
          end
        endcase
      end

    end

  endgenerate

endmodule // hwpe_stream_source
