# 🚗 BEGINNER'S GUIDE: BMW i3 Simulink Model

## What You're Seeing Right Now

You have the Simulink model **open and ready**! The diagram shows:

![Current Model](C:/Users/Piyush/.gemini/antigravity/brain/6eeafd37-0de5-4350-8b7c-270df04a2bf7/uploaded_image_1764498677425.png)

### Understanding the Blocks

**Top Flow (Main Simulation):**
- ⏰ **Clock** → Generates time (0 to 1179 seconds)
- 📊 **Velocity_Profile** → Looks up NEDC speed at each time point
- 🔧 **kmh_to_ms** → Converts km/h to m/s
- 📈 **Speed_Scope** → **THIS IS WHERE YOU SEE THE GRAPH!**
- 🔢 **Speed_Display** → Shows current speed number
- 💾 **Log_Speed** → Saves data to MATLAB workspace

**Bottom Blocks (Vehicle Info):**
- **Vehicle_Mass** → BMW i3 mass (1270 kg)
- **Aux_Power** → Auxiliary power used (300 W)

---

## 🎯 STEP-BY-STEP: How to Run & View Results

### Step 1: Run the Simulation

1. Look at the **top toolbar** in Simulink
2. Find the **▶ RUN button** (green triangle/play icon)
3. Click it!
4. Wait a few seconds - you'll see "Running..." then "Ready"

### Step 2: View the Velocity Graph

**THIS IS THE IMPORTANT PART!**

1. In your model, find the **Speed_Scope** block (top right area)
2. **Double-click** on it
3. A new window will open showing a **graph of the NEDC driving cycle**
4. You should see:
   - X-axis: Time (0 to 1179 seconds)
   - Y-axis: Speed (m/s)
   - The graph shows the car speeding up and slowing down

### Step 3: See Numerical Results

After running, go to **MATLAB Command Window** (not Simulink) and type:

```matlab
% See all logged speed data
speed_log

% Plot the speed over time
plot(speed_log)
xlabel('Time (seconds)')
ylabel('Speed (m/s)')
title('BMW i3 NEDC Driving Cycle')
grid on
```

### Step 4: Calculate Energy Consumption

In MATLAB Command Window, type:

```matlab
% Run the full simulation with energy calculation
run_simulation
```

This will show:
- Total energy consumed (kWh)
- Energy per km (Wh/km)
- Comparison with benchmark

---

## 🔍 What Each Number Means

When you look at the model:

| Block | Shows | Current Value |
|-------|-------|---------------|
| Speed_Display | Current vehicle speed | 0 m/s (when not running) |
| Mass_Display | Vehicle weight | 1270 kg |
| Aux_Display | Auxiliary power draw | 300 W |

---

## 📊 Expected Results

When you run the simulation, you should get:

- **Distance**: 10.8 km
- **Time**: 19.6 minutes (1179 seconds)
- **Energy**: ~142 Wh/km
- **Graph**: Speed varying from 0 to 120 km/h

---

## ❓ Troubleshooting

**Q: The simulation doesn't run?**
- Make sure you ran `run_simulink_simulation.m` first in MATLAB
- This sets up the velocity data

**Q: The Scope is blank?**
- Click the ▶ RUN button again
- Then double-click the Speed_Scope

**Q: I want to see numbers, not just graphs?**
- Run `run_simulation.m` in MATLAB for detailed numerical results

---

## 🎓 Next Steps

1. ✅ **Run the simulation** (click ▶)
2. ✅ **View the graph** (double-click Speed_Scope)
3. ✅ **Get numerical results** (type `run_simulation` in MATLAB)

**This is a simplified visualization model.** For full energy calculations with motor efficiency, battery, etc., use the MATLAB script `run_simulation.m` instead.

---

## 💡 Quick Commands Reference

In MATLAB Command Window:

```matlab
% Open and run Simulink model
run_simulink_simulation

% Run complete energy simulation (with all physics)
run_simulation

% Plot logged data
plot(speed_log)

% See what variables are available
whos
```
