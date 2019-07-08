[![Documentation Status](https://readthedocs.org/projects/hwpe-doc/badge/?version=latest)](https://hwpe-doc.readthedocs.io/en/latest/?badge=latest)

If you are using these IPs for an academic publication, please cite the following paper:
```
@article{conti2018xne, 
  author={F. {Conti} and P. D. {Schiavone} and L. {Benini}}, 
  journal={IEEE Transactions on Computer-Aided Design of Integrated Circuits and Systems}, 
  title={XNOR Neural Engine: A Hardware Accelerator IP for 21.6-fJ/op Binary Neural Network Inference}, 
  year={2018}, 
  doi={10.1109/TCAD.2018.2857019}, 
  ISSN={0278-0070}, 
}
```

See documentation on https://hwpe-doc.readthedocs.io/en/latest/.

The `hwpe-stream` repository contains the definition of the HWPE-Stream and TCDM interfaces used with HWPEs (HW Processing Engines), as well as the IPs necessary to manage the streams and construct streamers, e.g. for the XNE, HWCE, etc.
This repository contains the following IPs:

**basic** - basic IPs to manage HWPE-Streams:
 - *mux\_static*: multiplexes HWPE-Streams, driven by a static selection signal
 - *demux\_static*: demultiplexes for HWPE-Streams, driven by a static selection signal
 - *merge*: merges multiple same-sized HWPE-Streams into one with bigger data width
 - *split*: splits a HWPE-Stream in multiple ones with smaller data width
 - *fence*: synchronizes handshakes between a set of streams
 - *buffer*: delays a stream by 1 cycle (for timing purposes)

**fifo** - FIFO decoupling queues for HWPE-Streams:
 - *fifo*: parametric FIFO
 - *fifo\_sidech*: parametric FIFO (with side channel)
 - *fifo\_earlystall*: parametric FIFO stalling one cycle before being full
 - *fifo\_earlystall\_sidech*: parametric FIFO stalling one cycle before being full (with side channel)
 - *fifo\_ctrl*: standalone FIFO controller
 - *fifo\_scm*: standard cell memory (SCM) usable to implement a FIFO memory
 - *fifo\_scm\_test\_wrap*: BIST wrapper for SCM-based FIFO

**tcdm** - IPs to manage TCDM streams based on HWPE-Stream building blocks:
 - *tcdm\_mux\_static*: multiplexes TCDM streams, driven by a static selection signal
 - *tcdm\_reorder\_static*: reorders TCDM streams, driven by a static order
 - *tcdm\_mux*: multiplexes TCDM streams dynamically, according to a round-robin policy
 - *tcdm\_reorder*: reorders TCDM streams dynamically, according to a round-robin policy
 - *tcdm\_fifo\_store*: parametric FIFO decoupling queue for TCDM streams (only memory write operations)
 - *tcdm\_fifo\_load*: parametric FIFO decoupling queue for TCDM streams (only memory read operations)
 - *tcdm\_fifo\_load\_sidech*: parametric FIFO decoupling queue for TCDM streams (only memory read operations, with side channel)

**streamer** - IPs to transform TCDM streams in HWPE-Streams and viceversa:
 - *sink*: generates a HWPE-Stream from a TCDM load stream, according to a 3D strided pattern in TCDM
 - *source*: generates a TCDM store stream from a HWPE-Stream, according to a 3D strided pattern in TCDM
 - *addressgen*: generates memory addresses according to a 3D strided pattern in TCDM
 - *strbgen*: generates strobes for non-aligned lines
 - *sink\_realign*: HWPE-Stream realigner for non-aligned TCDM store streams
 - *source\_realign*: HWPE-Stream realigner for non-aligned TCDM load streams
