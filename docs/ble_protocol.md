# SHAPNEST — BLE Protocol & Data Flow Specification (Phase 1)

**Component:** Wireless Packet Wire-Formats, Bitfields & NDJSON Streaming Schema  
**Scope:** Phase 1 Multi-Node Distance Measurement & Central Hub Prototype  
**Author:** AI Pair Programmer & Embedded Systems Architect  
**Status:** Approved & Implemented  

---

## 1. Protocol Overview

The SHAPNEST Phase 1 protocol defines all over-the-air (OTA) and wired communication interfaces between the three physical hardware tiers:
1. **Nodes 1–5 $\rightarrow$ Child Wristband:** Autonomous non-connectable BLE beacons (12 Bytes).
2. **Child Wristband $\rightarrow$ Central Hub:** High-density packed BLE telemetry uplink (31 Bytes).
3. **Central Hub $\rightarrow$ Web Display App:** Streaming Newline-Delimited JSON (NDJSON) over USB-UART (115,200 baud).

```
[Node 1..5] --(12B BLE Beacon @ 5 Hz)--> [Child Wristband]
                                                 |
                             (31B Packed BLE Telemetry @ 1 Hz)
                                                 v
                                        [Central Hub]
                                                 |
                                (NDJSON over USB Serial @ 115200)
                                                 v
                                    [Web Display Application]
```

All binary protocol structures are strictly byte-packed using `#pragma pack(push, 1)` and use **Little-Endian byte order** for 16-bit fields (`uint16_t`), guaranteeing binary compatibility between 32-bit RISC-V (ESP32-C3) and Xtensa LX6 (ESP32-WROOM-32) architectures.

---

## 2. Node Beacon Wire Format (12 Bytes Total)

Nodes broadcast as non-connectable undirected advertisements (`ADV_NONCONN_IND`) every $200\text{ ms}$ at $+3\text{ dBm}$ TX power.

### 2.1 Packet Layout

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|  Flags Len    |  Flags Type   |  Flags Data   |  Mfr Len      |
|    (0x02)     |  (0x01:Flags) |    (0x06)     |    (0x08)     |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|  Mfr Type     |        Company ID (0x534E)    |  Frame Type   |
| (0xFF:MfrSpec)|  0x4E ('N')   |  0x53 ('S')   |  (0x01:Node)  |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|   Node ID     | Calibrated 1m | Path Loss Exp | Sequence Num  |
|   (1 to 5)    |  (-59 dBm)    |   x10 (22)    |  (0 to 255)   |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

### 2.2 Field Definitions

| Byte Offset | Field Name | Type | Value / Range | Description |
| :---: | :--- | :---: | :---: | :--- |
| **0** | `flags_length` | `uint8_t` | `0x02` | Length of BLE Flags AD structure. |
| **1** | `flags_type` | `uint8_t` | `0x01` | AD Type 0x01: Flags. |
| **2** | `flags_data` | `uint8_t` | `0x06` | LE General Discoverable (`0x02`) \| BR/EDR Not Supported (`0x04`). |
| **3** | `mfr_length` | `uint8_t` | `0x08` | 8 bytes follow (AD Type + 7 bytes payload). |
| **4** | `mfr_type` | `uint8_t` | `0xFF` | AD Type 0xFF: Manufacturer Specific Data. |
| **5–6** | `company_id` | `uint16_t` | `0x534E` | SHAPNEST Magic Identifier (`0x4E, 0x53` in Little-Endian). |
| **7** | `frame_type` | `uint8_t` | `0x01` | `SHAPNEST_FRAME_TYPE_NODE_BEACON`. |
| **8** | `node_id` | `uint8_t` | `1 .. 5` | Unique spatial anchor index. |
| **9** | `calibrated_rssi_1m` | `int8_t` | `-128 .. +127` | Calibrated reference RSSI at 1m (default: `-59` dBm). |
| **10** | `path_loss_exp_x10`| `uint8_t` | `10 .. 50` | Path loss exponent $n \times 10$ (default: `22` representing $n = 2.2$). |
| **11** | `sequence` | `uint8_t` | `0 .. 255` | Static boot sequence (Approach B: pure autonomous beaconing). |

Total size: **12 Bytes** (Leaves 19 bytes headroom in standard 31-byte legacy BLE PDU).

---

## 3. Wristband Telemetry Frame (31 Bytes Total)

The wristband packages filtered distance and RSSI for all 5 nodes into a single **maximum-density 31-byte Legacy BLE Advertisement**, completely saturating the standard PDU without requiring BLE 5.0 Extended Advertising.

### 3.1 Packet Layout

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|  Flags Len    |  Flags Type   |  Flags Data   |  Mfr Len      |
|    (0x02)     |  (0x01:Flags) |    (0x06)     |    (0x1B)     |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|  Mfr Type     |        Company ID (0x534E)    |  Frame Type   |
| (0xFF:MfrSpec)|  0x4E ('N')   |  0x53 ('S')   | (0x02:WbTel)  |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
| Wristband ID  | Sequence Num  |  Node Count   |               |
|     (0x01)    |   (0..255)    |    (0x05)     |               |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+               |
|                                                               |
|        Node 1 Telemetry Block (4 Bytes: Offset 11..14)        |
|        [Byte 0: ID+State | Bytes 1..2: Dist_cm | Byte 3: RSSI]|
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|        Node 2 Telemetry Block (4 Bytes: Offset 15..18)        |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|        Node 3 Telemetry Block (4 Bytes: Offset 19..22)        |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|        Node 4 Telemetry Block (4 Bytes: Offset 23..26)        |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|        Node 5 Telemetry Block (4 Bytes: Offset 27..30)        |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

