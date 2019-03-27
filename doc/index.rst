.. Hardware Processing Engines - Interface Specifications documentation master file, created by
   sphinx-quickstart on Sun Mar  3 23:38:08 2019.
   You can adapt this file completely to your liking, but it should at least
   contain the root `toctree` directive.

===========================
Hardware Processing Engines
===========================

.. toctree::
   :maxdepth: 2
   :caption: Contents:

.. ******************
.. Indices and tables
.. ******************

.. * :ref:`genindex`
.. * :ref:`modindex`
.. * :ref:`search`

******************
Document Revisions
******************

+-----------------+-----------------+-----------------+------------------+
| **Rev.**        | **Date**        | **Author**      | **Description**  |
+=================+=================+=================+==================+
| 1.0             | 14/01/18        | Francesco Conti | First draft of   |
|                 |                 |                 | the              |
|                 |                 |                 | specifications.  |
+-----------------+-----------------+-----------------+------------------+
| 1.1             | 19/01/18        | Francesco Conti | Added            |
|                 |                 |                 | description of   |
|                 |                 |                 | *hwpe-stream*,   |
|                 |                 |                 | *hwpe-ctrl*      |
|                 |                 |                 | modules.         |
+-----------------+-----------------+-----------------+------------------+
| 1.2             | 26/01/18        | Francesco Conti | Added            |
|                 |                 |                 | specification    |
|                 |                 |                 | of the           |
|                 |                 |                 | microcode        |
|                 |                 |                 | processor.       |
+-----------------+-----------------+-----------------+------------------+
| 1.3             | 10/02/18        | Francesco Conti | Removed some     |
|                 |                 |                 | unnecessary      |
|                 |                 |                 | constraints on   |
|                 |                 |                 | TCDM prot.       |
+-----------------+-----------------+-----------------+------------------+
| 1.4             | 27/03/19        | Francesco Conti | Switched to RST; |
|                 |                 |                 | major rehaul.    |
+-----------------+-----------------+-----------------+------------------+


************************
HWPE Interface Protocols
************************

Introduction
============

*Hardware Processing Engines* (HWPEs) are special-purpose,
memory-coupled accelerators that can be inserted in the SoC or cluster
of a PULP system to amplify its performance and energy efficiency in
particular tasks.

Differently from most accelerators in literature, HWPEs do not rely on
an external DMA to feed them with input and to extract output, and they
are not (necessarily) tied to a single core. Rather, they operate
directly on the same memory that is shared by other elements in the PULP
system (e.g. the L1 TCDM in a PULP cluster, or the shared L2 in
PULPissimo). Their control is memory-mapped and accessed through a
peripheral bus or interconnect. HW-based execution on an HWPE can be
readily intermixed with software code, because all that needs to be
exchanged between the two is a set of pointers and, if necessary, a few
parameters.

For more information on HWPEs and their properties, see references
[1]-[5].

.. figure:: img/hwpe.pdf
  :figwidth: 60%
  :width: 60%
  :align: center

  Template of a Hardware Processing Engine  (HWPE).

This document defines the interface protocols and modules that are used
to enable connecting HWPEs in a PULP system. Typically, such a module is
divided in a **streamer** interface towards the memory system, a
**control/peripheral** interface used for programming it, and an
**engine** containing the actual datapath of the accelerator.

HWPE-Stream protocol
====================

The HWPE-Stream protocol is a simple protocol designed to move data
between the various sub-components of an HWPE. As HWPEs are memory-based
accelerators, streams are typically generated and consumed internally
within the accelerator between fully synchronous devices.
HWPE-Stream can cross between two clock domains using dual-clock FIFOs;
handshakes still have to happen in a fully synchronous way.
HWPE-Stream streams are directional, flowing from a *source* to a *sink*
direction, using a two signal *handshake* and carrying a data *payload*.
:numref:`hwpe_stream_source_sink` and :numref:`hwpe_stream_signals` report
the signals used by the HWPE-Stream protocol.

