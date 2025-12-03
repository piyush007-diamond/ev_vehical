function build_full_model()
    % build_full_model - Programmatically construct the full BMW i3 EV Model
    
    model_name = 'bmw_i3_full_model';
    
    % Close if open
    try
        close_system(model_name, 0);
    catch
    end
    
    % Create new model
    new_system(model_name);
    open_system(model_name);
    
    % Setup Model Configuration
    set_param(model_name, 'Solver', 'ode45'); % Variable step for accuracy
    set_param(model_name, 'RelTol', '1e-4');
    set_param(model_name, 'StopTime', '1180'); % NEDC duration
    
    % Load Parameters
    fprintf('Loading parameters...\n');
    [vehicle, cycle] = setup_full_params();
    
    % Assign to base workspace so Simulink can see them
    assignin('base', 'vehicle', vehicle);
    assignin('base', 'cycle', cycle);
    
    %% 1. Build Subsystems
    fprintf('Building Subsystems...\n');
    
    build_driver_subsystem(model_name);
    build_regen_subsystem(model_name);
    build_motor_subsystem(model_name);
    build_transmission_subsystem(model_name);
    build_dynamics_subsystem(model_name);
    build_battery_subsystem(model_name);
    build_aux_subsystem(model_name);
    
    %% 2. Connect Subsystems
    fprintf('Connecting Subsystems...\n');
    connect_all_subsystems(model_name);
    
    %% 3. Add Logging & Scopes
    add_logging(model_name);
    
    %% 4. Save
    save_system(model_name);
    fprintf('Model "%s" created successfully!\n', model_name);
end

%% Subsystem Builders (Stubs for now)

function build_driver_subsystem(model_name)
    % Driver Model: PI Controller
    % Inputs: Desired Velocity, Actual Velocity
    % Outputs: Accel Command, Brake Command
    
    sub_name = [model_name '/Driver_Model'];
    add_block('simulink/Ports & Subsystems/Subsystem', sub_name, 'Position', [50, 50, 150, 150]);
    
    % Delete default contents
    Simulink.SubSystem.deleteContents(sub_name);
    
    % Inputs
    add_block('simulink/Sources/In1', [sub_name '/Vel_Ref'], 'Position', [20, 50, 50, 70]);
    add_block('simulink/Sources/In1', [sub_name '/Vel_Actual'], 'Position', [20, 100, 50, 120]);
    
    % Error Calculation
    add_block('simulink/Math Operations/Subtract', [sub_name '/Subtract'], 'Position', [100, 60, 130, 90]);
    add_line(sub_name, 'Vel_Ref/1', 'Subtract/1');
    add_line(sub_name, 'Vel_Actual/1', 'Subtract/2');
    
    % PI Controller (P=60, I=2)
    add_block('simulink/Continuous/PID Controller', [sub_name '/PID'], 'Position', [180, 60, 220, 90]);
    set_param([sub_name '/PID'], 'P', 'vehicle.driver.Kp', 'I', 'vehicle.driver.Ki', 'D', '0');
    add_line(sub_name, 'Subtract/1', 'PID/1');
    
    % Saturation (Limit -1 to 1)
    add_block('simulink/Discontinuities/Saturation', [sub_name '/Saturation'], 'Position', [260, 60, 290, 90]);
    set_param([sub_name '/Saturation'], 'UpperLimit', '1', 'LowerLimit', '-1');
    add_line(sub_name, 'PID/1', 'Saturation/1');
    
    % Split Accel/Brake Logic
    % Accel = max(0, u)
    % Brake = max(0, -u)
    
    % Accel Path
    add_block('simulink/Logic and Bit Operations/Relational Operator', [sub_name '/Is_Pos'], 'Position', [350, 40, 380, 70]);
    set_param([sub_name '/Is_Pos'], 'Operator', '>');
    
    add_block('simulink/Sources/Constant', [sub_name '/Zero_Ref_1'], 'Position', [300, 80, 320, 100]);
    set_param([sub_name '/Zero_Ref_1'], 'Value', '0');
    
    add_block('simulink/Signal Routing/Switch', [sub_name '/Switch_Accel'], 'Position', [450, 50, 480, 80]);
    set_param([sub_name '/Switch_Accel'], 'Threshold', '0.5'); % Boolean switch
    
    add_line(sub_name, 'Saturation/1', 'Is_Pos/1');
    add_line(sub_name, 'Zero_Ref_1/1', 'Is_Pos/2');
    add_line(sub_name, 'Is_Pos/1', 'Switch_Accel/2');
    add_line(sub_name, 'Saturation/1', 'Switch_Accel/1'); % Pass value if > 0
    
    add_block('simulink/Sources/Constant', [sub_name '/Zero'], 'Position', [350, 90, 380, 110]);
    set_param([sub_name '/Zero'], 'Value', '0');
    add_line(sub_name, 'Zero/1', 'Switch_Accel/3'); % Else 0
    
    % Brake Path
    add_block('simulink/Math Operations/Gain', [sub_name '/Negate'], 'Position', [350, 130, 380, 160]);
    set_param([sub_name '/Negate'], 'Gain', '-1');
    add_line(sub_name, 'Saturation/1', 'Negate/1');
    
    add_block('simulink/Logic and Bit Operations/Relational Operator', [sub_name '/Is_Neg'], 'Position', [420, 130, 450, 160]);
    set_param([sub_name '/Is_Neg'], 'Operator', '>'); % Check if -u > 0 (i.e. u < 0)
    
    add_block('simulink/Sources/Constant', [sub_name '/Zero_Ref_2'], 'Position', [380, 170, 400, 190]);
    set_param([sub_name '/Zero_Ref_2'], 'Value', '0');
    
    add_block('simulink/Signal Routing/Switch', [sub_name '/Switch_Brake'], 'Position', [520, 140, 550, 170]);
    
    add_line(sub_name, 'Negate/1', 'Is_Neg/1');
    add_line(sub_name, 'Zero_Ref_2/1', 'Is_Neg/2');
    add_line(sub_name, 'Is_Neg/1', 'Switch_Brake/2');
    add_line(sub_name, 'Negate/1', 'Switch_Brake/1'); % Pass -u if -u > 0
    add_line(sub_name, 'Zero/1', 'Switch_Brake/3'); % Else 0
    
    % Outputs
    add_block('simulink/Sinks/Out1', [sub_name '/Accel_Cmd'], 'Position', [600, 55, 630, 75]);
    add_block('simulink/Sinks/Out1', [sub_name '/Brake_Cmd'], 'Position', [600, 145, 630, 165]);
    
    add_line(sub_name, 'Switch_Accel/1', 'Accel_Cmd/1');
    add_line(sub_name, 'Switch_Brake/1', 'Brake_Cmd/1');
