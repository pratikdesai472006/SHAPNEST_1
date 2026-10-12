/**
 * ============================================================================
 * SHAPNEST PHASE 2 — Physical Node: Door (Node ID 3)
 * Target: ESP32-C3 Super Mini / Dev Module
 * Sensor: Magnetic Reed Switch (Door Open / Close Detector)
 * 
 * Hardware Wiring:
 *   - Lead 1 of Reed Switch -> GPIO 2 (REED_SWITCH_PIN)
 *   - Lead 2 of Reed Switch -> GND
 *   - No external resistor required (uses ESP32-C3 internal INPUT_PULLUP)
 * 
 * Logic (Standard Normally-Open Security Contact):
 *   - Magnet Near (Door CLOSED) -> Switch closes to GND -> GPIO reads LOW (0)
 *   - Magnet Away (Door OPEN)   -> Switch opens          -> GPIO pulled HIGH (1)
 * ============================================================================
 */

#include <Arduino.h>
#include <NimBLEDevice.h>
#include "shapnest_protocol.h"

// ============================================================================
// HARDWARE & SENSOR PIN CONFIGURATION
// ============================================================================
#define NODE_ID                 3       // Node 3 (Door Anchor)
#define REED_SWITCH_PIN         2       // GPIO 2 for Magnetic Reed Switch
#define STATUS_LED_PIN          8       // GPIO 8 on-board blue LED (-1 if none)

// LED active level (ESP32-C3 Super Mini on-board LED is Active LOW)
#define LED_ACTIVE_LEVEL        LOW
#define LED_INACTIVE_LEVEL      HIGH

// Reed switch contact polarity:
// false = Standard NO (Normally Open): Magnet Near -> LOW (CLOSED), Magnet Away -> HIGH (OPEN)
// true  = NC (Normally Closed): Magnet Near -> HIGH, Magnet Away -> LOW
#define REED_SWITCH_INVERT_LOGIC false

// Calibration parameters
#define CALIBRATED_RSSI_1M    -59       // Reference RSSI at 1 meter in dBm
#define PATH_LOSS_EXP_X10      22       // Environmental factor n * 10 (2.2)
#define TX_POWER_DBM            9       // RF output power: +9 dBm
#define ADV_INTERVAL_MS        40       // High-density BLE advertisement interval (40ms = 25 Hz)

// Debounce timing
#define DEBOUNCE_DELAY_MS      30       // 30 ms debounce filter

// ============================================================================
// GLOBAL OBJECTS & STATE
// ============================================================================
static NimBLEAdvertising*       pAdvertising = nullptr;
static shapnest_node_payload_t  nodePayload;

static int                      lastReading = HIGH;
static int                      stableState = HIGH;
static uint32_t                 lastDebounceTime = 0;
static uint32_t                 lastLogTime = 0;

// ============================================================================
// FUNCTION DECLARATIONS
// ============================================================================
static void initialize_ble_beacon();
static void broadcast_door_state(bool isDoorOpen);
static void set_status_led(bool turnOn);
static void blink_led(uint8_t count, uint16_t duration_ms);

// ============================================================================
// LED CONTROL HELPER
// ============================================================================
static void set_status_led(bool turnOn) {
    if (STATUS_LED_PIN < 0) return;
    digitalWrite(STATUS_LED_PIN, turnOn ? LED_ACTIVE_LEVEL : LED_INACTIVE_LEVEL);
}

static void blink_led(uint8_t count, uint16_t duration_ms) {
    if (STATUS_LED_PIN < 0) return;
    for (uint8_t i = 0; i < count; i++) {
        set_status_led(true);
        delay(duration_ms);
        set_status_led(false);
        if (i < count - 1) {
            delay(duration_ms);
        }
    }
}

// ============================================================================
// BLE ADVERTISEMENT BROADCAST HELPER
// ============================================================================
static void broadcast_door_state(bool isDoorOpen) {
    nodePayload.sequence++;
    nodePayload.sensor_state = isDoorOpen ? SHAPNEST_DOOR_OPEN : SHAPNEST_DOOR_CLOSED;

    // Create a fresh NimBLEAdvertisementData object each time to avoid payload accumulation (>31 bytes)
    NimBLEAdvertisementData freshAdvData;
    freshAdvData.setFlags(0x06); // LE General Discoverable, BR/EDR Not Supported
    freshAdvData.setManufacturerData(std::string((const char*)&nodePayload, sizeof(nodePayload)));

    if (pAdvertising != nullptr) {
        pAdvertising->setAdvertisementData(freshAdvData);
        if (!pAdvertising->isAdvertising()) {
            pAdvertising->start();
        }
    }
}