.. _hwpe_stream_source_sink:
.. figure:: img/hwpe_stream_source_sink.pdf
  :figwidth: 60%
  :width: 30%
  :align: center

  Data flow of the HWPE-Stream protocol. Red signals carry the *handshake*,
  blue ones the *payload*.

.. _hwpe_stream_signals:
.. table:: HWPE-Stream signals.

  +-----------------+-----------------+-----------------+-----------------+
  | **Signal**      | **Size**        | **Description** | **Direction**   |
  +-----------------+-----------------+-----------------+-----------------+
  | *data*          | Multiple of 8   | The data        | from *source*   |
  |                 | bits            | payload         | to *sink*       |
  |                 |                 | transported by  |                 |
  |                 |                 | the stream.     |                 |
  +-----------------+-----------------+-----------------+-----------------+
  | *strb*          | size(*data*)/8  | Optional.       | from *source*   |
  |                 |                 | Indicates valid | to *sink*       |
  |                 |                 | bytes in the    |                 |
  |                 |                 | data payload    |                 |
  |                 |                 | (1=valid).      |                 |
  +-----------------+-----------------+-----------------+-----------------+
  | *valid*         | 1 bit           | Handshake valid | from *source*   |
  |                 |                 | signal          | to *sink*       |
  |                 |                 | (1=asserted).   |                 |
  +-----------------+-----------------+-----------------+-----------------+
  | *ready*         | 1 bit           | Handshake ready | from *sink*     |
  |                 |                 | signal          | to *source*     |
  |                 |                 | (1=asserted).   |                 |
  +-----------------+-----------------+-----------------+-----------------+

The handshake signals *valid* and *ready* are used to validate
transactions between sources and sinks. Transactions are subject to the
following rules:

1. **A handshake occurs in the cycle when both** *valid* **and** *ready*
   **are asserted**. The handshake is the "atomic" event after which the
   current payload is considered consumed by the consumer at the sink
   side of the HWPE-Stream interface.

2. *data* **and** *strb* **can change their value either a) when** *valid*
   **is deasserted, or b) in the cycle following a handshake, even if**
   *valid* **remains asserted**. In other words, valid data payloads must
   stay on the interface until a valid handshake has occurred.

3. **The assertion of** *valid* **(transition 0 to 1) cannot depend**
   **combinationally on the state of** *ready*.
   On the other hand, the assertion of *ready* (transition 0 to 1) can
   depend combinationally on the state of *valid*. This rule, which is
   modeled around the similar behavior used by TCDM memories (see below)
   is meant to avoid any deadlock in ping-pong logic.

4. **The deassertion of** *valid* **(transition 1 to 0) can happen only**
   **in the cycle after a valid handshake**. In other words, valid data
   produced by a source must be correctly consumed before *valid*
   is deasserted.

.. .. _wavedrom_hwpe_stream_r2_ok:
.. .. wavedrom:: wavedrom/hwpe_stream_r2_ok.json
..   :width: 50 %
..   :caption: HWPE-Stream handshake satisfying rule 2.

.. _wavedrom_hwpe_stream:
.. wavedrom:: wavedrom/hwpe_stream.json
  :width: 100 %
  :caption: Example of a HWPE-Stream with an 8-bit data stream. Valid
            handshakes happen in cycles 3,4,6, and 8.

.. _wavedrom_hwpe_stream_r2_no:
.. wavedrom:: wavedrom/hwpe_stream_r2_no.json
  :width: 50 %
  :caption: Incorrect HWPE-Stream handshake, not satisfying rule 2.

.. _wavedrom_hwpe_stream_r4_no:
.. wavedrom:: wavedrom/hwpe_stream_r4_no.json
  :width: 50 %
  :caption: Incorrect HWPE-Stream handshake, not satisfying rule 4.

