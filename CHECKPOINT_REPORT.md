# SHAPNEST — Milestone Checkpoint Report (v1.0)
**Date:** October 4, 2026  
**Status:** All Firmware Flashed & Verified | Hub Eliminated | Mobile App Built | Git Checkpointed  
**Git Tag:** `checkpoint-v1.0-flashed`  
**Repository:** [github.com/pratikdesai472006/SHAPNEST_1](https://github.com/pratikdesai472006/SHAPNEST_1)

---

## 1. Executive Summary & Architectural Shift

The SHAPNEST system has undergone a complete architectural transformation:
1. **Central Hub Eliminated:** The ESP32-WROOM central gateway and serial-to-web intermediary bridges have been removed. The phone now communicates directly with anchor nodes and/or the wristband over BLE.
2. **Direct Mobile Processing:** Distance calculation, RSSI filtering, telemetry parsing, and spatial visualization run natively on the Android phone using Flutter.
3. **High-Accuracy Filtering Engine:** Solved BLE RSSI distance jitter by implementing a 1D Adaptive Kalman Filter, rolling outlier pre-filtering, speed clamping, and an in-app 1-Meter Phone Calibration Wizard.
4. **All 4 ESP32-C3 Devices Flashed:** Every physical board in the user's setup has been flashed and verified directly over USB serial.

---

## 2. Hardware & Firmware Inventory

All four ESP32-C3 Mini boards were successfully flashed with custom firmware:

| Node / Device | Role | Source Code | Flashed Port | Physical MAC Address | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Wristband** | Mobile Wearable Telemetry | `firmware/wristband/wristband.ino` | `COM9` | `ac:a7:04:d2:fc:84` | **Flashed & Running** |
| **Node 1 (Fan)** | Fixed Anchor 1 | `firmware/node_fan/node_fan.ino` | `COM6` | `70:af:09:2a:d7:f0` | **Flashed & Running** |
| **Node 2 (Iron)** | Fixed Anchor 2 | `firmware/node_iron/node_iron.ino` | `COM7` | `70:af:09:32:ed:28` | **Flashed & Running** |
| **Node 3 (Door)** | Fixed Anchor 3 | `firmware/node_door/node_door.ino` | `COM5` | `70:af:09:2b:1e:58` | **Flashed & Running** |

### RF & Protocol Specifications
- **Frequency:** 2.4 GHz Bluetooth Low Energy (BLE 5.0)
- **BLE Library:** `NimBLE-Arduino` v1.4.3 (low-latency, zero-heap-fragmentation)
- **Protocol Magic:** `0x534E` (`SN` Little-Endian)
- **Tx Power:** `+3 dBm` (ESP_PWR_LVL_P3)
- **Advertising Interval:** 100 ms (Fast responsive tracking)
- **Structure Packing:** Strict `#pragma pack(push, 1)` across all telemetry frames.

---

## 3. Mobile Application (Flutter APK)

A native Flutter Android application was developed and compiled to release APK.

- **APK File Location:** `e:\SHAPNEST\SHAPNEST_Tracker.apk`
- **File Size:** 47.95 MB
- **Target OS:** Android 8.0+ (API 26 through 37)
- **Source Directory:** `e:\SHAPNEST\shapnest_app/` and mirrored in `prototype_distance/shapnest_app/`

### Key App Features
- **Spatial Radar Interface:** Visualizes distance rings (Immediate $< 1\text{m}$, Near $1-3\text{m}$, Far $> 3\text{m}$, Lost $> 6\text{m}$) with animated node blips and proximity glow indicators.
- **Dual Tracking Modes:**
  - *Direct Scanning Mode:* The phone measures RSSI directly to all anchor nodes without needing the wristband.
  - *Wristband Mode:* The phone connects/listens to the wristband's aggregated multi-node ranging telemetry.
- **Distance Precision Engine:**
  - *Outlier Pre-Filter:* 5-sample rolling median window eliminates transient multipath RF reflection spikes.
  - *1D Adaptive Kalman Filter:* Dynamically scales measurement noise covariance $R$ during rapid movement to maintain sub-second responsiveness, and tightens $R$ when stationary to eliminate static jitter.
  - *Velocity Clamping:* Limits calculated node movement speed to $< 2.0\text{ m/s}$ (human walking limit) to prevent unrealistic teleportation artifacts.
  - *1-Meter Calibration Wizard:* Enables the user to stand at 1m from any node and tap "Calibrate", permanently storing the phone's calibrated reference RSSI ($A$) into persistent storage.
  - *Path Loss Exponent Tuning:* Configurable $n$ values (2.0 Open Space, 2.4 Typical Indoor, 3.0 Obstacle Heavy).

---

## 4. How to Retrieve This Checkpoint in the Future

This exact working state is tagged and pushed to GitHub. To view or restore it at any time:

### View Checkpoints & Tags
```powershell
cd e:\SHAPNEST\prototype_distance
git tag -n
```

### Inspect the Exact State
```powershell
git checkout checkpoint-v1.0-flashed
```

### Return to Latest Work
```powershell
git checkout main
```

### Clone Clean Copy from GitHub
```bash
git clone https://github.com/pratikdesai472006/SHAPNEST_1.git
cd SHAPNEST_1
git checkout checkpoint-v1.0-flashed
```

---

## 5. Recommended Next Steps

With all hardware flashed and the mobile app functional, future development phases can focus on:

1. **2D Trilateration Engine:**
   - Map $(X, Y)$ coordinates of the room by combining the 3 anchor distance circles (Fan, Iron, Door) to plot the user's exact 2D position on a room floor plan.
2. **Proximity Action Automation:**
   - Automatically trigger alerts or smart switches when entering the "Immediate Zone" (< 1 meter) of an appliance (e.g., auto-fan control or iron safety shutoff warning).
3. **Battery & Deep Sleep Optimizations:**
   - Implement dynamic BLE sleep cycles on the wristband node to achieve multi-day battery life on a small LiPo cell.
