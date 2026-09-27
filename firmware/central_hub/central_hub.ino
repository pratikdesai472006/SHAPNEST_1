/**
 * ============================================================================
 * SHAPNEST — PHASE 1 CENTRAL HUB GATEWAY FIRMWARE
 * Central Hub Firmware (ESP32-WROOM) — Telemetry Bridge
 * 
 * Target Board: ESP32-WROOM-32 / ESP32 Dev Module
 * CPU:          Dual-Core Xtensa LX6 @ 240 MHz
 * Framework:    Arduino IDE / PlatformIO
 * Library:      NimBLE-Arduino (by h2zero)
 * 
 * DESCRIPTION:
 *   Acts as the central hardware receiver and bridge between the BLE radio
 *   spectrum and the Display Application.
 *   - Core 0: Runs continuous, non-blocking NimBLE passive scanner.
 *             Filters strictly for 31-byte wristband telemetry frames.
 *   - Core 1: Formats validated wristband telemetry into single-line NDJSON frames
 *             and outputs to USB Serial at 115,200 baud.
 *   - Transports the authoritative distance measurements calculated by the Wristband.
 *     Does NOT recalculate or mutate distance values.
 *   - Emits structured diagnostic messages prefixed with "# [LOG]",
 *     "# [WARN]", or "# [ERROR]".
 * ============================================================================
 */

#include <Arduino.h>
#include <NimBLEDevice.h>
#include "shapnest_protocol.h"

// ============================================================================
// CONFIGURATION CONSTANTS
// ============================================================================
#define TARGET_WRISTBAND_ID         SHAPNEST_TARGET_WRISTBAND_ID  // Track Child Wristband #1
#define SERIAL_OUTPUT_INTERVAL_MS   1000                          // 1 Hz Serial telemetry rate
#define HUB_STATUS_LED_PIN          2                             // Standard ESP32 DevKit blue LED (GPIO 2)

// ============================================================================
// GLOBAL STATE & THREAD-SAFE BUFFERS
// ============================================================================
static NimBLEScan*                  pBLEScan = nullptr;

// Shared Wristband Ingestion Buffer
static portMUX_TYPE                 hubMux = portMUX_INITIALIZER_UNLOCKED;
static shapnest_wristband_payload_t latestWristbandPayload;
static volatile bool                hasNewWristbandPacket = false;
static volatile uint32_t            lastWristbandRxTimestamp = 0;
static volatile int8_t              lastWristbandRssi = 0;

// Hub Telemetry Sequence Tracking
static uint32_t                     hubSerialSequence = 0;
static uint32_t                     lastSerialOutputTime = 0;
static bool                         wristbandWasOnline = false;

// Pre-allocated JSON serialization buffer to prevent heap fragmentation
static char                         jsonBuffer[768];

// ============================================================================
// FUNCTION DECLARATIONS
// ============================================================================
static void initialize_ble_scanner();
static void process_serial_telemetry();
static void format_and_send_ndjson(bool isWristbandAlive, uint32_t wbAgeMs);
static void blink_led(uint8_t count, uint16_t duration_ms);

// ============================================================================
static void handle_wristband_advertisement(NimBLEAdvertisedDevice* advertisedDevice) {
    // Fast-path: Check manufacturer data presence
    if (!advertisedDevice->haveManufacturerData()) {
        return;
    }

    std::string mfrData = advertisedDevice->getManufacturerData();
    if (mfrData.length() < sizeof(shapnest_wristband_payload_t)) {
        return;
    }

    const shapnest_wristband_payload_t* pPayload = 
        reinterpret_cast<const shapnest_wristband_payload_t*>(mfrData.data());

    // Protocol & Frame Validation Gate (< 5 microseconds)
    if (pPayload->company_id != SHAPNEST_PROTOCOL_ID) {
        return; // Not a SHAPNEST frame
    }

    if (pPayload->frame_type != SHAPNEST_FRAME_TYPE_WRISTBAND_TEL) {
        return; // Not a wristband telemetry frame
    }

    if (pPayload->wristband_id != TARGET_WRISTBAND_ID) {
        return; // Foreign wristband ID
    }

    // Thread-safe copy into shared buffer
    portENTER_CRITICAL(&hubMux);
    memcpy(&latestWristbandPayload, pPayload, sizeof(shapnest_wristband_payload_t));
    hasNewWristbandPacket = true;
    lastWristbandRxTimestamp = millis();
    lastWristbandRssi = advertisedDevice->getRSSI();
    portEXIT_CRITICAL(&hubMux);
}