// ============================================================================
// SETUP
// ============================================================================
void setup() {
    Serial.begin(SHAPNEST_SERIAL_BAUD_RATE);
    delay(1000); // Allow USB CDC time to attach

    // 1. Configure Reed Switch with Internal Pull-Up
    pinMode(REED_SWITCH_PIN, INPUT_PULLUP);

    // 2. Configure Status LED
    if (STATUS_LED_PIN >= 0) {
        pinMode(STATUS_LED_PIN, OUTPUT);
        set_status_led(false);
    }

    // 3. Initial Sensor Read
    int raw = digitalRead(REED_SWITCH_PIN);
    lastReading = raw;
    stableState = raw;
    bool isDoorOpen = REED_SWITCH_INVERT_LOGIC ? (stableState == LOW) : (stableState == HIGH);

    // 4. Initialize Status LED: ON when Door OPEN (alert), OFF when CLOSED (secure)
    set_status_led(isDoorOpen);

    // 5. Diagnostic Banner
    Serial.println();
    Serial.println("==================================================");
    Serial.printf("# [LOG] SHAPNEST DOOR ANCHOR — NODE_%02d\n", NODE_ID);
    Serial.printf("# [LOG] Sensor: Magnetic Reed Switch on GPIO %d\n", REED_SWITCH_PIN);
    Serial.printf("# [LOG] Initial Door State: %s (GPIO = %s, Raw = %d)\n",
                  isDoorOpen ? "OPEN [ALERT]" : "CLOSED [SECURE]",
                  (stableState == HIGH) ? "HIGH" : "LOW",
                  stableState);
    Serial.printf("# [LOG] Protocol: v%d | Magic ID: 0x%04X ('SN')\n",
                  SHAPNEST_PROTOCOL_VERSION, SHAPNEST_PROTOCOL_ID);
    Serial.printf("# [LOG] Ref@1m: %d dBm | n: %.1f | TX: +%d dBm\n",
                  CALIBRATED_RSSI_1M, PATH_LOSS_EXP_X10 / 10.0f, TX_POWER_DBM);
    Serial.println("==================================================");

    // 6. Initialize NimBLE Beacon
    initialize_ble_beacon();

    // 7. Visual boot confirmation
    blink_led(3, 80);
    set_status_led(isDoorOpen);

    Serial.printf("# [LOG] NODE_%02d ACTIVE — Door monitoring & BLE broadcasting online.\n", NODE_ID);
}

// ============================================================================
// MAIN LOOP
// ============================================================================
void loop() {
    uint32_t now = millis();

    // 1. Debounced Reed Switch Reading
    int currentReading = digitalRead(REED_SWITCH_PIN);

    if (currentReading != lastReading) {
        lastDebounceTime = now;
    }

    if ((now - lastDebounceTime) > DEBOUNCE_DELAY_MS) {
        if (currentReading != stableState) {
            stableState = currentReading;
            bool isDoorOpen = REED_SWITCH_INVERT_LOGIC ? (stableState == LOW) : (stableState == HIGH);

            // Broadcast the fresh state over BLE immediately
            broadcast_door_state(isDoorOpen);

            // Update on-board LED indicator (LED ON when door OPEN)
            set_status_led(isDoorOpen);

            Serial.printf("# [DOOR EVENT] Door changed -> %s | Seq: %u | GPIO%d: %s\n",
                          isDoorOpen ? "OPEN [ALERT]" : "CLOSED [SECURE]",
                          nodePayload.sequence,
                          REED_SWITCH_PIN,
                          (stableState == HIGH) ? "HIGH" : "LOW");
        }
    }
    lastReading = currentReading;

    // 2. Periodic Serial Heartbeat Log (Every 5 seconds)
    if (now - lastLogTime >= 5000) {
        lastLogTime = now;
        bool isDoorOpen = REED_SWITCH_INVERT_LOGIC ? (stableState == LOW) : (stableState == HIGH);
        Serial.printf("# [LOG] NODE_03 (Door) Heartbeat | Status: %s | GPIO%d: %d | Seq: %u | Uptime: %lu s\n",
                      isDoorOpen ? "OPEN" : "CLOSED",
                      REED_SWITCH_PIN,
                      stableState,
                      nodePayload.sequence,
                      now / 1000UL);
    }

    // 3. Ensure BLE advertising remains active in hardware controller
    if (pAdvertising != nullptr && !pAdvertising->isAdvertising()) {
        pAdvertising->start();
    }

    // 50 Hz loop for instantaneous physical response
    delay(20);
}

// ============================================================================
// BLE BEACON INITIALIZATION
// ============================================================================
static void initialize_ble_beacon() {
    char deviceName[16];
    snprintf(deviceName, sizeof(deviceName), "SHAPNEST_N%d", NODE_ID);

    NimBLEDevice::init(deviceName);
    NimBLEDevice::setPower(ESP_PWR_LVL_P9, ESP_BLE_PWR_TYPE_ADV);
    NimBLEDevice::setPower(ESP_PWR_LVL_P9, ESP_BLE_PWR_TYPE_DEFAULT);

    pAdvertising = NimBLEDevice::getAdvertising();

    nodePayload.company_id          = SHAPNEST_PROTOCOL_ID;
    nodePayload.frame_type          = SHAPNEST_FRAME_TYPE_NODE_BEACON;
    nodePayload.node_id             = (uint8_t)NODE_ID;
    nodePayload.calibrated_rssi_1m  = (int8_t)CALIBRATED_RSSI_1M;
    nodePayload.path_loss_exp_x10   = (uint8_t)PATH_LOSS_EXP_X10;
    nodePayload.sequence            = 0;

#if defined(NIMBLE_CPP_VERSION_MAJOR) && (NIMBLE_CPP_VERSION_MAJOR >= 2)
    pAdvertising->setConnectable(true);
#else
    pAdvertising->setAdvertisementType(BLE_GAP_CONN_MODE_UND);
#endif

    const uint16_t intervalUnits = (ADV_INTERVAL_MS * 1000) / 625;
    pAdvertising->setMinInterval(intervalUnits);
    pAdvertising->setMaxInterval(intervalUnits);

    NimBLEAdvertisementData scanRespData;
    scanRespData.setName(deviceName);
    pAdvertising->setScanResponseData(scanRespData);

    bool isDoorOpen = REED_SWITCH_INVERT_LOGIC ? (stableState == LOW) : (stableState == HIGH);
    broadcast_door_state(isDoorOpen);
}
