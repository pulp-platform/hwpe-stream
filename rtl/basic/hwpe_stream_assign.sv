/*
 * hwpe_stream_assign.sv
 * Francesco Conti <f.conti@unibo.it>
 *
 * Copyright (C) 2014-2019 ETH Zurich, University of Bologna
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
 * The **hwpe_stream_assign** module is used to connect an input stream
 * `push_i` to an output stream `pop_o`.
 */

import hwpe_stream_package::*;

module hwpe_stream_assign
(
  hwpe_stream_intf_stream.sink   push_i,
  hwpe_stream_intf_stream.source pop_o
);

  // tcdm ports binding
  assign pop_o.valid = push_i.valid;
  assign pop_o.data  = push_i.data;
  assign pop_o.strb  = push_i.strb;
  assign push_i.ready = pop_o.ready;

endmodule // hwpe_stream_assign
