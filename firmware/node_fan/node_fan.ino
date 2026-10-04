/**
 * ============================================================================
 * SHAPNEST PHASE 1 — Physical Node: Fan (Node ID 1)
 * Target: ESP32-C3 Proximity Anchor Node
 * ============================================================================
 */
#pragma once

#ifndef NODE_ID
#define NODE_ID                 1     // Node ID 1 (Fan)
#endif

// Per-node physical calibration parameters (Update after physical calibration)
#ifndef CALIBRATED_RSSI_1M
#define CALIBRATED_RSSI_1M    -59     // Default reference RSSI at 1 meter in dBm
#endif

#ifndef PATH_LOSS_EXP_X10
#define PATH_LOSS_EXP_X10      22     // Environmental factor n * 10 (22 = 2.2)
#endif

#ifndef TX_POWER_DBM
#define TX_POWER_DBM            9     // RF output power: +9 dBm (Max link budget)
#endif

#ifndef STATUS_LED_PIN
#define STATUS_LED_PIN          8     // ESP32-C3 LED pin (GPIO 8)
#endif

#include "../common/node_core.h"
