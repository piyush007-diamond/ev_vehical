# BMW i3 Simulink Model - Complete Build Guide

This guide teaches you how to build the BMW i3 electric vehicle simulation model in Simulink from scratch, component by component.

---

## Table of Contents

1. [Overview](#overview)
2. [Model Architecture](#model-architecture)
3. [Prerequisites](#prerequisites)
4. [Building Each Component](#building-each-component)
5. [Testing Each Component](#testing-each-component)
6. [Integration & Results](#integration--results)

---

## Overview

### What We're Building

A complete BMW i3 EV simulation that models:
- **Driver behavior** (PI controller tracking speed)
- **Regenerative braking** (energy recovery)
- **Motor & inverter** (torque/power with efficiency maps)
- **Transmission** (gear ratio, force conversion)
- **Vehicle dynamics** (acceleration, drag, rolling resistance)
- **Battery pack** (Thevenin model with SoC tracking)
- **Auxiliaries** (constant power load)

### Model Flow

```
Drive Cycle → Driver → Motor Torque → Transmission → Vehicle Dynamics
                ↓                                           ↓
            Regen Brake ← ← ← ← ← ← ← ← ← ← ← Velocity (feedback)
                ↓
            Battery ← Motor Power
                ↑
            Auxiliaries
```

---

## Model Architecture

### Top-Level Structure

```
bmw_i3_full_model/
├── Clock (time source)
├── Drive_Cycle (lookup table: time → velocity)
├── Driver_Model (PI controller)
├── Regen_Controller (braking logic)
├── Motor_Drive (torque & power)
├── Transmission (gear ratio)
├── Vehicle_Dynamics (physics)
├── Battery_Pack (Thevenin model)
├── Auxiliaries (constant load)
└── Logging blocks (To Workspace)
```

---

## Prerequisites

### Required Toolboxes
- Simulink
- Simulink Control Design (for PID blocks)

### Parameters Setup

Before building, run this in MATLAB:
```matlab
[vehicle, cycle] = setup_full_params();
```

This creates two structs in your workspace with all parameters.

---

## Building Each Component

### 1. Driver Model (PI Controller)

**Purpose**: Track desired velocity by outputting accelerator/brake commands.

**Inputs**:
- `Vel_Ref` (m/s) - desired speed from drive cycle
- `Vel_Actual` (m/s) - current vehicle speed

**Outputs**:
- `Accel_Cmd` (0-1) - accelerator pedal position
- `Brake_Cmd` (0-1) - brake pedal position

**Logic**:
1. Calculate error: `error = Vel_Ref - Vel_Actual`
2. PI controller: `u = Kp*error + Ki*∫error` (Kp=60, Ki=2)
3. Saturate: `-1 ≤ u ≤ 1`
4. Split positive/negative:
   - If `u > 0`: `Accel_Cmd = u`, `Brake_Cmd = 0`
   - If `u < 0`: `Accel_Cmd = 0`, `Brake_Cmd = -u`

**Manual Build Steps**:

1. Create subsystem: `Driver_Model`
2. Add inputs: `Vel_Ref`, `Vel_Actual`
3. Add **Subtract** block: `Vel_Ref - Vel_Actual`
4. Add **PID Controller**:
   - Set P = 60, I = 2, D = 0
5. Add **Saturation**: Upper = 1, Lower = -1
6. Add logic to split accel/brake:
   - **Relational Operator**: `u > 0`
   - **Switch** (for accel): passes `u` if true, else 0
   - **Gain** (-1) + **Relational Operator** for brake
   - **Switch** (for brake): passes `-u` if `u < 0`, else 0
7. Add outputs: `Accel_Cmd`, `Brake_Cmd`

**Testing**:
```matlab
% Test driver response
open_system('bmw_i3_full_model/Driver_Model');
% Set Vel_Ref = 20 m/s (constant)
% Set Vel_Actual = 15 m/s (constant)
% Expected: Accel_Cmd > 0, Brake_Cmd = 0
```

---

### 2. Regenerative Braking Controller

**Purpose**: Split brake demand between regenerative (motor) and friction brakes.

**Inputs**:
- `Brake_Cmd` (0-1)
- `Velocity` (m/s)
- `SoC` (0-1)

**Outputs**:
- `T_regen_cmd` (Nm, negative) - motor braking torque
- `F_friction` (N) - mechanical brake force

**Logic**:

1. **Calculate total brake force demand**:
   ```
   F_demand = Brake_Cmd × F_max
   F_max = M × g × μ = 1270 × 9.81 × 0.8 ≈ 9966 N
   ```

2. **Calculate max regen force available**:
   ```
   F_power_limit = P_regen_max / v  (50 kW / velocity)
   Speed_factor = fade from 0% at 10 km/h to 100% at 20 km/h
   SoC_factor = fade from 100% at 90% SoC to 0% at 98% SoC
   F_regen_avail = F_power_limit × Speed_factor × SoC_factor
   ```

3. **Split forces**:
   ```
   F_regen = min(F_demand, F_regen_avail)
   F_friction = F_demand - F_regen
   ```

4. **Convert to motor torque**:
   ```
   T_regen = -F_regen × r_tire / (gear_ratio × η_trans)
   ```

**Manual Build Steps**:

1. Create subsystem: `Regen_Controller`
2. Add inputs: `Brake_Cmd`, `Velocity`, `SoC`
3. Calculate `F_demand`:
   - **Gain**: `Brake_Cmd × 1270 × 9.81 × 0.8`
4. Calculate power limit:
   - **Constant**: `P_regen_max = 50000`
   - **Saturation**: protect velocity (min = 0.1)
   - **Product** (divide): `P_regen_max / v`
5. Add **1-D Lookup Table** for speed fade:
   - Breakpoints: `[0, 2.77, 5.55, 100]`
   - Table: `[0, 0, 1, 1]`
6. Add **1-D Lookup Table** for SoC fade:
   - Breakpoints: `[0, 0.9, 0.98, 1]`
   - Table: `[1, 1, 0, 0]`
7. **Product** (3 inputs): multiply power limit × speed factor × SoC factor
8. **MinMax** (min): `F_regen = min(F_demand, F_avail)`
9. **Subtract**: `F_friction = F_demand - F_regen`
10. **Gain**: convert to torque: `-r_tire / (gear_ratio × η_trans)`
11. Add outputs: `T_regen_cmd`, `F_friction`

**Testing**:
```matlab
% Test at different speeds and SoC
% Low speed (5 m/s): expect low regen
% High speed (20 m/s): expect full regen
% High SoC (0.97): expect reduced regen
```

---

### 3. Motor Drive

**Purpose**: Convert torque demand to actual torque and calculate electrical power.

**Inputs**:
- `T_demand` (Nm)
- `Speed_rads` (rad/s)

**Outputs**:
- `T_actual` (Nm) - limited by motor capability
- `P_elec` (W) - electrical power from battery

**Logic**:

1. **Torque limiting**:
   ```
   T_max(RPM) = lookup from motor torque curve
   T_actual = saturate(T_demand, -T_max, T_max)
   ```

2. **Efficiency lookup**:
   ```
   η_motor(RPM, |T|) = 2D lookup table
   η_total = η_motor × η_inverter (0.95)
   ```

3. **Power calculation**:
   ```
   P_mech = T_actual × ω
   If P_mech > 0 (motoring): P_elec = P_mech / η_total
   If P_mech < 0 (generating): P_elec = P_mech × η_total
   ```

**Manual Build Steps**:

1. Create subsystem: `Motor_Drive`
2. Add inputs: `T_demand`, `Speed_rads`
3. Convert speed to RPM:
   - **Gain**: `60 / (2π)`
4. **1-D Lookup Table**: `T_max(RPM)`
   - Breakpoints: `vehicle.motor.speed_vec`
   - Table: `vehicle.motor.max_torque`
5. **Gain** (-1): for negative limit
6. **Saturation Dynamic**: limit torque between `-T_max` and `T_max`
7. **Abs**: for efficiency lookup
8. **2-D Lookup Table**: `η(RPM, |T|)`
   - Row breakpoints: `vehicle.motor.speed_vec`
   - Column breakpoints: `vehicle.motor.torque_vec`
   - Table: `vehicle.motor.eff_map`
9. **Constant**: inverter efficiency = 0.95
10. **Product**: `η_total = η_motor × η_inv`
11. **Product**: `P_mech = T × ω`
12. **Relational Operator**: `P_mech > 0`
13. **Switch**: select motoring or generating path
    - Motoring: **Product** (divide): `P_mech / η_total`
    - Generating: **Product** (multiply): `P_mech × η_total`
14. Add outputs: `T_actual`, `P_elec`

**Testing**:
```matlab
% Test motoring (positive torque)
% Test regenerating (negative torque)
% Verify efficiency is applied correctly
```

---

### 4. Transmission

**Purpose**: Convert between motor torque/speed and wheel force/speed.

**Inputs**:
- `Motor_Torque` (Nm)
- `Veh_Speed` (m/s)

**Outputs**:
- `Tractive_Force` (N)
- `Motor_Speed` (rad/s)

**Logic**:
```
F_tractive = T_motor × G × η_trans / r_tire
ω_motor = v_vehicle × G / r_tire

Where:
G = gear_ratio = 9.665
η_trans = 0.95
r_tire = 0.318 m
```

**Manual Build Steps**:

1. Create subsystem: `Transmission`
2. Add inputs: `Motor_Torque`, `Veh_Speed`
3. **Gain** (for force): `G × η_trans / r_tire`
4. **Gain** (for speed): `G / r_tire`
5. Add outputs: `Tractive_Force`, `Motor_Speed`

**Testing**:
```matlab
% Simple conversion - verify math
% T_motor = 250 Nm → F ≈ 7200 N
% v = 20 m/s → ω ≈ 607 rad/s
```

---

### 5. Vehicle Dynamics

**Purpose**: Calculate vehicle motion from forces.

**Inputs**:
- `F_Tractive` (N)
- `F_Brake` (N)

**Outputs**:
- `Velocity` (m/s)
- `Distance` (m)

**Logic**:

1. **Aerodynamic drag**:
   ```
   F_aero = 0.5 × ρ × Cd × A × v²
   ρ = 1.225 kg/m³, Cd = 0.29, A = 2.38 m²
   ```

2. **Rolling resistance**:
   ```
   F_roll = Crr × M × g
   Crr = 0.01, M = 1270 kg
   ```

3. **Net force**:
   ```
   F_net = F_tractive - F_brake - F_aero - F_roll
   ```

4. **Acceleration**:
   ```
   a = F_net / (M × 1.05)  [1.05 accounts for rotational inertia]
   ```

5. **Integration**:
   ```
   v = ∫a dt
   distance = ∫v dt
   ```

**Manual Build Steps**:

1. Create subsystem: `Vehicle_Dynamics`
2. Add inputs: `F_Tractive`, `F_Brake`
3. Calculate aerodynamic drag:
   - **Product**: `v × v` (feedback from integrator)
   - **Gain**: `0.5 × 1.225 × 0.29 × 2.38`
4. **Constant**: rolling resistance = `0.01 × 1270 × 9.81`
5. **Add** (4 inputs, signs: `+---`): sum all forces
6. **Gain**: `1 / (1270 × 1.05)` for acceleration
7. **Integrator**: velocity (IC = 0)
8. **Integrator**: distance (IC = 0)
9. Connect velocity feedback to drag calculation
10. Add outputs: `Velocity`, `Distance`

**Testing**:
```matlab
% Apply constant force, verify acceleration
% Check terminal velocity (drag balances force)
```

---

### 6. Battery Pack (Thevenin Model)

**Purpose**: Model battery voltage, current, and state of charge.

**Inputs**:
- `P_elec` (W) - power from motor
- `P_aux` (W) - auxiliary load

**Outputs**:
- `SoC` (0-1)
- `V_term` (V) - terminal voltage
- `I_batt` (A) - current

**Logic**:

1. **Equivalent circuit**:
   ```
   V_term = V_oc - I×R0 - V1
   V1 dynamics: dV1/dt = -V1/(R1×C1) + I/C1
   ```

2. **Current calculation** (from power):
   ```
   P = V_term × I = (V_oc - I×R0 - V1) × I
   Solving quadratic: I = (V_oc - V1 - √[(V_oc-V1)² - 4×R0×P]) / (2×R0)
   ```

3. **SoC dynamics**:
   ```
   dSoC/dt = -I / (Capacity × 3600)
   Capacity = 22 Ah
   ```

4. **Parameter lookups** (all functions of SoC):
   - `V_oc(SoC)`: open circuit voltage
   - `R0(SoC)`: series resistance
   - `R1(SoC)`, `C1(SoC)`: RC pair

**Manual Build Steps**:

1. Create subsystem: `Battery_Pack`
2. Add inputs: `P_elec`, `P_aux`
3. **Add**: total power = `P_elec + P_aux`
4. Add four **1-D Lookup Tables** (all vs SoC):
   - `V_oc`: breakpoints = `vehicle.battery.soc_vec`, table = `vehicle.battery.ocv_vec`
   - `R0`: table = `vehicle.battery.r0_vec`
   - `R1`: table = `vehicle.battery.r1_vec`
   - `C1`: table = `vehicle.battery.c1_vec`
5. Calculate current using **Fcn** block:
   - Inputs (via **Mux**): `[P, V_oc, R0, V1]`
   - Expression: `((u(2)-u(4)) - sqrt((u(2)-u(4))^2 - 4*u(3)*u(1))) / (2*u(3))`
6. Calculate V1 dynamics using **Fcn** block:
   - Inputs (via **Mux**): `[I, V1, R1, C1]`
   - Expression: `-u(2)/(u(3)*u(4)) + u(1)/u(4)`
7. **Integrator**: V1 (IC = 0)
8. Calculate SoC change:
   - **Gain**: `-1 / (22 × 3600)`
9. **Integrator**: SoC (IC = 1.0 = 100%)
10. Calculate terminal voltage:
    - **Product**: `I × R0`
    - **Add** (signs: `+--`): `V_oc - I×R0 - V1`
11. Connect SoC feedback to all lookup tables
12. Connect V1 feedback to current and V1 calculations
13. Add outputs: `SoC`, `V_term`, `I_batt`

**Testing**:
```matlab
% Constant discharge: verify SoC decreases linearly
% Check voltage drop under load
% Verify current calculation
```

---

### 7. Auxiliaries

**Purpose**: Constant power load (HVAC, electronics, etc.)

**Outputs**:
- `P_aux` (W)

**Manual Build Steps**:

1. Create subsystem: `Auxiliaries`
2. **Constant**: value = `vehicle.aux_power` (300 W)
3. Add output: `P_aux`

---

## Testing Each Component

### Component-Level Testing

Create a test harness for each subsystem:

```matlab
% Example: Test Driver Model
model = 'test_driver';
new_system(model);
open_system(model);

% Add constant sources for inputs
add_block('simulink/Sources/Constant', [model '/Vel_Ref']);
set_param([model '/Vel_Ref'], 'Value', '20');

add_block('simulink/Sources/Constant', [model '/Vel_Actual']);
set_param([model '/Vel_Actual'], 'Value', '15');

% Add your subsystem
add_block('bmw_i3_full_model/Driver_Model', [model '/Driver']);

% Connect and add scopes
add_line(model, 'Vel_Ref/1', 'Driver/1');
add_line(model, 'Vel_Actual/1', 'Driver/2');

add_block('simulink/SinksBehaviours[model '/Scope']);
add_line(model, 'Driver/1', 'Scope/1');

% Run
sim(model);
```

### Expected Behaviors

| Component | Test Input | Expected Output |
|-----------|------------|-----------------|
| Driver | Vel_Ref=20, Vel_Actual=15 | Accel > 0, Brake = 0 |
| Driver | Vel_Ref=15, Vel_Actual=20 | Accel = 0, Brake > 0 |
| Regen | Brake=1, v=5 m/s | Low regen (speed fade) |
| Regen | Brake=1, v=20 m/s, SoC=0.5 | Full regen |
| Motor | T=250, ω=300 | P_elec > 0 (motoring) |
| Motor | T=-100, ω=300 | P_elec < 0 (generating) |
| Battery | P=10000 W | I ≈ 28 A, SoC decreases |

---

## Integration & Results

### Connecting Everything

The top-level model connects all subsystems with feedback loops:

**Main Connections**:
1. `Clock` → `Drive_Cycle` → `Driver/Vel_Ref`
2. `Driver/Accel_Cmd` → (scaled by 250) → `Motor/T_demand`
3. `Driver/Brake_Cmd` → `Regen/Brake_Cmd`
4. `Regen/T_regen_cmd` → (summed with accel torque) → `Motor/T_demand`
5. `Motor/T_actual` → `Transmission/Motor_Torque`
6. `Transmission/Tractive_Force` → `Dynamics/F_Tractive`
7. `Regen/F_friction` → `Dynamics/F_Brake`
8. `Motor/P_elec` → `Battery/P_elec`
9. `Auxiliaries/P_aux` → `Battery/P_aux`

**Feedback Loops** (use Goto/From blocks):
- `Velocity`: Dynamics → Driver, Regen, Transmission
- `SoC`: Battery → Regen
- `Motor_Speed`: Transmission → Motor

### Running the Full Simulation

```matlab
% Run the complete model
run_full_simulation
```

### Viewing Results

**During Simulation**:
- Add **Scope** blocks to any signal
- Double-click scope to view real-time plot

**After Simulation**:
The script generates 3 plots:

1. **Speed Tracking**: Reference vs Actual velocity
2. **Power Consumption**: Battery power over time
3. **State of Charge**: SoC depletion

**Key Metrics Displayed**:
```
Total Distance:       11.0 km
Total Energy:         1485 Wh
Consumption:          135 Wh/km
SoC Drop:             6.6%
Max Speed Error:      2.3 km/h
```

### Interpreting Results

**Good Results**:
- Speed tracking error < 3 km/h
- Consumption: 130-140 Wh/km (matches BMW i3 spec)
- SoC drop: 6-7% for NEDC cycle
- Power profile shows regeneration (negative power) during braking

**Common Issues**:
| Issue | Cause | Fix |
|-------|-------|-----|
| Speed oscillates | PI gains too high | Reduce Kp/Ki |
| Poor tracking | PI gains too low | Increase Kp/Ki |
| High consumption | Efficiency maps wrong | Check motor/battery params |
| Negative SoC | Battery too small | Increase capacity |

---

## Advanced: Viewing Intermediate Signals

### Method 1: Scopes

Add scope to any signal:
```matlab
add_block('simulink/Sinks/Scope', 'bmw_i3_full_model/My_Scope');
add_line('bmw_i3_full_model', 'Motor_Drive/1', 'My_Scope/1');
```

### Method 2: Signal Logging

Enable signal logging:
1. Right-click signal → Properties
2. Check "Log signal data"
3. After simulation: `simOut.logsout`

### Method 3: To Workspace

Already implemented for key signals:
- `sim_time`, `vel_ref`, `vel_actual`
- `soc`, `v_term`, `i_batt`
- `p_elec`, `distance`

Access after simulation:
```matlab
plot(time, soc*100);
ylabel('SoC (%)');
```

---

## Summary

You've learned:
1. ✅ **Architecture**: 7 subsystems with feedback loops
2. ✅ **Each Component**: Purpose, logic, manual build steps
3. ✅ **Testing**: How to verify each component works
4. ✅ **Integration**: Connecting everything together
5. ✅ **Results**: Running simulation and interpreting outputs

**Next Steps**:
- Build each subsystem manually following this guide
- Test individually before integration
- Experiment with different drive cycles
- Modify parameters to see effects on consumption

**Key Files**:
- [setup_full_params.m](file:///c:/Users/Piyush/Downloads/agents/execution/setup_full_params.m) - All parameters
- [build_full_model.m](file:///c:/Users/Piyush/Downloads/agents/execution/build_full_model.m) - Automated build script
- [run_full_simulation.m](file:///c:/Users/Piyush/Downloads/agents/execution/run_full_simulation.m) - Run and analyze
