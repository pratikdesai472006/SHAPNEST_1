/**
 * ============================================================================
 * SHAPNEST PHASE 2 — Physical Node: Iron (Node ID 2)
 * Target: ESP32-C3 Super Mini / Dev Module
 * Sensor: DS18B20 Digital 1-Wire Temperature Sensor on GPIO 3
 *         (with automatic analog NTC thermistor fallback)
 * 
 * Hardware Wiring:
 *   - Red Wire   -> 3.3V (VCC)
 *   - Black Wire -> GND
 *   - Yellow Wire-> GPIO 3 (Data / 1-Wire)
 *   - Status LED -> GPIO 8 (On-board Blue LED, Active LOW)
 * 
 * Temperature Measurement:
 *   - Primary: DallasTemperature / OneWire digital sensor (DS18B20)
 *   - Non-blocking 10-bit conversion (~187ms) for fast 4 Hz sampling without BLE lag
 *   - Fallback: Calibrated ADC voltage measurement if analog NTC is connected
 *   - Ambient safe default (28°C) if disconnected
 *   - Interactive Serial override support (e.g. "TEMP 75" or "SET_TEMP 85")
 * 
 * Burn Hazard Safety Thresholds:
 *   - < 40°C: SAFE (Room / Cool Iron)
 *   - 40°C - 49°C: WARM (Warming or cooling down)
 *   - >= 50°C: HOT [ALERT] (High burn hazard, LED illuminated)
 * ============================================================================
 */

#include <Arduino.h>
#include <NimBLEDevice.h>
#include <OneWire.h>
#include <DallasTemperature.h>
#include <algorithm>
#include <cmath>
#include "shapnest_protocol.h"

// ============================================================================
// HARDWARE & SENSOR PIN CONFIGURATION
// ============================================================================
#define NODE_ID                     2       // Node 2 (Iron Anchor)
#define TEMP_SENSOR_PIN             9       // GPIO 9 (On-board hardware 10k pull-up resistor to 3.3V)
#define STATUS_LED_PIN              8       // GPIO 8 on-board blue LED (-1 if none)

// LED active level (ESP32-C3 Super Mini on-board LED is Active LOW)
#define LED_ACTIVE_LEVEL            LOW
#define LED_INACTIVE_LEVEL          HIGH

// Calibration parameters
#define CALIBRATED_RSSI_1M        -59       // Reference RSSI at 1 meter in dBm
#define PATH_LOSS_EXP_X10          22       // Environmental factor n * 10 (2.2)
#define TX_POWER_DBM                9       // RF output power: +9 dBm
#define ADV_INTERVAL_MS            40       // High-density BLE advertisement interval (40ms = 25 Hz)

// Sensor measurement timings
#define TEMP_SAMPLE_INTERVAL_MS   250       // 4 Hz temperature sampling
#define TEMP_FORCE_REFRESH_MS    1500       // Force BLE advertisement refresh at least every 1.5s

// ============================================================================
// GLOBAL OBJECTS & STATE
// ============================================================================
static NimBLEAdvertising*       pAdvertising = nullptr;
static shapnest_node_payload_t  nodePayload;

// 1-Wire & DallasTemperature objects
static OneWire                  oneWire(TEMP_SENSOR_PIN);
static DallasTemperature       sensors(&oneWire);
static bool                     ds18b20Found = false;
static uint8_t                  deviceCount = 0;
static uint32_t                 lastConversionTime = 0;
static bool                     conversionPending = false;
static uint8_t                  ds18b20ErrorStreak = 0;
static uint32_t                 lastScanAttemptTime = 0;

// Temperature state
static uint8_t                  currentTemperatureC = SHAPNEST_IRON_TEMP_DEFAULT_AMB;
static uint8_t                  lastBroadcastTempC = 0;
static uint32_t                 lastSampleTime = 0;
static uint32_t                 lastBroadcastTime = 0;
static uint32_t                 lastLogTime = 0;

// Interactive Serial override state (for physical/automated bench testing)
static bool                     manualOverride = false;
static uint8_t                  manualTemperatureC = SHAPNEST_IRON_TEMP_DEFAULT_AMB;

