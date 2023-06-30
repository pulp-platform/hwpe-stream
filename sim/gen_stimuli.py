#!/usr/bin/env python

# get RESERVOIR_SIZE and FILE_NAME from command line
import sys
if len(sys.argv) == 3:
    RESERVOIR_SIZE = int(sys.argv[1])
    FILE_NAME = sys.argv[2]
else:
    print("Usage: gen_stimuli.py RESERVOIR_SIZE FILE_NAME")
    sys.exit(1)

# generate RESERVOIR_SIZE random numbers and write them in hex format in the file FILE_NAME
import random
with open(FILE_NAME, 'w') as f:
    for i in range(RESERVOIR_SIZE):
        # this gen_stim.py assumes 32-bit DATA_WIDTH
        f.write(hex(random.randint(0, 2**32-1))[2:] + '\n')
