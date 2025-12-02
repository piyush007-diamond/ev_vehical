% run_full_simulation.m - Execute and Verify BMW i3 Full Model

% 1. Build the Model (Ensures it exists and is up to date)
fprintf('Building Simulink Model...\n');
try
    build_full_model();
catch ME
    fprintf('Error building model: %s\n', ME.message);
    return;
end

% 2. Run Simulation
fprintf('Running Simulation (NEDC Cycle)...\n');
try
    simOut = sim('bmw_i3_full_model');
    fprintf('Simulation Complete.\n');
catch ME
    fprintf('Error running simulation: %s\n', ME.message);
    return;
end

% 3. Extract Results
% The To Workspace blocks save data to the simOut object
% We need to extract from simOut

% Check if data is in workspace (old behavior) or in simOut (new behavior)
if exist('sim_time', 'var')
    % Data in workspace - extract directly
    fprintf('Extracting data from workspace...\n');
    time = sim_time;
    vel_ref_data = vel_ref.signals.values;
    vel_actual_data = vel_actual.signals.values;
    soc_data = soc.signals.values;
    v_term_data = v_term.signals.values;
    i_batt_data = i_batt.signals.values;
    p_elec_data = p_elec.signals.values;
    distance_data = distance.signals.values;
else
    % Data in simOut object - extract from there
    fprintf('Extracting data from simOut object...\n');
    
    % Extract from simOut - the variable names match what we set in To Workspace blocks
    try
        time = simOut.sim_time;
        vel_ref_data = simOut.vel_ref.signals.values;
        vel_actual_data = simOut.vel_actual.signals.values;
        soc_data = simOut.soc.signals.values;
        v_term_data = simOut.v_term.signals.values;
        i_batt_data = simOut.i_batt.signals.values;
        p_elec_data = simOut.p_elec.signals.values;
        distance_data = simOut.distance.signals.values;
    catch ME
        fprintf('Error extracting from simOut: %s\n', ME.message);
        fprintf('SimOut contents:\n');
        disp(simOut);
        error('Could not extract simulation data from simOut object.');
    end
end

% Assign to simple variable names for the rest of the script
vel_ref = vel_ref_data;
vel_actual = vel_actual_data;
soc = soc_data;
v_term = v_term_data;
i_batt = i_batt_data;
p_elec = p_elec_data;
distance = distance_data;

dt = [diff(time); 0];

% 4. Analysis

% Total Distance
total_dist_m = distance(end);
total_dist_km = total_dist_m / 1000;

% Energy Consumption
% P_elec is in Watts. Energy = Integral(P * dt)
energy_J = trapz(time, p_elec);
energy_Wh = energy_J / 3600;
energy_kWh = energy_Wh / 1000;

% Specific Consumption
consumption_Wh_km = energy_Wh / total_dist_km;

% SoC Drop
soc_start = soc(1) * 100;
soc_end = soc(end) * 100;
soc_drop = soc_start - soc_end;

% Speed Tracking Error
error_kmh = (vel_ref - vel_actual) * 3.6;
max_error = max(abs(error_kmh));
rms_error = rms(error_kmh);

% 5. Validation
benchmark_Wh_km = 135;
error_pct = (consumption_Wh_km - benchmark_Wh_km) / benchmark_Wh_km * 100;

fprintf('\n==================================================\n');
fprintf('BMW i3 Simulation Results (Full Model)\n');
fprintf('==================================================\n');
fprintf('Driving Cycle:        NEDC\n');
fprintf('Total Distance:       %.2f km\n', total_dist_km);
fprintf('Total Energy:         %.2f Wh\n', energy_Wh);
fprintf('Consumption:          %.2f Wh/km\n', consumption_Wh_km);
fprintf('Benchmark:            %.2f Wh/km\n', benchmark_Wh_km);
fprintf('Error:                %.2f %%\n', error_pct);
fprintf('SoC Drop:             %.2f %%\n', soc_drop);
fprintf('Max Speed Error:      %.2f km/h\n', max_error);
fprintf('RMS Speed Error:      %.2f km/h\n', rms_error);
fprintf('==================================================\n');

if abs(error_pct) < 6
    fprintf('VALIDATION STATUS: PASS\n');
else
    fprintf('VALIDATION STATUS: FAIL (Target < 6%%)\n');
end

% 6. Plotting
figure('Name', 'BMW i3 Simulation Results', 'NumberTitle', 'off');

subplot(3,1,1);
plot(time, vel_ref*3.6, 'k--', 'LineWidth', 1.5); hold on;
plot(time, vel_actual*3.6, 'b', 'LineWidth', 1);
ylabel('Speed (km/h)');
legend('Reference', 'Actual');
title('Speed Tracking');
grid on;

subplot(3,1,2);
plot(time, p_elec/1000, 'r');
ylabel('Battery Power (kW)');
title('Power Consumption (Positive = Discharge)');
grid on;

subplot(3,1,3);
plot(time, soc*100, 'g');
ylabel('SoC (%)');
xlabel('Time (s)');
title('State of Charge');
grid on;