// ============================================================================
// FUNCTION DECLARATIONS
// ============================================================================
static void initialize_ble_beacon();
static void broadcast_iron_temperature(uint8_t tempC);
static void set_status_led(bool turnOn);
static void blink_led(uint8_t count, uint16_t duration_ms);
static uint8_t read_temperature_celsius();
static void handle_serial_commands();

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
// TEMPERATURE SENSING ENGINE (DS18B20 Primary + Analog Fallback)
// ============================================================================
static uint8_t read_temperature_celsius() {
    if (manualOverride) {
        return manualTemperatureC;
    }

    uint32_t now = millis();

    // 1. If DS18B20 not yet detected, attempt periodic probe scan every 2 seconds
    if (!ds18b20Found && (now - lastScanAttemptTime >= 2000)) {
        lastScanAttemptTime = now;
        pinMode(TEMP_SENSOR_PIN, INPUT_PULLUP);
        gpio_set_pull_mode((gpio_num_t)TEMP_SENSOR_PIN, GPIO_PULLUP_ONLY);
        sensors.begin();
        deviceCount = sensors.getDeviceCount();
        if (deviceCount > 0) {
            ds18b20Found = true;
            sensors.setResolution(10); // 10-bit: 0.25°C resolution, 187.5ms conversion
            sensors.setWaitForConversion(false);
            sensors.requestTemperatures();
            lastConversionTime = now;
            conversionPending = true;
            ds18b20ErrorStreak = 0;
            Serial.printf("# [DS18B20] Probe detected! Devices: %u (10-bit mode)\n", deviceCount);
        }
    }

    // 2. Read from DS18B20 if available
    if (ds18b20Found) {
        if (!conversionPending) {
            // Initiate conversion
            sensors.requestTemperatures();
            lastConversionTime = now;
            conversionPending = true;
        } else if (now - lastConversionTime >= 200) { // 10-bit takes 187.5ms
            float tempC = sensors.getTempCByIndex(0);
            conversionPending = false;

            // Trigger next conversion immediately for continuous pipeline
            sensors.requestTemperatures();
            lastConversionTime = now;
            conversionPending = true;

            // Validate reading (-55°C to +125°C is DS18B20 operating range)
            if (tempC != DEVICE_DISCONNECTED_C && tempC >= -10.0f && tempC <= 140.0f) {
                ds18b20ErrorStreak = 0;
                uint8_t clampedTemp = (uint8_t)roundf(std::max(0.0f, tempC));
                return clampedTemp;
            } else {
                ds18b20ErrorStreak++;
                if (ds18b20ErrorStreak >= 4) {
                    // Re-scan bus if repeated errors occur (e.g. loose wire)
                    ds18b20Found = false;
                }
            }
        }
        return currentTemperatureC; // Return stable last value while conversion completes
    }

    // 3. Fallback to default ambient if no DS18B20 1-Wire device is attached
    return SHAPNEST_IRON_TEMP_DEFAULT_AMB;
}

// ============================================================================
// BLE ADVERTISEMENT BROADCAST HELPER
// ============================================================================
static void broadcast_iron_temperature(uint8_t tempC) {
    nodePayload.sequence++;
    nodePayload.sensor_state = tempC;

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
    lastBroadcastTempC = tempC;
    lastBroadcastTime = millis();
}

