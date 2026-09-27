/**
 * ============================================================================
 * SHAPNEST — PHASE 1 CHILD WRISTBAND FIRMWARE
 * Child Wristband Firmware (ESP32-C3 Mini)
 * 
 * Target Board: ESP32-C3 Mini / ESP32C3 Dev Module
 * CPU:          Single-Core 32-bit RISC-V @ 160 MHz, 400 KB SRAM
 * Framework:    Arduino IDE (ESP32 Board Package >= 2.0.14 or >= 3.0.0)
 * Library:      NimBLE-Arduino (by h2zero)
 * 
 * ARDUINO IDE CONFIGURATION:
 *   - Tools -> Board: "ESP32C3 Dev Module"
 *   - Tools -> USB CDC On Boot: "Enabled" (Crucial for USB Serial on C3!)
 *   - Tools -> Flash Size: "4MB (32Mb)"
 *   - Tools -> CPU Frequency: "160MHz (WiFi/BT)"
 *   - Tools -> Upload Speed: "921600" or "115200"
 * 
 * DESCRIPTION:
 *   The primary sensor and distance measurement engine for the child.
 *   - Cooperative Time-Slicing:
 *       • 900 ms dedicated passive scanning window (100% radio in RX).
 *       • 10 ms digital filtering & distance estimation.
 *       • 90 ms dedicated 3-pulse uplink burst to Central Hub.
 *   - Signal Conditioning Pipeline:
 *       • Outlier rejection gate.
 *       • 5-sample rolling Median filter per node (strips multipath nulls).
 *       • Exponential Moving Average (EMA, alpha = 0.25) low-pass smoothing.
 *       • Log-Distance Path Loss Model (using node's broadcasted A & n).
 *       • Boundary Clamping: 0.15 m floor / 8.00 m ceiling.
 *       • Staleness State Machine: ACTIVE (<1.2s), STALE (1.2-3.5s), OFFLINE (>3.5s).
 *   - Broadcasts the exact 31-byte telemetry frame to the Central Hub at 1 Hz.
 * ============================================================================
 */

#include <Arduino.h>
#include <NimBLEDevice.h>
#include <algorithm>
#include <cmath>
#include "shapnest_protocol.h"

// ============================================================================
// CONFIGURATION CONSTANTS
// ============================================================================
#define WRISTBAND_ID            SHAPNEST_TARGET_WRISTBAND_ID  // Wristband #1
#define STATUS_LED_PIN          8                             // ESP32-C3 on-board LED GPIO (set -1 if unused)
#define MEDIAN_WINDOW_SIZE      5                             // 5-sample sliding median window
#define EMA_ALPHA               0.25f                         // Low-pass smoothing factor

// ============================================================================
// PER-NODE FILTER & STATE TRACKER STRUCT
// ============================================================================
struct NodeTracker {
    // Raw sample sliding ring buffer
    int8_t   rawBuffer[MEDIAN_WINDOW_SIZE];
    uint8_t  bufferCount;
    uint8_t  bufferHead;

    // Filter states
    float    emaRssi;
    bool     hasEma;

    // Node-broadcasted calibration parameters
    int8_t   calibratedRefA;       // A (dBm at 1m)
    uint8_t  pathLossExpX10;       // n * 10

    // Timestamps & State Machine
    uint32_t lastSeenMs;
    shapnest_node_state_t state;

    // Computed Output Telemetry
    uint16_t distanceCm;
    int8_t   filteredRssi;
};

// Global Node Trackers (Index 0 = Node 1, Index 4 = Node 5)
static NodeTracker nodeTrackers[SHAPNEST_MAX_NODES];

// Global BLE Objects
static NimBLEScan*                  pScan = nullptr;
static NimBLEAdvertising*           pAdvertising = nullptr;
static shapnest_wristband_payload_t uplinkPayload;
static NimBLEAdvertisementData      advData;
static uint8_t                      uplinkSeq = 0;
static uint32_t                     lastDiagnosticLogTime = 0;

// Mutex for thread-safe buffer updates from BLE callback
static portMUX_TYPE                 filterMux = portMUX_INITIALIZER_UNLOCKED;