end

function build_regen_subsystem(model_name)
    % Regenerative Braking Controller
    % Inputs: Brake_Cmd (0-1), Velocity (m/s), SoC (0-1)
    % Outputs: Motor_Torque_Cmd (Nm, negative), Friction_Brake_Force (N)
    
    sub_name = [model_name '/Regen_Controller'];
    add_block('simulink/Ports & Subsystems/Subsystem', sub_name, 'Position', [200, 200, 300, 300]);
    Simulink.SubSystem.deleteContents(sub_name);
    
    % Inputs
    add_block('simulink/Sources/In1', [sub_name '/Brake_Cmd'], 'Position', [20, 50, 50, 70]);
    add_block('simulink/Sources/In1', [sub_name '/Velocity'], 'Position', [20, 150, 50, 170]);
    add_block('simulink/Sources/In1', [sub_name '/SoC'], 'Position', [20, 250, 50, 270]);
    
    % Constants
    % Max Braking Force (F_bmax) = M * g * phi (0.8)
    % We'll use a Gain for this: Brake_Cmd * F_bmax
    % F_bmax approx 1270 * 9.81 * 0.8 = 9966 N
    add_block('simulink/Math Operations/Gain', [sub_name '/Calc_F_Demand'], 'Position', [100, 45, 150, 75]);
    set_param([sub_name '/Calc_F_Demand'], 'Gain', 'vehicle.M_vehicle*vehicle.g*0.8'); 
    add_line(sub_name, 'Brake_Cmd/1', 'Calc_F_Demand/1');
    
    % Calculate Max Regen Force Available
    % 1. Power Limit: F_lim_p = P_max / v
    add_block('simulink/Sources/Constant', [sub_name '/P_regen_max'], 'Position', [100, 120, 140, 140]);
    set_param([sub_name '/P_regen_max'], 'Value', 'vehicle.regen.max_power');
    
    add_block('simulink/Math Operations/Product', [sub_name '/Div_P_by_V'], 'Position', [200, 130, 230, 160]);
    set_param([sub_name '/Div_P_by_V'], 'Inputs', '*/');
    
    % Protect against divide by zero (v < 0.1)
    add_block('simulink/Discontinuities/Saturation', [sub_name '/Min_Vel'], 'Position', [100, 150, 130, 170]);
    set_param([sub_name '/Min_Vel'], 'LowerLimit', '0.1', 'UpperLimit', 'inf');
    add_line(sub_name, 'Velocity/1', 'Min_Vel/1');
    
    add_line(sub_name, 'P_regen_max/1', 'Div_P_by_V/1');
    add_line(sub_name, 'Min_Vel/1', 'Div_P_by_V/2');
    
    % 2. Speed Fade (0% at 0.5 m/s, 100% at 2.0 m/s)
    % 0.5 m/s = 1.8 km/h, 2.0 m/s = 7.2 km/h
    add_block('simulink/Lookup Tables/1-D Lookup Table', [sub_name '/Speed_Factor'], 'Position', [200, 180, 250, 210]);
    set_param([sub_name '/Speed_Factor'], 'Table', '[0 0 1 1]', 'BreakpointsForDimension1', '[0 0.5 2.0 100]');
    add_line(sub_name, 'Velocity/1', 'Speed_Factor/1');
    
    % 3. SoC Fade (100% at 90%, 0% at 98%)
    add_block('simulink/Lookup Tables/1-D Lookup Table', [sub_name '/SoC_Factor'], 'Position', [200, 250, 250, 280]);
    set_param([sub_name '/SoC_Factor'], 'Table', '[1 1 0 0]', 'BreakpointsForDimension1', '[0 0.9 0.98 1]');
    add_line(sub_name, 'SoC/1', 'SoC_Factor/1');
    
    % Combine Limits: F_regen_avail = F_lim_p * Speed_Factor * SoC_Factor
    add_block('simulink/Math Operations/Product', [sub_name '/Calc_F_Avail'], 'Position', [300, 150, 330, 200]);
    set_param([sub_name '/Calc_F_Avail'], 'Inputs', '3');
    add_line(sub_name, 'Div_P_by_V/1', 'Calc_F_Avail/1');
    add_line(sub_name, 'Speed_Factor/1', 'Calc_F_Avail/2');
    add_line(sub_name, 'SoC_Factor/1', 'Calc_F_Avail/3');
    
    % Logic: Min(F_Demand, F_Avail) is Regen Force
    add_block('simulink/Math Operations/MinMax', [sub_name '/Min_Force'], 'Position', [400, 60, 430, 120]);
    set_param([sub_name '/Min_Force'], 'Function', 'min', 'Inputs', '2');
    add_line(sub_name, 'Calc_F_Demand/1', 'Min_Force/1');
    add_line(sub_name, 'Calc_F_Avail/1', 'Min_Force/2');
    
    % Calculate Friction: F_Friction = F_Demand - F_Regen
    add_block('simulink/Math Operations/Subtract', [sub_name '/Sub_Friction'], 'Position', [500, 50, 530, 80]);
    add_line(sub_name, 'Calc_F_Demand/1', 'Sub_Friction/1');
    add_line(sub_name, 'Min_Force/1', 'Sub_Friction/2');
    
    % Convert F_Regen to Motor Torque
    % T_regen = F_regen * r_tire / gear_ratio / eta_trans
    % Note: Torque is negative for braking
    add_block('simulink/Math Operations/Gain', [sub_name '/Force_to_Torque'], 'Position', [500, 100, 550, 130]);
    set_param([sub_name '/Force_to_Torque'], 'Gain', '-vehicle.r_tire / vehicle.gear_ratio / vehicle.eta_trans');
    add_line(sub_name, 'Min_Force/1', 'Force_to_Torque/1');
    
    % Outputs
    add_block('simulink/Sinks/Out1', [sub_name '/T_regen_cmd'], 'Position', [650, 105, 680, 125]);
    add_block('simulink/Sinks/Out1', [sub_name '/F_friction'], 'Position', [650, 55, 680, 75]);
    
    add_line(sub_name, 'Force_to_Torque/1', 'T_regen_cmd/1');
    add_line(sub_name, 'Sub_Friction/1', 'F_friction/1');