#if defined(NIMBLE_CPP_VERSION_MAJOR) && (NIMBLE_CPP_VERSION_MAJOR >= 2)
class WristbandScanCallbacks : public NimBLEScanCallbacks {
    void onDiscovered(const NimBLEAdvertisedDevice* advertisedDevice) override {}
    void onResult(const NimBLEAdvertisedDevice* advertisedDevice) override {
        handle_wristband_advertisement(const_cast<NimBLEAdvertisedDevice*>(advertisedDevice));
    }
};
#else
class WristbandScanCallbacks : public NimBLEAdvertisedDeviceCallbacks {
    void onResult(NimBLEAdvertisedDevice* advertisedDevice) override {
        handle_wristband_advertisement(advertisedDevice);
    }
};
#endif

static WristbandScanCallbacks scanCallbacks;

#if defined(NIMBLE_CPP_VERSION_MAJOR) && (NIMBLE_CPP_VERSION_MAJOR >= 2)
static void hubScanCompleteCB(const NimBLEScanResults& results, int reason) {
    (void)results;
    (void)reason;
}
#else
static void hubScanCompleteCB(NimBLEScanResults results) {
    (void)results;
}
#endif

// ============================================================================
// CORE 0 DEDICATED FREERTOS BLE SCANNER TASK
// ============================================================================
static void hub_scan_task(void* pvParameters) {
    (void)pvParameters;

#if defined(NIMBLE_CPP_VERSION_MAJOR) && (NIMBLE_CPP_VERSION_MAJOR >= 2)
    pBLEScan->start(0, false, true);
#else
    pBLEScan->start(0, hubScanCompleteCB, false);
#endif

    for (;;) {
        vTaskDelay(pdMS_TO_TICKS(1000));
        // Liveness watchdog: automatically restart scan if controller ever halts it
        if (!pBLEScan->isScanning()) {
#if defined(NIMBLE_CPP_VERSION_MAJOR) && (NIMBLE_CPP_VERSION_MAJOR >= 2)
            pBLEScan->start(0, false, true);
#else
            pBLEScan->start(0, hubScanCompleteCB, false);
#endif
        }
    }
}

// ============================================================================
// SETUP (Runs on Core 1)
// ============================================================================
void setup() {
    Serial.begin(SHAPNEST_SERIAL_BAUD_RATE);
    delay(1000); // Allow host COM port to settle

    if (HUB_STATUS_LED_PIN >= 0) {
        pinMode(HUB_STATUS_LED_PIN, OUTPUT);
        digitalWrite(HUB_STATUS_LED_PIN, LOW);
    }

    // Print Structured Diagnostic Boot Banner
    Serial.println();
    Serial.println("==================================================");
    Serial.printf("# [LOG] SHAPNEST CENTRAL HUB GATEWAY — ESP32-WROOM\n");
    Serial.printf("# [LOG] Protocol: v%d | Magic ID: 0x%04X ('SN')\n", SHAPNEST_PROTOCOL_VERSION, SHAPNEST_PROTOCOL_ID);
    Serial.printf("# [LOG] Target Wristband ID: %d\n", TARGET_WRISTBAND_ID);
    Serial.printf("# [LOG] Max Monitored Nodes: %d\n", SHAPNEST_MAX_NODES);
    Serial.printf("# [LOG] Serial Interface: USB UART @ %d baud (NDJSON)\n", SHAPNEST_SERIAL_BAUD_RATE);
    Serial.printf("# [LOG] Core 0: NimBLE Continuous Scanner | Core 1: Serializer\n");
    Serial.println("==================================================");

    initialize_ble_scanner();

    // Spawn Core 0 Dedicated FreeRTOS Scan Task (Non-blocking, isolated on Core 0)
    xTaskCreatePinnedToCore(
        hub_scan_task,
        "HubBLEScan",
        4096,
        NULL,
        1,        // Normal priority
        NULL,
        0         // Pinned strictly to Core 0
    );

    blink_led(3, 100);
    Serial.println("# [LOG] Central Hub ONLINE — Listening for Child Wristband telemetry...");
}