:numref:`wavedrom_hwpe_stream` shows several correct handshakes on
a HWPE-Stream, while :numref:`wavedrom_hwpe_stream_r2_no` and
:numref:`wavedrom_hwpe_stream_r4_no` show two examples of incorrect
transactions. Both behaviors are checked by means of asserts in the
reference SystemVerilog code for HWPE-Stream interfaces.
Rule 3 cannot be checked by means of asserts; it is up to the designer
to avoid *valid* to *ready* combinational dependencies that could
result in combinational loops, since the value of *ready* is assumed
to be combinationally dependent from *valid*.

The only side channel that can be included in an HWPE-Stream is *strb*,
which is optionally used to signal which bytes of the *data* payload
contain meaningful data. HWPE-Stream streams in which *strb* is absent
are assumed to have only valid bytes in their *data* payload. We refer
HWPE-Stream streams with *strb* as *strobed streams*.

HWPE-Mem protocols
==================

HWPE-Mem
--------

HWPEs are connected to external L1/L2 shared-memory by means of a simple
memory protocol, using a request/grant handshake. The protocol used is
called HWPE Memory (*HWPE-Mem*) protocol, and it is essnetially similar
to the protocol used by cores and DMAs operating on memories.
This document focuses on the specific signal names used within HWPEs
and in the reference implementation of HWPE-Stream IPs.
It supports neither multiple outstanding transactions nor bursts, as
HWPEs using this protocol are assumed to be closely coupled to memories.
It uses a two signal *handshake* and carries two phases, a *request* and
a *response*.

The HWPE-Mem protocol is used to connect a *master* to a *slave*.
:numref:`hwpe_tcdm_master_slave` and :numref:`hwpe_tcdm_signals` report
the signals used by the HWPE-Mem protocol.

.. _hwpe_tcdm_master_slave:
.. figure:: img/hwpe_tcdm_master_slave.pdf
  :figwidth: 60%
  :width: 30%
  :align: center

  Data flow of the HWPE-Mem protocol. Red signals carry the
  *handshake*; blue signals the *request* phase; green signals the
  *response* phase.

.. _hwpe_tcdm_signals:
.. table:: HWPE-Mem signals.

  +------------+----------+----------------------------------------+---------------------+
  | **Signal** | **Size** | **Description**                        | **Direction**       |
  +------------+----------+----------------------------------------+---------------------+
  | *req*      | 1 bit    | Handshake request signal (1=asserted). | *master* to *slave* |
  +------------+----------+----------------------------------------+---------------------+
  | *gnt*      | 1 bit    | Handshake grant signal (1=asserted).   | *slave* to *master* |
  +------------+----------+----------------------------------------+---------------------+
  | *add*      | 32 bit   | Word-aligned memory address.           | *master* to *slave* |
  +------------+----------+----------------------------------------+---------------------+
  | *wen*      | 1 bit    | Write enable signal (1=read, 0=write). | *master* to *slave* |
  +------------+----------+----------------------------------------+---------------------+
  | *be*       | 4 bit    | Byte enable signal (1=valid byte).     | *master* to *slave* |
  +------------+----------+----------------------------------------+---------------------+
  | *data*     | 32 bit   | Data word to be stored.                | *master* to *slave* |
  +------------+----------+----------------------------------------+---------------------+
  | *r_data*   | 32 bit   | Loaded data word.                      | *slave* to *master* |
  +------------+----------+----------------------------------------+---------------------+
  | *r_valid*  | 1 bit    | Valid loaded data word (1=asserted).   | *slave* to *master* |
  +------------+----------+----------------------------------------+---------------------+

The handshake signals *req* and *gnt* are used to validate transactions
between masters and slaves. Transactions are subject to the following
rules:

1. **A valid handshake occurs in the cycle when both** *req* **and** *gnt*
   **are asserted**. This is true for both write and read transactions.

2. *r_valid* **must be asserted the cycle after a valid read handshake;**
   *r_data* **must be valid on this cycle**. This is due to
   the tightly-coupled nature of memories; if the memory cannot
   respond in one cycle, it must delay granting the transaction.

3. **The assertion of** *req* **(transition 0 to 1) cannot depend**
   **combinationally on the state of** *gnt*. On the other hand,
   the assertion of *gnt* (transition 0 to 1) can depend combinationally
   on the state of *req* (and typically it does). This rule avoids
   deadlocks in ping-pong logic.