// ============================================================================
// FUNCTION DECLARATIONS
// ============================================================================
static void initialize_ble_subsystem();
static void reset_node_trackers();
static void process_signal_conditioning(uint32_t now);
static void assemble_uplink_payload();
static void transmit_uplink_burst();
static void print_diagnostic_heartbeat(uint32_t now);
static void blink_led(uint8_t count, uint16_t duration_ms);

// ============================================================================
// NIMBLE ADVERTISED DEVICE CALLBACK (Runs on Core 0 BLE Task)
// Fast-path: records raw RSSI and node parameters into ring buffer in < 5 us
// ============================================================================
static void handle_node_advertisement(NimBLEAdvertisedDevice* advertisedDevice) {
    if (!advertisedDevice->haveManufacturerData()) return;

    std::string mfr = advertisedDevice->getManufacturerData();
    if (mfr.length() < sizeof(shapnest_node_payload_t)) return;

    const shapnest_node_payload_t* pNodePayload = 
        reinterpret_cast<const shapnest_node_payload_t*>(mfr.data());

    // Fast Protocol Validation
    if (pNodePayload->company_id != SHAPNEST_PROTOCOL_ID) return;
    if (pNodePayload->frame_type != SHAPNEST_FRAME_TYPE_NODE_BEACON) return;

    uint8_t nodeId = pNodePayload->node_id;
    if (nodeId < SHAPNEST_NODE_ID_MIN || nodeId > SHAPNEST_NODE_ID_MAX) return;

    uint8_t idx = nodeId - 1;
    int8_t  rawRssi = (int8_t)advertisedDevice->getRSSI();

    // Push raw sample into node's ring buffer (thread-safe)
    portENTER_CRITICAL(&filterMux);
    NodeTracker* n = &nodeTrackers[idx];
    n->calibratedRefA = pNodePayload->calibrated_rssi_1m;
    n->pathLossExpX10 = pNodePayload->path_loss_exp_x10;
    n->lastSeenMs     = millis();

    n->rawBuffer[n->bufferHead] = rawRssi;
    n->bufferHead = (n->bufferHead + 1) % MEDIAN_WINDOW_SIZE;
    if (n->bufferCount < MEDIAN_WINDOW_SIZE) {
        n->bufferCount++;
    }
    portEXIT_CRITICAL(&filterMux);
}

#if defined(NIMBLE_CPP_VERSION_MAJOR) && (NIMBLE_CPP_VERSION_MAJOR >= 2)
class NodeBeaconCallbacks : public NimBLEScanCallbacks {
    void onDiscovered(const NimBLEAdvertisedDevice* advertisedDevice) override {}
    void onResult(const NimBLEAdvertisedDevice* advertisedDevice) override {
        handle_node_advertisement(const_cast<NimBLEAdvertisedDevice*>(advertisedDevice));
    }
};
#else
class NodeBeaconCallbacks : public NimBLEAdvertisedDeviceCallbacks {
    void onResult(NimBLEAdvertisedDevice* advertisedDevice) override {
        handle_node_advertisement(advertisedDevice);
    }
};
#endif

static NodeBeaconCallbacks scanCallbacks;

// Scan completion callback to ensure non-blocking operation in NimBLE v1.x and v2.x
#if defined(NIMBLE_CPP_VERSION_MAJOR) && (NIMBLE_CPP_VERSION_MAJOR >= 2)
static void scanCompleteCB(const NimBLEScanResults& results, int reason) {
    (void)results;
    (void)reason;
}
#else
static void scanCompleteCB(NimBLEScanResults results) {
    (void)results;
}
#endif

