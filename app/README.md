# MyEMG — Flutter App

Flutter client for **My_EMG**: connects to the sEMG sensor over BLE and runs same-session action comparisons (Route A — relative comparison within one electrode placement, not MVC, not a medical device).

Full project background (system overview, firmware, BLE protocol): see the [root README](../README.md).

## Screenshots

| Connect device | Set up comparison | Record envelope |
| :---: | :---: | :---: |
| <img src="assets/icons/7009275416d5b03b652c9c3a030506c0.jpg" width="230" alt="Devices page — BLE connect"> | <img src="assets/icons/ab4ab753de49ae1941a2ceb47ebfca9f.jpg" width="230" alt="Compare setup — pick actions, order, notes"> | <img src="assets/icons/43399a7497ffe319286da92c69062d0f.jpg" width="230" alt="Live adjustedEnv envelope during an action"> |

| Session results | Recent comparisons | Connect-first prompt |
| :---: | :---: | :---: |
| <img src="assets/icons/832cc19475a70fc6da8961e038501e4a.jpg" width="230" alt="Ranked results in env units"> | <img src="assets/icons/9301b71b1092023d01778c93f3699c13.jpg" width="230" alt="History of recent comparison sessions"> | <img src="assets/icons/98a7726161b5fd9ec5e736c81122cd49.jpg" width="230" alt="Compare tab before a sensor is connected"> |

## Quick start

```bash
flutter pub get
flutter run       # real device required (BLE)
flutter test
flutter analyze
```

BLE needs a physical phone. On Android, grant the Bluetooth (and on older versions, Location) permissions when prompted.

## Features

- Same-session action comparison (2–4 actions, one electrode placement)
- Relaxed (resting) calibration before recording
- Real-time envelope display while recording
- Per-rep review before an action is scored
- Editable action library per target muscle
- History of the 8 most recent comparison sessions
