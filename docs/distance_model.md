# SHAPNEST — RF Distance Calculation & Signal Filtering Specification

**Component:** Distance Estimation Model, RF Propagation Physics & Filter Pipeline  
**Scope:** Phase 1 Multi-Node Distance Measurement & Central Hub Prototype  
**Author:** AI Pair Programmer & Signal Processing Specialist  
**Status:** Approved & Implemented  

---

## 1. Introduction & RF Propagation Challenges

In the 2.4 GHz ISM frequency band, Received Signal Strength Indication (RSSI) provides a practical, hardware-free mechanism for estimating physical distance between commercial Bluetooth Low Energy (BLE) transceivers. However, raw 2.4 GHz RF propagation in indoor and semi-outdoor living environments is subject to severe non-idealities:

1. **Multipath Fading & Interference:** Direct-path radio waves reflect off walls, floors, ceilings, and furniture, arriving at the receiver antenna with phase shifts that constructively or destructively interfere. This can cause instantaneous RSSI variations of $\pm 10$ to $\pm 15\text{ dBm}$ over distances of just a few centimeters (quarter-wavelength $\lambda/4 \approx 3.1\text{ cm}$).
2. **Body Shadowing & Human Absorption:** Human tissue is composed primarily of saline water, which exhibits high dielectric absorption at 2.4 GHz. A child wearing the wristband will attenuate the line-of-sight signal by $8$ to $15\text{ dBm}$ when their torso or arm blocks the anchor node.
3. **Antenna Polarization & Radiation Patterns:** The omnidirectional radiation patterns of small ceramic SMD antennas have significant nulls and gain variations depending on orientation and ground plane layout.

To overcome these challenges without requiring expensive Ultra-Wideband (UWB) or Time-of-Flight (ToF) transceivers, SHAPNEST implements a **calibrated Log-Distance Path Loss model coupled with a dual-stage nonlinear filtering pipeline**.

---

## 2. The Log-Distance Path Loss Model

### 2.1 Mathematical Formulation
The attenuation of an RF signal over distance in a given environment is modeled by the classic Log-Distance Path Loss equation:

$$\text{RSSI}(d) = A - 10 \cdot n \cdot \log_{10}\left(\frac{d}{d_0}\right) + X_\sigma$$

Where:
- $d$: Physical separation distance between transmitter and receiver (meters).
- $d_0$: Reference distance, standardized to **$1.0\text{ meter}$**.
- $\text{RSSI}(d)$: Received signal power at distance $d$ ($\text{dBm}$).
- $A$: Received signal power at the reference distance $d_0 = 1\text{ m}$ ($\text{dBm}$).
- $n$: Path Loss Exponent (dimensionless environmental coefficient).
- $X_\sigma$: Zero-mean Gaussian random variable representing shadow fading ($\text{dB}$).

### 2.2 Inverting for Distance Calculation
Inverting the path loss formula to solve directly for estimated distance $d$:

$$d = 10^{\frac{A - \text{RSSI}}{10 \cdot n}}$$

```
Example Calculation (Default Parameters: A = -59 dBm, n = 2.2):
- Measured Filtered RSSI = -59 dBm:
    d = 10^((-59 - (-59)) / (10 * 2.2)) = 10^0 = 1.00 m
- Measured Filtered RSSI = -68 dBm:
    d = 10^((-59 - (-68)) / 22) = 10^(9 / 22) = 10^0.4091 = 2.56 m
- Measured Filtered RSSI = -80 dBm:
    d = 10^((-59 - (-80)) / 22) = 10^(21 / 22) = 10^0.9545 = 9.00 m (Clamped to > 8.0 m)
```

### 2.3 Environmental Parameter Guidelines

| Parameter | Identifier in Firmware | Default Value | Typical Environmental Range | Physical Description |
| :--- | :--- | :--- | :--- | :--- |
| **Reference RSSI** | `CALIBRATED_RSSI_1M` | **$-59\text{ dBm}$** | $-55\text{ dBm}$ to $-65\text{ dBm}$ | Transmit power (+3 dBm) minus free-space loss at 1m. |
| **Path Loss Exp** | `PATH_LOSS_EXP_X10` | **$22$ ($n = 2.2$)** | $1.8$ to $3.5$ | Free space: $n = 2.0$; Furnished rooms: $n = 2.2 - 2.8$; Obstructed: $n = 3.0 - 4.0$. |

---

## 3. Dual-Stage Signal Filtering Pipeline

Raw RSSI values are never passed directly into the Log-Distance equation. The child wristband executes a two-stage filter pipeline every $1000\text{ ms}$ cooperative cycle for each of the 5 nodes:

```
[Raw BLE Beacons] -> [5-Sample Ring Buffer] -> [Stage 1: Median Filter] -> [Stage 2: EMA Filter] -> [Log-Distance Equation] -> [Bounds Clamping]
   (~4-5 pkts/sec)      (Stores last 5 RSSIs)      (Rejects Impulse Spikes)    (alpha = 0.25 Smoothing)       d = 10^((A-RSSI)/(10*n))     [0.15m <= d <= 8.00m]
```

### 3.1 Stage 1: 5-Sample Rolling Median Filter
- **Purpose:** Reject high-amplitude, non-Gaussian impulse noise caused by multipath constructive/destructive nulls and momentary RF dropouts.
- **Algorithm:**
  1. Each node maintains a circular buffer of the last $N = 5$ valid RSSI measurements: $\mathbf{R} = [r_0, r_1, r_2, r_3, r_4]$.
  2. In the calculation window, the buffer is sorted in ascending order:
     $$\mathbf{R}_{\text{sorted}} = \text{sort}(\mathbf{R})$$
  3. The median value is selected:
     $$r_{\text{median}} = \mathbf{R}_{\text{sorted}}[2]$$