// ============================================================================
// SETUP
// ============================================================================
void setup() {
    Serial.begin(SHAPNEST_SERIAL_BAUD_RATE);
    delay(1000); // Allow USB CDC to attach

    if (STATUS_LED_PIN >= 0) {
        pinMode(STATUS_LED_PIN, OUTPUT);
        digitalWrite(STATUS_LED_PIN, LOW);
    }

    // Print Diagnostic Boot Banner
    Serial.println();
    Serial.println("==================================================");
    Serial.printf("# [LOG] SHAPNEST CHILD WRISTBAND — ESP32-C3 MINI\n");
    Serial.printf("# [LOG] Wristband ID: %d | Protocol: v%d (0x%04X)\n", WRISTBAND_ID, SHAPNEST_PROTOCOL_VERSION, SHAPNEST_PROTOCOL_ID);
    Serial.printf("# [LOG] Monitored Nodes: %d (NODE_01 to NODE_05)\n", SHAPNEST_MAX_NODES);
    Serial.printf("# [LOG] Filter Pipeline: 5-Sample Median + EMA (alpha=%.2f)\n", EMA_ALPHA);
    Serial.printf("# [LOG] Distance Bounds: %.2f m to %.2f m\n", SHAPNEST_DISTANCE_MIN_CM / 100.0f, SHAPNEST_DISTANCE_MAX_CM / 100.0f);
    Serial.printf("# [LOG] Cooperative Time-Slice: %d ms Scan / %d ms Uplink\n", 
                  SHAPNEST_WRISTBAND_SCAN_MS, SHAPNEST_WRISTBAND_UPLINK_BURST_MS);
    Serial.println("==================================================");

    reset_node_trackers();
    initialize_ble_subsystem();

    blink_led(WRISTBAND_ID, 100);
    Serial.println("# [LOG] Wristband Engine ONLINE — Starting Cooperative Loop.");
}

// ============================================================================
// MAIN LOOP: COOPERATIVE TIME-SLICED SCHEDULER (1 Hz Cycle)
// ============================================================================
void loop() {
    uint32_t cycleStart = millis();

    // ------------------------------------------------------------------------
    // WINDOW 1: DEDICATED PASSIVE SCANNING (900 ms)
    // 100% of the 2.4 GHz radio is dedicated to capturing Node advertisements.
    // Must be non-blocking so the cooperative timer loop can control duration.
    // ------------------------------------------------------------------------
#if defined(NIMBLE_CPP_VERSION_MAJOR) && (NIMBLE_CPP_VERSION_MAJOR >= 2)
    pScan->start(0, false, true);
#else
    pScan->start(0, scanCompleteCB, false);
#endif

    while (millis() - cycleStart < SHAPNEST_WRISTBAND_SCAN_MS) {
        delay(10); // Yield to FreeRTOS to allow BLE callback packet processing
    }

    // Stop scanning cleanly; halts RX synthesizer and clears controller state
    pScan->stop();

    // ------------------------------------------------------------------------
    // WINDOW 2: SIGNAL CONDITIONING & DISTANCE CALCULATION (< 5 ms)
    // ------------------------------------------------------------------------
    uint32_t now = millis();
    process_signal_conditioning(now);

    // ------------------------------------------------------------------------
    // WINDOW 3: DEDICATED UPLINK TRANSMISSION BURST (90 ms)
    // Packs 31-byte frame and transmits 3 rapid pulses to Central Hub.
    // ------------------------------------------------------------------------
    assemble_uplink_payload();
    transmit_uplink_burst();

    // ------------------------------------------------------------------------
    // DIAGNOSTIC LOGGING (Every 5 seconds)
    // ------------------------------------------------------------------------
    if (now - lastDiagnosticLogTime >= 5000) {
        lastDiagnosticLogTime = now;
        print_diagnostic_heartbeat(now);
    }

    // ------------------------------------------------------------------------
    // SETTLE & COMPENSATE TO MAINTAIN EXACT 1000 ms MASTER CYCLE
    // ------------------------------------------------------------------------
    uint32_t elapsed = millis() - cycleStart;
    if (elapsed < SHAPNEST_WRISTBAND_CYCLE_MS) {
        delay(SHAPNEST_WRISTBAND_CYCLE_MS - elapsed);
    }
}

// ============================================================================
// BLE SUBSYSTEM INITIALIZATION
// ============================================================================
static void initialize_ble_subsystem() {
    NimBLEDevice::init("SHAPNEST_WB1");
    NimBLEDevice::setPower(ESP_PWR_LVL_P3); // +3 dBm TX power

    // 1. Configure Scanner
    pScan = NimBLEDevice::getScan();
#if defined(NIMBLE_CPP_VERSION_MAJOR) && (NIMBLE_CPP_VERSION_MAJOR >= 2)
    pScan->setScanCallbacks(&scanCallbacks, false);
#else
    pScan->setAdvertisedDeviceCallbacks(&scanCallbacks, false);
#endif
    pScan->setActiveScan(false); // Passive scanning (pure RX, zero TX collisions)
    pScan->setInterval(160);     // 100 ms
    pScan->setWindow(160);       // 100% continuous during scan window
    pScan->setDuplicateFilter(false);

    // 2. Configure Broadcaster (Uplink to Central Hub)
    pAdvertising = NimBLEDevice::getAdvertising();

#if defined(NIMBLE_CPP_VERSION_MAJOR) && (NIMBLE_CPP_VERSION_MAJOR >= 2)
    pAdvertising->setConnectable(false);
#else
    pAdvertising->setAdvertisementType(BLE_GAP_CONN_MODE_NON);
#endif

    // Fast 25 ms advertising interval (40 * 0.625 ms = 25 ms)
    pAdvertising->setMinInterval(40);
    pAdvertising->setMaxInterval(40);
}

