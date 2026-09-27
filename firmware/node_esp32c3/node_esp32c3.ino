/**
 * ============================================================================
 * SHAPNEST — PHASE 1 PROXIMITY BEACON FIRMWARE
 * Node Firmware (ESP32-C3 Mini) — Pure Autonomous Static Beaconing
 * 
 * Target Board: ESP32-C3 Mini / ESP32C3 Dev Module
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
 *   Acts as a pure autonomous, non-connectable BLE broadcaster (ADV_NONCONN_IND).
 *   The payload is loaded ONCE at boot into the hardware link-layer controller.
 *   Zero runtime buffer modifications or advertising restarts occur in loop().
 *   Transmits a 12-byte Legacy BLE beacon packet containing:
 *     - Company ID: 0x534E ('S', 'N')
 *     - Frame Type: 0x01 (NODE_BEACON)
 *     - Node ID: 1..5
 *     - Calibrated Reference RSSI at 1 meter (A)
 *     - Environmental Path-Loss Exponent (n x 10)
 *     - Boot Sequence Counter (static 0x00)
 * ============================================================================
 */

#include <Arduino.h>
#include <NimBLEDevice.h>
#include "shapnest_protocol.h"

// ============================================================================
// NODE CONFIGURATION (Configure per physical ESP32-C3 board before flashing)
// ============================================================================
#define NODE_ID                 1     // Set 1, 2, 3, 4, or 5 (e.g. 1 for NODE_01)
#define CALIBRATED_RSSI_1M    -59     // Measured RSSI at 1 meter in dBm
#define PATH_LOSS_EXP_X10      22     // Environmental factor n * 10 (22 = 2.2)
#define TX_POWER_DBM            3     // RF output power: +3 dBm
#define STATUS_LED_PIN          8     // Typical ESP32-C3 on-board LED GPIO (set -1 if none)

// Compile-time sanity check on configured Node ID
#if (NODE_ID < SHAPNEST_NODE_ID_MIN || NODE_ID > SHAPNEST_NODE_ID_MAX)
#error "NODE_ID must be configured between 1 and 5 for Phase 1!"
#endif

// ============================================================================
// GLOBAL STATE & OBJECTS
// ============================================================================
static NimBLEAdvertising*       pAdvertising = nullptr;
static shapnest_node_payload_t  nodePayload;
static NimBLEAdvertisementData  advData;
static uint32_t                 lastLogTime = 0;

// ============================================================================
// FUNCTION DECLARATIONS
// ============================================================================
static void initialize_autonomous_beacon();
static void blink_led(uint8_t count, uint16_t duration_ms);

// ============================================================================
// SETUP
// ============================================================================
void setup() {
    // 1. Initialize Serial Monitor (115200 baud)
    Serial.begin(SHAPNEST_SERIAL_BAUD_RATE);
    
    // Give USB CDC time to attach if opened in Serial Monitor
    delay(1000);

    // 2. Initialize optional Status LED
    if (STATUS_LED_PIN >= 0) {
        pinMode(STATUS_LED_PIN, OUTPUT);
        digitalWrite(STATUS_LED_PIN, LOW);
    }

    // 3. Print Structured Diagnostic Boot Banner
    Serial.println();
    Serial.println("==================================================");
    Serial.printf("# [LOG] SHAPNEST PROXIMITY BEACON — NODE_%02d\n", NODE_ID);
    Serial.printf("# [LOG] Mode: PURE AUTONOMOUS STATIC BEACON (Zero Runtime Updates)\n");
    Serial.printf("# [LOG] Protocol: v%d | Magic ID: 0x%04X ('SN')\n", SHAPNEST_PROTOCOL_VERSION, SHAPNEST_PROTOCOL_ID);
    Serial.printf("# [LOG] Calibrated RSSI @ 1m: %d dBm\n", CALIBRATED_RSSI_1M);
    Serial.printf("# [LOG] Environmental Exponent (n): %.1f (raw: %u)\n", PATH_LOSS_EXP_X10 / 10.0f, PATH_LOSS_EXP_X10);
    Serial.printf("# [LOG] Configured TX Power: +%d dBm\n", TX_POWER_DBM);
    Serial.printf("# [LOG] Autonomous Advertising Interval: %d ms\n", SHAPNEST_NODE_ADV_INTERVAL_MS);
    Serial.println("==================================================");

    // 4. Initialize and Start Autonomous BLE Hardware Beacon
    initialize_autonomous_beacon();

    // 5. Visual confirmation on boot
    blink_led(NODE_ID, 120);

    Serial.printf("# [LOG] NODE_%02d ACTIVE — Autonomous Hardware Link-Layer Broadcasting.\n", NODE_ID);
}