end

function build_motor_subsystem(model_name)
    % Motor Drive Subsystem
    % Inputs: T_demand (Nm), Speed (rad/s)
    % Outputs: T_actual (Nm), P_elec (W)
    
    sub_name = [model_name '/Motor_Drive'];
    add_block('simulink/Ports & Subsystems/Subsystem', sub_name, 'Position', [350, 50, 450, 150]);
    Simulink.SubSystem.deleteContents(sub_name);
    
    % Inputs
    add_block('simulink/Sources/In1', [sub_name '/T_demand'], 'Position', [20, 50, 50, 70]);
    add_block('simulink/Sources/In1', [sub_name '/Speed_rads'], 'Position', [20, 150, 50, 170]);
    
    % Convert Speed to RPM for Lookup
    add_block('simulink/Math Operations/Gain', [sub_name '/To_RPM'], 'Position', [100, 145, 140, 175]);
    set_param([sub_name '/To_RPM'], 'Gain', '60/(2*pi)');
    add_line(sub_name, 'Speed_rads/1', 'To_RPM/1');
    
    % 1. Limit Torque based on Max Torque Curve
    % Lookup Max Torque (RPM -> Nm)
    add_block('simulink/Lookup Tables/1-D Lookup Table', [sub_name '/Max_Torque_Map'], 'Position', [200, 200, 250, 230]);
    set_param([sub_name '/Max_Torque_Map'], 'Table', 'vehicle.motor.max_torque', 'BreakpointsForDimension1', 'vehicle.motor.speed_vec');
    add_line(sub_name, 'To_RPM/1', 'Max_Torque_Map/1');
    
    % Min Torque is -Max Torque (simplified)
    add_block('simulink/Math Operations/Gain', [sub_name '/Neg_Max'], 'Position', [300, 220, 330, 250]);
    set_param([sub_name '/Neg_Max'], 'Gain', '-1');
    add_line(sub_name, 'Max_Torque_Map/1', 'Neg_Max/1');
    
    % Dynamic Saturation
    add_block('simulink/Discontinuities/Saturation Dynamic', [sub_name '/Torque_Limit'], 'Position', [400, 50, 430, 90]);
    add_line(sub_name, 'T_demand/1', 'Torque_Limit/1');
    add_line(sub_name, 'Max_Torque_Map/1', 'Torque_Limit/2'); % Upper
    add_line(sub_name, 'Neg_Max/1', 'Torque_Limit/3'); % Lower
    
    % 2. Calculate Efficiency
    % 2-D Lookup: (Speed, Torque) -> Efficiency
    % Note: Efficiency map usually defined for positive torque.
    % We'll use abs(Torque) for efficiency lookup
    add_block('simulink/Math Operations/Abs', [sub_name '/Abs_Torque'], 'Position', [450, 120, 480, 150]);
    add_line(sub_name, 'Torque_Limit/1', 'Abs_Torque/1');
    
    add_block('simulink/Lookup Tables/2-D Lookup Table', [sub_name '/Eff_Map'], 'Position', [550, 130, 600, 170]);
    set_param([sub_name '/Eff_Map'], 'Table', 'vehicle.motor.eff_map', ...
        'BreakpointsForDimension1', 'vehicle.motor.speed_vec', ...
        'BreakpointsForDimension2', 'vehicle.motor.torque_vec');
    add_line(sub_name, 'To_RPM/1', 'Eff_Map/1');
    add_line(sub_name, 'Abs_Torque/1', 'Eff_Map/2');
    
    % 3. Calculate Electrical Power
    % P_mech = T * w
    add_block('simulink/Math Operations/Product', [sub_name '/Calc_P_mech'], 'Position', [500, 40, 530, 70]);
    add_line(sub_name, 'Torque_Limit/1', 'Calc_P_mech/1');
    add_line(sub_name, 'Speed_rads/1', 'Calc_P_mech/2');
    
    % Logic:
    % If Motoring (P_mech > 0): P_elec = P_mech / eff / inv_eff
    % If Generating (P_mech < 0): P_elec = P_mech * eff * inv_eff
    
    % Inverter Efficiency (Constant for now)
    add_block('simulink/Sources/Constant', [sub_name '/Inv_Eff'], 'Position', [550, 200, 580, 220]);
    set_param([sub_name '/Inv_Eff'], 'Value', '0.95');
    
    % Combined Efficiency = Motor_Eff * Inv_Eff
    add_block('simulink/Math Operations/Product', [sub_name '/Total_Eff'], 'Position', [650, 150, 680, 180]);
    add_line(sub_name, 'Eff_Map/1', 'Total_Eff/1');
    add_line(sub_name, 'Inv_Eff/1', 'Total_Eff/2');
    
    % Switch for Motoring/Generating
    add_block('simulink/Logic and Bit Operations/Relational Operator', [sub_name '/Is_Motoring'], 'Position', [600, 10, 630, 40]);
    set_param([sub_name '/Is_Motoring'], 'Operator', '>');
    
    add_block('simulink/Sources/Constant', [sub_name '/Zero_Ref_M'], 'Position', [550, 80, 570, 100]);
    set_param([sub_name '/Zero_Ref_M'], 'Value', '0');
    
    add_line(sub_name, 'Calc_P_mech/1', 'Is_Motoring/1');
    add_line(sub_name, 'Zero_Ref_M/1', 'Is_Motoring/2');
    
    add_block('simulink/Signal Routing/Switch', [sub_name '/Power_Switch'], 'Position', [750, 50, 780, 90]);
    
    % Motoring Path: P / Eff
    add_block('simulink/Math Operations/Product', [sub_name '/Div_Eff'], 'Position', [700, 40, 730, 70]);
    set_param([sub_name '/Div_Eff'], 'Inputs', '*/');
    add_line(sub_name, 'Calc_P_mech/1', 'Div_Eff/1');
    add_line(sub_name, 'Total_Eff/1', 'Div_Eff/2');
    
    % Generating Path: P * Eff
    add_block('simulink/Math Operations/Product', [sub_name '/Mult_Eff'], 'Position', [700, 90, 730, 120]);
    add_line(sub_name, 'Calc_P_mech/1', 'Mult_Eff/1');
    add_line(sub_name, 'Total_Eff/1', 'Mult_Eff/2');
    
    % Connect Switch
    add_line(sub_name, 'Is_Motoring/1', 'Power_Switch/2');
    add_line(sub_name, 'Div_Eff/1', 'Power_Switch/1');
    add_line(sub_name, 'Mult_Eff/1', 'Power_Switch/3');
    
    % Outputs
    add_block('simulink/Sinks/Out1', [sub_name '/T_actual'], 'Position', [850, 20, 880, 40]);
    add_block('simulink/Sinks/Out1', [sub_name '/P_elec'], 'Position', [850, 70, 880, 90]);
    
    add_line(sub_name, 'Torque_Limit/1', 'T_actual/1');
    add_line(sub_name, 'Power_Switch/1', 'P_elec/1');