The semantics of the *r_valid* signal are not well defined with respect
to the usual TCDM protocol. In PULP clusters, *r_valid* will be asserted
also after write transactions, not only in reads. However, the HWPE-Mem
protocol and the IPs in this repository should not make assumptions
on the *r_valid* in write transactions.

HWPE-MemDecoupled
-----------------

The HWPE-Mem protocol can be used to directly connect an accelerator to the
shared memory of a PULP-based system. However, transactions using this protocol
are inherently latency sensitive. HWPE-Mem rule 2 embodies this: an operation
is complete only when its response has arrived. This means that HWPE-Mem
streams, including load and store transactions, cannot be enqueued in
a FIFO queue.
To overcome this limitation, a variant of the HWPE-Mem protocol is
HWPE-MemDecoupled. This protocol uses the same interface as HWPE-Mem but
lifts rule 2 and adds a new rule 4. Transactions are thus following the
following rules:

1. **A valid handshake occurs in the cycle when both** *req* **and** *gnt*
   **are asserted**. This is true for both write and read transactions.

3. **The assertion of** *req* **(transition 0 to 1) cannot depend**
   **combinationally on the state of** *gnt*. On the other hand,
   the assertion of *gnt* (transition 0 to 1) can depend combinationally
   on the state of *req* (and typically it does). This rule avoids
   deadlocks in ping-pong logic.

4. **The stream of transactions includes only reads (** *wen* **=1) or**
   **only writes (** *wen* **=0)**. Mixing reads and writes in the stream
   is not allowed.

HWPE-MemDecoupled transactions are insensitive to latency and their
*request* and *response* phases can be treated similarly to separate
HWPE-Stream streams.
Once two or more HWPE-MemDecoupled transactions are mixed, the mixed
interface has to be treated as a HWPE-Mem protocol (i.e. it is sensitive
to latency).

Exchanging data between HWPE-Mem and HWPE-Stream
------------------------------------------------

As HWPEs ultimately consume and produce data to the external shared
memory using one or more ports exposing TCDM interfaces, converting data
between HWPE-Mem and HWPE-Stream (i.e., exchanging data between the
memory-based and the stream-based worlds) is one of the main tasks to be
accomplished in the design of an accelerator. The HWPE-Stream and HWPE-Mem
protocols are similar by design, which makes the handling of handshakes
signficantly easier.
The following applies to HWPE-Mem and HWPE-MemDecoupled in a similar
manner.

Three objectives have to be met:

-  HWPE-Stream has no notion of address: to produce a stream out of HWPE-Mem
   loads, or consume a stream in a series of HWPE-Mem stores, it is
   necessary to generate addresses according to some rule.

-  HWPE-Stream streams can be longer than 32 bits; it is necessary to
   generate them from / split them into multiple TCDM loads/stores.

-  HWPE-Mem addresses may be misaligned with respect to word
   boundaries, in which case two TCDM loads/stores are necessary to
   transact a single 32-bit word and strobes have to be also aligned.

In the current version of the HWPE specifications, we address these
issues by providing a set of modules which can incrementally be used to
solve each of the problems above. This are referred to in a later section.

.. _tcdm_stream_source:
.. figure:: img/tcdm_stream_source.pdf
  :figwidth: 100%
  :width: 100%
  :align: center

  Example of data exchange between a series of HWPE-Mem loads and a
  HWPE-Stream. Four data packets have to be produced at the sink end
  of the stream; since data is not well aligned in memory, this results
  in five loads on the HWPE-Mem interface, which are then transformed
  in a strobed HWPE-Stream. The stream is then realigned so that the
  correct four elements are available.

.. _tcdm_stream_sink:
.. figure:: img/tcdm_stream_sink.pdf
  :figwidth: 100%
  :width: 100%
  :align: center

  Example of data exchange between a HWPE-Stream and a series of HWPE-Mem
  stores. Four data packets have to be consumed at the source end
  of the stream; since data is not well aligned in memory, this results
  in a strobed HWPE-Stream with five packets, the first and last of which
  contain also null data. The strobed stream is then converted in a set of
  five HWPE-Mem store transactions.

