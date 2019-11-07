/*
 * hwpe_stream_tcdm_assign.sv
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

import hwpe_stream_package::*;

module hwpe_stream_tcdm_assign
(
  hwpe_stream_intf_tcdm.slave  tcdm_slave,
  hwpe_stream_intf_tcdm.master tcdm_master
);

  assign tcdm_master.add  = tcdm_slave.add;
  assign tcdm_master.data = tcdm_slave.data;
  assign tcdm_master.be   = tcdm_slave.be;
  assign tcdm_master.wen  = tcdm_slave.wen;
  assign tcdm_master.req  = tcdm_slave.req;

  assign tcdm_slave.gnt     = tcdm_master.gnt;
  assign tcdm_slave.r_valid = tcdm_master.r_valid;
  assign tcdm_slave.r_data  = tcdm_master.r_data;

endmodule // hwpe_stream_tcdm_assign