end

function build_transmission_subsystem(model_name)
    % Transmission Subsystem
    % Inputs: Motor_Torque (Nm), Vehicle_Speed (m/s)
    % Outputs: Tractive_Force (N), Motor_Speed (rad/s)
    
    sub_name = [model_name '/Transmission'];
    add_block('simulink/Ports & Subsystems/Subsystem', sub_name, 'Position', [500, 50, 600, 150]);
    Simulink.SubSystem.deleteContents(sub_name);
    
    % Inputs
    add_block('simulink/Sources/In1', [sub_name '/Motor_Torque'], 'Position', [20, 50, 50, 70]);
    add_block('simulink/Sources/In1', [sub_name '/Veh_Speed'], 'Position', [20, 150, 50, 170]);
    
    % 1. Calculate Tractive Force
    % F = T_motor * Gear_Ratio * Eta_Trans / r_tire
    add_block('simulink/Math Operations/Gain', [sub_name '/Calc_Force'], 'Position', [150, 45, 250, 75]);
    set_param([sub_name '/Calc_Force'], 'Gain', 'vehicle.gear_ratio * vehicle.eta_trans / vehicle.r_tire');
    add_line(sub_name, 'Motor_Torque/1', 'Calc_Force/1');
    
    % 2. Calculate Motor Speed
    % w_motor = v_vehicle / r_tire * Gear_Ratio
    add_block('simulink/Math Operations/Gain', [sub_name '/Calc_Motor_Speed'], 'Position', [150, 145, 250, 175]);
    set_param([sub_name '/Calc_Motor_Speed'], 'Gain', 'vehicle.gear_ratio / vehicle.r_tire');
    add_line(sub_name, 'Veh_Speed/1', 'Calc_Motor_Speed/1');
    
    % Outputs
    add_block('simulink/Sinks/Out1', [sub_name '/Tractive_Force'], 'Position', [350, 55, 380, 75]);
    add_block('simulink/Sinks/Out1', [sub_name '/Motor_Speed'], 'Position', [350, 155, 380, 175]);
    
    add_line(sub_name, 'Calc_Force/1', 'Tractive_Force/1');
    add_line(sub_name, 'Calc_Motor_Speed/1', 'Motor_Speed/1');
end

