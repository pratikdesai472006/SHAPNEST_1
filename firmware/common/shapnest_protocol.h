#ifndef SHAPNEST_PROTOCOL_H
#define SHAPNEST_PROTOCOL_H

/**
 * ============================================================================
 * SHAPNEST — PHASE 1 MASTER PROTOCOL SPECIFICATION
 * 
 * Target Architectures:
 *   - Nodes:      ESP32-C3 Mini (32-bit RISC-V)
 *   - Wristband:  ESP32-C3 Mini (32-bit RISC-V)
 *   - Hub:        ESP32-WROOM   (32-bit Xtensa LX6 Dual-Core)
 *   - App:        Modern Web Application (Web Serial / Web Bluetooth)
 * 
 * All structures are strictly byte-packed (#pragma pack(push, 1)) to prevent
 * cross-compiler alignment discrepancies between RISC-V and Xtensa.
 * ============================================================================
 */

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* -------------------------------------------------------------------------- */
/* PROTOCOL IDENTIFIERS & MAGIC CONSTANTS                                     */
/* -------------------------------------------------------------------------- */
#define SHAPNEST_PROTOCOL_ID                 0x534E  /* 'S', 'N' in Little-Endian */
#define SHAPNEST_PROTOCOL_VERSION            0x01

#define SHAPNEST_FRAME_TYPE_NODE_BEACON      0x01
#define SHAPNEST_FRAME_TYPE_WRISTBAND_TEL    0x02

#define SHAPNEST_TARGET_WRISTBAND_ID         1
#define SHAPNEST_MAX_NODES                   3
#define SHAPNEST_NODE_ID_MIN                 1
#define SHAPNEST_NODE_ID_MAX                 3

/* -------------------------------------------------------------------------- */
/* RF & CALIBRATION DEFAULTS                                                  */
/* -------------------------------------------------------------------------- */
#define SHAPNEST_DEFAULT_TX_POWER_DBM        3       /* +3 dBm */
#define SHAPNEST_DEFAULT_REF_RSSI_1M        -59      /* Reference RSSI at 1 meter in dBm */
#define SHAPNEST_DEFAULT_PATH_LOSS_EXP_X10   22      /* 22 represents n = 2.2 */

/* Operational Distance Bounds (Centimeters) */
#define SHAPNEST_DISTANCE_MIN_CM             15      /* Minimum operational floor: 0.15 m */
#define SHAPNEST_DISTANCE_MAX_CM             800     /* Maximum operational ceiling: 8.00 m */
#define SHAPNEST_DISTANCE_OFFLINE_CM         0xFFFF  /* Sentinel value for OFFLINE (65535) */
#define SHAPNEST_RSSI_OFFLINE                -128    /* Sentinel value for OFFLINE RSSI */

/* -------------------------------------------------------------------------- */
/* TIMING & STALENESS THRESHOLDS (MILLISECONDS)                               */
/* -------------------------------------------------------------------------- */
#define SHAPNEST_NODE_ADV_INTERVAL_MS        150     /* Node advertising interval (150ms for dense RSSI sampling) */
#define SHAPNEST_NODE_ACTIVE_TIMEOUT_MS      1200    /* < 1200 ms -> ACTIVE */
#define SHAPNEST_NODE_OFFLINE_TIMEOUT_MS     3500    /* > 3500 ms -> OFFLINE */

#define SHAPNEST_WRISTBAND_CYCLE_MS          1000    /* Full cooperative cycle */
#define SHAPNEST_WRISTBAND_SCAN_MS           900     /* Dedicated scanning window */
#define SHAPNEST_WRISTBAND_CALC_GAP_MS       10      /* Calculation & payload packing */
#define SHAPNEST_WRISTBAND_UPLINK_BURST_MS   90      /* Dedicated 3-pulse uplink burst */
#define SHAPNEST_WRISTBAND_OFFLINE_TIMEOUT_MS 3500   /* Hub marks wristband OFFLINE if silent */