:numref:`tcdm_stream_source`, :numref:`tcdm_stream_sink` show two
examples of transactions going (respectively) from a series of loads
on the HWPE-Mem interface to internal HWPE-Streams and from an internal
HWPE-Stream to a series of stores on HWPE-Mem. The example focuses on
the realignment behavior.

HWPE-Periph protocol
====================

To enable control, HWPEs typically expose a slave port to the
peripheral system interconnect. The slave port follows an extension of
the HWPE-Mem protocol which we call HWPE-Periph in this document.
The HWPE-Periph protocol is essentially the same one exposed by most
peripherals in a PULP system and used by the core to communicate with them.

.. _hwpe_periph_signals:
.. table:: HWPE-Periph signals.

  +-----------------+-----------------+-----------------+---------------------+
  | **Signal**      | **Size**        | **Description** | **Direction**       |
  +-----------------+-----------------+-----------------+---------------------+
  | *req*           | 1 bit           | Handshake       | *master* to *slave* |
  |                 |                 | request signal  |                     |
  |                 |                 | (1=asserted).   |                     |
  +-----------------+-----------------+-----------------+---------------------+
  | *gnt*           | 1 bit           | Handshake grant | *slave* to *master* |
  |                 |                 | signal          |                     |
  |                 |                 | (1=asserted).   |                     |
  +-----------------+-----------------+-----------------+---------------------+
  | *add*           | 32 bit          | Word-aligned    | *master* to *slave* |
  |                 |                 | memory address. |                     |
  +-----------------+-----------------+-----------------+---------------------+
  | *wen*           | 1 bit           | Write enable    | *master* to *slave* |
  |                 |                 | signal (1=read, |                     |
  |                 |                 | 0=write).       |                     |
  +-----------------+-----------------+-----------------+---------------------+
  | *be*            | 4 bit           | Byte enable     | *master* to *slave* |
  |                 |                 | signal (1=valid |                     |
  |                 |                 | byte).          |                     |
  +-----------------+-----------------+-----------------+---------------------+
  | *data*          | 32 bit          | Data word to be | *master* to *slave* |
  |                 |                 | stored.         |                     |
  +-----------------+-----------------+-----------------+---------------------+
  | *id*            | ID_WIDTH bits   | ID used to      | *master* to *slave* |
  |                 |                 | identify the    |                     |
  |                 |                 | master          |                     |
  |                 |                 | (request).      |                     |
  +-----------------+-----------------+-----------------+---------------------+
  | *r_data*        | 32 bit          | Loaded data     | *slave* to *master* |
  |                 |                 | word.           |                     |
  +-----------------+-----------------+-----------------+---------------------+
  | *r_valid*       | 1 bit           | Valid loaded    | *slave* to *master* |
  |                 |                 | data word       |                     |
  |                 |                 | (1=asserted).   |                     |
  +-----------------+-----------------+-----------------+---------------------+
  | *r_id*          | ID_WIDTH bits   | ID used to      | *slave* to *master* |
  |                 |                 | identify the    |                     |
  |                 |                 | master (reply). |                     |
  +-----------------+-----------------+-----------------+---------------------+

The HWPE-Periph protocol is distinguished by the HWPE-Mem protocol by the *id*
and *r_id* side channels. These are used in load operations issued
through a PERIPH interface: the *id* identifies the master during the
request phase, is buffered by the slave peripherals and accompanies the
response phase as *r_id*. In this way, multiple masters can distinguish
which traffic is related to themselves.
For the rest of the purposes related with HWPEs, HWPE-Periph and HWPE-Mem work
in the same way.


.. -  The **hwpe_stream_addressgen** module is responsible of generating
..    addresses according to a pattern of 3D blocks characterized by width,
..    height and depth.