### 3.2 4-Byte Per-Node Telemetry Block Anatomy

Each node block occupies exactly 4 bytes (`shapnest_node_telemetry_block_t`):

```
Byte 0: ID & State (8 bits)
+---+---+---+---+---+---+---+---+
| R | R | State |    Node ID    |
+---+---+---+---+---+---+---+---+
  7   6   5   4   3   2   1   0

- Bits 0..3: Node ID (1 to 5)
- Bits 4..5: Freshness State:
    0b00 (0): ACTIVE  (< 1200 ms)
    0b01 (1): STALE   (1200 to 3500 ms)
    0b10 (2): OFFLINE (> 3500 ms)
- Bits 6..7: Reserved (0)

Bytes 1..2: Distance in Centimeters (16-bit Unsigned Integer, Little-Endian)
- 15 to 800: Valid physical distance (0.15 m to 8.00 m)
- 0xFFFF: Sentinel value for OFFLINE (65535)

Byte 3: Filtered RSSI (8-bit Signed Integer)
- -127 to +127: Filtered smoothed RSSI in dBm
- -128 (0x80): Sentinel value for OFFLINE
```

---

## 4. Central Hub $\rightarrow$ Web App NDJSON Serial Specification

The Central Hub streams one **Newline-Delimited JSON (NDJSON)** string per second over USB Serial at **115,200 baud, 8-N-1**.

### 4.1 Schema Definition

```json
{
  "type": "telemetry",
  "wristband_id": 1,
  "sequence": 42,
  "hub_uptime_s": 128,
  "wristband_freshness": "ONLINE",
  "nodes": [
    {
      "node_id": 1,
      "distance": 0.82,
      "distance_cm": 82,
      "rssi": -57,
      "state": "ACTIVE"
    },
    {
      "node_id": 2,
      "distance": 1.45,
      "distance_cm": 145,
      "rssi": -63,
      "state": "ACTIVE"
    },
    {
      "node_id": 3,
      "distance": 2.10,
      "distance_cm": 210,
      "rssi": -67,
      "state": "STALE"
    },
    {
      "node_id": 4,
      "distance": 8.00,
      "distance_cm": 800,
      "rssi": -85,
      "state": "OUT_OF_RANGE"
    },
    {
      "node_id": 5,
      "distance": null,
      "distance_cm": 65535,
      "rssi": -128,
      "state": "OFFLINE"
    }
  ]
}
```

### 4.2 Diagnostic Logs (`# [LOG]` Protocol)

Human-readable diagnostic messages from the Hub (such as scan statistics, buffer overflow warnings, or hardware boots) are prefixed with `# [LOG]`. The Web App serial parser filters these lines into the Collapsible Diagnostic Console without causing JSON parse exceptions:

```
# [LOG] SHAPNEST Central Hub Booting... Free Heap: 298412 bytes
# [LOG] BLE Scanning active on Core 0. UART bridge on Core 1.
# [LOG] Uplink packet received from Wristband 1 (Seq: 43, RSSI: -48 dBm)
```

---

## 5. End-to-End System Timing Diagram

```
Node 1..5          Child Wristband              Central Hub              Web Display App
   |                      |                          |                          |
   |-- ADV (200ms) ------>|                          |                          |
   |-- ADV (200ms) ------>| (900ms Scan Window)      |                          |
   |-- ADV (200ms) ------>|                          |                          |
   |                      |                          |                          |
   |                      |-- [10ms Math Gap]        |                          |
   |                      |   Sort Median Ring       |                          |
   |                      |   Calculate EMA & Dist   |                          |
   |                      |   Pack 31B PDU           |                          |
   |                      |                          |                          |
   |                      |=== 3-Pulse Burst (90ms)==|                          |
   |                      |---- Tel Pkt (Seq 42) --->| (Core 0 RX Callback)     |
   |                      |---- Tel Pkt (Seq 42) --->|                          |
   |                      |---- Tel Pkt (Seq 42) --->| (Unpack & Validate)      |
   |                      |                          |                          |
   |                      |                          |-- Serial NDJSON -------->|
   |                      |                          |   (115,200 baud)         |-- Render Cards
   |                      |                          |                          |-- Update Gauges
   |                      |                          |                          |-- Plot Signals
```

---

## 6. Sentinel Values & Edge-Case Truth Table

| State / Condition | `id_and_state` (Bits 4..5) | `distance_cm` (Wire) | `distance` (NDJSON) | `rssi` (Wire / JSON) | UI Representation |
| :--- | :---: | :---: | :---: | :---: | :--- |
| **Normal Active** | `0b00` (`ACTIVE`) | $15 \le d \le 800$ | $0.15 \le d \le 8.00$ | $-127 \le r \le 0$ | Green pill, distance readout, active progress bar. |
| **Near-Field Clamped**| `0b00` (`ACTIVE`) | $15$ | $0.15$ | $>-35$ dBm | Green pill, shows `0.15 m` (`15 cm`) (floor). |
| **Far-Field / Out of Range**| `0b00` (`ACTIVE`) | $800$ | $8.00$ | $-85$ to $-92$ dBm | Amber pill, displays `> 8.0 m` (`> 800 cm`). |
| **Stale (Packet Miss)**| `0b01` (`STALE`) | Last valid cm | Last valid meters | Last valid RSSI | Yellow pill, displays last known values. |
| **Node Offline** | `0b10` (`OFFLINE`)| `0xFFFF` (`65535`)| `null` | `-128` dBm | Gray pill, displays `OFFLINE`, bar empty. |
| **Wristband Lost**| N/A | N/A | `null` for all nodes | N/A | Header alert: `WRISTBAND OFFLINE`, all 5 nodes gray. |
