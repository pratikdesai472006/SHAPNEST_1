/**
 * ============================================================================
 * SHAPNEST — PHASE 1 CHILD WRISTBAND FIRMWARE
 * Target Board: ESP32-C3 Mini / ESP32C3 Dev Module
 * CPU:          Single-Core 32-bit RISC-V @ 160 MHz, 400 KB SRAM
 * Framework:    Arduino IDE / PlatformIO
 * Library:      NimBLE-Arduino (by h2zero)
 * 
 * DESCRIPTION:
 *   High-precision, ultra-responsive distance estimation tracking engine.
 *   - Pure BLE single-radio operation (eliminates Wi-Fi RF collisions and radio lockups).
 *   - Continuous 80% duty cycle passive scanning for maximum sample density.
 *   - On-Chip Dual-Regime 1D Adaptive Kalman Filter:
 *       • Stationary mode (Q=0.005, R=14.0): Aggressively suppresses multipath RF flutter.
 *       • Motion mode (Q=0.60, R=0.80): Instant tracking of physical movement.
 *       • Fast Attack mode (Q=1.40, R=0.25): Single-packet snap on separation or approach.
 *   - In-Window rolling median filter + sanity outlier gating.
 *   - High-rate (4 Hz / 250ms) 23-byte telemetry broadcaster with zero packet truncation.
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
#define ROLLING_SAMPLE_CAPACITY 16                            // Capacity of rolling circular sample buffer
#define SAMPLE_MAX_AGE_MS       1200                          // Max validity age of RSSI samples (ms)
#define RSSI_SANITY_MIN         -95                           // Lower physical sanity bound in dBm
#define RSSI_SANITY_MAX         -20                           // Upper physical sanity bound in dBm (saturation)
#define IMPULSE_OUTLIER_THRESH   12                           // Outlier threshold from window median (dBm)

// ============================================================================
// DUAL-REGIME 1D ADAPTIVE KALMAN FILTER (ON-CHIP FIRMWARE ENGINE)
// ============================================================================
enum FirmwareMotionState {
    FW_MOTION_STATIONARY = 0,
    FW_MOTION_MOVING     = 1,
    FW_MOTION_FAST_ATTACK= 2
};

struct RssiKalmanFilter {
    float x;            // Estimated RSSI in dBm
    float p;            // Estimation error covariance
    bool  initialized;
    uint8_t motionState; // FW_MOTION_STATIONARY / MOVING / FAST_ATTACK
    uint8_t consecutiveStationary;
    uint8_t consecutiveMoving;
    float lastDelta;
    uint8_t warmupCycles; // Initial fast-convergence sample counter

    // Stationary Tuning: suppresses multipath RF jitter without infinite lag (K ~ 0.02)
    static constexpr float qStationary = 0.005f;
    static constexpr float rStationary = 14.0f;

    // Moving Tuning: highly responsive physical motion tracking (K ~ 0.45)
    static constexpr float qMoving     = 0.50f;
    static constexpr float rMoving     = 1.00f;

    // Fast Attack: rapid approach into danger zone / initial acquisition (K ~ 0.85)
    static constexpr float qFastAttack = 1.40f;
    static constexpr float rFastAttack = 0.30f;

    void reset() {
        x = -60.0f;
        p = 4.0f;
        initialized = false;
        warmupCycles = 5;
        motionState = FW_MOTION_FAST_ATTACK;
        consecutiveStationary = 0;
        consecutiveMoving = 2;
        lastDelta = 0.0f;
    }

    float update(float z) {
        if (!initialized) {
            x = z;
            p = 4.0f;
            initialized = true;
            warmupCycles = 5;
            motionState = FW_MOTION_FAST_ATTACK;
            consecutiveStationary = 0;
            consecutiveMoving = 2;
            lastDelta = 0.0f;
            return x;
        }

        float delta = z - x;
        float absDiff = fabsf(delta);

        // Rapid warm-up phase (first 5 samples after node detection)
        if (warmupCycles > 0) {
            warmupCycles--;
            motionState = FW_MOTION_FAST_ATTACK;
            consecutiveStationary = 0;
            consecutiveMoving = 2;
        }
        // Fast Approach into Danger or large step change (|delta| >= 8.0)
        else if ((delta >= 5.0f && (x < -64.0f || z > -60.0f)) || absDiff >= 8.0f) {
            motionState = FW_MOTION_FAST_ATTACK;
            consecutiveStationary = 0;
            consecutiveMoving = 3;
        } else if (absDiff >= 3.0f) {
            bool sameDirection = (delta * lastDelta > 0.0f);
            if (sameDirection || absDiff >= 5.0f) {
                consecutiveMoving++;
                if (consecutiveMoving >= 2 || absDiff >= 6.0f) {
                    motionState = FW_MOTION_MOVING;
                    consecutiveStationary = 0;
                }
            }
        } else if (absDiff <= 2.2f) {
            consecutiveStationary++;
            if (consecutiveStationary >= 2) {
                motionState = FW_MOTION_STATIONARY;
                consecutiveMoving = 0;
            }
        }

        lastDelta = delta;

        float q, r;
        if (motionState == FW_MOTION_FAST_ATTACK) {
            q = qFastAttack;
            r = rFastAttack;
        } else if (motionState == FW_MOTION_MOVING) {
            q = qMoving;
            r = rMoving;
        } else {
            q = qStationary;
            r = rStationary;
        }

        p = p + q;
        float k = p / (p + r);
        x = x + k * delta;
        p = (1.0f - k) * p;

        return x;
    }
};

// ============================================================================
// PER-NODE FILTER & STATE TRACKER STRUCT
// ============================================================================
struct RssiSample {
    int8_t   rssi;
    uint32_t timestampMs;
};

struct NodeTracker {
    // Rolling circular sample buffer for rich statistical filtering
    RssiSample sampleBuffer[ROLLING_SAMPLE_CAPACITY];
    uint8_t    sampleHead;
    uint8_t    sampleCount;
    uint8_t    samplesSinceLastProcess;

    // Dual-regime Kalman filter
    RssiKalmanFilter kalmanRssi;

    // Ultra-Stable Distance Hysteresis State (eliminates stationary numeric flutter)
    float    lockedDistanceM;
    uint8_t  deadbandBreachCount;
    float    smoothDistanceM;

    // Node-broadcasted calibration parameters
    int8_t   calibratedRefA;       // A (dBm at 1m)
    uint8_t  pathLossExpX10;       // n * 10
    bool     manualCalOverride;    // True if calibrated manually via Serial CDC on wristband

    // Timestamps & State Machine
    uint32_t lastSeenMs;
    shapnest_node_state_t state;

    // Computed Output Telemetry (Authoritative measurement)
    uint16_t distanceCm;
    int8_t   filteredRssi;
};

// Global Node Trackers (Index 0 = Node 1 [Fan], Index 1 = Node 2 [Iron], Index 2 = Node 3 [Door])
static NodeTracker nodeTrackers[SHAPNEST_MAX_NODES];

// Global BLE Objects
static NimBLEScan*                  pScan = nullptr;
static NimBLEAdvertising*           pAdvertising = nullptr;
static shapnest_wristband_payload_t uplinkPayload;
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
static void print_diagnostic_heartbeat(uint32_t now);
static void blink_led(uint8_t count, uint16_t duration_ms);
static void handle_serial_commands();

// ============================================================================
// NIMBLE ADVERTISED DEVICE CALLBACK (Runs on Core 0 BLE Task)
// ============================================================================
static void handle_node_advertisement(NimBLEAdvertisedDevice* advertisedDevice) {
    if (!advertisedDevice->haveManufacturerData()) return;

    std::string mfr = advertisedDevice->getManufacturerData();
    if (mfr.length() < SHAPNEST_NODE_PAYLOAD_MIN_SIZE) return;

    const shapnest_node_payload_t* pNodePayload = 
        reinterpret_cast<const shapnest_node_payload_t*>(mfr.data());

    // 1. Protocol Validation Gate
    if (pNodePayload->company_id != SHAPNEST_PROTOCOL_ID) return;
    if (pNodePayload->frame_type != SHAPNEST_FRAME_TYPE_NODE_BEACON) return;

    uint8_t nodeId = pNodePayload->node_id;
    if (nodeId < SHAPNEST_NODE_ID_MIN || nodeId > SHAPNEST_NODE_ID_MAX) return;

    uint8_t idx = nodeId - 1;
    int8_t  rawRssi = (int8_t)advertisedDevice->getRSSI();

    // 2. Physical Sanity Outlier Gate
    if (rawRssi < RSSI_SANITY_MIN || rawRssi > RSSI_SANITY_MAX) {
        return;
    }

    // 3. Store into rolling circular sample buffer (Thread-safe)
    portENTER_CRITICAL(&filterMux);
    NodeTracker* n = &nodeTrackers[idx];
    if (!n->manualCalOverride) {
        if (pNodePayload->calibrated_rssi_1m < 0 && pNodePayload->calibrated_rssi_1m >= -100) {
            n->calibratedRefA = pNodePayload->calibrated_rssi_1m;
        }
        if (pNodePayload->path_loss_exp_x10 >= 10 && pNodePayload->path_loss_exp_x10 <= 50) {
            n->pathLossExpX10 = pNodePayload->path_loss_exp_x10;
        }
    }
    n->lastSeenMs = millis();
    n->sampleBuffer[n->sampleHead].rssi = rawRssi;
    n->sampleBuffer[n->sampleHead].timestampMs = n->lastSeenMs;
    n->sampleHead = (n->sampleHead + 1) % ROLLING_SAMPLE_CAPACITY;
    if (n->sampleCount < ROLLING_SAMPLE_CAPACITY) {
        n->sampleCount++;
    }
    n->samplesSinceLastProcess++;
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

#if defined(NIMBLE_CPP_VERSION_MAJOR) && (NIMBLE_CPP_VERSION_MAJOR >= 2)
static void scanCompleteCB(const NimBLEScanResults& results, int reason) {
    (void)results;
    (void)reason;
    if (pScan != nullptr && !pScan->isScanning()) {
        pScan->start(0, false, true);
    }
}
#else
static void scanCompleteCB(NimBLEScanResults results) {
    (void)results;
    if (pScan != nullptr && !pScan->isScanning()) {
        pScan->start(0, scanCompleteCB, false);
    }
}
#endif

// ============================================================================
// SETUP
// ============================================================================
void setup() {
    // 1. Immediately turn on on-board Status LED (active-LOW on ESP32-C3 Super Mini)
    if (STATUS_LED_PIN >= 0) {
        pinMode(STATUS_LED_PIN, OUTPUT);
        digitalWrite(STATUS_LED_PIN, LOW);
    }

    Serial.begin(SHAPNEST_SERIAL_BAUD_RATE);
    delay(500); // Allow USB CDC time to attach

    Serial.println();
    Serial.println("==================================================");
    Serial.printf("# [LOG] SHAPNEST CHILD WRISTBAND — ESP32-C3 MINI\n");
    Serial.printf("# [LOG] Wristband ID: %d | Protocol: v%d (0x%04X)\n", WRISTBAND_ID, SHAPNEST_PROTOCOL_VERSION, SHAPNEST_PROTOCOL_ID);
    Serial.printf("# [LOG] Signal Conditioning: Dual-Regime 1D Adaptive Kalman Filter\n");
    Serial.printf("# [LOG] Distance Bounds: %.2f m to %.2f m\n", SHAPNEST_DISTANCE_MIN_CM / 100.0f, SHAPNEST_DISTANCE_MAX_CM / 100.0f);
    Serial.println("==================================================");

    reset_node_trackers();
    initialize_ble_subsystem();

    assemble_uplink_payload();
    pAdvertising->start();

#if defined(NIMBLE_CPP_VERSION_MAJOR) && (NIMBLE_CPP_VERSION_MAJOR >= 2)
    pScan->start(0, false, true);
#else
    pScan->start(0, scanCompleteCB, false);
#endif

    blink_led(WRISTBAND_ID, 100);
    Serial.println("# [LOG] Wristband Engine ONLINE — Pure BLE Dual-Regime Kalman Filter active.");
}

// ============================================================================
// MAIN LOOP: CONTINUOUS PROCESSING CYCLE (4 Hz Update Rate)
// ============================================================================
void loop() {
    uint32_t now = millis();

    // 1. Handle bench-test Serial commands
    handle_serial_commands();

    // 2. Compute multi-stage filtered distance for all nodes
    process_signal_conditioning(now);

    // 3. Assemble fresh telemetry payload and update advertising packet
    assemble_uplink_payload();

    // 4. Ensure advertising remains active
    if (!pAdvertising->isAdvertising()) {
        pAdvertising->start();
    }

    // 4b. Ensure scanner remains active (scanner watchdog)
    if (pScan != nullptr && !pScan->isScanning()) {
#if defined(NIMBLE_CPP_VERSION_MAJOR) && (NIMBLE_CPP_VERSION_MAJOR >= 2)
        pScan->start(0, false, true);
#else
        pScan->start(0, scanCompleteCB, false);
#endif
    }

    // 5. Diagnostic Logging (Every 3 seconds)
    if (now - lastDiagnosticLogTime >= 3000) {
        lastDiagnosticLogTime = now;
        print_diagnostic_heartbeat(now);
    }

    delay(100); // 10 Hz telemetry refresh (100 ms) for high-speed reading & rapid offline response
}

// ============================================================================
// BLE SUBSYSTEM INITIALIZATION
// ============================================================================
static void initialize_ble_subsystem() {
    NimBLEDevice::init("SHAPNEST_WB1");
    NimBLEDevice::setPower(ESP_PWR_LVL_P9, ESP_BLE_PWR_TYPE_ADV);
    NimBLEDevice::setPower(ESP_PWR_LVL_P9, ESP_BLE_PWR_TYPE_DEFAULT);

    // 1. Configure Scanner (80% continuous duty cycle)
    pScan = NimBLEDevice::getScan();
#if defined(NIMBLE_CPP_VERSION_MAJOR) && (NIMBLE_CPP_VERSION_MAJOR >= 2)
    pScan->setScanCallbacks(&scanCallbacks, false);
#else
    pScan->setAdvertisedDeviceCallbacks(&scanCallbacks, false);
#endif
    pScan->setActiveScan(false); // Passive scanning
    pScan->setInterval(64);      // 40 ms interval
    pScan->setWindow(50);        // 31.25 ms window (78.1% duty cycle)
    pScan->setDuplicateFilter(false);

    // 2. Configure Broadcaster (Uplink to Phone / Central Hub)
    pAdvertising = NimBLEDevice::getAdvertising();

#if defined(NIMBLE_CPP_VERSION_MAJOR) && (NIMBLE_CPP_VERSION_MAJOR >= 2)
    pAdvertising->setConnectable(true);
#else
    pAdvertising->setAdvertisementType(BLE_GAP_CONN_MODE_UND);
#endif

    // Fast 40 ms advertising interval (25 Hz)
    pAdvertising->setMinInterval(64);
    pAdvertising->setMaxInterval(64);

    // 3. Scan Response Data (Broadcasts full device name "SHAPNEST_WB1")
    NimBLEAdvertisementData scanRespData;
    scanRespData.setName("SHAPNEST_WB1");
    pAdvertising->setScanResponseData(scanRespData);
}

// ============================================================================
// RESET NODE TRACKERS
// ============================================================================
static void reset_node_trackers() {
    for (uint8_t i = 0; i < SHAPNEST_MAX_NODES; i++) {
        nodeTrackers[i].sampleHead              = 0;
        nodeTrackers[i].sampleCount             = 0;
        nodeTrackers[i].samplesSinceLastProcess = 0;
        nodeTrackers[i].lockedDistanceM         = 0.0f;
        nodeTrackers[i].deadbandBreachCount     = 0;
        nodeTrackers[i].smoothDistanceM         = 0.0f;
        nodeTrackers[i].calibratedRefA          = SHAPNEST_DEFAULT_REF_RSSI_1M;
        nodeTrackers[i].pathLossExpX10          = SHAPNEST_DEFAULT_PATH_LOSS_EXP_X10;
        nodeTrackers[i].manualCalOverride       = false;
        nodeTrackers[i].lastSeenMs              = 0;
        nodeTrackers[i].state                   = SHAPNEST_NODE_STATE_OFFLINE;
        nodeTrackers[i].distanceCm              = SHAPNEST_DISTANCE_OFFLINE_CM;
        nodeTrackers[i].filteredRssi            = SHAPNEST_RSSI_OFFLINE;
        nodeTrackers[i].kalmanRssi.reset();
    }
}

// ============================================================================
// MULTI-STAGE SIGNAL CONDITIONING & DISTANCE ESTIMATION
// ============================================================================
static void process_signal_conditioning(uint32_t now) {
    portENTER_CRITICAL(&filterMux);

    for (uint8_t i = 0; i < SHAPNEST_MAX_NODES; i++) {
        NodeTracker* n = &nodeTrackers[i];

        // 1. Evaluate Node Staleness State Machine
        uint32_t ageMs = (n->lastSeenMs == 0) ? 999999 : ((now >= n->lastSeenMs) ? (now - n->lastSeenMs) : 0);

        if (n->lastSeenMs == 0 || ageMs > SHAPNEST_NODE_OFFLINE_TIMEOUT_MS) {
            n->state                   = SHAPNEST_NODE_STATE_OFFLINE;
            n->distanceCm              = SHAPNEST_DISTANCE_OFFLINE_CM;
            n->filteredRssi            = SHAPNEST_RSSI_OFFLINE;
            n->lockedDistanceM         = 0.0f;
            n->deadbandBreachCount     = 0;
            n->smoothDistanceM         = 0.0f;
            n->sampleCount             = 0;
            n->sampleHead              = 0;
            n->samplesSinceLastProcess = 0;
            n->kalmanRssi.reset();
            continue;
        } else if (ageMs >= SHAPNEST_NODE_ACTIVE_TIMEOUT_MS) {
            n->state = SHAPNEST_NODE_STATE_STALE;
            // Retain last validated distance and RSSI while stale; do NOT recalculate from old data
            continue;
        } else {
            n->state = SHAPNEST_NODE_STATE_ACTIVE;
        }

        // Only process if fresh samples arrived since last cycle
        if (n->samplesSinceLastProcess == 0) {
            continue;
        }
        n->samplesSinceLastProcess = 0;

        // 2. Extract recent valid samples from rolling circular buffer (within 400ms)
        int8_t tempSort[ROLLING_SAMPLE_CAPACITY];
        uint8_t validCount = 0;

        for (uint8_t s = 0; s < n->sampleCount; s++) {
            uint32_t sampleTs = n->sampleBuffer[s].timestampMs;
            uint32_t sampleAge = (now >= sampleTs) ? (now - sampleTs) : 0;
            if (sampleAge <= 400) {
                tempSort[validCount++] = n->sampleBuffer[s].rssi;
            }
        }

        if (validCount > 0) {
            std::sort(tempSort, tempSort + validCount);
            int8_t medianRssi = tempSort[validCount / 2];

            // 3. In-Window Impulse Outlier Rejection (if >= 3 samples available)
            if (validCount >= 3) {
                int8_t inlierSamples[ROLLING_SAMPLE_CAPACITY];
                uint8_t inlierCount = 0;
                for (uint8_t s = 0; s < validCount; s++) {
                    if (abs((int)tempSort[s] - (int)medianRssi) <= IMPULSE_OUTLIER_THRESH) {
                        inlierSamples[inlierCount++] = tempSort[s];
                    }
                }
                if (inlierCount > 0) {
                    medianRssi = inlierSamples[inlierCount / 2];
                }
            }

            // 4. Dual-Regime 1D Adaptive Kalman Filter for RSSI
            float kRssi = n->kalmanRssi.update((float)medianRssi);
            n->filteredRssi = (int8_t)roundf(kRssi);

            // 5. Calibrated Log-Distance Path Loss Model Calculation
            // d = 10 ^ ((A - RSSI) / (10 * n))
            float refA = (n->calibratedRefA < 0 && n->calibratedRefA >= -100) ? (float)n->calibratedRefA : -59.0f;
            float expN = (n->pathLossExpX10 >= 10 && n->pathLossExpX10 <= 50) ? (n->pathLossExpX10 / 10.0f) : 2.2f;

            float exponent = (refA - kRssi) / (10.0f * expN);
            float distMeters = powf(10.0f, exponent);

            // 6. Operational Boundary Clamping [0.15 m to 8.00 m]
            if (distMeters < (SHAPNEST_DISTANCE_MIN_CM / 100.0f)) {
                distMeters = SHAPNEST_DISTANCE_MIN_CM / 100.0f;
            } else if (distMeters > (SHAPNEST_DISTANCE_MAX_CM / 100.0f)) {
                distMeters = SHAPNEST_DISTANCE_MAX_CM / 100.0f;
            }

            // 7. Ultra-Stable Distance Hysteresis Dead-Band & Smooth Motion Tracking
            if (n->lockedDistanceM <= 0.0f || n->kalmanRssi.warmupCycles > 0) {
                n->lockedDistanceM     = distMeters;
                n->smoothDistanceM     = distMeters;
                n->deadbandBreachCount = 0;
            }

            float db;
            if (n->lockedDistanceM <= 0.50f) {
                db = 0.04f; // 4 cm in critical danger
            } else if (n->lockedDistanceM <= 1.20f) {
                db = 0.08f; // 8 cm in danger zone
            } else if (n->lockedDistanceM <= 2.50f) {
                db = 0.16f; // 16 cm in warning zone
            } else {
                db = fminf(0.35f, 0.08f * n->lockedDistanceM); // up to 35 cm in safe zone
            }

            float diffFromLocked = fabsf(distMeters - n->lockedDistanceM);

            if (n->kalmanRssi.motionState == FW_MOTION_STATIONARY) {
                // Stationary: must breach deadband for 2 consecutive cycles OR exceed 1.5x deadband to unlock
                if (diffFromLocked >= db) {
                    n->deadbandBreachCount++;
                    if (n->deadbandBreachCount >= 2 || diffFromLocked >= 1.5f * db) {
                        n->lockedDistanceM = distMeters;
                        n->deadbandBreachCount = 0;
                    }
                } else {
                    if (n->deadbandBreachCount > 0) {
                        n->deadbandBreachCount--;
                    }
                }
                n->smoothDistanceM = n->lockedDistanceM;
            } else {
                // Moving / Fast Attack: responsive tracking via EMA prevents jerky jumping
                n->deadbandBreachCount = 0;
                float alpha = (n->kalmanRssi.motionState == FW_MOTION_FAST_ATTACK) ? 0.80f : 0.60f;
                n->smoothDistanceM = alpha * distMeters + (1.0f - alpha) * n->smoothDistanceM;
                n->lockedDistanceM = n->smoothDistanceM;
            }

            n->distanceCm = (uint16_t)roundf(n->smoothDistanceM * 100.0f);
        }
    }

    portEXIT_CRITICAL(&filterMux);
}

// ============================================================================
// ASSEMBLE 23-BYTE TELEMETRY PAYLOAD (18 Bytes Mfr Payload)
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

    // Load packed 18-byte payload into a FRESH advertisement object (Total = 28 bytes < 31 byte limit)
    NimBLEAdvertisementData freshAdvData;
    freshAdvData.setFlags(0x06); // LE General Discoverable | BR/EDR Not Supported
    freshAdvData.setManufacturerData(std::string((const char*)&uplinkPayload, sizeof(uplinkPayload)));
    freshAdvData.setShortName("WB1");

    // In-place atomic update of BLE advertisement data without stopping the radio
    pAdvertising->setAdvertisementData(freshAdvData);
}

// ============================================================================
// DIAGNOSTIC SERIAL LOGGING
// ============================================================================
static void print_diagnostic_heartbeat(uint32_t now) {
    Serial.printf("# [LOG] WB#%d Uplink Seq: %u | Uptime: %lu s\n", WRISTBAND_ID, uplinkSeq, now / 1000UL);
    for (uint8_t i = 0; i < SHAPNEST_MAX_NODES; i++) {
        NodeTracker* n = &nodeTrackers[i];
        if (n->state == SHAPNEST_NODE_STATE_ACTIVE) {
            Serial.printf("# [LOG]   NODE_0%d: %.2f m | Filtered RSSI: %d dBm | Samples: %u | Motion: %s | RefA@1m: %d dBm | n: %.1f\n",
                          i + 1, shapnest_cm_to_meters(n->distanceCm), n->filteredRssi, n->sampleCount,
                          (n->kalmanRssi.motionState == 2 ? "FAST_ATTACK" : (n->kalmanRssi.motionState == 1 ? "MOVING" : "STATIONARY")),
                          n->calibratedRefA, (n->pathLossExpX10 > 0 ? n->pathLossExpX10 / 10.0f : 2.2f));
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
    digitalWrite(STATUS_LED_PIN, LOW); // Active-LOW: keep ON
}

// ============================================================================
// INTERACTIVE BENCH-TEST SERIAL COMMANDS
// ============================================================================
static void handle_serial_commands() {
    if (!Serial.available()) return;

    String line = Serial.readStringUntil('\n');
    line.trim();
    if (line.isEmpty()) return;

    if (line.equalsIgnoreCase("STATUS") || line.equalsIgnoreCase("HELP")) {
        Serial.println("==================================================");
        Serial.printf("# [STATUS] Child Wristband #%d | Seq: %u | Uptime: %lu s\n", WRISTBAND_ID, uplinkSeq, millis() / 1000UL);
        for (uint8_t i = 0; i < SHAPNEST_MAX_NODES; i++) {
            NodeTracker* n = &nodeTrackers[i];
            Serial.printf("# [NODE_%02d] %s | Dist: %.2f m (%u cm) | RSSI: %d dBm | Samples: %u | RefA: %d dBm%s | n: %.1f | Motion: %s\n",
                          i + 1,
                          shapnest_state_to_string(n->state),
                          shapnest_cm_to_meters(n->distanceCm),
                          n->distanceCm,
                          n->filteredRssi,
                          n->sampleCount,
                          n->calibratedRefA,
                          (n->manualCalOverride ? " [LOCKED]" : ""),
                          (n->pathLossExpX10 > 0 ? n->pathLossExpX10 / 10.0f : 2.2f),
                          (n->kalmanRssi.motionState == 2 ? "FAST_ATTACK" : (n->kalmanRssi.motionState == 1 ? "MOVING" : "STATIONARY")));
        }
        Serial.println("# [HELP] Commands: 'STATUS', 'CAL <node_id> <refA>', 'EXP <node_id> <n_x10>', 'RESET <node_id>'");
        Serial.println("==================================================");
    } else if (line.startsWith("CAL") || line.startsWith("SET_CAL")) {
        int firstSpace = line.indexOf(' ');
        if (firstSpace >= 0) {
            int secondSpace = line.indexOf(' ', firstSpace + 1);
            if (secondSpace >= 0) {
                int nodeId = line.substring(firstSpace + 1, secondSpace).toInt();
                int calA = line.substring(secondSpace + 1).toInt();
                if (nodeId >= SHAPNEST_NODE_ID_MIN && nodeId <= SHAPNEST_NODE_ID_MAX && calA < 0 && calA >= -100) {
                    portENTER_CRITICAL(&filterMux);
                    nodeTrackers[nodeId - 1].calibratedRefA = (int8_t)calA;
                    nodeTrackers[nodeId - 1].manualCalOverride = true;
                    portEXIT_CRITICAL(&filterMux);
                    Serial.printf("# [CMD] Node %d Calibrated RefA set to %d dBm (Locked)\n", nodeId, calA);
                }
            }
        }
    } else if (line.startsWith("EXP") || line.startsWith("SET_EXP")) {
        int firstSpace = line.indexOf(' ');
        if (firstSpace >= 0) {
            int secondSpace = line.indexOf(' ', firstSpace + 1);
            if (secondSpace >= 0) {
                int nodeId = line.substring(firstSpace + 1, secondSpace).toInt();
                int expX10 = line.substring(secondSpace + 1).toInt();
                if (nodeId >= SHAPNEST_NODE_ID_MIN && nodeId <= SHAPNEST_NODE_ID_MAX && expX10 >= 10 && expX10 <= 50) {
                    portENTER_CRITICAL(&filterMux);
                    nodeTrackers[nodeId - 1].pathLossExpX10 = (uint8_t)expX10;
                    nodeTrackers[nodeId - 1].manualCalOverride = true;
                    portEXIT_CRITICAL(&filterMux);
                    Serial.printf("# [CMD] Node %d Path Loss Exp set to %.1f (Locked)\n", nodeId, expX10 / 10.0f);
                }
            }
        }
    } else if (line.startsWith("RESET")) {
        int spaceIdx = line.indexOf(' ');
        if (spaceIdx >= 0) {
            int nodeId = line.substring(spaceIdx + 1).toInt();
            if (nodeId >= SHAPNEST_NODE_ID_MIN && nodeId <= SHAPNEST_NODE_ID_MAX) {
                portENTER_CRITICAL(&filterMux);
                uint8_t idx = nodeId - 1;
                nodeTrackers[idx].kalmanRssi.reset();
                nodeTrackers[idx].lockedDistanceM = 0.0f;
                nodeTrackers[idx].smoothDistanceM = 0.0f;
                nodeTrackers[idx].deadbandBreachCount = 0;
                nodeTrackers[idx].sampleCount = 0;
                nodeTrackers[idx].sampleHead = 0;
                nodeTrackers[idx].calibratedRefA = SHAPNEST_DEFAULT_REF_RSSI_1M;
                nodeTrackers[idx].pathLossExpX10 = SHAPNEST_DEFAULT_PATH_LOSS_EXP_X10;
                nodeTrackers[idx].manualCalOverride = false;
                portEXIT_CRITICAL(&filterMux);
                Serial.printf("# [CMD] Node %d Filter & Calibration RESET\n", nodeId);
            }
        }
    }
}