.. -  The **hwpe_stream_merge** and **hwpe_stream_split** modules can be
..    used to merge/split HWPE-Stream streams. In this way, on the module
..    boundary 32-bit streams can be converted in TCDM accesses.

.. -  The **hwpe_stream_source_realign** and **hwpe_stream_sink_realign**
..    modules can be used to transform a strobed stream into unstrobed ones
..    and to transform unstrobed streams into strobed ones. In this way,
..    misaligned TCDM accesses can be already transformed in streams with a
..    strobe to indicate what data is meaningful.

**********************
HWPE Interface Modules
**********************

HWPE-Stream basic modules
=========================

Basic HWPE-Stream management modules are used to select multiple streams,
merge multiple streams into one, split a stream in multiple ones, synchronize
their handshakes and similar basic ``morphing'' functionality; or to delay
and enqueue streams.
Modules performing these functions can be found within the `rtl/basic` and
`rtl/fifo` subfolders of the `hwpe-stream` repository.

.. raw:: latex

    \clearpage

hwpe_stream_merge
-----------------

.. _hwpe_stream_merge:
.. svprettyplot:: ../rtl/basic/hwpe_stream_merge.sv

.. raw:: latex

    \clearpage

hwpe_stream_split
-----------------

.. _hwpe_stream_split:
.. svprettyplot:: ../rtl/basic/hwpe_stream_split.sv

.. raw:: latex

    \clearpage

hwpe_stream_fence
-----------------

.. _hwpe_stream_fence:
.. svprettyplot:: ../rtl/basic/hwpe_stream_fence.sv

.. raw:: latex

    \clearpage

hwpe_stream_mux_static
----------------------

.. _hwpe_stream_mux_static:
.. svprettyplot:: ../rtl/basic/hwpe_stream_mux_static.sv

.. raw:: latex

    \clearpage

hwpe_stream_demux_static
------------------------

.. _hwpe_stream_demux_static:
.. svprettyplot:: ../rtl/basic/hwpe_stream_demux_static.sv

.. raw:: latex

    \clearpage

.. hwpe_stream_buffer
.. ------------------
..
.. .. _hwpe_stream_buffer:
.. .. svprettyplot:: ../rtl/fifo/hwpe_stream_buffer.sv
..
.. .. raw:: latex
..
..     \clearpage

hwpe_stream_fifo
----------------

.. _hwpe_stream_fifo:
.. svprettyplot:: ../rtl/fifo/hwpe_stream_fifo.sv

.. raw:: latex

    \clearpage

hwpe_stream_fifo_earlystall
---------------------------

.. _hwpe_stream_fifo_earlystall:
.. svprettyplot:: ../rtl/fifo/hwpe_stream_fifo_earlystall.sv

.. raw:: latex

    \clearpage

hwpe_stream_fifo_ctrl
---------------------

.. _hwpe_stream_fifo_ctrl:
.. svprettyplot:: ../rtl/fifo/hwpe_stream_fifo_ctrl.sv

.. raw:: latex

    \clearpage

Streamer modules
================

Streamer modules constitute the heart of the IPs use to interface HWPEs
with a PULP system. They include all the modules that are used to
generate HWPE-Streams from address patterns on the TCDM, including the
address generation itself, data realignment to enable access to data located
at non-byte-aligned addresses, strobe generation to selectively disable parts
of a stream, and the main streamer source and sink modules used to put
these functions together.
Modules performing these functions can be found within the `rtl/streamer`
subfolder of the `hwpe-stream` repository.

.. raw:: latex

    \clearpage

hwpe_stream_addressgen
----------------------

.. _hwpe_stream_addressgen:
.. svprettyplot:: ../rtl/streamer/hwpe_stream_addressgen.sv

.. raw:: latex

    \clearpage

.. Source realigner
.. ----------------

.. .. .. _hwpe_stream_source_realign:
.. .. .. svprettyplot:: ../rtl/basic/hwpe_stream_source_realign.sv

.. ..   **hwpe_stream_source_realign** module.