// ============================================================================
// RESET NODE TRACKERS
// ============================================================================
static void reset_node_trackers() {
    for (uint8_t i = 0; i < SHAPNEST_MAX_NODES; i++) {
        nodeTrackers[i].bufferCount    = 0;
        nodeTrackers[i].bufferHead     = 0;
        nodeTrackers[i].emaRssi        = 0.0f;
        nodeTrackers[i].hasEma         = false;
        nodeTrackers[i].calibratedRefA = SHAPNEST_DEFAULT_REF_RSSI_1M;
        nodeTrackers[i].pathLossExpX10 = SHAPNEST_DEFAULT_PATH_LOSS_EXP_X10;
        nodeTrackers[i].lastSeenMs     = 0;
        nodeTrackers[i].state          = SHAPNEST_NODE_STATE_OFFLINE;
        nodeTrackers[i].distanceCm     = SHAPNEST_DISTANCE_OFFLINE_CM;
        nodeTrackers[i].filteredRssi   = SHAPNEST_RSSI_OFFLINE;
    }
}

// ============================================================================
// TWO-STAGE SIGNAL CONDITIONING & DISTANCE ESTIMATION
// ============================================================================
static void process_signal_conditioning(uint32_t now) {
    portENTER_CRITICAL(&filterMux);

    for (uint8_t i = 0; i < SHAPNEST_MAX_NODES; i++) {
        NodeTracker* n = &nodeTrackers[i];

        // 1. Evaluate Node Staleness State Machine
        uint32_t ageMs = (n->lastSeenMs > 0) ? (now - n->lastSeenMs) : 999999;

        if (n->lastSeenMs == 0 || ageMs > SHAPNEST_NODE_OFFLINE_TIMEOUT_MS) {
            n->state        = SHAPNEST_NODE_STATE_OFFLINE;
            n->distanceCm   = SHAPNEST_DISTANCE_OFFLINE_CM;
            n->filteredRssi = SHAPNEST_RSSI_OFFLINE;
            n->hasEma       = false;
            n->bufferCount  = 0;
            continue;
        } else if (ageMs >= SHAPNEST_NODE_ACTIVE_TIMEOUT_MS) {
            n->state = SHAPNEST_NODE_STATE_STALE;
            // Retain last known distance and RSSI while stale
            continue;
        } else {
            n->state = SHAPNEST_NODE_STATE_ACTIVE;
        }

        // 2. Stage 1: Rolling Median Filter (strips multipath impulse spikes)
        if (n->bufferCount > 0) {
            int8_t tempSort[MEDIAN_WINDOW_SIZE];
            uint8_t count = n->bufferCount;
            memcpy(tempSort, n->rawBuffer, count * sizeof(int8_t));
            std::sort(tempSort, tempSort + count);

            int8_t medianRssi = tempSort[count / 2];

            // 3. Stage 2: Exponential Moving Average (EMA Low-Pass Smoothing)
            if (!n->hasEma) {
                n->emaRssi = (float)medianRssi;
                n->hasEma  = true;
            } else {
                n->emaRssi = (EMA_ALPHA * (float)medianRssi) + ((1.0f - EMA_ALPHA) * n->emaRssi);
            }

            n->filteredRssi = (int8_t)roundf(n->emaRssi);

            // 4. Stage 3: Log-Distance Path Loss Model Calculation
            // d = 10 ^ ((A - RSSI) / (10 * n))
            float refA = (float)n->calibratedRefA;
            float expN = (n->pathLossExpX10 > 0) ? (n->pathLossExpX10 / 10.0f) : 2.2f;

            float exponent = (refA - n->emaRssi) / (10.0f * expN);
            float distMeters = powf(10.0f, exponent);

            // 5. Stage 4: Operational Boundary Clamping
            // Min floor: 0.15 m | Ceiling: 8.00 m
            if (distMeters < (SHAPNEST_DISTANCE_MIN_CM / 100.0f)) {
                distMeters = SHAPNEST_DISTANCE_MIN_CM / 100.0f;
            } else if (distMeters > (SHAPNEST_DISTANCE_MAX_CM / 100.0f)) {
                distMeters = SHAPNEST_DISTANCE_MAX_CM / 100.0f;
            }

            n->distanceCm = (uint16_t)roundf(distMeters * 100.0f);
        }
    }

    portEXIT_CRITICAL(&filterMux);
}