- **Performance:** A single spurious drop to $-95\text{ dBm}$ (e.g., during antenna orientation change) is completely eliminated from the output, preventing false distance spikes.

### 3.2 Stage 2: Exponential Moving Average (EMA) Smoothing
- **Purpose:** Provide smooth temporal continuity between successive 1-second cycles while remaining responsive to real human movement.
- **Formulation:**
  $$\text{RSSI}_{\text{EMA}}(t) = \alpha \cdot r_{\text{median}}(t) + (1 - \alpha) \cdot \text{RSSI}_{\text{EMA}}(t-1)$$
- **Smoothing Factor ($\alpha = 0.25$):**
  - $\alpha = 0.25$ provides a $75\%$ weighting on historical signal continuity and $25\%$ on fresh measurements.
  - Time constant: $\tau \approx \frac{T}{\alpha} \approx \frac{1.0\text{ s}}{0.25} = 4.0\text{ seconds}$ for $63\%$ step response, perfectly balancing natural child walking speeds ($\approx 0.5 - 1.0\text{ m/s}$) with jitter suppression.

---

## 4. Operational Boundaries & Clamping Policy

Due to logarithmic divergence at physical extremes, unbounded RSSI distance models produce erratic values near the antenna and at the RF noise floor. SHAPNEST enforces strict engineering operational bounds:

```
0.00 m       0.15 m                                                   8.00 m                  Infinity
  |------------|=========================================================|------------------------>
  [Saturation] [           Valid Operational Measurement Range           ] [ Out-of-Range Ceiling ]
  Clamped to   [ Linear Log-Distance Model: 15 cm <= distance <= 800 cm  ] Displayed as "> 8.0 m"
    0.15 m                                                                 Preserves Raw RSSI
```

### 4.1 Near-Field Boundary (Floor: $0.15\text{ m}$ / $15\text{ cm}$)
- **Physical Rationale:** At distances under $15\text{ cm}$, electromagnetic near-field capacitive/inductive coupling dominates over radiation-field propagation, causing receiver LNA saturation (RSSI values of $-30$ to $-35\text{ dBm}$).
- **Implementation:** Any calculated distance below $0.15\text{ m}$ is clamped to `SHAPNEST_DISTANCE_MIN_CM` ($15\text{ cm}$).

### 4.2 Far-Field Boundary (Ceiling: $8.00\text{ m}$ / $800\text{ cm}$)
- **Physical Rationale:** Beyond $8\text{ meters}$ in typical residential spaces, RSSI approaches the $-85$ to $-90\text{ dBm}$ ambient noise floor. Because the derivative $\frac{\partial d}{\partial \text{RSSI}} = -\frac{\ln(10)}{10 n} \cdot 10^{\frac{A - \text{RSSI}}{10 n}}$ grows exponentially with distance, a tiny $1\text{ dB}$ fluctuation at $-88\text{ dBm}$ swings estimated distance by over $\pm 2.5\text{ meters}$.
- **Implementation:**
  - Calculated distances exceeding $8.00\text{ m}$ are capped at `SHAPNEST_DISTANCE_MAX_CM` ($800\text{ cm}$).
  - The application displays this state explicitly as **`> 8.0 m`** or **`OUT_OF_RANGE`**, avoiding misleading false precision while preserving the underlying RSSI for diagnostic visibility.

### 4.3 Offline Sentinel Handling
- When a node has transmitted no packets for $t \ge 3500\text{ ms}$, distance is assigned the sentinel value **`0xFFFF` (`65535` cm)** and RSSI is assigned **`-128 dBm`**.
- The application interprets `0xFFFF` as `OFFLINE`, hides numerical distance, and displays an inactive state pill.

---

## 5. Practical Calibration Procedure

To achieve optimal distance tracking in a new physical room or bench setup:

1. **Setup 1-Meter Calibration Line:**
   - Place Node 1 on a non-metallic table $1.0\text{ meter}$ above the floor.
   - Place the Wristband exactly $1.0\text{ meter}$ away, aligned with line-of-sight.
2. **Measure Average Reference RSSI:**
   - Connect the Central Hub to the Web Application.
   - Open the Collapsible Diagnostic Console (`# [LOG]`).
   - Observe the raw RSSI reported for Node 1 over 30 seconds.
   - Average the readings (typically $-58$ to $-61\text{ dBm}$). This value is your room-specific $A$ (`CALIBRATED_RSSI_1M`).
3. **Calibrate Path Loss Exponent ($n$):**
   - Move the wristband to $3.0\text{ meters}$.
   - Observe the measured RSSI at $3\text{ m}$ ($\text{RSSI}_{3\text{m}}$).
   - Calculate $n$:
     $$n = \frac{A - \text{RSSI}_{3\text{m}}}{10 \cdot \log_{10}(3.0)} = \frac{A - \text{RSSI}_{3\text{m}}}{4.77}$$
   - Example: If $A = -59\text{ dBm}$ and $\text{RSSI}_{3\text{m}} = -70\text{ dBm}$:
     $$n = \frac{-59 - (-70)}{4.77} = \frac{11}{4.77} = 2.30 \implies \text{Set } \texttt{PATH_LOSS_EXP_X10} = 23$$
4. **Update Node Firmware:**
   - Update `CALIBRATED_RSSI_1M` and `PATH_LOSS_EXP_X10` in `node_esp32c3.ino` (or use the Web App Path Loss Exponent slider to dynamically evaluate corrections in real time).