function build_dynamics_subsystem(model_name)
    % Vehicle Dynamics Subsystem
    % Inputs: Tractive_Force (N), Friction_Brake (N)
    % Outputs: Velocity (m/s), Distance (m)
    
    sub_name = [model_name '/Vehicle_Dynamics'];
    add_block('simulink/Ports & Subsystems/Subsystem', sub_name, 'Position', [650, 50, 750, 150]);
    Simulink.SubSystem.deleteContents(sub_name);
    
    % Inputs
    add_block('simulink/Sources/In1', [sub_name '/F_Tractive'], 'Position', [20, 50, 50, 70]);
    add_block('simulink/Sources/In1', [sub_name '/F_Brake'], 'Position', [20, 100, 50, 120]);
    
    % Feedback Velocity (needed for Drag/Roll)
    % We'll use a Memory block or GoTo/From to break algebraic loop, 
    % but Integrator output is state, so we can just feed back.
    % However, inside this subsystem, we need the velocity signal.
    
    % 1. Calculate Resistances
    % We need Velocity. Let's assume we can tap off the integrator output.
    
    % Aerodynamic Drag: 0.5 * rho * Cd * A * v^2
    % We need a product block for v^2
    add_block('simulink/Math Operations/Product', [sub_name '/V_Squared'], 'Position', [200, 200, 230, 230]);
    
    add_block('simulink/Math Operations/Gain', [sub_name '/Aero_Coeff'], 'Position', [250, 200, 350, 230]);
    set_param([sub_name '/Aero_Coeff'], 'Gain', '0.5 * vehicle.rho_air * vehicle.Cd * vehicle.A_frontal');
    add_line(sub_name, 'V_Squared/1', 'Aero_Coeff/1');
    
    % Rolling Resistance: C_rr * M * g (Simplified constant)
    add_block('simulink/Sources/Constant', [sub_name '/Roll_Res'], 'Position', [250, 250, 300, 280]);
    set_param([sub_name '/Roll_Res'], 'Value', 'vehicle.C_RR * vehicle.M_vehicle * vehicle.g');
    
    % Gradient: 0 (Flat)
    
    % 2. Sum Forces
    % F_net = F_Tractive - F_Brake - F_Aero - F_Roll
    add_block('simulink/Math Operations/Add', [sub_name '/Sum_Forces'], 'Position', [400, 50, 430, 150]);
    set_param([sub_name '/Sum_Forces'], 'Inputs', '+---');
    
    add_line(sub_name, 'F_Tractive/1', 'Sum_Forces/1');
    add_line(sub_name, 'F_Brake/1', 'Sum_Forces/2');
    add_line(sub_name, 'Aero_Coeff/1', 'Sum_Forces/3');
    add_line(sub_name, 'Roll_Res/1', 'Sum_Forces/4');
    
    % 3. Calculate Acceleration
    % a = F_net / (M * mass_factor)
    add_block('simulink/Math Operations/Gain', [sub_name '/Inv_Mass'], 'Position', [450, 85, 500, 115]);
    set_param([sub_name '/Inv_Mass'], 'Gain', '1/(vehicle.M_vehicle * 1.05)'); % 1.05 for inertia
    add_line(sub_name, 'Sum_Forces/1', 'Inv_Mass/1');
    
    % 4. Integrate to Velocity
    add_block('simulink/Continuous/Integrator', [sub_name '/Integrator_Vel'], 'Position', [550, 85, 580, 115]);
    set_param([sub_name '/Integrator_Vel'], 'InitialCondition', '0');
    add_line(sub_name, 'Inv_Mass/1', 'Integrator_Vel/1');
    
    % Feedback Velocity to V_Squared
    add_line(sub_name, 'Integrator_Vel/1', 'V_Squared/1');
    add_line(sub_name, 'Integrator_Vel/1', 'V_Squared/2');
    
    % 5. Integrate to Distance
    add_block('simulink/Continuous/Integrator', [sub_name '/Integrator_Dist'], 'Position', [650, 150, 680, 180]);
    set_param([sub_name '/Integrator_Dist'], 'InitialCondition', '0');
    add_line(sub_name, 'Integrator_Vel/1', 'Integrator_Dist/1');
    
    % Outputs
    add_block('simulink/Sinks/Out1', [sub_name '/Velocity'], 'Position', [750, 90, 780, 110]);
    add_block('simulink/Sinks/Out1', [sub_name '/Distance'], 'Position', [750, 160, 780, 180]);
    
    add_line(sub_name, 'Integrator_Vel/1', 'Velocity/1');
    add_line(sub_name, 'Integrator_Dist/1', 'Distance/1');
end