// ============================================================================
// MAIN LOOP (Runs on Core 1)
// ============================================================================
void loop() {
    uint32_t now = millis();

    // Enforce 1 Hz Serial Telemetry Output Rate
    if (now - lastSerialOutputTime >= SERIAL_OUTPUT_INTERVAL_MS) {
        lastSerialOutputTime = now;
        process_serial_telemetry();
    }

    delay(10);
}

// ============================================================================
// BLE SCANNER INITIALIZATION
// ============================================================================
static void initialize_ble_scanner() {
    NimBLEDevice::init("SHAPNEST_HUB");

    pBLEScan = NimBLEDevice::getScan();
#if defined(NIMBLE_CPP_VERSION_MAJOR) && (NIMBLE_CPP_VERSION_MAJOR >= 2)
    pBLEScan->setScanCallbacks(&scanCallbacks, false);
#else
    pBLEScan->setAdvertisedDeviceCallbacks(&scanCallbacks, false);
#endif
    pBLEScan->setActiveScan(false);

    // 100% Continuous Duty Cycle on Hub
    pBLEScan->setInterval(160);
    pBLEScan->setWindow(160);
    pBLEScan->setDuplicateFilter(false);
}

// ============================================================================
// SERIAL TELEMETRY PROCESSING & DISPATCH (Core 1)
// ============================================================================
static void process_serial_telemetry() {
    uint32_t now = millis();
    shapnest_wristband_payload_t localCopy;
    bool packetFresh = false;
    uint32_t rxTimestamp = 0;

    // Snapshot shared buffer atomically
    portENTER_CRITICAL(&hubMux);
    if (hasNewWristbandPacket) {
        memcpy(&localCopy, &latestWristbandPayload, sizeof(shapnest_wristband_payload_t));
        hasNewWristbandPacket = false;
        packetFresh = true;
    }
    rxTimestamp = lastWristbandRxTimestamp;
    portEXIT_CRITICAL(&hubMux);

    // Evaluate Wristband Staleness & Connection State
    uint32_t wbAgeMs = (rxTimestamp > 0) ? (now - rxTimestamp) : 999999;
    bool isWristbandOnline = (rxTimestamp > 0) && (wbAgeMs < SHAPNEST_WRISTBAND_OFFLINE_TIMEOUT_MS);

    // State transition diagnostic alerts
    if (isWristbandOnline && !wristbandWasOnline) {
        wristbandWasOnline = true;
        Serial.printf("# [LOG] Wristband #%d CONNECTED (Signal: %d dBm | Age: %u ms)\n", 
                      TARGET_WRISTBAND_ID, lastWristbandRssi, wbAgeMs);
        if (HUB_STATUS_LED_PIN >= 0) digitalWrite(HUB_STATUS_LED_PIN, HIGH);
    } else if (!isWristbandOnline && wristbandWasOnline) {
        wristbandWasOnline = false;
        Serial.printf("# [WARN] Wristband #%d LOST / OUT OF RANGE (> %d ms silence)\n", 
                      TARGET_WRISTBAND_ID, SHAPNEST_WRISTBAND_OFFLINE_TIMEOUT_MS);
        if (HUB_STATUS_LED_PIN >= 0) digitalWrite(HUB_STATUS_LED_PIN, LOW);
    }

    // Format and transmit exact NDJSON line to Web Application
    format_and_send_ndjson(isWristbandOnline, wbAgeMs);
}