// ============================================================================
// INTERACTIVE SERIAL COMMAND PARSER
// ============================================================================
static void handle_serial_commands() {
    if (!Serial.available()) return;

    String line = Serial.readStringUntil('\n');
    line.trim();
    if (line.isEmpty()) return;

    if (line.equalsIgnoreCase("AUTO")) {
        manualOverride = false;
        Serial.println("# [CMD] Auto temperature sensing RESTORED.");
    } else if (line.equalsIgnoreCase("STATUS") || line.equalsIgnoreCase("HELP")) {
        bool isHot = (currentTemperatureC >= SHAPNEST_IRON_TEMP_HOT_THRESH);
        Serial.println("==================================================");
        Serial.printf("# [STATUS] Node 2 (Iron) | Temp: %d °C [%s]\n",
                      currentTemperatureC,
                      isHot ? "HOT ALERT" : (currentTemperatureC >= SHAPNEST_IRON_TEMP_WARM_THRESH ? "WARM" : "SAFE"));
        Serial.printf("# [STATUS] Sensor: %s (Devices: %u) | Mode: %s\n",
                      ds18b20Found ? "DS18B20 Digital (1-Wire)" : "Analog / Default Ambient",
                      deviceCount,
                      manualOverride ? "MANUAL_TEST" : "AUTO");
        Serial.printf("# [STATUS] Calibrated RefA: %d dBm | Path Loss Exp: %.1f (x10=%u)\n",
                      nodePayload.calibrated_rssi_1m,
                      nodePayload.path_loss_exp_x10 / 10.0f,
                      nodePayload.path_loss_exp_x10);
        Serial.printf("# [STATUS] LED: %s | Uptime: %lu s\n",
                      isHot ? "ON (ALERT)" : "OFF (SAFE)",
                      millis() / 1000UL);
        Serial.println("# [HELP] Commands: 'TEMP <celsius>', 'AUTO', 'CAL <refA>', 'EXP <n_x10>', 'RESET', 'STATUS'");
        Serial.println("==================================================");
    } else if (line.equalsIgnoreCase("RESET") || line.equalsIgnoreCase("RESET_CAL")) {
        nodePayload.calibrated_rssi_1m = (int8_t)CALIBRATED_RSSI_1M;
        nodePayload.path_loss_exp_x10 = (uint8_t)PATH_LOSS_EXP_X10;
        broadcast_iron_temperature(currentTemperatureC);
        Serial.printf("# [CMD] Node 2 Calibration RESET to default (RefA: %d dBm, n: %.1f)\n",
                      CALIBRATED_RSSI_1M, PATH_LOSS_EXP_X10 / 10.0f);
    } else if (line.startsWith("CAL") || line.startsWith("SET_CAL")) {
        int spaceIdx = line.indexOf(' ');
        if (spaceIdx >= 0) {
            String valStr = line.substring(spaceIdx + 1);
            valStr.trim();
            int val = valStr.toInt();
            if (val >= -100 && val < 0) {
                nodePayload.calibrated_rssi_1m = (int8_t)val;
                broadcast_iron_temperature(currentTemperatureC);
                Serial.printf("# [CMD] Node 2 Calibrated RefA set to %d dBm\n", val);
            } else {
                Serial.println("# [ERROR] Invalid RefA. Valid range: -100 to -1 dBm");
            }
        }
    } else if (line.startsWith("EXP") || line.startsWith("SET_EXP")) {
        int spaceIdx = line.indexOf(' ');
        if (spaceIdx >= 0) {
            String valStr = line.substring(spaceIdx + 1);
            valStr.trim();
            int val = valStr.toInt();
            if (val >= 10 && val <= 50) {
                nodePayload.path_loss_exp_x10 = (uint8_t)val;
                broadcast_iron_temperature(currentTemperatureC);
                Serial.printf("# [CMD] Node 2 Path Loss Exp set to %.1f (x10=%d)\n", val / 10.0f, val);
            } else {
                Serial.println("# [ERROR] Invalid Path Loss Exp. Valid range: 10 to 50 (1.0 to 5.0)");
            }
        }
    } else if (line.startsWith("TEMP") || line.startsWith("SET_TEMP") || line.startsWith("T:")) {
        int spaceIdx = line.indexOf(' ');
        if (spaceIdx < 0) spaceIdx = line.indexOf(':');
        if (spaceIdx >= 0) {
            String valStr = line.substring(spaceIdx + 1);
            valStr.trim();
            int val = valStr.toInt();
            if (val >= 0 && val <= 250) {
                manualOverride = true;
                manualTemperatureC = (uint8_t)val;
                currentTemperatureC = manualTemperatureC;
                broadcast_iron_temperature(currentTemperatureC);
                bool isHot = (currentTemperatureC >= SHAPNEST_IRON_TEMP_HOT_THRESH);
                set_status_led(isHot);
                Serial.printf("# [CMD] Temperature manually overridden to %d °C [%s]\n",
                              currentTemperatureC, isHot ? "HOT ALERT" : "SAFE");
            }
        }
    } else {
        bool isNumeric = true;
        for (unsigned int i = 0; i < line.length(); i++) {
            if (!isDigit(line.charAt(i))) {
                isNumeric = false;
                break;
            }
        }
        if (isNumeric && line.length() > 0) {
            int val = line.toInt();
            if (val >= 0 && val <= 250) {
                manualOverride = true;
                manualTemperatureC = (uint8_t)val;
                currentTemperatureC = manualTemperatureC;
                broadcast_iron_temperature(currentTemperatureC);
                bool isHot = (currentTemperatureC >= SHAPNEST_IRON_TEMP_HOT_THRESH);
                set_status_led(isHot);
                Serial.printf("# [CMD] Temperature set to %d °C [%s]\n",
                              currentTemperatureC, isHot ? "HOT ALERT" : "SAFE");
            }
        }
    }
}

