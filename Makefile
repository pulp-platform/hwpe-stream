# Copyright (C) 2022-2023 ETH Zurich and University of Bologna
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# SPDX-License-Identifier: Apache-2.0
#
# Author: Yvan Tortorella (yvan.tortorella@unibo.it)
#
# Top-level Makefile

# Paths to folders
mkfile_path    := $(dir $(abspath $(firstword $(MAKEFILE_LIST))))
BUILD_DIR      ?= $(mkfile_path)/build
QUESTA         ?=
BENDER_DIR     ?= .
BENDER         ?= ./bender
WAVES          ?= $(mkfile_path)/wave.do

compile_script ?= compile.tcl
compile_flag   ?= -suppress 2583 -suppress 13314

INI_PATH  = $(mkfile_path)/modelsim.ini
WORK_PATH = $(BUILD_DIR)
STIM_FILE = $(BUILD_DIR)/stimuli.txt
RESERVOIR_SIZE = 1024

# Useful Parameters
gui      ?= 0
P_STALL_GEN  ?= 0.0
P_STALL_RECV ?= 0.0

# Setup build object dirs
VSIM_INI=$(BUILD_DIR)/modelsim.ini
VSIM_LIBS=$(BUILD_DIR)/work

# Build implicit rules
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

SHELL := /bin/bash

# Generate instructions and data stimuli
# Run the simulation
run: $(STIM_FILE)
ifeq ($(gui), 0)
	cd $(BUILD_DIR);                       \
	$(QUESTA) vsim -c vopt_tb -do "run -a" \
	-gPROB_STALL_GEN=$(P_STALL_GEN)        \
	-gPROB_STALL_RECV=$(P_STALL_RECV)      \
	-gSTIM_FILE=$(STIM_FILE)            \
	-gRESERVOIR_SIZE=$(RESERVOIR_SIZE)
else
	$(QUESTA) vsim vopt_tb              \
	-do "add log -r sim:/tb_template/*" \
	-do "source $(WAVES)"               \
	-gPROB_STALL_GEN=$(P_STALL_GEN)        \
	-gPROB_STALL_RECV=$(P_STALL_RECV)      \
	-gSTIM_FILE=$(STIM_FILE)            \
	-gRESERVOIR_SIZE=$(RESERVOIR_SIZE)
endif

gen-stimuli: $(STIM_FILE)

$(STIM_FILE): $(BUILD_DIR)
	@echo "Generating stimuli..."
	./gen_stimuli.py $(RESERVOIR_SIZE) $(STIM_FILE)

# Download bender
$(BENDER):
	curl --proto '=https'  \
	--tlsv1.2 https://pulp-platform.github.io/bender/init -sSf | sh -s -- 0.24.0

update-ips: $(BENDER)
	$(BENDER) update
	$(BENDER) script vsim        \
	--vlog-arg="$(compile_flag)" \
	--vcom-arg="-pedanticerrors" \
	-t rtl -t fifo_test          \
	> ${compile_script}

build-hw: hw-all

# Hardware rules
hw-clean-all:
	rm -rf $(BUILD_DIR)
	rm -rf .bender
	rm -rf $(compile_script)
	rm -rf modelsim.ini
	rm -rf *.log
	rm -rf transcript
	rm -rf .cached_ipdb.json

hw-opt:
	$(QUESTA) vopt +acc=npr -o vopt_tb tb_template -floatparameters+tb_template -work $(BUILD_DIR)/work

hw-compile:
	$(QUESTA) vsim -c +incdir+$(UVM_HOME) -do 'quit -code [source $(compile_script)]'

hw-lib:
	@touch modelsim.ini
	@mkdir -p $(BUILD_DIR)
	@$(QUESTA) vlib $(BUILD_DIR)/work
	@$(QUESTA) vmap work $(BUILD_DIR)/work
	@chmod +w modelsim.ini

hw-clean:
	rm -rf transcript
	rm -rf modelsim.ini

hw-all: hw-lib hw-compile hw-opt
