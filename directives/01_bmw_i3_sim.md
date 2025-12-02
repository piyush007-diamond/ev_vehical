# Electric Vehicle Energy Consumption Simulation Directive

## Goal
Develop an autonomous agent that creates and executes MATLAB/Simulink models for electric vehicle energy consumption estimation across standardized driving cycles, achieving <6% error compared to experimental benchmarks (BMW i3 case study).

## Inputs
* **Vehicle Configuration File**: JSON/YAML with EV specifications (mass, aerodynamics, powertrain parameters, battery specs)
  - Example: `configs/bmw_i3_2014.json`
* **Efficiency Map Data**: Motor and inverter efficiency tables
  - Format: `.mat` files or CSV (torque × speed grids)
  - Location: `data/efficiency_maps/motor_efficiency.csv`, `data/efficiency_maps/inverter_efficiency.csv`
* **Driving Cycle Files**: Standard test cycle velocity profiles (NEDC, FTP-75, HWFET, US06, SC03)
  - Format: CSV with columns `[time_s, velocity_kmh]`
  - Location: `data/driving_cycles/`
* **Validation Benchmarks**: Expected energy consumption values for validation
  - Format: JSON with test results (e.g., `{"NEDC": 135, "EPA_combined": 179}` in Wh/km)
* **MATLAB MCP Server**: Must be running and accessible via stdio
  - Installation path for verification

## Tools & Execution Strategy
* **Primary Script**: `ev_simulation_agent.py` (Agent orchestrator - connects to MATLAB MCP, manages workflow)
* **Model Generator Script**: `matlab_model_builder.py` (Generates Simulink .slx files programmatically via MCP commands)
* **Simulation Runner Script**: `run_simulation.py` (Executes simulations and collects results via MATLAB MCP)
* **Validation Script**: `validate_results.py` (Compares outputs against benchmarks, calculates error metrics)
* **External APIs**:
  - **MATLAB MCP Server** (stdio connection): For all MATLAB/Simulink operations
  - **NumPy/Pandas**: Data manipulation and numerical calculations
  - **Matplotlib/Seaborn**: Visualization of results (speed tracking, energy profiles, error analysis)
* **Storage**:
  - Simulink models: `models/ev_model_[timestamp].slx`
  - Simulation outputs: `outputs/simulation_results/[cycle_name]_[timestamp].csv`
  - Validation reports: `outputs/validation_reports/report_[timestamp].md`
  - Logs: `logs/agent_execution_[timestamp].log`

## Process (SOP)

### 1. Initialization & Environment Verification
* **Verify MATLAB MCP Connection**: Test connection to MATLAB MCP server using stdio protocol
* **Load Vehicle Configuration**: Parse `configs/bmw_i3_2014.json` (or specified vehicle config)
* **Import Efficiency Maps**: 
  - Read motor efficiency map (torque × speed → efficiency %)
  - Read inverter efficiency map (torque × speed → efficiency %)
  - Validate data completeness (check for NaN values, reasonable ranges 0-100%)
* **Load Driving Cycles**: Import all `.csv` files from `data/driving_cycles/` directory
* **Validate Input Data Integrity**:
  - Confirm all required vehicle parameters exist (mass, Cd, frontal area, battery capacity, gear ratio, etc.)
  - Check driving cycle format (time monotonically increasing, velocity non-negative)
  - Verify efficiency maps cover full operational range (0-11400 rpm, 0-250 Nm for BMW i3)
* **Load Validation Benchmarks**: Read expected energy consumption values from `configs/validation_benchmarks.json`

### 2. Simulink Model Construction (via MATLAB MCP)
The agent will issue MATLAB commands through MCP to build the model programmatically:

**2.1 Create Base Model Structure**
* Send MCP command: Create new Simulink model `ev_energy_model.slx`
* Define simulation parameters (solver: ode45, fixed-step: 1 second, stop time: from driving cycle duration)

**2.2 Build Subsystem: Driving Cycle Input**
* Create "From Workspace" block reading time-series data `[time, velocity_desired]`
* Add unit conversion block (km/h → m/s)

**2.3 Build Subsystem: Driver Model (PI Controller)**
* Implement PI controller (P=60, I=2) using Simulink PID block
* Input: `velocity_error = velocity_desired - velocity_actual`
* Output: Driver command [-100, +100] → Split into:
  - Accelerator command [0, 1] (when positive)
  - Brake command [0, 1] (when negative)
* Add saturation blocks to enforce ±2 km/h tracking tolerance