function build_battery_subsystem(model_name)
    % Battery Pack Subsystem (Thevenin Model)
    % Inputs: P_elec (W), P_aux (W)
    % Outputs: SoC (0-1), V_term (V), I_batt (A)
    
    sub_name = [model_name '/Battery_Pack'];
    add_block('simulink/Ports & Subsystems/Subsystem', sub_name, 'Position', [350, 200, 450, 300]);
    Simulink.SubSystem.deleteContents(sub_name);
    
    % Inputs
    add_block('simulink/Sources/In1', [sub_name '/P_elec'], 'Position', [20, 50, 50, 70]);
    add_block('simulink/Sources/In1', [sub_name '/P_aux'], 'Position', [20, 100, 50, 120]);
    
    % Sum Power
    add_block('simulink/Math Operations/Add', [sub_name '/Sum_Power'], 'Position', [100, 60, 130, 90]);
    add_line(sub_name, 'P_elec/1', 'Sum_Power/1');
    add_line(sub_name, 'P_aux/1', 'Sum_Power/2');
    
    % Feedback SoC needed for lookups
    % We'll use an Integrator for SoC, output is state
    
    % 1. Lookups (SoC dependent)
    % We need SoC signal. Let's assume we can tap off Integrator.
    
    % V_oc
    add_block('simulink/Lookup Tables/1-D Lookup Table', [sub_name '/V_oc_Map'], 'Position', [200, 150, 250, 180]);
    set_param([sub_name '/V_oc_Map'], 'Table', 'vehicle.battery.ocv_vec', 'BreakpointsForDimension1', 'vehicle.battery.soc_vec');
    
    % R0
    add_block('simulink/Lookup Tables/1-D Lookup Table', [sub_name '/R0_Map'], 'Position', [200, 200, 250, 230]);
    set_param([sub_name '/R0_Map'], 'Table', 'vehicle.battery.r0_vec', 'BreakpointsForDimension1', 'vehicle.battery.soc_vec');
    
    % R1
    add_block('simulink/Lookup Tables/1-D Lookup Table', [sub_name '/R1_Map'], 'Position', [200, 250, 250, 280]);
    set_param([sub_name '/R1_Map'], 'Table', 'vehicle.battery.r1_vec', 'BreakpointsForDimension1', 'vehicle.battery.soc_vec');
    
    % C1
    add_block('simulink/Lookup Tables/1-D Lookup Table', [sub_name '/C1_Map'], 'Position', [200, 300, 250, 330]);
    set_param([sub_name '/C1_Map'], 'Table', 'vehicle.battery.c1_vec', 'BreakpointsForDimension1', 'vehicle.battery.soc_vec');
    
    % 2. Calculate Current (Using Fcn Block for Quadratic Formula)
    % I = (Voc - V1 - sqrt((Voc-V1)^2 - 4*R0*P)) / (2*R0)
    % Inputs: u(1)=P, u(2)=Voc, u(3)=R0, u(4)=V1
    
    add_block('simulink/Signal Routing/Mux', [sub_name '/Mux_Current'], 'Position', [350, 80, 355, 200]);
    set_param([sub_name '/Mux_Current'], 'Inputs', '4', 'DisplayOption', 'bar');
    
    add_line(sub_name, 'Sum_Power/1', 'Mux_Current/1');
    add_line(sub_name, 'V_oc_Map/1', 'Mux_Current/2');
    add_line(sub_name, 'R0_Map/1', 'Mux_Current/3');
    % V1 connected later
    
    add_block('simulink/User-Defined Functions/Fcn', [sub_name '/Calc_Current'], 'Position', [400, 120, 500, 160]);
    % Expression: ((Voc-V1) - sqrt((Voc-V1)^2 - 4*R0*P)) / (2*R0)
    % u(1)=P, u(2)=Voc, u(3)=R0, u(4)=V1
    expr = '((u(2)-u(4)) - sqrt((u(2)-u(4))^2 - 4*u(3)*u(1))) / (2*u(3))';
    set_param([sub_name '/Calc_Current'], 'Expr', expr);
    
    add_line(sub_name, 'Mux_Current/1', 'Calc_Current/1');
    
    % 3. Calculate V1 Dynamics (Using Fcn Block)
    % dV1/dt = -V1/(R1*C1) + I/C1
    % Inputs: u(1)=I, u(2)=V1, u(3)=R1, u(4)=C1
    
    add_block('simulink/Signal Routing/Mux', [sub_name '/Mux_dV1'], 'Position', [550, 250, 555, 350]);
    set_param([sub_name '/Mux_dV1'], 'Inputs', '4', 'DisplayOption', 'bar');
    
    add_line(sub_name, 'Calc_Current/1', 'Mux_dV1/1');
    % V1 connected later
    add_line(sub_name, 'R1_Map/1', 'Mux_dV1/3');
    add_line(sub_name, 'C1_Map/1', 'Mux_dV1/4');
    
    add_block('simulink/User-Defined Functions/Fcn', [sub_name '/Calc_dV1'], 'Position', [600, 290, 660, 310]);
    set_param([sub_name '/Calc_dV1'], 'Expr', '-u(2)/(u(3)*u(4)) + u(1)/u(4)');
    
    add_line(sub_name, 'Mux_dV1/1', 'Calc_dV1/1');
    
    % Integrator for V1
    add_block('simulink/Continuous/Integrator', [sub_name '/Integrator_V1'], 'Position', [680, 290, 710, 320]);
    set_param([sub_name '/Integrator_V1'], 'InitialCondition', '0');
    add_line(sub_name, 'Calc_dV1/1', 'Integrator_V1/1');
    
    % Feedback V1
    add_line(sub_name, 'Integrator_V1/1', 'Mux_Current/4');
    add_line(sub_name, 'Integrator_V1/1', 'Mux_dV1/2');
    
    % 4. Calculate SoC Dynamics
    % dSoC = -I / (Capacity * 3600)
    add_block('simulink/Math Operations/Gain', [sub_name '/Calc_dSoC'], 'Position', [550, 80, 600, 110]);
    set_param([sub_name '/Calc_dSoC'], 'Gain', '-1/(vehicle.battery.capacity_Ah * 3600)');
    add_line(sub_name, 'Calc_Current/1', 'Calc_dSoC/1');
    
    % Integrator for SoC
    add_block('simulink/Continuous/Integrator', [sub_name '/Integrator_SoC'], 'Position', [650, 80, 680, 110]);
    set_param([sub_name '/Integrator_SoC'], 'InitialCondition', '1'); % Start at 100%
    add_line(sub_name, 'Calc_dSoC/1', 'Integrator_SoC/1');
    
    % Feedback SoC to Lookups
    add_line(sub_name, 'Integrator_SoC/1', 'V_oc_Map/1');
    add_line(sub_name, 'Integrator_SoC/1', 'R0_Map/1');
    add_line(sub_name, 'Integrator_SoC/1', 'R1_Map/1');
    add_line(sub_name, 'Integrator_SoC/1', 'C1_Map/1');
    
    % 5. Calculate Terminal Voltage
    % V_term = Voc - I*R0 - V1
    add_block('simulink/Math Operations/Add', [sub_name '/Calc_V_term'], 'Position', [800, 150, 830, 200]);
    set_param([sub_name '/Calc_V_term'], 'Inputs', '+--');
    
    add_line(sub_name, 'V_oc_Map/1', 'Calc_V_term/1');
    
    % I*R0
    add_block('simulink/Math Operations/Product', [sub_name '/I_R0'], 'Position', [750, 180, 780, 210]);
    add_line(sub_name, 'Calc_Current/1', 'I_R0/1');
    add_line(sub_name, 'R0_Map/1', 'I_R0/2');
    add_line(sub_name, 'I_R0/1', 'Calc_V_term/2');
    
    add_line(sub_name, 'Integrator_V1/1', 'Calc_V_term/3');
    
    % Outputs
    add_block('simulink/Sinks/Out1', [sub_name '/SoC'], 'Position', [900, 90, 930, 110]);
    add_block('simulink/Sinks/Out1', [sub_name '/V_term'], 'Position', [900, 170, 930, 190]);
    add_block('simulink/Sinks/Out1', [sub_name '/I_batt'], 'Position', [900, 50, 930, 70]);
    
    add_line(sub_name, 'Integrator_SoC/1', 'SoC/1');
    add_line(sub_name, 'Calc_V_term/1', 'V_term/1');
    add_line(sub_name, 'Calc_Current/1', 'I_batt/1');