.. The **hwpe_stream_source_realign** module is used to transform a strobed
.. (misaligned) stream of size DATA_WIDTH into a realigned stream of the
.. same size, taking as input a strobe generated from an address generator
.. (see below).

.. The module does not work for generic strobes, but rather it assumes that
.. strobes result in a *rotation*, which is what happens for streams
.. generated from a batch of misaligned transfers.

.. Sink realigner
.. ~~~~~~~~~~~~~~~

.. .. .. _hwpe_stream_sink_realign:
.. .. .. svprettyplot:: ../rtl/basic/hwpe_stream_sink_realign.sv

.. ..   **hwpe_stream_sink_realign** module.

.. The **hwpe_stream_sink_realign** module is used to transform a stream of
.. size DATA_WIDTH into a realigned strobed stream of the same size, taking
.. as input a strobe generated from an address generator (see below).

.. The module does not work for generic strobes, but rather it assumes that
.. strobes result in a *rotation*, which is what happens for streams used
.. to generate from a batch of misaligned transfers.

.. TCDM / HWPE-Stream interface modules
.. ------------------------------------

.. At the interface between the TCDM and HWPE-Stream modules, the main
.. necessity is to generate an address for the streams. They also reside in
.. the *hwpe-stream* repository.

.. Address generator
.. ~~~~~~~~~~~~~~~~~

.. .. .. _hwpe_stream_source_realign:
.. .. .. svprettyplot:: ../rtl/basic/hwpe_stream_source_realign.sv

.. ..   **hwpe_stream_source_realign** module.

.. The **hwpe_stream_addressgen** module is used to generate addresses to
.. load or store HWPE-Stream streams. The REALIGN_TYPE parameter is used to
.. generate appropriate strobes to realign the streams in the sink and
.. source cases.

.. The address generator can be used to generate address from a
.. three-dimensional space of “words”, “lines” and “features”. Lines and
.. features can be separated by a certain stride, and a roll parameter can
.. be used to reuse the same offsets multiple times.

.. While useful in accelerators (e.g. in the HWCE [1][2][5]) the multiple
.. loops are essentially supersed by the functionality provided by the
.. microcode processor that can be embedded in HWPEs. The usage of more
.. than a single loop is discouraged, i.e. the HWPE designer should
.. statically set line_stride=0, feat_length=1, feat_stride=0.

.. Source
.. ~~~~~~~

.. The **hwpe_stream_source** puts together an address generator, a stream
.. merger, and a source realigner to create an interface between
.. NB_TCDM_PORTS memory ports using the TCDM protocol (for loads alone) and
.. a stream of size DATA_WIDTH=NB_TCDM_PORTS*32.

.. Typically it is sufficient to instantiate directly this module instead
.. of the address generator, stream merger and source realigner alone.

.. Sink
.. ~~~~~

.. The **hwpe_stream_sink** puts together an address generator, a stream
.. splitter, and a sink realigner to create an interface between a stream
.. of size DATA_WIDTH=NB_TCDM_PORTS*32 and NB_TCDM_PORTS memory ports using
.. the TCDM protocol (for store alone).

.. Typically it is sufficient to instantiate directly this module instead
.. of the address generator, stream merger and sink realigner alone.

.. TCDM management modules
.. -----------------------

.. Modules to manage TCDM streams with address also reside within the
.. *hwpe-stream* repository.

.. TCDM FIFO (loads)
.. ~~~~~~~~~~~~~~~~~~

.. The **hwpe_stream_tcdm_fifo_load** module can be used to decouple loads
.. with two FIFOs (one for requests, one for responses). It is currently
.. not fully tested.

.. TCDM FIFO (stores)
.. ~~~~~~~~~~~~~~~~~~~

.. The **hwpe_stream_tcdm_fifo_store** module can be used to decouple
.. stores with a FIFO (for requests). It is currently not fully tested.

.. TCDM dynamic multiplexer
.. ~~~~~~~~~~~~~~~~~~~~~~~~

