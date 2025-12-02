# 🚗 Electric Vehicle Model Components - Complete Guide

This document explains **every component** of the BMW i3 simulation model in simple terms. Read this before building the Simulink model to understand what each part does and why it's needed.

---

## 📋 Table of Contents

1. [Overall Model Architecture](#overall-model-architecture)
2. [Component 1: Driving Cycle Input](#component-1-driving-cycle-input)
3. [Component 2: Driver Model (PI Controller)](#component-2-driver-model-pi-controller)
4. [Component 3: Longitudinal Vehicle Dynamics](#component-3-longitudinal-vehicle-dynamics)
5. [Component 4: Transmission System](#component-4-transmission-system)
6. [Component 5: Electric Motor & Inverter](#component-5-electric-motor--inverter)
7. [Component 6: Regenerative Braking Controller](#component-6-regenerative-braking-controller)
8. [Component 7: Battery Model (Thevenin)](#component-7-battery-model-thevenin)
9. [Component 8: Auxiliary Devices](#component-8-auxiliary-devices)
10. [How Everything Connects](#how-everything-connects)

---

## Overall Model Architecture

### The Big Picture

Think of the EV model as a **closed-loop feedback system**:

```
┌─────────────────────────────────────────────────────────────────┐
│                     COMPLETE EV MODEL FLOW                       │
└─────────────────────────────────────────────────────────────────┘

  ┌──────────────┐
  │ Driving Cycle│ (What speed we WANT)
  │  (NEDC/EPA)  │
  └──────┬───────┘
         │ Desired Speed
         ▼
  ┌──────────────┐
  │    Driver    │ (Compares desired vs actual)
  │  PI Control  │
  └──────┬───────┘
         │ Accelerator/Brake Commands
         ▼
  ┌──────────────┐
  │   Regen      │ (Decides: Electric brake or friction brake?)
  │   Braking    │
  └──────┬───────┘
         │ Motor Torque Demand
         ▼
  ┌──────────────┐
  │ Motor +      │ (Converts electrical → mechanical power)
  │ Inverter     │
  └──────┬───────┘
         │ Shaft Torque
         ▼
  ┌──────────────┐
  │ Transmission │ (Multiplies torque for wheels)
  └──────┬───────┘
         │ Wheel Torque → Force
         ▼
  ┌──────────────┐
  │  Vehicle     │ (Physics: Forces → Acceleration → Speed)
  │  Dynamics    │
  └──────┬───────┘
         │ Actual Speed (FEEDBACK)
         └──────────┐
                    │
  ┌─────────────────▼──┐
  │     Battery        │ (Energy source/sink)
  │ (Thevenin Model)   │
  └────────────────────┘
```

### Key Concept: **Forward vs Backward Models**

This is a **BACKWARD-FACING** (quasi-static) model:
- We **assume** the vehicle follows the desired speed perfectly (or very closely)
- We calculate **what power is required** to achieve that speed
- Then we work backwards to find battery energy consumption

(Opposed to forward models where you apply throttle and see what speed results)

---

## Component 1: Driving Cycle Input

### What It Does
Provides the **reference speed profile** that the vehicle should follow over time.

### Real-World Example
Imagine you're taking a driving test where you must follow a specific pattern:
- "Stay at 0 km/h for 10 seconds"
- "Accelerate to 50 km/h over 20 seconds"
- "Cruise at 50 km/h for 30 seconds"
- "Decelerate to 0 km/h over 10 seconds"

That's a driving cycle!

### Standard Driving Cycles Used

| Cycle | Type | Duration | Max Speed | Description |
|-------|------|----------|-----------|-------------|
| **NEDC** | European | 1180 s | 120 km/h | 4× Urban + 1× Highway |
| **FTP-75** | US City | 1874 s | 91.2 km/h | Stop-and-go city |
| **HWFET** | US Highway | 765 s | 96.4 km/h | Steady highway |
| **US06** | US Aggressive | 596 s | 129.2 km/h | Hard acceleration |
| **SC03** | US AC Test | 596 s | 88.2 km/h | With air conditioning |

### Inputs
- **Time vector**: `[0, 1, 2, 3, ..., 1179]` seconds
- **Velocity vector**: `[0, 0, 15, 15, 32, ...]` km/h

### Output
- **Desired velocity** at each time step

### In Simulink
- **Block Type**: `From Workspace` or `1-D Lookup Table`
- **Data**: Load from CSV file or MATLAB workspace
- **Signal**: Time (s) → Velocity (km/h)

---

## Component 2: Driver Model (PI Controller)

### What It Does
Acts like a **human driver** trying to match the desired speed using the accelerator and brake pedals.

### The Problem It Solves
If the driving cycle says "be at 50 km/h at t=100s", but the car is only at 48 km/h, the driver needs to:
- Press the accelerator a bit more, OR
- If going too fast (52 km/h), ease off the accelerator or brake

### How PI Control Works

**PI = Proportional + Integral**

```
Error = Desired_Speed - Actual_Speed

Output = Kp × Error + Ki × ∫(Error) dt

Where:
- Kp = 60 (Proportional gain - reacts to current error)
- Ki = 2 (Integral gain - corrects accumulated error)
```

**Example:**
- If you're 5 km/h too slow → Strong accelerator command
- If you're 0.5 km/h too slow → Gentle accelerator command
- If error persists for a long time → Integral part increases output

### Inputs
1. **Desired velocity** (from driving cycle)
2. **Actual velocity** (feedback from vehicle dynamics)

### Outputs
1. **Accelerator command**: 0 to 1 (0% to 100% throttle)
2. **Brake command**: 0 to 1 (0% to 100% brake)

### Logic

```
If Output > 0:
    Accelerator = Output (clamped to [0, 1])
    Brake = 0
    
If Output < 0:
    Accelerator = 0
    Brake = |Output| (clamped to [0, 1])
```

### In Simulink
- **Block Type**: `PID Controller` (set D=0, only use P and I)
- **Parameters**: Kp=60, Ki=2
- **Additional**: Saturation blocks to limit output to ±100

### Why These Specific Gains?
- Tuned to achieve **speed tracking error < 2 km/h**
- Too high → Oscillations (car speeds up/slows down erratically)
- Too low → Sluggish response (can't keep up with cycle)

---

## Component 3: Longitudinal Vehicle Dynamics

### What It Does
Calculates the **forces acting on the vehicle** and determines **acceleration and velocity**.

This is where **physics happens**!

### The Forces

#### 1. **Aerodynamic Drag Force** (Air Resistance)

```
F_aero = 0.5 × ρ × Cd × A_frontal × (V_vehicle - V_wind)²

Where:
- ρ = 1.225 kg/m³ (air density)
- Cd = 0.29 (drag coefficient - BMW i3)
- A_frontal = 2.38 m² (frontal area - BMW i3)
- V_vehicle = vehicle speed (m/s)
- V_wind = wind speed (usually 0)
```

**Example:** At 100 km/h (27.8 m/s):
```
F_aero = 0.5 × 1.225 × 0.29 × 2.38 × 27.8²
       ≈ 316 N
```

#### 2. **Rolling Resistance Force** (Tire-Road Friction)

```
F_roll = C_RR × M_vehicle × g × cos(θ)

Where:
- C_RR = 0.01 × (1 + V/100) (speed-dependent coefficient)
- M_vehicle = 1270 kg (vehicle mass)
- g = 9.81 m/s² (gravity)
- θ = road angle (0° for flat road)
```

**Example:** At 50 km/h on flat road:
```
C_RR = 0.01 × (1 + 50/100) = 0.015
F_roll = 0.015 × 1270 × 9.81 × 1
       ≈ 187 N
```

#### 3. **Gradient Resistance Force** (Hills)

```
F_grade = M_vehicle × g × sin(θ)

Where:
- θ = road incline angle
```

**Example:** 5° uphill slope:
```
F_grade = 1270 × 9.81 × sin(5°)
        ≈ 108 N
```

(For NEDC testing, θ = 0° - flat road)

#### 4. **Inertia Force** (Acceleration)

```
F_inertia = δ × M_vehicle × a

Where:
- δ = 1.04 (mass factor - accounts for rotating parts)
- a = acceleration (m/s²)
```

**Example:** Accelerating at 1 m/s²:
```
F_inertia = 1.04 × 1270 × 1
          ≈ 1321 N
```

#### 5. **Transmission Loss** (Mechanical Friction)

```
F_trans = (F_roll + F_aero + F_grade + F_inertia) × (1 - η_trans) / η_trans

Where:
- η_trans = 0.98 (transmission efficiency)
```

### Total Tractive Force Required

```
F_total = F_aero + F_roll + F_grade + F_inertia + F_trans
```

### Newton's Second Law

```
a = (F_tractive - F_total) / M_vehicle

Integrate acceleration → velocity
Integrate velocity → distance
```

### Inputs
1. **Tractive force** (from motor/transmission)
2. **Current velocity**

### Outputs
1. **New velocity** (actual speed of vehicle)
2. **Distance traveled**

### In Simulink
- **MATLAB Function blocks** for each force calculation
- **Integrator blocks** for acceleration → velocity
- **Math operations** to sum forces

---

## Component 4: Transmission System

### What It Does
Converts **motor shaft torque** to **wheel torque** and **motor speed** from **wheel speed**.

### Why We Need It
Electric motors spin very fast (up to 11,400 RPM in BMW i3) but car wheels spin slowly. We need a **gear ratio** to match them.

### The Math

#### Motor Speed to Wheel Speed
```
ω_wheel = v_vehicle / r_tire

ω_motor = ω_wheel × gear_ratio

Where:
- r_tire = 0.35 m (tire radius)
- gear_ratio = 9.7 (BMW i3 - single speed)
- v_vehicle = vehicle speed (m/s)
```

**Example:** At 100 km/h (27.8 m/s):
```
ω_wheel = 27.8 / 0.35 = 79.4 rad/s = 758 RPM
ω_motor = 758 × 9.7 = 7,353 RPM
```

#### Wheel Torque to Motor Torque
```
T_wheel = T_motor × gear_ratio × η_trans

F_tractive = T_wheel / r_tire

Where:
- T_motor = motor shaft torque (Nm)
- η_trans = 0.98 (transmission efficiency)
```

**Example:** Motor producing 250 Nm:
```
T_wheel = 250 × 9.7 × 0.98 = 2,376 Nm
F_tractive = 2,376 / 0.35 = 6,789 N
```

### Inputs
1. **Motor torque** (Nm)
2. **Vehicle speed** (m/s)

### Outputs
1. **Wheel torque** / **Tractive force**
2. **Motor speed** (RPM)

### In Simulink
- **Gain blocks** for gear ratio multiplication
- **Math blocks** for efficiency losses

---

## Component 5: Electric Motor & Inverter

### What It Does
Converts **electrical power** from the battery to **mechanical power** at the motor shaft.

### Two Key Characteristics

#### A. **Torque-Speed Curve** (Motor Capability)

The motor can't produce maximum torque at all speeds!

```
┌─────────────────────────────────────┐
│   Motor Torque vs Speed (BMW i3)    │
└─────────────────────────────────────┘

 Torque (Nm)
   ▲
250│████████████╲
   │            │╲
   │  Constant  │ ╲  Constant Power
   │   Torque   │  ╲    Region
150│            │   ╲_______________
   │            │
   └────────────┴──────────────────────▶ Speed (RPM)
   0         5,000              11,400
```

**Regions:**
- **0-5000 RPM**: Max torque = 250 Nm (constant)
- **5000-11400 RPM**: Torque decreases (power constant at ~125 kW)

#### B. **Efficiency Map** (Energy Losses)

Motor efficiency varies with torque and speed!

```
Efficiency Map (Torque × Speed → Efficiency %)

        Speed (RPM)
         1000  3000  5000  7000  9000
Torque    ┌─────────────────────────┐
50 Nm   │  82    85    87    85    82 │
100 Nm  │  86    90    92    91    88 │
150 Nm  │  88    92    94    93    90 │
200 Nm  │  89    93    95    94    91 │
250 Nm  │  87    91    93    92    89 │
        └─────────────────────────┘

Peak efficiency: 95% at 5000 RPM, 150-200 Nm
```

### Motor Power Calculation

```
Demanded Torque = (T_max at current speed) × Accelerator_Command

P_motor_mechanical = T_motor × ω_motor

Efficiency = lookup(T_motor, ω_motor) from efficiency map

P_motor_electrical = P_motor_mechanical / η_motor
```

### Inverter (DC to AC Converter)

Converts battery DC power to motor AC power with its own efficiency map.

```
P_battery = P_motor_electrical / η_inverter

Where:
- η_inverter = lookup(T_motor, ω_motor) from inverter efficiency map
- Typical: 92-97%
```

### Inputs
1. **Accelerator command** (0-1)
2. **Motor speed** (from transmission feedback)

### Outputs
1. **Motor torque** (Nm)
2. **Battery power demand** (W)

### In Simulink
- **2-D Lookup tables** for torque curve and efficiency maps
- **Product/Divide blocks** for power calculations
- **Data files**: Load efficiency maps from CSV/MAT files

---

## Component 6: Regenerative Braking Controller

### What It Does
Decides how much braking force comes from the **electric motor** (capturing energy) vs **friction brakes** (wasting energy as heat).

### The Goal
**Maximize energy recovery** while ensuring **safe braking**.

### Constraints (When Regen is Limited)

#### 1. **Speed Limit** (Safety)
```
If speed < 10 km/h:
    Regen = 0% (Use friction brakes only)
    
If 10 km/h < speed < 20 km/h:
    Regen = (speed - 10) / 10 × 100%  (Linear ramp)
    
If speed > 20 km/h:
    Regen = 100% (Full regen available)
```

**Why?** At low speeds, motor cannot generate enough braking torque smoothly.

#### 2. **Power Limit**
```
P_regen_max = 53 kW (BMW i3 limit)

If P_regen_available > 53 kW:
    Use only 53 kW regen + friction makeup
```

**Why?** Battery charging rate limited by chemistry and inverter capacity.

#### 3. **Deceleration Limit**
```
If deceleration > 0.7g (6.87 m/s²):
    Regen = 0% (Emergency braking - use all friction)
```

**Why?** Need maximum braking force instantly, can't rely on electric motor ramp-up.

#### 4. **SoC Limit**
```
If SoC > 95%:
    Regen = 0% (Battery full, can't accept charge)
```

**Why?** Overcharging damages battery.

### Braking Distribution Logic

```
Step 1: Calculate total braking force needed
F_brake_total = Brake_Command × φ × M_vehicle × g
(where φ = 0.8 = max tire grip coefficient)

Step 2: Calculate max regen force available
P_regen_avail = min(53 kW, Motor_Max_Power_at_Current_Speed)
F_regen_max = P_regen_avail / v_vehicle

Step 3: Apply constraints
F_regen_actual = F_regen_max × speed_factor × soc_factor × decel_factor

Step 4: Distribute braking
If F_brake_total < F_regen_actual:
    F_electric = F_brake_total
    F_friction = 0
Else:
    F_electric = F_regen_actual
    F_friction = F_brake_total - F_regen_actual
```

### Example Scenario

**Braking from 80 km/h to 50 km/h**

```
Vehicle speed: 80 km/h = 22.2 m/s
Brake command: 0.3 (30%)
SoC: 60%

F_brake_total = 0.3 × 0.8 × 1270 × 9.81 = 2,993 N

P_regen_avail = 53,000 W
F_regen_max = 53,000 / 22.2 = 2,387 N

Speed factor: 100% (above 20 km/h)
SoC factor: 100% (below 95%)
Decel factor: 100% (gentle braking)

F_regen_actual = 2,387 N
F_friction = 2,993 - 2,387 = 606 N

Energy recovered: 2,387 × 22.2 = 53 kW (charging battery)
Energy wasted: 606 × 22.2 = 13.5 kW (heat in brakes)

Regen efficiency: 53 / (53 + 13.5) = 80%
```

### Inputs
1. **Brake command** (0-1)
2. **Vehicle speed**
3. **Battery SoC**
4. **Motor capabilities**

### Outputs
1. **Regenerative braking torque** (to motor)
2. **Friction braking force** (to vehicle dynamics)

### In Simulink
- **Switch/Saturation blocks** for constraints
- **Lookup tables** for regen power limits
- **Logic blocks** for distribution algorithm

---

## Component 7: Battery Model (Thevenin)

### What It Does
Models the **electrical behavior** of the battery pack and calculates **State of Charge (SoC)**.

### Why Simple Models Don't Work

**Simple model (wrong):**
```
Battery = voltage source + resistance
V_battery = V_nominal - I × R
```

**Problem:** Real batteries have:
- Voltage changes with SoC (100% charge = 4.2V, 0% = 3.0V per cell)
- Resistance changes with SoC (higher when nearly full/empty)
- Dynamic voltage drop during load (polarization)

### Thevenin Equivalent Circuit

```
┌─────────────────────────────────────────────┐
│        Single Cell Model                    │
└─────────────────────────────────────────────┘

     I_cell
      ──▶
  ┌────────┬────[R₀]────┬─────────┐
  │        │            │         │
  │   V_OC │            │         │
  │  (SoC) │          [R₁]      + V_terminal -
  │        │            │
  │        │          [C₁]
  │        │            │
  └────────┴────────────┴─────────┘

Components:
- V_OC(SoC): Open circuit voltage (no load)
- R₀(SoC): Ohmic resistance (instant voltage drop)
- R₁(SoC): Polarization resistance (slow voltage drop)
- C₁(SoC): Polarization capacitance (time constant)
```

### The Equations

#### 1. **Terminal Voltage**
```
V_terminal = V_OC(SoC) - R₀(SoC) × I - V₁

Where V₁ is the voltage across R₁-C₁ branch:
dV₁/dt = -V₁/(R₁ × C₁) + I/C₁
```

#### 2. **Current Calculation**
```
Given power demand P_battery, solve for current:

P = V × I
P = [V_OC - R₀ × I - V₁] × I
P = V_OC × I - R₀ × I² - V₁ × I

Rearranging (quadratic equation):
I = (V_OC - √(V_OC² - 4 × R₀ × P)) / (2 × R₀)
```

#### 3. **SoC Update** (Coulomb Counting)
```
dSoC/dt = -I / (Q_total × 3600) × 100

Where:
- Q_total = battery capacity (Ah) = 60 Ah for BMW i3
- I in Amperes
- Result in %/second

Integration:
SoC(t) = SoC(0) + ∫(dSoC/dt) dt
```

### SoC-Dependent Parameters

For BMW i3 (example values):

```
SoC (%)  │  V_OC (V)  │  R₀ (Ω)  │  R₁ (Ω)  │  C₁ (F)
─────────┼────────────┼──────────┼──────────┼──────────
  100    │   370.0    │  0.045   │  0.028   │  1500
   90    │   368.5    │  0.042   │  0.025   │  1600
   80    │   367.0    │  0.040   │  0.023   │  1650
   70    │   365.5    │  0.039   │  0.022   │  1700
   60    │   364.0    │  0.038   │  0.021   │  1750
   50    │   362.5    │  0.037   │  0.020   │  1800
   40    │   361.0    │  0.038   │  0.021   │  1750
   30    │   359.0    │  0.040   │  0.023   │  1700
   20    │   356.5    │  0.043   │  0.026   │  1600
   10    │   353.0    │  0.048   │  0.031   │  1450
```

1-D lookup tables interpolate between these points.

### Battery Pack Configuration

BMW i3 has:
- **96 cells in series** (96s1p)
- **Each cell**: 3.7V nominal, 60 Ah
- **Total voltage**: 355V nominal (345-370V range)
- **Total capacity**: 60 Ah = 21.3 kWh (18.8 kWh usable)

### Efficiency Losses

```
During discharge (traction):
    P_actual = P_demand / η_discharge
    (η_discharge ≈ 0.95)

During charge (regen):
    P_actual = P_regen × η_charge
    (η_charge ≈ 0.95)
```

### Inputs
1. **Power demand** (W) - positive for discharge, negative for charge

### Outputs
1. **Battery current** (A)
2. **Battery voltage** (V)
3. **State of Charge** (%)
4. **Energy consumed** (integrated over time)

### In Simulink
- **Subsystem** containing:
  - 1-D Lookup tables for V_OC(SoC), R₀(SoC), R₁(SoC), C₁(SoC)
  - MATLAB Function for current calculation
  - Integrator for V₁ dynamics
  - Integrator for SoC calculation

---

## Component 8: Auxiliary Devices

### What It Does
Models **non-propulsion electrical loads** like lights, computers, climate control.

### Why It Matters
Auxiliary power can be **20-30% of total consumption** in city driving!

### Power Levels by Test Cycle

According to EPA/NEDC standards:

| Driving Cycle | Auxiliary Load | What's Included |
|---------------|----------------|-----------------|
| **NEDC** | 300 W | Driving controls + energy management only |
| **FTP-75** | 420 W | + Headlights + taillights |
| **HWFET** | 420 W | + Headlights + taillights |
| **US06** | 420 W | + Headlights + taillights |
| **SC03** | 920 W | + Air conditioning (500W extra) |

### Breakdown of 300W Base Load

```
Controller computers:        80 W
Power steering:             50 W
Brake booster:              30 W
Battery management system:  40 W
Instrument cluster:         20 W
Infotainment system:        30 W
12V battery charging:       50 W
─────────────────────────────────
Total:                     300 W
```

### DC/DC Converter

12V systems draw from the 355V high-voltage battery through a DC/DC converter:

```
P_HV_battery = P_12V_load / (η_DCDC × η_12V_batt)

Where:
- η_DCDC = 0.90 (DC/DC converter efficiency)
- η_12V_batt = 0.95 (12V battery charge/discharge)

Example:
420W at 12V → 420 / (0.90 × 0.95) = 491W from HV battery
```

### Temperature Effects (SC03 Cycle)

Air conditioning load varies with ambient temperature:

```
T_ambient = 35°C (95°F) for SC03 test
P_AC = 500W at steady state
(Can peak at 2-3 kW during initial cooldown)
```

### Inputs
- **Driving cycle type** (determines load level)

### Outputs
- **Constant power draw** (W) added to battery load

### In Simulink
- **Constant block** with value set based on test cycle
- **Add block** to sum with propulsion power

---

## How Everything Connects

### Signal Flow Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                    COMPLETE SIGNAL FLOW                          │
└──────────────────────────────────────────────────────────────────┘

DRIVING     ┌────────────┐
CYCLE  ────▶│  Velocity  │ Desired
            │   Lookup   │ Speed (km/h)
            └──────┬─────┘
                   │
                   ▼
            ┌────────────┐        Actual Speed ◀────────┐
            │   Driver   │        (feedback)             │
            │ PI Control │                               │
            └──────┬─────┘                               │
                   │                                     │
        ┌──────────┴────────────┐                        │
        │                       │                        │
   Accelerator              Brake                        │
   (0-1)                    (0-1)                        │
        │                       │                        │
        ▼                       ▼                        │
    ┌──────────────────────────────────┐                 │
    │  Regenerative Braking Controller │                 │
    └──────────┬───────────────────────┘                 │
               │                                          │
        ┌──────┴────────┐                                │
        │               │                                │
   Motor Torque    Friction Brake                        │
   Demand (Nm)     Force (N)                             │
        │               │                                │
        ▼               │                                │
    ┌──────────┐       │        Motor                   │
    │  Motor + │       │        Speed (RPM)             │
    │ Inverter │       │         ▲                       │
    └────┬─────┘       │         │                       │
         │             │         │                       │
    Motor Torque       │         │                       │
    (Nm)               │         │                       │
         │             │         │                       │
         ▼             │         │                       │
    ┌─────────────────────────────┐                      │
    │     Transmission             │                      │
    │                              │                      │
    └────────┬────────────────┬────┘                      │
             │                │                           │
        Tractive           Motor Speed ──────────────┐    │
        Force (N)          (feedback)                │    │
             │                                       │    │
             ▼                                       │    │
    ┌─────────────────┐                             │    │
    │   Longitudinal  │                             │    │
    │   Vehicle       │                             │    │
    │   Dynamics      │                             │    │
    └────────┬────────┘                             │    │
             │                                      │    │
        Acceleration                                │    │
             │                                      │    │
             ▼                                      │    │
       ┌──────────┐                                 │    │
       │ Integrator│ ────────────────────────────────┤    │
       └──────────┘                                 │    │
                         Actual Velocity ───────────┴────┘
                         (feedback to driver)

POWER FLOW (separate from above):

Motor     P_motor_mech
Power  ─────────────────▶ ┌──────────┐
                          │ Inverter │
                          └────┬─────┘
                               │ P_inverter
                               ▼
                          ┌──────────┐
                          │ DC/DC +  │
                          │Auxiliaries│
                          └────┬─────┘
                               │ P_total
                               ▼
                          ┌──────────┐     SoC (%)
                          │ Battery  │──────────▶
                          │(Thevenin)│
                          └──────────┘
```

### Simulation Loop (Each Time Step)

```
FOR each time step (t = 0, 1, 2, ... seconds):

    1. Get desired_velocity from driving cycle at time t
    
    2. Calculate velocity_error = desired_velocity - actual_velocity
    
    3. Driver PI controller:
       → accelerator_command, brake_command
    
    4. Regen braking controller:
       (based on brake_command, speed, SoC)
       → motor_torque_demand, friction_brake_force
       
    5. Motor model:
       (based on motor_torque_demand, motor_speed)
       → actual_motor_torque
       → P_motor_electrical (power from battery)
       
    6. Inverter:
       (based on P_motor_electrical)
       → P_battery_propulsion
       
    7. Auxiliaries:
       → P_auxiliary (constant 300W for NEDC)
       
    8. Battery model:
       P_total = P_battery_propulsion + P_auxiliary
       → I_battery, V_battery, new_SoC
       
    9. Transmission:
       (based on actual_motor_torque, gear_ratio)
       → tractive_force
       → motor_speed (for next iteration)
       
   10. Vehicle dynamics:
       (based on tractive_force, friction_brake_force)
       → Calculate all resistance forces
       → net_force = tractive_force - resistances
       → acceleration = net_force / mass
       
   11. Integrate acceleration:
       → new_velocity (becomes actual_velocity for next step)
       → distance_traveled
       
   12. Log results:
       → Store velocity, SoC, power, energy at time t

NEXT time step
```

---

## Quick Reference: Key Parameters (BMW i3)

### Vehicle
- Mass: 1270 kg (with driver)
- Drag coefficient (Cd): 0.29
- Frontal area: 2.38 m²
- Tire radius: 0.35 m

### Transmission
- Gear ratio: 9.7:1
- Efficiency: 98%

### Motor
- Max torque: 250 Nm
- Max power: 125 kW (170 HP)
- Max speed: 11,400 RPM
- Peak efficiency: 95% @ 5000 RPM

### Battery
- Configuration: 96s1p (96 cells series)
- Nominal voltage: 355V
- Capacity: 60 Ah (21.3 kWh total, 18.8 kWh usable)
- Chemistry: Lithium-ion

### Target Results (NEDC)
- Distance: 10.8 km
- Duration: 1180 seconds
- Energy consumption: **135 Wh/km** (expected)
- Acceptable error: ±6%

---

## Next Steps

Now that you understand each component:

1. ✅ You know **what** each subsystem does
2. ✅ You know **why** it's needed
3. ✅ You know **how** it calculates outputs from inputs

**Ready to build?** The next step is to create the actual Simulink model with all these components connected.

Would you like me to:
- Start building the Simulink model step-by-step?
- Create a more detailed guide on any specific component?
- Generate the efficiency map data files needed?
