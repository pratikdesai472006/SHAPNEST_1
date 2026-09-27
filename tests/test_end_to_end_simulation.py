#!/usr/bin/env python3
"""
===============================================================================
SHAPNEST PHASE 1 — END-TO-END SIMULATION & INTEGRATION TEST SUITE
===============================================================================
Tests all protocol structures, signal filtering mathematics, log-distance calculations,
boundary clamping, binary serialization/deserialization, Central Hub NDJSON generation,
and Web Application presentation conversions.
===============================================================================
"""

import struct
import math
import json
import unittest

# Protocol Constants
SHAPNEST_PROTOCOL_ID = 0x534E
SHAPNEST_PROTOCOL_VERSION = 0x01
SHAPNEST_FRAME_TYPE_NODE_BEACON = 0x01
SHAPNEST_FRAME_TYPE_WRISTBAND_TEL = 0x02
SHAPNEST_DEFAULT_REF_RSSI_1M = -59
SHAPNEST_DEFAULT_PATH_LOSS_EXP_X10 = 22  # n = 2.2
SHAPNEST_DISTANCE_MIN_CM = 15            # 0.15 m floor
SHAPNEST_DISTANCE_MAX_CM = 800           # 8.00 m ceiling
SHAPNEST_DISTANCE_OFFLINE_CM = 0xFFFF    # 65535 sentinel
SHAPNEST_RSSI_OFFLINE = -128             # Sentinel

STATE_ACTIVE = 0
STATE_STALE = 1
STATE_OFFLINE = 2

def pack_id_state(node_id: int, state: int) -> int:
    return (node_id & 0x0F) | ((state & 0x03) << 4)

def unpack_id(packed: int) -> int:
    return packed & 0x0F

def unpack_state(packed: int) -> int:
    return (packed >> 4) & 0x03

def calculate_log_distance(rssi: float, a: float = -59.0, n: float = 2.2) -> float:
    """Computes physical distance in meters using Log-Distance model."""
    if rssi >= 0:
        return 0.15
    ratio = (a - rssi) / (10.0 * n)
    raw_dist = math.pow(10.0, ratio)
    return raw_dist

def clamp_distance_cm(dist_m: float) -> int:
    """Clamps distance to 15 cm floor and 800 cm ceiling."""
    if dist_m < 0:
        return SHAPNEST_DISTANCE_OFFLINE_CM
    cm = round(dist_m * 100.0)
    if cm < SHAPNEST_DISTANCE_MIN_CM:
        return SHAPNEST_DISTANCE_MIN_CM
    if cm > SHAPNEST_DISTANCE_MAX_CM:
        return SHAPNEST_DISTANCE_MAX_CM
    return int(cm)