end

function build_aux_subsystem(model_name)
    % Auxiliaries Subsystem
    % Outputs: P_aux (W)
    
    sub_name = [model_name '/Auxiliaries'];
    add_block('simulink/Ports & Subsystems/Subsystem', sub_name, 'Position', [200, 200, 300, 300]);
    Simulink.SubSystem.deleteContents(sub_name);
    
    add_block('simulink/Sources/Constant', [sub_name '/Aux_Load'], 'Position', [50, 50, 100, 80]);
    set_param([sub_name '/Aux_Load'], 'Value', 'vehicle.aux_power');
    
    add_block('simulink/Sinks/Out1', [sub_name '/P_aux'], 'Position', [200, 55, 230, 75]);
    add_line(sub_name, 'Aux_Load/1', 'P_aux/1');
end

function connect_all_subsystems(model_name)
    % Connect all subsystems together
    
    % 1. Add Global Inputs (Clock & Cycle)
    add_block('simulink/Sources/Clock', [model_name '/Clock'], 'Position', [20, 50, 40, 70]);
    
    add_block('simulink/Lookup Tables/1-D Lookup Table', [model_name '/Drive_Cycle'], 'Position', [80, 40, 130, 80]);
    set_param([model_name '/Drive_Cycle'], 'Table', 'cycle.velocity_ms', 'BreakpointsForDimension1', 'cycle.time');
    add_line(model_name, 'Clock/1', 'Drive_Cycle/1');
    
    % 2. Driver Connections
    % In1: Vel_Ref (from Cycle)
    add_line(model_name, 'Drive_Cycle/1', 'Driver_Model/1');
    % In2: Vel_Actual (from Dynamics) - Feedback Loop
    % We'll connect this later or use a GoTo/From pair to avoid line clutter
    
    % 3. Regen Connections
    % In1: Brake_Cmd (from Driver)
    add_line(model_name, 'Driver_Model/2', 'Regen_Controller/1');
    % In2: Velocity (from Dynamics)
    % In3: SoC (from Battery)
    
    % 4. Motor Connections
    % In1: T_demand = (Accel_Cmd * 250) + T_regen_cmd
    % We need a Gain and Sum block
    add_block('simulink/Math Operations/Gain', [model_name '/Accel_Gain'], 'Position', [250, 60, 300, 90]);
    set_param([model_name '/Accel_Gain'], 'Gain', 'vehicle.motor.peak_torque'); % Max Torque Scaling
    add_line(model_name, 'Driver_Model/1', 'Accel_Gain/1');
    
    add_block('simulink/Math Operations/Add', [model_name '/Sum_Torque'], 'Position', [320, 60, 340, 90]);
    add_line(model_name, 'Accel_Gain/1', 'Sum_Torque/1');
    add_line(model_name, 'Regen_Controller/1', 'Sum_Torque/2'); % T_regen (negative)
    
    add_line(model_name, 'Sum_Torque/1', 'Motor_Drive/1');
    
    % In2: Speed_rads (from Transmission)
    add_line(model_name, 'Transmission/2', 'Motor_Drive/2');
    
    % 5. Transmission Connections
    % In1: Motor_Torque (from Motor)
    add_line(model_name, 'Motor_Drive/1', 'Transmission/1');
    % In2: Veh_Speed (from Dynamics)
    
    % 6. Dynamics Connections
    % In1: F_Tractive (from Transmission)
    add_line(model_name, 'Transmission/1', 'Vehicle_Dynamics/1');
    % In2: F_Brake (from Regen)
    add_line(model_name, 'Regen_Controller/2', 'Vehicle_Dynamics/2');
    
    % 7. Battery Connections
    % In1: P_elec (from Motor)
    add_line(model_name, 'Motor_Drive/2', 'Battery_Pack/1');
    % In2: P_aux (from Aux)
    add_line(model_name, 'Auxiliaries/1', 'Battery_Pack/2');
    
    % 8. Feedback Loops (Using GoTo/From for cleanliness)
    
    % Velocity Feedback
    add_block('simulink/Signal Routing/Goto', [model_name '/Goto_Vel'], 'Position', [800, 90, 840, 110]);
    set_param([model_name '/Goto_Vel'], 'GotoTag', 'Vel');
    add_line(model_name, 'Vehicle_Dynamics/1', 'Goto_Vel/1');
    
    % Connect Velocity to:
    % - Driver
    add_block('simulink/Signal Routing/From', [model_name '/From_Vel_Driver'], 'Position', [20, 100, 60, 120]);
    set_param([model_name '/From_Vel_Driver'], 'GotoTag', 'Vel');
    add_line(model_name, 'From_Vel_Driver/1', 'Driver_Model/2');
    
    % - Regen
    add_block('simulink/Signal Routing/From', [model_name '/From_Vel_Regen'], 'Position', [150, 240, 190, 260]);
    set_param([model_name '/From_Vel_Regen'], 'GotoTag', 'Vel');
    add_line(model_name, 'From_Vel_Regen/1', 'Regen_Controller/2');
    
    % - Transmission
    add_block('simulink/Signal Routing/From', [model_name '/From_Vel_Trans'], 'Position', [450, 100, 490, 120]);
    set_param([model_name '/From_Vel_Trans'], 'GotoTag', 'Vel');
    add_line(model_name, 'From_Vel_Trans/1', 'Transmission/2');
    
    % SoC Feedback
    add_block('simulink/Signal Routing/Goto', [model_name '/Goto_SoC'], 'Position', [500, 220, 540, 240]);
    set_param([model_name '/Goto_SoC'], 'GotoTag', 'SoC');
    add_line(model_name, 'Battery_Pack/1', 'Goto_SoC/1');
    
    % Connect SoC to Regen
    add_block('simulink/Signal Routing/From', [model_name '/From_SoC_Regen'], 'Position', [150, 280, 190, 300]);
    set_param([model_name '/From_SoC_Regen'], 'GotoTag', 'SoC');
    add_line(model_name, 'From_SoC_Regen/1', 'Regen_Controller/3');
    
