/*
 * hwpe_stream_transaction_tracer.sv
 * Francesco Conti <f.conti@unibo.it>
 *
 * Copyright (C) 2026 ETH Zurich, University of Bologna
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
 * The **hwpe_stream_transaction_tracer** module is a purely passive,
 * simulation-only monitor: it observes a HWPE-Stream through the `monitor`
 * modport of a `hwpe_stream_intf_stream` interface and appends every
 * *handshaken* beat (i.e. every cycle in which `valid & ready` holds) to a
 * JSON log file, whose name is given by the `LOG_FILE` parameter.
 *
 * A HWPE-Stream is unidirectional, so a single log file is produced. Its
 * format is described by the `hwpe_stream_transaction-v1` JSON schema in
 * `tracer/hwpe_stream_transaction.schema.json`. The resulting logs can be
 * compared against each other -- or against HCI transaction logs -- with the
 * `hci-tracer` utility found in the `tracer/` directory of the HCI repository.
 *
 * The log is a single well-formed JSON document: the header and the opening of
 * the `transactions` array are emitted by an `initial` block, one object per
 * beat is emitted as the simulation progresses, and the array and object are
 * closed by a `final` block. Should the simulation be aborted before the
 * `final` block runs, the resulting truncated file is still accepted (and
 * repaired) by `hci-tracer`.
 *
 * Logging is gated by `enable_i`, which can be used to restrict tracing to a
 * region of interest; `cycle` counts clock cycles from the release of `rst_ni`
 * and is reported for waveform cross-reference only -- transaction *time* is
 * never used when comparing two logs.
 *
 * The body of the module is enclosed in a `ifndef SYNTHESIS guard, so that the
 * tracer can be instantiated unconditionally: under synthesis it elaborates to
 * an empty module.
 */

module hwpe_stream_transaction_tracer
#(
  parameter int unsigned DATA_WIDTH    = 32,
  parameter int unsigned ELEMENT_WIDTH = 8,
  parameter string       LOG_FILE      = "hwpe_stream_trace.json"
)
(
  input logic                     clk_i,
  input logic                     rst_ni,
  input logic                     enable_i,
  hwpe_stream_intf_stream.monitor stream
);

`ifndef SYNTHESIS

  localparam int unsigned STRB_WIDTH = DATA_WIDTH/ELEMENT_WIDTH;

  int              fd;
  longint unsigned cycle_q;
  longint unsigned seq;
  string           sep;

  initial
  begin
    fd = $fopen(LOG_FILE, "w");
    if(fd == 0) begin
      $fatal(1, "[hwpe_stream_transaction_tracer] could not open log file %s", LOG_FILE);
    end
    seq = 0;
    sep = "";
    $fwrite(fd, "{\n");
    $fwrite(fd, "  \"schema\": \"hwpe_stream_transaction-v1\",\n");
    $fwrite(fd, "  \"interface\": { \"DATA_WIDTH\": %0d, \"ELEMENT_WIDTH\": %0d,",
      DATA_WIDTH, ELEMENT_WIDTH);
    $fwrite(fd, " \"STRB_WIDTH\": %0d },\n", STRB_WIDTH);
    $fwrite(fd, "  \"path\": \"%m\",\n");
    $fwrite(fd, "  \"transactions\": [");
  end

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni) begin
      cycle_q <= '0;
    end
    else begin
      cycle_q <= cycle_q + 1;
    end
  end

  always @(posedge clk_i)
  begin
    if(rst_ni & enable_i & stream.valid & stream.ready & (fd != 0)) begin
      $fwrite(fd, "%s\n    {\"seq\": %0d, \"cycle\": %0d, \"data\": \"0x%h\", \"strb\": \"0x%h\"}",
        sep, seq, cycle_q, stream.data, stream.strb);
      sep = ",";
      seq = seq + 1;
    end
  end

  final
  begin
    if(fd != 0) begin
      $fwrite(fd, "\n  ]\n}\n");
      $fclose(fd);
    end
  end

/*
 * Interface size asserts
 */
`ifndef VERILATOR
  initial
    data_width : assert(DATA_WIDTH == stream.DATA_WIDTH);
  initial
    element_width : assert(ELEMENT_WIDTH == stream.ELEMENT_WIDTH);
`endif

`endif /* `ifndef SYNTHESIS */

endmodule // hwpe_stream_transaction_tracer