**2.4 Build Subsystem: Longitudinal Vehicle Dynamics**
* **Calculate Resistance Forces** (using MATLAB Function blocks):
  - Gradient resistance: `R_theta = M_vehicle * g * sin(road_angle)`
  - Rolling resistance: `R_roll = C_RR * M_vehicle * g * cos(road_angle)` where `C_RR = 0.01 * (1 + V_vehicle/100)`
  - Aerodynamic drag: `R_aero = 0.5 * rho * A_frontal * Cd * (V_vehicle - V_wind)^2`
  - Inertia resistance: `R_inertia = delta * M_vehicle * acceleration`
  - Transmission loss: `R_trans = (R_roll + R_aero + R_theta + R_inertia) * (1 - eta_transmission) / eta_transmission`
* **Integrate Vehicle Speed**: 
  - Net force = Tractive force - Total resistance
  - Acceleration = Net force / M_vehicle
  - Integrate acceleration → velocity (output: `velocity_actual`)

**2.5 Build Subsystem: Regenerative Braking Controller**
* **Implement Series Brake Logic**:
  - Calculate `X_BMAX = phi * M_vehicle * g` (max braking force)
  - Calculate demanded motor braking torque from brake command
  - Apply power limit: `P_regen_max = 53 kW` (for BMW i3)
  - **Speed-dependent factor**: 
    - 0% below 10 km/h
    - Linear ramp from 10-20 km/h
    - 100% above 20 km/h
  - **Deceleration limit**: Disable regen above 0.7g deceleration
  - **SoC limit**: Disable regen above 95% SoC
  - **Distribute braking**: 
    - If `brake_demand < EM_available_brake` → 100% regen, 0% friction
    - Else → Max regen + friction makeup

**2.6 Build Subsystem: Electric Motor & Inverter**
* **Motor Torque Lookup**: 
  - Input: Motor speed (rpm)
  - 1D lookup table: Max torque vs speed (from motor torque curve)
  - Calculate demanded torque: `T_demand = T_max * accelerator_command`
* **Motor Efficiency Lookup**:
  - 2D lookup table: Input (torque, speed) → Output (efficiency %)
  - Apply efficiency: `T_output = T_demand * eta_motor`
* **Inverter Efficiency Lookup**:
  - 2D lookup table: Input (torque, speed) → Output (efficiency %)
  - Calculate battery power: `P_battery = P_motor / eta_inverter`
* **DC/DC Converter**: Fixed 90% efficiency for auxiliary power

**2.7 Build Subsystem: Transmission**
* Calculate wheel torque: `T_wheel = T_motor * gear_ratio * eta_transmission`
* Calculate tractive force: `F_traction = T_wheel / r_tire`
* Calculate motor speed: `omega_motor = V_vehicle * gear_ratio / r_tire`

**2.8 Build Subsystem: Battery Model (Thevenin Equivalent Circuit)**
* **Thevenin Parameters** (SoC-dependent lookup tables):
  - Open circuit voltage: `V_OC(SoC)`
  - Ohmic resistance: `R_0(SoC)`
  - Polarization resistance: `R_1(SoC)`
  - Polarization capacitance: `C_1(SoC)`
* **Voltage Calculation**:
  - `V_terminal = V_OC - R_0 * I_battery - V_1`
  - `dV_1/dt = -V_1/(R_1*C_1) + I_battery/C_1`
* **Current Calculation** (from power demand):
  - `I_cell = (V_OC - sqrt(V_OC^2 - 4*R_0*P_cell)) / (2*R_0)`
  - Apply charging/discharging efficiency (95% for Li-ion)
* **SoC Update** (Coulomb counting):
  - `SoC(t) = SoC_0 - integral(I_cell / C_cell * dt)`
  - Initialize: `SoC_0 = 100%`

**2.9 Build Subsystem: Auxiliary Devices**
* Define auxiliary load profiles (from Table 3 in paper):
  - NEDC: 300W (driving control + energy management only)
  - EPA FTP-75/HWFET/US06: 420W (+ head/tail lamps)
  - EPA SC03: 920W (+ air conditioning 500W)
* Calculate power demand: `P_aux_demand = P_aux / (eta_DC_DC * eta_12V_battery)`

**2.10 Connect All Subsystems**
* Wire signal flows between subsystems
* Add scopes/loggers for key signals: velocity, SoC, battery power, motor torque, energy consumption
* Configure data logging to workspace: `logsout` structure

### 3. Execution Loop (Per Driving Cycle)

**For each driving cycle (NEDC, FTP-75, HWFET, US06, SC03):**

**3.1 Configure Simulation**
* Load velocity profile for current cycle
* Set auxiliary load based on test procedure (see Section 3.1 in paper)
* Initialize battery SoC = 100%
* Set simulation stop time = cycle duration