// ============================================================================
// NDJSON SERIALIZER
// ============================================================================
static void format_and_send_ndjson(bool isWristbandAlive, uint32_t wbAgeMs) {
    hubSerialSequence++;

    int offset = 0;

    // JSON Header
    offset += snprintf(jsonBuffer + offset, sizeof(jsonBuffer) - offset,
        "{\"v\":%d,\"hub_status\":\"ONLINE\",\"seq\":%u,\"wb\":{\"id\":%d,\"status\":\"%s\",\"age_ms\":%u,\"seq\":%u},\"nodes\":[",
        SHAPNEST_PROTOCOL_VERSION,
        hubSerialSequence,
        TARGET_WRISTBAND_ID,
        isWristbandAlive ? "ONLINE" : "OFFLINE",
        isWristbandAlive ? wbAgeMs : 999999,
        isWristbandAlive ? latestWristbandPayload.sequence : 0
    );

    // Iterate across monitored nodes (1..3)
    for (uint8_t i = 0; i < SHAPNEST_MAX_NODES; i++) {
        uint8_t expectedNodeId = i + 1;

        if (isWristbandAlive) {
            const shapnest_node_telemetry_block_t* nBlock = &latestWristbandPayload.nodes[i];
            uint8_t  nodeId = SHAPNEST_UNPACK_ID(nBlock->id_and_state);
            shapnest_node_state_t state = SHAPNEST_UNPACK_STATE(nBlock->id_and_state);

            // Sanity check: Ensure node block matches expected ID
            if (nodeId == expectedNodeId && state != SHAPNEST_NODE_STATE_OFFLINE && nBlock->distance_cm != SHAPNEST_DISTANCE_OFFLINE_CM) {
                float dist_m = shapnest_cm_to_meters(nBlock->distance_cm);
                const char* stateStr = (nBlock->distance_cm >= SHAPNEST_DISTANCE_MAX_CM) ? "OUT_OF_RANGE" : shapnest_state_to_string(state);
                offset += snprintf(jsonBuffer + offset, sizeof(jsonBuffer) - offset,
                    "{\"id\":%u,\"dist_m\":%.2f,\"rssi\":%d,\"state\":\"%s\"}%s",
                    nodeId,
                    dist_m,
                    nBlock->filtered_rssi,
                    stateStr,
                    (i < SHAPNEST_MAX_NODES - 1) ? "," : ""
                );
            } else {
                offset += snprintf(jsonBuffer + offset, sizeof(jsonBuffer) - offset,
                    "{\"id\":%u,\"dist_m\":null,\"rssi\":null,\"state\":\"OFFLINE\"}%s",
                    expectedNodeId,
                    (i < SHAPNEST_MAX_NODES - 1) ? "," : ""
                );
            }
        } else {
            offset += snprintf(jsonBuffer + offset, sizeof(jsonBuffer) - offset,
                "{\"id\":%u,\"dist_m\":null,\"rssi\":null,\"state\":\"OFFLINE\"}%s",
                expectedNodeId,
                (i < SHAPNEST_MAX_NODES - 1) ? "," : ""
            );
        }
    }

    offset += snprintf(jsonBuffer + offset, sizeof(jsonBuffer) - offset, "]}\n");
    Serial.print(jsonBuffer);
}

// ============================================================================
// HELPER: BLINK STATUS LED
// ============================================================================
static void blink_led(uint8_t count, uint16_t duration_ms) {
    if (HUB_STATUS_LED_PIN < 0) return;

    for (uint8_t i = 0; i < count; i++) {
        digitalWrite(HUB_STATUS_LED_PIN, HIGH);
        delay(duration_ms);
        digitalWrite(HUB_STATUS_LED_PIN, LOW);
        if (i < count - 1) {
            delay(duration_ms);
        }
    }
}