// ============================================================================
// SETUP
// ============================================================================
void setup() {
    Serial.begin(SHAPNEST_SERIAL_BAUD_RATE);
    delay(1000); // Allow USB CDC time to attach

    // 1. Configure Pin & Initialize DS18B20 1-Wire bus
    pinMode(TEMP_SENSOR_PIN, INPUT_PULLUP);
    gpio_set_pull_mode((gpio_num_t)TEMP_SENSOR_PIN, GPIO_PULLUP_ONLY);
    sensors.begin();
    deviceCount = sensors.getDeviceCount();
    if (deviceCount > 0) {
        ds18b20Found = true;
        sensors.setResolution(10); // 10-bit: 0.25°C resolution, 187.5ms conversion
        sensors.setWaitForConversion(false);
        sensors.requestTemperatures();
        lastConversionTime = millis();
        conversionPending = true;
    }

    // 2. Configure Status LED (Active LOW on ESP32-C3 Super Mini)
    if (STATUS_LED_PIN >= 0) {
        pinMode(STATUS_LED_PIN, OUTPUT);
        set_status_led(false);
    }

    // 3. Initial Temperature Reading
    currentTemperatureC = read_temperature_celsius();
    bool isHot = (currentTemperatureC >= SHAPNEST_IRON_TEMP_HOT_THRESH);
    set_status_led(isHot);

    // 4. Diagnostic Banner
    Serial.println();
    Serial.println("==================================================");
    Serial.printf("# [LOG] SHAPNEST IRON ANCHOR — NODE_%02d\n", NODE_ID);
    Serial.printf("# [LOG] Sensor Type: %s (Found: %u)\n",
                  ds18b20Found ? "DS18B20 Digital 1-Wire" : "Analog NTC / Fallback",
                  deviceCount);
    Serial.printf("# [LOG] Pin: GPIO %d | Initial Temp: %d °C [%s]\n",
                  TEMP_SENSOR_PIN, currentTemperatureC, isHot ? "HOT ALERT" : "SAFE");
    Serial.printf("# [LOG] Protocol: v%d | Magic ID: 0x%04X ('SN')\n",
                  SHAPNEST_PROTOCOL_VERSION, SHAPNEST_PROTOCOL_ID);
    Serial.printf("# [LOG] Ref@1m: %d dBm | n: %.1f | TX: +%d dBm\n",
                  CALIBRATED_RSSI_1M, PATH_LOSS_EXP_X10 / 10.0f, TX_POWER_DBM);
    Serial.println("==================================================");

    // 5. Initialize NimBLE Beacon
    initialize_ble_beacon();

    // 6. Visual boot confirmation
    blink_led(NODE_ID, 80);
    set_status_led(isHot);

    Serial.printf("# [LOG] NODE_%02d ACTIVE — Iron temperature monitoring & BLE broadcasting online.\n", NODE_ID);
}

// ============================================================================
// MAIN LOOP
// ============================================================================
void loop() {
    uint32_t now = millis();

    // 1. Handle incoming Serial test commands
    handle_serial_commands();

    // 2. Periodic Temperature Sampling (every 250ms)
    if (now - lastSampleTime >= TEMP_SAMPLE_INTERVAL_MS) {
        lastSampleTime = now;
        uint8_t measuredTemp = read_temperature_celsius();

        // Check if temperature changed or forced refresh interval elapsed
        bool tempChanged = (measuredTemp != currentTemperatureC);
        bool forcedRefresh = (now - lastBroadcastTime >= TEMP_FORCE_REFRESH_MS);

        if (tempChanged || forcedRefresh) {
            currentTemperatureC = measuredTemp;
            broadcast_iron_temperature(currentTemperatureC);

            bool isHot = (currentTemperatureC >= SHAPNEST_IRON_TEMP_HOT_THRESH);
            set_status_led(isHot);

            if (tempChanged) {
                Serial.printf("# [IRON EVENT] Temp -> %d °C | %s | Seq: %u\n",
                              currentTemperatureC,
                              isHot ? "HOT [ALERT]" : (currentTemperatureC >= SHAPNEST_IRON_TEMP_WARM_THRESH ? "WARM" : "SAFE"),
                              nodePayload.sequence);
            }
        }
    }

    // 3. Periodic Diagnostic Heartbeat (Every 5 seconds)
    if (now - lastLogTime >= 5000) {
        lastLogTime = now;
        bool isHot = (currentTemperatureC >= SHAPNEST_IRON_TEMP_HOT_THRESH);
        Serial.printf("# [LOG] NODE_02 (Iron) | Temp: %d °C [%s] | Sensor: %s | Uptime: %lu s\n",
                      currentTemperatureC,
                      isHot ? "HOT" : (currentTemperatureC >= SHAPNEST_IRON_TEMP_WARM_THRESH ? "WARM" : "SAFE"),
                      ds18b20Found ? "DS18B20" : "FALLBACK",
                      now / 1000UL);
    }

    // 4. Ensure BLE advertising remains active in hardware controller
    if (pAdvertising != nullptr && !pAdvertising->isAdvertising()) {
        pAdvertising->start();
    }

    delay(20); // 50 Hz loop
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
    nodePayload.sensor_state        = currentTemperatureC;

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

    broadcast_iron_temperature(currentTemperatureC);
}