**3.2 Run Simulation (via MATLAB MCP)**
* Send MCP command: `sim('ev_energy_model')`
* Monitor simulation progress (check for errors/warnings)
* Capture simulation outputs: time-series data for all logged signals

**3.3 Calculate Energy Metrics**
* **Extract battery power data**: `P_battery(t)` from simulation output
* **Calculate energy consumed during traction**:
  - `E_traction = sum(P_battery(t) * dt)` for all timesteps where `P_battery > 0`
* **Calculate energy regenerated during braking**:
  - `E_regen = sum(P_battery(t) * dt)` for all timesteps where `P_battery < 0`
* **Net energy consumption**: `E_net = E_traction - E_regen` (in Wh)
* **Distance traveled**: `distance = sum(velocity * dt)` (in km)
* **Specific energy consumption**: `E_specific = E_net / distance` (in Wh/km)

**3.4 Store Simulation Results**
* Save detailed time-series to CSV: `outputs/simulation_results/[cycle]_detailed_[timestamp].csv`
  - Columns: time, velocity_desired, velocity_actual, motor_torque, battery_power, SoC, energy_cumulative
* Save summary metrics to JSON: `outputs/simulation_results/[cycle]_summary_[timestamp].json`
  - Fields: cycle_name, distance_km, energy_wh, energy_per_km, simulation_time_s, tracking_error_max

### 4. EPA Combined Calculation (If Running All EPA Cycles)
* Calculate EPA city fuel economy using Equations 30-31 from paper:
  - `City_Running_FE = 0.82 * [0.89/FTP + 0.11/US06] + 0.18/FTP + 0.133 * 1.083 * [1/SC03 - 1/FTP]`
  - `City_FC = 1/0.905 * 1/City_Running_FE`
* Calculate EPA highway fuel economy using Equations 32-33:
  - `Highway_Running_FE = 1.007 * [0.79/US06 + 0.21/HWFET] + 0.133 * 0.377 * [1/SC03 - 1/FTP]`
  - `Highway_FC = 1/0.905 * 1/Highway_Running_FE`
* Calculate EPA combined using Equation 34:
  - `Combined_FC = 0.55 * City_FC + 0.45 * Highway_FC`

### 5. Validation & Error Analysis
* **Load Benchmark Data**: Read expected values from `configs/validation_benchmarks.json`
  - Example: `{"NEDC": 135, "EPA_combined": 179}` (Wh/km)
* **Calculate Errors**:
  - For each cycle: `error_percent = (simulated - expected) / expected * 100`
  - Flag validation as PASS if `|error| < 6%`, else FAIL
* **Generate Comparison Table**:
  ```
  | Cycle        | Expected (Wh/km) | Simulated (Wh/km) | Error (%) | Status |
  |--------------|------------------|-------------------|-----------|--------|
  | NEDC         | 135              | 143               | +5.9      | PASS   |
  | EPA Combined | 179              | 176               | -1.7      | PASS   |
  ```
* **Identify Discrepancies**: If error > 6%, log potential causes:
  - Auxiliary load mismatch
  - Efficiency map interpolation errors
  - Driver controller tracking issues
  - Battery model parameter inaccuracies

### 6. Visualization & Reporting
* **Generate Plots** (using Matplotlib):
  - **Speed Tracking Plot**: Reference vs actual velocity over time (like Figure 5 in paper)
  - **Energy Flow Plot**: Battery power vs time (distinguish traction/regen phases)
  - **SoC Depletion**: Battery SoC vs distance traveled
  - **Error Analysis**: Bar chart of percent error by cycle
* **Create Validation Report** (Markdown format):
  - Executive summary (overall accuracy, pass/fail status)
  - Detailed results table (all cycles)
  - Error analysis and potential improvement areas
  - Visualizations embedded as images
  - Save to: `outputs/validation_reports/report_[timestamp].md`

## Self-Annealing & Error Handling

### MATLAB MCP Connection Failures
* **If MCP connection fails at startup**: 
  - Log error details (connection timeout, server not found, etc.)
  - Check if MATLAB MCP server process is running
  - Attempt reconnection up to 3 times with 5-second delays
  - If all retries fail: Print diagnostic instructions ("Ensure MATLAB MCP server is running via `matlab-mcp-server` command") and exit gracefully
  - **Self-Fix**: Attempt to programmatically start MCP server if path is known from config