.. .. _hwpe_stream_tcdm_mux:
.. .. svprettyplot:: ../rtl/tcdm/hwpe_stream_tcdm_mux.sv

..   **hwpe_stream_tcdm_mux** module.

.. The **hwpe_stream_tcdm_mux** module can be used to dynamically share
.. NB_IN_CHAN channels using the TCDM protocol into NB_OUT_CHAN channels,
.. with NB_OUT_CHAN < NB_IN_CHAN. The multiplexer is not “optimal” in the
.. sense that there is no reorder buffer, so transactions cannot be swapped
.. in-flight. In practice this limitation is compensated by the fact that
.. the cost of the reorder buffer is saved, and it works well in practice
.. in the Fulmine HWCE [1].

.. TCDM static multiplexer
.. ~~~~~~~~~~~~~~~~~~~~~~~

.. The **hwpe_stream_tcdm_mux_static** module is used to statically share
.. NB_CHAN ports using the TCDM protocol between two sets of NB_CHAN input
.. ports. It works similarly to the **hwpe_stream_mux_static** and
.. similarly requires a strictly static selector.

.. TCDM reorder block
.. ~~~~~~~~~~~~~~~~~~

.. The **hwpe_stream_tcdm_reorder** module is used to shuffle the order of
.. NB_CHAN channels using the TCDM protocol according to an external order,
.. that can be changed arbitrarily (e.g. with a counter). This is useful in
.. some cases (e.g. [1]) so that the probability of a transaction is
.. equalized between multiple ports.

.. PERIPH and controller modules
.. -----------------------------

.. The control interface of HWPEs exposes a PERIPH interface that is used
.. to program a memory-mapped register file. The *hwpe-ctrl* repository
.. contains several IPs that can be used to compose the control interface;
.. apart from the PERIPH interface, these modules are optional – and the
.. main control finite-state machines are accelerator-specific and have to
.. be designed from scratch in any case.

.. Microcode processor
.. ~~~~~~~~~~~~~~~~~~~

.. The **hwpe_ctrl_ucode** module is a microcode processor that can be used
.. to execute the main computation block of an HWPE (implemented within the
.. “engine”) multiple times according to several rules, at the same time
.. adapting the value of several internal parameters. The microcode
.. processor can be used to execute a default number of 6 nested loops.

.. The microcode supports four R/W registers and twelve R/O registers (by
.. default); the microcode has two instructions: an **add** operation and a
.. **move** operation. The **add** operation performs RA := RA + RB; the
.. **move** operation performs RA := RB. R/O registers can only be used as
.. RB. The R/W registers can be used to generate offsets to program the
.. address generators, or for other purposes.

.. The microcode can be specified in a “high-level” fashion in terms of
.. YAML description, which can then be “compiled” by the *ucode_compile.py*
.. Python script, also within the *hwpe-ctrl* repository. The compiler
.. provides the two bit fields to be used to program the HWPE microcode
.. processor, typically this is either hardwired or passed through
.. job-independent registers.

.. Slave interface and register file
.. ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. The **hwpe_ctrl_slave** module implements the PERIPH slave interface.
.. The **hwpe_ctrl_regfile**, which is instantiated inside it, implements
.. the actual register file. The register file contains N_GENERIC_REGS
.. registers which are non-contexted, i.e. their value stays constant
.. between consecutive job offloads; and N_IO_REGS registers which are
.. contexted, i.e. which are used to implement a queue of jobs that can be
.. offloaded also when the HWPE is active. The slave module also generates
.. the events that are propagated in the PULP platform.

.. Sequential multiplier
.. ~~~~~~~~~~~~~~~~~~~~~

.. The **hwpe_ctrl_seq_mult** module is a utility module to implement a
.. sequential multiplier; it can be used to produce derivative parameters
.. e.g. for usage as read-only registers in the microcode processor. When
.. the *start* input is asserted, the multiplier will start compute the
.. product of the two inputs *a* and *b*. The sequential multiplier takes
.. *width(a)* cycles to compute the output and asserts a valid bit when the
.. product has been computed.