#define SHAPNEST_SERIAL_WATCHDOG_TIMEOUT_MS  2000    /* App flags HUB: DISCONNECTED if silent */
#define SHAPNEST_SERIAL_BAUD_RATE            115200

/* -------------------------------------------------------------------------- */
/* NODE CONNECTION STATES                                                     */
/* -------------------------------------------------------------------------- */
typedef enum {
    SHAPNEST_NODE_STATE_ACTIVE  = 0,  /* 0b00: Normal, fresh packet received < 1200ms */
    SHAPNEST_NODE_STATE_STALE   = 1,  /* 0b01: Missed packets; holding last reading (1200-3500ms) */
    SHAPNEST_NODE_STATE_OFFLINE = 2,  /* 0b10: Node out of range / powered off (> 3500ms) */
    SHAPNEST_NODE_STATE_RESERVED= 3   /* 0b11: Reserved for future expansion */
} shapnest_node_state_t;

/* Bitfield manipulation helpers for packing Node ID (bits 0..3) & State (bits 4..5) */
#define SHAPNEST_PACK_ID_STATE(id, state) \
    ((uint8_t)(((uint8_t)(id) & 0x0F) | (((uint8_t)(state) & 0x03) << 4)))

#define SHAPNEST_UNPACK_ID(packed_byte) \
    ((uint8_t)((packed_byte) & 0x0F))

#define SHAPNEST_UNPACK_STATE(packed_byte) \
    ((shapnest_node_state_t)(((packed_byte) >> 4) & 0x03))

/* -------------------------------------------------------------------------- */
/* PACKED BINARY STRUCTURES                                                   */
/* -------------------------------------------------------------------------- */
#pragma pack(push, 1)

/**
 * 1. Node Manufacturer Specific Data Payload (Inside BLE AD Type 0xFF)
 * Total Size: Exactly 7 Bytes.
 */
typedef struct {
    uint16_t company_id;           /* 0x534E ('S', 'N') */
    uint8_t  frame_type;           /* 0x01 (NODE_BEACON) */
    uint8_t  node_id;              /* 1..3 */
    int8_t   calibrated_rssi_1m;   /* e.g. -59 dBm */
    uint8_t  path_loss_exp_x10;    /* e.g. 22 representing n = 2.2 */
    uint8_t  sequence;             /* Rolling packet counter (0..255) */
} shapnest_node_payload_t;

/**
 * Complete Node BLE Advertisement Packet (Standard 31-Byte PDU)
 * Total Size: Exactly 12 Bytes (19 Bytes unused headroom).
 */
typedef struct {
    /* BLE Flags AD Structure (3 Bytes) */
    uint8_t  flags_length;         /* 0x02 */
    uint8_t  flags_type;           /* 0x01 (Flags) */
    uint8_t  flags_data;           /* 0x06 (LE General Discoverable, BR/EDR Not Supported) */

    /* Manufacturer Specific AD Structure (9 Bytes) */
    uint8_t  mfr_length;           /* 0x08 (8 bytes follow: type + 7 bytes payload) */
    uint8_t  mfr_type;             /* 0xFF (Manufacturer Specific Data) */
    shapnest_node_payload_t payload; /* 7 Bytes */
} shapnest_node_beacon_packet_t;

/**
 * 2. Per-Node Telemetry Block inside Wristband Uplink
 * Total Size: Exactly 4 Bytes per node.
 */
typedef struct {
    uint8_t  id_and_state;         /* Bits 0..3: Node ID (1..3), Bits 4..5: State (0..2) */
    uint16_t distance_cm;          /* Distance in cm (15..800 cm, or 0xFFFF if OFFLINE) */
    int8_t   filtered_rssi;        /* Filtered RSSI in dBm (-128 if OFFLINE) */
} shapnest_node_telemetry_block_t;

/**
 * Wristband Manufacturer Specific Data Payload (Inside BLE AD Type 0xFF)
 * Total Size: Exactly 18 Bytes (3 Nodes x 4 Bytes + 6 Bytes Header).
 */