end

function add_logging(model_name)
    % Add To Workspace blocks for data logging
    
    % 1. Velocity (Ref vs Actual)
    add_block('simulink/Sinks/To Workspace', [model_name '/Log_Vel_Ref'], 'Position', [150, 10, 210, 30]);
    set_param([model_name '/Log_Vel_Ref'], 'VariableName', 'vel_ref', 'SaveFormat', 'Structure with Time');
    add_line(model_name, 'Drive_Cycle/1', 'Log_Vel_Ref/1');
    
    add_block('simulink/Sinks/To Workspace', [model_name '/Log_Vel_Act'], 'Position', [800, 120, 860, 140]);
    set_param([model_name '/Log_Vel_Act'], 'VariableName', 'vel_actual', 'SaveFormat', 'Structure with Time');
    add_line(model_name, 'Vehicle_Dynamics/1', 'Log_Vel_Act/1');
    
    % 2. SoC
    add_block('simulink/Sinks/To Workspace', [model_name '/Log_SoC'], 'Position', [500, 250, 560, 270]);
    set_param([model_name '/Log_SoC'], 'VariableName', 'soc', 'SaveFormat', 'Structure with Time');
    add_line(model_name, 'Battery_Pack/1', 'Log_SoC/1');
    
    % 3. Battery Power/Current/Voltage
    add_block('simulink/Sinks/To Workspace', [model_name '/Log_V_term'], 'Position', [500, 280, 560, 300]);
    set_param([model_name '/Log_V_term'], 'VariableName', 'v_term', 'SaveFormat', 'Structure with Time');
    add_line(model_name, 'Battery_Pack/2', 'Log_V_term/1');
    
    add_block('simulink/Sinks/To Workspace', [model_name '/Log_I_batt'], 'Position', [500, 310, 560, 330]);
    set_param([model_name '/Log_I_batt'], 'VariableName', 'i_batt', 'SaveFormat', 'Structure with Time');
    add_line(model_name, 'Battery_Pack/3', 'Log_I_batt/1');
    
    % 4. Motor Torque/Power
    add_block('simulink/Sinks/To Workspace', [model_name '/Log_T_motor'], 'Position', [480, 10, 540, 30]);
    set_param([model_name '/Log_T_motor'], 'VariableName', 't_motor', 'SaveFormat', 'Structure with Time');
    add_line(model_name, 'Motor_Drive/1', 'Log_T_motor/1');
    
    add_block('simulink/Sinks/To Workspace', [model_name '/Log_P_elec'], 'Position', [480, 160, 540, 180]);
    set_param([model_name '/Log_P_elec'], 'VariableName', 'p_elec', 'SaveFormat', 'Structure with Time');
    add_line(model_name, 'Motor_Drive/2', 'Log_P_elec/1');
    
    % 5. Distance
    add_block('simulink/Sinks/To Workspace', [model_name '/Log_Dist'], 'Position', [800, 160, 860, 180]);
    set_param([model_name '/Log_Dist'], 'VariableName', 'distance', 'SaveFormat', 'Structure with Time');
    add_line(model_name, 'Vehicle_Dynamics/2', 'Log_Dist/1');
    
    % 6. Time - Use Array format for time vector
    add_block('simulink/Sinks/To Workspace', [model_name '/Log_Time'], 'Position', [60, 10, 120, 30]);
    set_param([model_name '/Log_Time'], 'VariableName', 'sim_time', 'SaveFormat', 'Array');
    add_line(model_name, 'Clock/1', 'Log_Time/1');
end