class SignalFilterPipeline:
    """Simulates the wristband's 5-sample median filter + EMA smoothing."""
    def __init__(self, alpha: float = 0.25):
        self.alpha = alpha
        self.buffer = []
        self.ema_rssi = None

    def add_sample(self, rssi: float):
        self.buffer.append(rssi)
        if len(self.buffer) > 5:
            self.buffer.pop(0)

    def compute(self) -> float:
        if not self.buffer:
            return -128.0
        # Stage 1: Median
        sorted_buf = sorted(self.buffer)
        median_val = sorted_buf[len(sorted_buf) // 2]
        
        # Stage 2: EMA
        if self.ema_rssi is None:
            self.ema_rssi = median_val
        else:
            self.ema_rssi = self.alpha * median_val + (1.0 - self.alpha) * self.ema_rssi
        return self.ema_rssi


class TestProtocolSerialization(unittest.TestCase):
    """Verifies strict byte packing and lengths of all binary frames."""

    def test_node_beacon_packet_layout(self):
        """Node packet must be exactly 12 bytes."""
        # Struct format: < (Little-Endian)
        # B: flags_len (0x02)
        # B: flags_type (0x01)
        # B: flags_data (0x06)
        # B: mfr_len (0x08)
        # B: mfr_type (0xFF)
        # H: company_id (0x534E)
        # B: frame_type (0x01)
        # B: node_id (1)
        # b: cal_rssi (-59)
        # B: exp_x10 (22)
        # B: seq (10)
        fmt = "<BBB BB H B B b B B"
        pkt = struct.pack(fmt,
                          0x02, 0x01, 0x06,
                          0x08, 0xFF,
                          SHAPNEST_PROTOCOL_ID,
                          SHAPNEST_FRAME_TYPE_NODE_BEACON,
                          1, -59, 22, 10)
        self.assertEqual(len(pkt), 12, "Node beacon packet must be exactly 12 bytes")
        
        # Unpack and verify fields
        unpacked = struct.unpack(fmt, pkt)
        self.assertEqual(unpacked[5], 0x534E)  # Company ID
        self.assertEqual(unpacked[6], 0x01)    # Node Beacon frame type
        self.assertEqual(unpacked[7], 1)       # Node ID
        self.assertEqual(unpacked[8], -59)     # Calibrated RSSI
        self.assertEqual(unpacked[9], 22)      # Path Loss Exp x10

    def test_wristband_telemetry_packet_layout(self):
        """Wristband telemetry packet must be exactly 31 bytes (Legacy BLE PDU limit)."""
        # Header: Flags (3B), MFR AD (2B: len 0x1B, type 0xFF), Company ID (2B: 0x534E),
        #         Frame Type (1B: 0x02), Wristband ID (1B: 1), Seq (1B), Count (1B: 5)
        # Nodes: 5 x (id_state: 1B, dist_cm: 2B, rssi: 1B) = 20B
        # Total: 3 + 2 + 2 + 1 + 1 + 1 + 1 + 20 = 31 Bytes
        header_fmt = "<BBB BB H B B B B"
        node_block_fmt = "<B H b"  # 4 bytes
        
        header = struct.pack(header_fmt,
                             0x02, 0x01, 0x06,
                             0x1B, 0xFF,
                             SHAPNEST_PROTOCOL_ID,
                             SHAPNEST_FRAME_TYPE_WRISTBAND_TEL,
                             1,  # Wristband ID
                             42, # Sequence
                             5   # Node count
                             )
        self.assertEqual(len(header), 11)
        
        # Pack 5 node blocks
        blocks = b""
        test_nodes = [
            (1, STATE_ACTIVE, 82, -57),
            (2, STATE_ACTIVE, 145, -63),
            (3, STATE_STALE, 280, -69),
            (4, STATE_ACTIVE, 800, -85),
            (5, STATE_OFFLINE, SHAPNEST_DISTANCE_OFFLINE_CM, SHAPNEST_RSSI_OFFLINE)
        ]
        for node_id, state, dist_cm, rssi in test_nodes:
            id_state_byte = pack_id_state(node_id, state)
            block = struct.pack(node_block_fmt, id_state_byte, dist_cm, rssi)
            self.assertEqual(len(block), 4)
            blocks += block
            
        full_packet = header + blocks
        self.assertEqual(len(full_packet), 31, "Wristband packet must be exactly 31 bytes")

    def test_id_and_state_bitfield_packing(self):
        """Test packing and unpacking of Node ID (0..15) and State (0..3)."""
        for nid in range(1, 6):
            for state in [STATE_ACTIVE, STATE_STALE, STATE_OFFLINE]:
                packed = pack_id_state(nid, state)
                self.assertEqual(unpack_id(packed), nid)
                self.assertEqual(unpack_state(packed), state)


class TestFilteringAndMath(unittest.TestCase):
    """Verifies median filter, EMA smoothing, log-distance formula, and clamping."""

    def test_median_filter_impulse_rejection(self):
        """Rolling median must completely discard isolated multipath spikes."""
        filt = SignalFilterPipeline(alpha=0.25)
        # Normal sequence with an extreme -95 dBm multipath dropout
        measurements = [-60, -61, -95, -60, -59]
        for m in measurements:
            filt.add_sample(m)
        
        # Sorted: [-95, -61, -60, -60, -59] -> Median is -60
        sorted_m = sorted(measurements)
        self.assertEqual(sorted_m[2], -60)
        
        # Output should be close to -60, not pulled down by -95
        output = filt.compute()
        self.assertAlmostEqual(output, -60.0, places=1)

    def test_ema_smoothing_convergence(self):
        """EMA should smoothly track a step change with alpha=0.25."""
        filt = SignalFilterPipeline(alpha=0.25)
        # Start at -60 dBm
        for _ in range(5):
            filt.add_sample(-60)
        filt.compute()
        self.assertAlmostEqual(filt.ema_rssi, -60.0)
        
        # Step to -70 dBm
        filt.buffer = []
        for _ in range(5):
            filt.add_sample(-70)
        
        step1 = filt.compute()
        # 0.25 * (-70) + 0.75 * (-60) = -17.5 - 45 = -62.5
        self.assertAlmostEqual(step1, -62.5, places=2)

    def test_log_distance_calculation(self):
        """Verifies distance formula at reference, closer, and farther points."""
        a = -59.0
        n = 2.2
        # At reference RSSI (-59 dBm) distance must be exactly 1.00 m
        d1 = calculate_log_distance(-59.0, a, n)
        self.assertAlmostEqual(d1, 1.00, places=2)
        
        # At -68 dBm: d = 10^(( -59 - (-68) ) / 22) = 10^(9/22) = 10^0.4091 = 2.565 m
        d2 = calculate_log_distance(-68.0, a, n)
        self.assertAlmostEqual(d2, 2.565, places=2)

    def test_operational_bounds_clamping(self):
        """Verifies clamping to 0.15 m floor, 8.00 m ceiling, and sentinels."""
        # Near-field saturation: RSSI = -35 dBm -> calculated d ~ 0.08 m -> clamped to 15 cm
        d_close = calculate_log_distance(-35.0)
        self.assertLess(d_close, 0.15)
        self.assertEqual(clamp_distance_cm(d_close), SHAPNEST_DISTANCE_MIN_CM)
        
        # Far-field noise: RSSI = -85 dBm -> calculated d ~ 15.1 m -> clamped to 800 cm
        d_far = calculate_log_distance(-85.0)
        self.assertGreater(d_far, 8.00)
        self.assertEqual(clamp_distance_cm(d_far), SHAPNEST_DISTANCE_MAX_CM)
        
        # Normal distance: 1.45 m -> 145 cm
        self.assertEqual(clamp_distance_cm(1.45), 145)
        
        # Offline sentinel
        self.assertEqual(clamp_distance_cm(-1.0), SHAPNEST_DISTANCE_OFFLINE_CM)


class TestCentralHubNDJSONIntegration(unittest.TestCase):
    """Simulates Hub receiving 31-byte binary packet and generating NDJSON for Web App."""

    def test_end_to_end_packet_to_ndjson(self):
        """Simulates full RX -> Unpack -> NDJSON Serialization pipeline."""
        # 1. Assemble 31-byte raw BLE packet
        header = struct.pack("<BBB BB H B B B B",
                             0x02, 0x01, 0x06,
                             0x1B, 0xFF,
                             SHAPNEST_PROTOCOL_ID,
                             SHAPNEST_FRAME_TYPE_WRISTBAND_TEL,
                             1,  # Wristband 1
                             105, # Sequence 105
                             5)  # 5 nodes
        
        node_data = [
            {"id": 1, "state": STATE_ACTIVE, "dist_cm": 82,  "rssi": -57},
            {"id": 2, "state": STATE_ACTIVE, "dist_cm": 145, "rssi": -63},
            {"id": 3, "state": STATE_STALE,  "dist_cm": 280, "rssi": -69},
            {"id": 4, "state": STATE_ACTIVE, "dist_cm": 800, "rssi": -85},  # > 8.0m
            {"id": 5, "state": STATE_OFFLINE,"dist_cm": 65535, "rssi": -128}
        ]
        
        payload = b""
        for nd in node_data:
            id_st = pack_id_state(nd["id"], nd["state"])
            payload += struct.pack("<B H b", id_st, nd["dist_cm"], nd["rssi"])
            
        raw_ble_packet = header + payload
        self.assertEqual(len(raw_ble_packet), 31)
        
        # 2. Simulate Central Hub Core 0 parsing
        # Validate Magic and Type
        co_id = struct.unpack_from("<H", raw_ble_packet, 5)[0]
        ftype = raw_ble_packet[7]
        self.assertEqual(co_id, 0x534E)
        self.assertEqual(ftype, 0x02)
        
        wb_id = raw_ble_packet[8]
        seq = raw_ble_packet[9]
        node_cnt = raw_ble_packet[10]
        self.assertEqual(wb_id, 1)
        self.assertEqual(seq, 105)
        self.assertEqual(node_cnt, 5)
        
        # 3. Simulate Central Hub Core 1 NDJSON Formatting
        nodes_json_list = []
        for i in range(5):
            offset = 11 + i * 4
            id_st_b, dist_cm_u16, rssi_i8 = struct.unpack_from("<B H b", raw_ble_packet, offset)
            n_id = unpack_id(id_st_b)
            n_st_code = unpack_state(id_st_b)
            
            st_str = "ACTIVE" if n_st_code == 0 else ("STALE" if n_st_code == 1 else "OFFLINE")
            if n_st_code != STATE_OFFLINE and dist_cm_u16 >= SHAPNEST_DISTANCE_MAX_CM:
                st_str = "OUT_OF_RANGE"
                
            dist_val = None if n_st_code == STATE_OFFLINE else round(dist_cm_u16 / 100.0, 2)
            nodes_json_list.append({
                "node_id": n_id,
                "distance": dist_val,
                "distance_cm": dist_cm_u16,
                "rssi": rssi_i8,
                "state": st_str
            })
            
        ndjson_obj = {
            "type": "telemetry",
            "wristband_id": wb_id,
            "sequence": seq,
            "hub_uptime_s": 342,
            "wristband_freshness": "ONLINE",
            "nodes": nodes_json_list
        }
        
        ndjson_line = json.dumps(ndjson_obj)
        self.assertTrue(ndjson_line.startswith('{"type": "telemetry"'))
        
        # 4. Simulate Web App JSON.parse() and Validation
        parsed_app_obj = json.loads(ndjson_line)
        self.assertEqual(parsed_app_obj["wristband_id"], 1)
        self.assertEqual(len(parsed_app_obj["nodes"]), 5)
        
        # Node 1: 0.82 m / 82 cm
        self.assertEqual(parsed_app_obj["nodes"][0]["distance"], 0.82)
        self.assertEqual(parsed_app_obj["nodes"][0]["state"], "ACTIVE")
        
        # Node 3: STALE
        self.assertEqual(parsed_app_obj["nodes"][2]["state"], "STALE")
        
        # Node 4: OUT_OF_RANGE (> 8.0m)
        self.assertEqual(parsed_app_obj["nodes"][3]["state"], "OUT_OF_RANGE")
        self.assertEqual(parsed_app_obj["nodes"][3]["distance_cm"], 800)
        
        # Node 5: OFFLINE
        self.assertIsNone(parsed_app_obj["nodes"][4]["distance"])
        self.assertEqual(parsed_app_obj["nodes"][4]["state"], "OFFLINE")

    def test_dynamic_unit_conversion_display_logic(self):
        """Verifies that unit toggle 'm' <-> 'cm' converts display strings correctly without mutating data."""
        def format_distance(dist_m: float, dist_cm: int, state: str, unit: str) -> str:
            if state == "OFFLINE" or dist_m is None:
                return "--"
            if state == "OUT_OF_RANGE" or dist_cm >= 800:
                return "> 8.0 m" if unit == "m" else "> 800 cm"
            if unit == "cm":
                return f"{dist_cm} cm"
            return f"{dist_m:.2f} m"

        # Active node at 0.82m / 82cm
        self.assertEqual(format_distance(0.82, 82, "ACTIVE", "m"), "0.82 m")
        self.assertEqual(format_distance(0.82, 82, "ACTIVE", "cm"), "82 cm")

        # Active node at 1.45m / 145cm
        self.assertEqual(format_distance(1.45, 145, "ACTIVE", "m"), "1.45 m")
        self.assertEqual(format_distance(1.45, 145, "ACTIVE", "cm"), "145 cm")

        # Out-of-range node
        self.assertEqual(format_distance(8.00, 800, "OUT_OF_RANGE", "m"), "> 8.0 m")
        self.assertEqual(format_distance(8.00, 800, "OUT_OF_RANGE", "cm"), "> 800 cm")

        # Offline node
        self.assertEqual(format_distance(None, 65535, "OFFLINE", "m"), "--")
        self.assertEqual(format_distance(None, 65535, "OFFLINE", "cm"), "--")


if __name__ == "__main__":
    print("\n" + "=" * 70)
    print("RUNNING SHAPNEST PHASE 1 AUTOMATED INTEGRATION & SIMULATION SUITE")
    print("=" * 70 + "\n")
    unittest.main(verbosity=2)