// ============================================================================
// MAIN LOOP (Zero runtime modifications to BLE advertising buffer)
// ============================================================================
void loop() {
    uint32_t now = millis();

    // Periodic Serial Diagnostic Heartbeat (every 10 seconds)
    // The BLE radio runs 100% autonomously in the link-layer hardware.
    if (now - lastLogTime >= 10000) {
        lastLogTime = now;
        Serial.printf("# [LOG] NODE_%02d Beacon Active | TX: +%d dBm | Ref@1m: %d dBm | n: %.1f | Uptime: %lu s\n",
                      NODE_ID,
                      TX_POWER_DBM,
                      CALIBRATED_RSSI_1M,
                      PATH_LOSS_EXP_X10 / 10.0f,
                      now / 1000UL);
    }

    // Yield CPU to FreeRTOS idle task to conserve power
    delay(1000);
}

// ============================================================================
// BLE BEACON INITIALIZATION (Loaded ONCE into Hardware Controller)
// ============================================================================
static void initialize_autonomous_beacon() {
    // Generate device name e.g. "SHAPNEST_N1"
    char deviceName[16];
    snprintf(deviceName, sizeof(deviceName), "SHAPNEST_N%d", NODE_ID);

    // Initialize NimBLE stack
    NimBLEDevice::init(deviceName);

    // Set physical TX output power to +3 dBm
    NimBLEDevice::setPower(ESP_PWR_LVL_P3);

    // Retrieve global advertising controller
    pAdvertising = NimBLEDevice::getAdvertising();

    // Populate binary manufacturer payload (Static Boot Configuration)
    nodePayload.company_id          = SHAPNEST_PROTOCOL_ID;
    nodePayload.frame_type          = SHAPNEST_FRAME_TYPE_NODE_BEACON;
    nodePayload.node_id             = (uint8_t)NODE_ID;
    nodePayload.calibrated_rssi_1m  = (int8_t)CALIBRATED_RSSI_1M;
    nodePayload.path_loss_exp_x10   = (uint8_t)PATH_LOSS_EXP_X10;
    nodePayload.sequence            = 0x00; // Static boot sequence

    // Build raw advertisement packet
    advData.setFlags(0x06); // LE General Discoverable + BR/EDR Not Supported
    advData.setManufacturerData(std::string((const char*)&nodePayload, sizeof(nodePayload)));

    // Configure advertising parameters
    pAdvertising->setAdvertisementData(advData);

    // Configure as non-connectable beacon (ADV_NONCONN_IND)
#if defined(NIMBLE_CPP_VERSION_MAJOR) && (NIMBLE_CPP_VERSION_MAJOR >= 2)
    pAdvertising->setConnectable(false);
#else
    pAdvertising->setAdvertisementType(BLE_GAP_CONN_MODE_NON);
#endif

    // Interval units: 0.625 ms (320 * 0.625ms = 200ms)
    const uint16_t intervalUnits = (SHAPNEST_NODE_ADV_INTERVAL_MS * 1000) / 625;
    pAdvertising->setMinInterval(intervalUnits);
    pAdvertising->setMaxInterval(intervalUnits);

    // Start continuous autonomous link-layer advertising
    pAdvertising->start();
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
