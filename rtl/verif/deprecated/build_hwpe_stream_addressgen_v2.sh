#!/bin/bash
set -e
vlog -sv -work work ../../../hwpe-stream/rtl/hwpe_stream_package.sv
vlog -sv -work work ../../../hwpe-stream/rtl/hwpe_stream_interfaces.sv
vlog -sv -work work ../../../hwpe-stream/tb/tb_hwpe_stream_receiver.sv
vlog -sv -work work ../../../hwpe-stream/tb/tb_hwpe_stream_reservoir.sv
vlog -sv -work work ../streamer/hwpe_stream_addressgen_v2.sv
vlog -sv -work work ./tb_hwpe_stream_addressgen_v2.sv
vopt +acc=mnpr -o vopt_tb_hwpe_stream_addressgen_v2 tb_hwpe_stream_addressgen_v2 -work work