typedef struct {
    uint16_t company_id;           /* 0x534E ('S', 'N') */
    uint8_t  frame_type;           /* 0x02 (WRISTBAND_TELEMETRY) */
    uint8_t  wristband_id;         /* 1 */
    uint8_t  sequence;             /* Rolling sequence counter (0..255) */
    uint8_t  node_count;           /* 3 */
    shapnest_node_telemetry_block_t nodes[SHAPNEST_MAX_NODES]; /* 3 * 4 = 12 Bytes */
} shapnest_wristband_payload_t;

/**
 * Complete Wristband BLE Telemetry Packet (Standard 31-Byte PDU)
 * Total Size: Exactly 23 Bytes (8 Bytes headroom under 31-byte BLE limit).
 */
typedef struct {
    /* BLE Flags AD Structure (3 Bytes) */
    uint8_t  flags_length;         /* 0x02 */
    uint8_t  flags_type;           /* 0x01 (Flags) */
    uint8_t  flags_data;           /* 0x06 (LE General Discoverable, BR/EDR Not Supported) */

    /* Manufacturer Specific AD Structure (20 Bytes) */
    uint8_t  mfr_length;           /* 0x13 (19 bytes follow: type + 18 bytes payload) */
    uint8_t  mfr_type;             /* 0xFF (Manufacturer Specific Data) */
    shapnest_wristband_payload_t payload; /* 18 Bytes */
} shapnest_wristband_telemetry_packet_t;

#pragma pack(pop)

/* -------------------------------------------------------------------------- */
/* COMPILE-TIME SIZE VERIFICATIONS                                            */
/* -------------------------------------------------------------------------- */
#if defined(__cplusplus) && __cplusplus >= 201103L
static_assert(sizeof(shapnest_node_payload_t) == 7, 
              "shapnest_node_payload_t must be exactly 7 bytes");
static_assert(sizeof(shapnest_node_beacon_packet_t) == 12, 
              "shapnest_node_beacon_packet_t must be exactly 12 bytes");
static_assert(sizeof(shapnest_node_telemetry_block_t) == 4, 
              "shapnest_node_telemetry_block_t must be exactly 4 bytes");
static_assert(sizeof(shapnest_wristband_payload_t) == 18, 
              "shapnest_wristband_payload_t must be exactly 18 bytes");
static_assert(sizeof(shapnest_wristband_telemetry_packet_t) == 23, 
              "shapnest_wristband_telemetry_packet_t must be exactly 23 bytes");
#endif

/* -------------------------------------------------------------------------- */
/* INLINE UTILITY & CONVERSION FUNCTIONS                                      */
/* -------------------------------------------------------------------------- */
static inline float shapnest_cm_to_meters(uint16_t cm) {
    if (cm == SHAPNEST_DISTANCE_OFFLINE_CM) {
        return -1.0f;
    }
    return (float)cm / 100.0f;
}

static inline uint16_t shapnest_meters_to_cm(float meters) {
    if (meters < 0.0f) {
        return SHAPNEST_DISTANCE_OFFLINE_CM;
    }
    float cm_float = meters * 100.0f;
    if (cm_float < (float)SHAPNEST_DISTANCE_MIN_CM) {
        return SHAPNEST_DISTANCE_MIN_CM;
    }
    if (cm_float > (float)SHAPNEST_DISTANCE_MAX_CM) {
        return SHAPNEST_DISTANCE_MAX_CM;
    }
    return (uint16_t)(cm_float + 0.5f);
}

static inline const char* shapnest_state_to_string(shapnest_node_state_t state) {
    switch (state) {
        case SHAPNEST_NODE_STATE_ACTIVE:  return "ACTIVE";
        case SHAPNEST_NODE_STATE_STALE:   return "STALE";
        case SHAPNEST_NODE_STATE_OFFLINE: return "OFFLINE";
        default:                          return "UNKNOWN";
    }
}

#ifdef __cplusplus
}
#endif

#endif /* SHAPNEST_PROTOCOL_H */