### Simulink Model Building Errors
* **If model creation command fails**:
  - Read MATLAB error message from MCP response
  - Common issues: Invalid block names, connection errors, parameter mismatches
  - **Self-Fix Strategy**:
    - Parse error message for block/parameter name
    - Log: "Failed to create block [name] due to [reason]"
    - Attempt alternative block configuration (e.g., use built-in blocks vs custom functions)
    - Retry model creation with corrected parameters
  - If 3 consecutive failures: Save partial model state, log failure point, request human intervention

### Simulation Execution Errors
* **If simulation crashes or produces NaN values**:
  - Analyze simulation diagnostics from MATLAB
  - Common causes: Solver issues, algebraic loops, division by zero, integrator wind-up
  - **Self-Fix Strategy**:
    - Switch solver (ode45 → ode23 → ode15s for stiff systems)
    - Reduce simulation step size (1s → 0.5s → 0.1s)
    - Add saturation blocks to prevent unrealistic values
    - Check for algebraic loops and break them with unit delays
    - Re-run simulation with modified settings
  - Log all attempted fixes and outcomes

### Data Loading/Parsing Errors
* **If efficiency map or driving cycle file is malformed**:
  - Catch file read exceptions (FileNotFoundError, JSONDecodeError, pd.errors.ParserError)
  - **Self-Fix Strategy**:
    - Attempt alternative file formats (try .mat if .csv fails, vice versa)
    - Check for common issues: wrong delimiter, missing headers, encoding problems
    - If motor efficiency map is missing: Assume constant 90% efficiency and log warning
    - If driving cycle has gaps: Interpolate missing velocity values linearly
  - Document all data quality issues in validation report

### Validation Failures (Error > 6%)
* **If simulated energy consumption deviates significantly from benchmark**:
  - Do NOT stop execution - this is expected behavior requiring investigation
  - **Self-Analysis Strategy**:
    - Compare auxiliary load assumptions vs actual test conditions
    - Check driver controller tracking quality (max speed error should be ≤2 km/h)
    - Verify efficiency map coverage at operating points (log warnings for extrapolation)
    - Analyze regenerative braking energy recovery (should be 15-25% of total braking energy)
  - **Self-Tuning Attempts**:
    - If speed tracking error > 2 km/h: Increase PI controller gains (P+10, I+0.5) and re-simulate
    - If auxiliary load suspected: Run sensitivity analysis with ±20% load variation
    - If regen energy too low/high: Adjust speed thresholds (u1, u2) or power limits
  - Document all tuning iterations in report

### Incomplete Results
* **If simulation completes but outputs are missing**:
  - Check MATLAB workspace for logged signals
  - **Self-Fix**: Re-run simulation with verbose logging enabled
  - If specific signals missing: Add explicit data logging commands and retry
  - Generate partial report with available data + note missing elements

### File System Errors
* **If unable to write outputs (permissions, disk full)**:
  - Catch IOError/OSError exceptions
  - Attempt to write to alternative location (`/tmp/` or user home directory)
  - Log warning with alternative file path
  - Continue execution if critical data can be stored temporarily

### Critical Failure Protocol
* **If unrecoverable error occurs**:
  - Save agent state to `logs/crash_dump_[timestamp].json` (configuration, execution stage, error stack trace)
  - Generate partial report with results obtained before failure
  - Print diagnostic summary to console with actionable next steps
  - Exit with non-zero status code

## Outputs
* **Primary Deliverable**: Validated Simulink model (`models/ev_energy_model.slx`) achieving <6% error on NEDC and EPA cycles
* **Simulation Results**: CSV files with time-series data for each driving cycle (velocity, power, SoC, energy)
* **Validation Report**: Markdown document (`outputs/validation_reports/report_[timestamp].md`) containing:
  - Energy consumption comparison table (simulated vs. expected)
  - Error analysis by cycle
  - Embedded visualizations (speed tracking, energy flow, SoC curves)
  - Recommendations for model improvement
* **Configuration Archive**: Copy of all input files used (vehicle config, efficiency maps, driving cycles) for reproducibility
* **Execution Log**: Detailed log file (`logs/agent_execution_[timestamp].log`) documenting all agent actions, MCP commands, and errors

---

## Agent Behavior Notes
* **Autonomous Operation**: The agent should run end-to-end without human intervention once initiated
* **Progressive Enhancement**: Start with basic model (no auxiliaries, constant efficiency) → Add complexity → Validate at each step
* **Verbose Logging**: Log every major action (MCP command sent, simulation started, validation result) for transparency
* **Graceful Degradation**: If advanced features fail (e.g., variable efficiency), fall back to simplified assumptions and continue
* **Reproducibility**: Timestamp all outputs and save configurations to enable exact reproduction of results