// ============================================================================
// ASSEMBLE 31-BYTE TELEMETRY PAYLOAD
// ============================================================================
static void assemble_uplink_payload() {
    uplinkSeq++;

    uplinkPayload.company_id   = SHAPNEST_PROTOCOL_ID;
    uplinkPayload.frame_type   = SHAPNEST_FRAME_TYPE_WRISTBAND_TEL;
    uplinkPayload.wristband_id = (uint8_t)WRISTBAND_ID;
    uplinkPayload.sequence     = uplinkSeq;
    uplinkPayload.node_count   = SHAPNEST_MAX_NODES;

    for (uint8_t i = 0; i < SHAPNEST_MAX_NODES; i++) {
        uint8_t nodeId = i + 1;
        NodeTracker* n = &nodeTrackers[i];

        // Pack Node ID (bits 0..3) and State (bits 4..5)
        uplinkPayload.nodes[i].id_and_state = SHAPNEST_PACK_ID_STATE(nodeId, n->state);
        uplinkPayload.nodes[i].distance_cm  = n->distanceCm;
        uplinkPayload.nodes[i].filtered_rssi= n->filteredRssi;
    }

    // Load packed 26-byte payload into standard BLE advertisement data structure
    advData.setFlags(0x06); // LE General Discoverable | BR/EDR Not Supported
    advData.setManufacturerData(std::string((const char*)&uplinkPayload, sizeof(uplinkPayload)));
    pAdvertising->setAdvertisementData(advData);
}

// ============================================================================
// TRANSMIT 3-PULSE UPLINK BURST (90 ms Window)
// ============================================================================
static void transmit_uplink_burst() {
    // Start fast 25 ms advertising pulses
    pAdvertising->start();

    // Remain in transmit mode for 90 ms (emits ~3 advertising pulses on Ch 37, 38, 39)
    delay(SHAPNEST_WRISTBAND_UPLINK_BURST_MS);

    // Stop transmission cleanly before returning to scanning
    pAdvertising->stop();
}

// ============================================================================
// DIAGNOSTIC SERIAL LOGGING
// ============================================================================
static void print_diagnostic_heartbeat(uint32_t now) {
    Serial.printf("# [LOG] WB#%d Uplink Seq: %u | Uptime: %lu s\n", WRISTBAND_ID, uplinkSeq, now / 1000UL);
    for (uint8_t i = 0; i < SHAPNEST_MAX_NODES; i++) {
        NodeTracker* n = &nodeTrackers[i];
        if (n->state == SHAPNEST_NODE_STATE_ACTIVE) {
            Serial.printf("# [LOG]   NODE_0%d: %.2f m | RSSI: %d dBm | ACTIVE\n",
                          i + 1, shapnest_cm_to_meters(n->distanceCm), n->filteredRssi);
        } else if (n->state == SHAPNEST_NODE_STATE_STALE) {
            Serial.printf("# [WARN]  NODE_0%d: %.2f m (STALE, last seen %u ms ago)\n",
                          i + 1, shapnest_cm_to_meters(n->distanceCm), now - n->lastSeenMs);
        } else {
            Serial.printf("# [LOG]   NODE_0%d: OFFLINE\n", i + 1);
        }
    }
}

// ============================================================================
// HELPER: BLINK STATUS LED
// ============================================================================
static void blink_led(uint8_t count, uint16_t duration_ms) {
    if (STATUS_LED_PIN < 0) return;

    for (uint8_t i = 0; i < count; i++) {
        digitalWrite(STATUS_LED_PIN, HIGH);
        delay(duration_ms);
        digitalWrite(STATUS_LED_PIN, LOW);
        if (i < count - 1) {
            delay(duration_ms);
        }
    }
}
