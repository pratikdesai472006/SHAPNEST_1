#!/usr/bin/env python3
"""
===============================================================================
SHAPNEST PHASE 1 — END-TO-END SIMULATION & INTEGRATION TEST SUITE
===============================================================================
Tests all protocol structures, signal filtering mathematics, log-distance calculations,
boundary clamping, binary serialization/deserialization, Central Hub NDJSON generation,
and Web Application presentation conversions.
Includes comprehensive tests for:
- Fresh scan-window sampling and stale sample isolation
- RSSI sanity bounds (-95 dBm to -20 dBm)
- In-window impulse outlier rejection
- Adaptive EMA filter (fast alpha=0.60 vs slow alpha=0.25)
- EMA clean initialization
- Stale and Offline state machine progression
- Per-node independent calibration constants (A and n)
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
    """Simulates the legacy wristband's 5-sample median filter + EMA smoothing."""
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


class AdvancedSignalFilterPipeline:
    """Accurately simulates the updated wristband firmware signal conditioning pipeline."""
    def __init__(self, alpha_fast=0.60, alpha_slow=0.25, step_thresh=4.0,
                 sanity_min=-95, sanity_max=-20, impulse_thresh=15,
                 refA=-59, expN=2.2):
        self.alpha_fast = alpha_fast
        self.alpha_slow = alpha_slow
        self.step_thresh = step_thresh
        self.sanity_min = sanity_min
        self.sanity_max = sanity_max
        self.impulse_thresh = impulse_thresh
        self.refA = float(refA)
        self.expN = float(expN)
        
        self.window_samples = []
        self.ema_rssi = None
        self.last_seen_ms = 0
        self.state = STATE_OFFLINE
        self.distance_cm = SHAPNEST_DISTANCE_OFFLINE_CM
        self.filtered_rssi = SHAPNEST_RSSI_OFFLINE

    def start_window(self):
        """Called at the beginning of each 900ms scan window to isolate fresh samples."""
        self.window_samples = []

    def add_raw_sample(self, rssi: int, now_ms: int) -> bool:
        """Applies physical sanity gate before recording into window buffer."""
        if rssi < self.sanity_min or rssi > self.sanity_max:
            return False
        self.window_samples.append(rssi)
        self.last_seen_ms = now_ms
        return True

    def process_cycle(self, now_ms: int):
        """Processes signal conditioning and distance estimation at the end of the scan."""
        age_ms = (now_ms - self.last_seen_ms) if self.last_seen_ms > 0 else 999999
        
        # Staleness State Machine
        if self.last_seen_ms == 0 or age_ms > 3500:
            self.state = STATE_OFFLINE
            self.distance_cm = SHAPNEST_DISTANCE_OFFLINE_CM
            self.filtered_rssi = SHAPNEST_RSSI_OFFLINE
            self.ema_rssi = None
            return
        elif age_ms >= 1200:
            self.state = STATE_STALE
            # Retain last valid distance; do NOT recalculate from old data
            return
        else:
            self.state = STATE_ACTIVE

        # Only process if fresh samples arrived in this scan window
        if len(self.window_samples) > 0:
            sorted_s = sorted(self.window_samples)
            med = sorted_s[len(sorted_s) // 2]

            # In-window impulse rejection (>= 3 samples)
            if len(sorted_s) >= 3:
                inliers = [s for s in sorted_s if abs(s - med) <= self.impulse_thresh]
                if inliers:
                    med = inliers[len(inliers) // 2]

            # Adaptive EMA Filter
            if self.ema_rssi is None:
                self.ema_rssi = float(med)
            else:
                delta = abs(float(med) - self.ema_rssi)
                alpha = self.alpha_fast if delta > self.step_thresh else self.alpha_slow
                self.ema_rssi = (alpha * float(med)) + ((1.0 - alpha) * self.ema_rssi)

            self.filtered_rssi = round(self.ema_rssi)
            exponent = (self.refA - self.ema_rssi) / (10.0 * self.expN)
            dist_m = math.pow(10.0, exponent)
            self.distance_cm = clamp_distance_cm(dist_m)


class TestProtocolSerialization(unittest.TestCase):
    """Verifies strict byte packing and lengths of all binary frames."""

    def test_node_beacon_packet_layout(self):
        """Node packet must be exactly 12 bytes."""
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
        """Wristband telemetry packet must be exactly 23 bytes (3 nodes, 8 bytes headroom)."""
        header_fmt = "<BBB BB H B B B B"
        node_block_fmt = "<B H b"  # 4 bytes
        
        header = struct.pack(header_fmt,
                             0x02, 0x01, 0x06,
                             0x13, 0xFF,
                             SHAPNEST_PROTOCOL_ID,
                             SHAPNEST_FRAME_TYPE_WRISTBAND_TEL,
                             1,  # Wristband ID
                             42, # Sequence
                             3   # Node count: exactly 3 nodes
                             )
        self.assertEqual(len(header), 11)
        
        blocks = b""
        test_nodes = [
            (1, STATE_ACTIVE, 82, -57),   # Node 1: Fan
            (2, STATE_ACTIVE, 145, -63),  # Node 2: Iron
            (3, STATE_STALE, 280, -69)    # Node 3: Door
        ]
        for node_id, state, dist_cm, rssi in test_nodes:
            id_state_byte = pack_id_state(node_id, state)
            block = struct.pack(node_block_fmt, id_state_byte, dist_cm, rssi)
            self.assertEqual(len(block), 4)
            blocks += block
            
        full_packet = header + blocks
        self.assertEqual(len(full_packet), 23, "Wristband packet must be exactly 23 bytes for 3 nodes")

    def test_id_and_state_bitfield_packing(self):
        """Test packing and unpacking of Node ID (1..3) and State (0..2)."""
        for nid in range(1, 4):
            for state in [STATE_ACTIVE, STATE_STALE, STATE_OFFLINE]:
                packed = pack_id_state(nid, state)
                self.assertEqual(unpack_id(packed), nid)
                self.assertEqual(unpack_state(packed), state)


class TestFilteringAndMath(unittest.TestCase):
    """Verifies median filter, EMA smoothing, log-distance formula, and clamping."""

    def test_median_filter_impulse_rejection(self):
        """Rolling median must completely discard isolated multipath spikes."""
        filt = SignalFilterPipeline(alpha=0.25)
        measurements = [-60, -61, -95, -60, -59]
        for m in measurements:
            filt.add_sample(m)
        
        sorted_m = sorted(measurements)
        self.assertEqual(sorted_m[2], -60)
        output = filt.compute()
        self.assertAlmostEqual(output, -60.0, places=1)

    def test_ema_smoothing_convergence(self):
        """EMA should smoothly track a step change with alpha=0.25."""
        filt = SignalFilterPipeline(alpha=0.25)
        for _ in range(5):
            filt.add_sample(-60)
        filt.compute()
        self.assertAlmostEqual(filt.ema_rssi, -60.0)
        
        filt.buffer = []
        for _ in range(5):
            filt.add_sample(-70)
        
        step1 = filt.compute()
        self.assertAlmostEqual(step1, -62.5, places=2)

    def test_log_distance_calculation(self):
        """Verifies distance formula at reference, closer, and farther points."""
        a = -59.0
        n = 2.2
        d1 = calculate_log_distance(-59.0, a, n)
        self.assertAlmostEqual(d1, 1.00, places=2)
        
        d2 = calculate_log_distance(-68.0, a, n)
        self.assertAlmostEqual(d2, 2.565, places=2)

    def test_operational_bounds_clamping(self):
        """Verifies clamping to 0.15 m floor, 8.00 m ceiling, and sentinels."""
        d_close = calculate_log_distance(-35.0)
        self.assertLess(d_close, 0.15)
        self.assertEqual(clamp_distance_cm(d_close), SHAPNEST_DISTANCE_MIN_CM)
        
        d_far = calculate_log_distance(-85.0)
        self.assertGreater(d_far, 8.00)
        self.assertEqual(clamp_distance_cm(d_far), SHAPNEST_DISTANCE_MAX_CM)
        
        self.assertEqual(clamp_distance_cm(1.45), 145)
        self.assertEqual(clamp_distance_cm(-1.0), SHAPNEST_DISTANCE_OFFLINE_CM)


class TestAdvancedSignalConditioningPipeline(unittest.TestCase):
    """Directly verifies the new distance-accuracy enhancements."""

    def test_sanity_bounds_rejection(self):
        """Raw RSSI outside [-95, -20] dBm must be rejected by the physical sanity gate."""
        pipe = AdvancedSignalFilterPipeline()
        pipe.start_window()
        self.assertFalse(pipe.add_raw_sample(-96, 1000), "Should reject < -95 dBm")
        self.assertFalse(pipe.add_raw_sample(-100, 1000), "Should reject extreme noise")
        self.assertFalse(pipe.add_raw_sample(-15, 1000), "Should reject RF saturation > -20 dBm")
        self.assertFalse(pipe.add_raw_sample(0, 1000), "Should reject non-negative RSSI")
        self.assertTrue(pipe.add_raw_sample(-59, 1000), "Should accept valid -59 dBm")
        self.assertTrue(pipe.add_raw_sample(-25, 1000), "Should accept valid -25 dBm")
        self.assertTrue(pipe.add_raw_sample(-90, 1000), "Should accept valid -90 dBm")

    def test_fresh_scan_window_isolation(self):
        """Previous cycle samples must not leak into new scan windows."""
        pipe = AdvancedSignalFilterPipeline()
        # Window 1: Node at 1.0 m (approx -59 dBm)
        pipe.start_window()
        pipe.add_raw_sample(-59, 1000)
        pipe.add_raw_sample(-60, 1050)
        pipe.add_raw_sample(-58, 1100)
        pipe.process_cycle(1200)
        self.assertEqual(len(pipe.window_samples), 3)
        self.assertEqual(pipe.distance_cm, 100)

        # Window 2: Window starts, buffer must be isolated
        pipe.start_window()
        self.assertEqual(len(pipe.window_samples), 0, "Window buffer must be reset at window start")
        
        # Add 3 samples for 3.0 m (approx -70 dBm)
        pipe.add_raw_sample(-70, 2000)
        pipe.add_raw_sample(-71, 2050)
        pipe.add_raw_sample(-70, 2100)
        pipe.process_cycle(2200)
        self.assertEqual(len(pipe.window_samples), 3)
        # Because samples from Window 1 were cleared, median is -70, not affected by -59
        self.assertLess(pipe.filtered_rssi, -64)

    def test_in_window_impulse_outlier_rejection(self):
        """Multipath null impulse spikes (>15 dBm deviation) must be filtered in-window."""
        pipe = AdvancedSignalFilterPipeline()
        pipe.start_window()
        # 4 clean samples around -60 dBm, 1 severe multipath null at -85 dBm (-25 dBm dev)
        pipe.add_raw_sample(-60, 1000)
        pipe.add_raw_sample(-59, 1050)
        pipe.add_raw_sample(-85, 1100)  # Impulse spike
        pipe.add_raw_sample(-61, 1150)
        pipe.add_raw_sample(-60, 1200)
        pipe.process_cycle(1300)
        # Outlier -85 dBm must be rejected from inliers, median must be -60
        self.assertEqual(pipe.filtered_rssi, -60)
        self.assertEqual(pipe.distance_cm, 111)

    def test_adaptive_ema_fast_tracking_vs_slow_smoothing(self):
        """Verifies fast alpha=0.60 on step change and slow alpha=0.25 when stationary."""
        pipe = AdvancedSignalFilterPipeline()
        # Establish baseline at -60 dBm
        pipe.start_window()
        pipe.add_raw_sample(-60, 1000)
        pipe.process_cycle(1100)
        self.assertEqual(pipe.ema_rssi, -60.0)

        # 1. Step change of 10 dBm (movement to -70 dBm): delta = 10 > 4 -> alpha=0.60
        pipe.start_window()
        pipe.add_raw_sample(-70, 2000)
        pipe.process_cycle(2100)
        # ema = 0.60 * (-70) + 0.40 * (-60) = -42 - 24 = -66.0 dBm
        self.assertAlmostEqual(pipe.ema_rssi, -66.0, places=2)

        # 2. Small step of 1 dBm (stationary at -67 dBm): delta = 1 <= 4 -> alpha=0.25
        pipe.start_window()
        pipe.add_raw_sample(-67, 3000)
        pipe.process_cycle(3100)
        # ema = 0.25 * (-67) + 0.75 * (-66) = -16.75 - 49.50 = -66.25 dBm
        self.assertAlmostEqual(pipe.ema_rssi, -66.25, places=2)

    def test_ema_clean_initialization(self):
        """First valid sample initializes EMA directly without artificial jumps."""
        pipe = AdvancedSignalFilterPipeline()
        self.assertIsNone(pipe.ema_rssi)
        pipe.start_window()
        pipe.add_raw_sample(-64, 1000)
        pipe.process_cycle(1100)
        self.assertEqual(pipe.ema_rssi, -64.0, "First sample must initialize EMA directly")
        self.assertEqual(pipe.filtered_rssi, -64)

    def test_zero_samples_window_stale_and_offline(self):
        """Zero samples in window preserves previous distance and ages to STALE then OFFLINE."""
        pipe = AdvancedSignalFilterPipeline()
        # Initialize node at t=1000 ms
        pipe.start_window()
        pipe.add_raw_sample(-59, 1000)
        pipe.process_cycle(1050)
        self.assertEqual(pipe.state, STATE_ACTIVE)
        self.assertEqual(pipe.distance_cm, 100)

        # Window at t=1500 ms (elapsed 500 ms): 0 samples -> still ACTIVE (<1200ms), distance preserved
        pipe.start_window()
        pipe.process_cycle(1500)
        self.assertEqual(pipe.state, STATE_ACTIVE)
        self.assertEqual(pipe.distance_cm, 100)

        # Window at t=2500 ms (elapsed 1500 ms): 0 samples -> STALE (1200-3500ms), distance preserved
        pipe.start_window()
        pipe.process_cycle(2500)
        self.assertEqual(pipe.state, STATE_STALE)
        self.assertEqual(pipe.distance_cm, 100, "Stale state must preserve last valid distance")

        # Window at t=5000 ms (elapsed 4000 ms): 0 samples -> OFFLINE (>3500ms), distance set to sentinel
        pipe.start_window()
        pipe.process_cycle(5000)
        self.assertEqual(pipe.state, STATE_OFFLINE)
        self.assertEqual(pipe.distance_cm, SHAPNEST_DISTANCE_OFFLINE_CM)
        self.assertEqual(pipe.filtered_rssi, SHAPNEST_RSSI_OFFLINE)

    def test_per_node_calibration_math(self):
        """Verifies that nodes with different physical A and n produce correct distances."""
        # Node 1 (Fan): Calibrated A = -56 dBm, n = 2.0
        pipe1 = AdvancedSignalFilterPipeline(refA=-56, expN=2.0)
        pipe1.start_window()
        pipe1.add_raw_sample(-56, 1000)
        pipe1.process_cycle(1100)
        self.assertEqual(pipe1.distance_cm, 100)  # Exactly 1.00m at A

        # Node 2 (Iron): Calibrated A = -62 dBm, n = 2.5
        pipe2 = AdvancedSignalFilterPipeline(refA=-62, expN=2.5)
        pipe2.start_window()
        pipe2.add_raw_sample(-62, 1000)
        pipe2.process_cycle(1100)
        self.assertEqual(pipe2.distance_cm, 100)  # Exactly 1.00m at A

        # Node 2 at -74.5 dBm -> exponent = (-62 - (-74.5)) / (25) = 12.5 / 25 = 0.5 -> 10^0.5 = 3.16m
        pipe2.start_window()
        pipe2.add_raw_sample(-75, 2000)
        pipe2.process_cycle(2100)
        self.assertGreater(pipe2.distance_cm, 200)


class TestCentralHubNDJSONIntegration(unittest.TestCase):
    """Simulates Hub receiving 23-byte binary packet and generating NDJSON for Web App."""

    def test_end_to_end_packet_to_ndjson(self):
        """Simulates full RX -> Unpack -> NDJSON Serialization pipeline for 3 nodes."""
        header = struct.pack("<BBB BB H B B B B",
                             0x02, 0x01, 0x06,
                             0x13, 0xFF,
                             SHAPNEST_PROTOCOL_ID,
                             SHAPNEST_FRAME_TYPE_WRISTBAND_TEL,
                             1,   # Wristband 1
                             105, # Sequence 105
                             3)   # 3 nodes: Fan, Iron, Door
        
        node_data = [
            {"id": 1, "state": STATE_ACTIVE, "dist_cm": 82,  "rssi": -57},  # Fan
            {"id": 2, "state": STATE_ACTIVE, "dist_cm": 145, "rssi": -63},  # Iron
            {"id": 3, "state": STATE_STALE,  "dist_cm": 280, "rssi": -69}   # Door
        ]
        
        payload = b""
        for nd in node_data:
            id_st = pack_id_state(nd["id"], nd["state"])
            payload += struct.pack("<B H b", id_st, nd["dist_cm"], nd["rssi"])
            
        raw_ble_packet = header + payload
        self.assertEqual(len(raw_ble_packet), 23)
        
        co_id = struct.unpack_from("<H", raw_ble_packet, 5)[0]
        ftype = raw_ble_packet[7]
        self.assertEqual(co_id, 0x534E)
        self.assertEqual(ftype, 0x02)
        
        wb_id = raw_ble_packet[8]
        seq = raw_ble_packet[9]
        node_cnt = raw_ble_packet[10]
        self.assertEqual(wb_id, 1)
        self.assertEqual(seq, 105)
        self.assertEqual(node_cnt, 3)
        
        nodes_json_list = []
        for i in range(3):
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
        
        parsed_app_obj = json.loads(ndjson_line)
        self.assertEqual(parsed_app_obj["wristband_id"], 1)
        self.assertEqual(len(parsed_app_obj["nodes"]), 3)
        
        # Node 1 (Fan): 0.82 m / 82 cm
        self.assertEqual(parsed_app_obj["nodes"][0]["distance"], 0.82)
        self.assertEqual(parsed_app_obj["nodes"][0]["state"], "ACTIVE")
        
        # Node 2 (Iron): 1.45 m / 145 cm
        self.assertEqual(parsed_app_obj["nodes"][1]["distance"], 1.45)
        self.assertEqual(parsed_app_obj["nodes"][1]["state"], "ACTIVE")
        
        # Node 3 (Door): STALE
        self.assertEqual(parsed_app_obj["nodes"][2]["state"], "STALE")

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

        self.assertEqual(format_distance(0.82, 82, "ACTIVE", "m"), "0.82 m")
        self.assertEqual(format_distance(0.82, 82, "ACTIVE", "cm"), "82 cm")
        self.assertEqual(format_distance(1.45, 145, "ACTIVE", "m"), "1.45 m")
        self.assertEqual(format_distance(1.45, 145, "ACTIVE", "cm"), "145 cm")
        self.assertEqual(format_distance(8.00, 800, "OUT_OF_RANGE", "m"), "> 8.0 m")
        self.assertEqual(format_distance(8.00, 800, "OUT_OF_RANGE", "cm"), "> 800 cm")
        self.assertEqual(format_distance(None, 65535, "OFFLINE", "m"), "--")
        self.assertEqual(format_distance(None, 65535, "OFFLINE", "cm"), "--")


if __name__ == "__main__":
    print("\n" + "=" * 70)
    print("RUNNING SHAPNEST PHASE 1 AUTOMATED INTEGRATION & SIMULATION SUITE")
    print("=" * 70 + "\n")
    unittest.main(verbosity=2)
