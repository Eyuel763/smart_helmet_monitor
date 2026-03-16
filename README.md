# Smart Helmet Monitor

Smart Helmet Monitor is a Flutter application that connects to an ESP32 over WebSockets to visualize gas, temperature, and vital sensor data in real time. It surfaces safety alerts, plays an alarm, and logs notifications locally for quick review.

## Features

- **Live WebSocket telemetry** for MQ2/MQ7 gas sensors, body/ambient temperature, heart rate, and SpO2.
- **Status cards** that summarize gas, fatigue/fever, and vital conditions.
- **Alerting** with audio alarms, local notifications, and a persistent alert log.
- **Offline-friendly history** using SharedPreferences to retain recent alerts.

## Tech Stack

- Flutter (Material 3)
- Dart 3
- WebSocket telemetry (`web_socket_channel`)
- Local notifications (`flutter_local_notifications`)
- Audio playback (`audioplayers`)
- Local storage (`shared_preferences`)

## Requirements

- Flutter SDK (3.5+ recommended)
- An ESP32 (or compatible device) streaming JSON over WebSockets

## Setup

1. Install dependencies:
   ```bash
   flutter pub get
   ```
2. Ensure the alarm audio file is present at `assets/sounds/alarm.mp3`.
3. Connect your mobile device/emulator to the same network as the ESP32.

## Configuration

Update the WebSocket endpoint to match your ESP32 IP address in `lib/main.dart`:

```dart
const String esp32Url = "ws://10.12.80.50:81";
```

The app expects JSON payloads containing the following keys:

- `mq2` (int)
- `mq7` (int)
- `body_temp` (num)
- `ambient_temp` (num)
- `heart_rate` (num)
- `spo2` (num)

## Running the App

```bash
flutter run
```

## Project Structure

- `lib/main.dart`: Main application UI and WebSocket/alert logic.
- `assets/sounds/alarm.mp3`: Alarm sound used for safety alerts.
- `android/`, `ios/`, `web/`, `windows/`, `macos/`, `linux/`: Platform targets.

## Testing

```bash
flutter test
```

## Notes

- You can use `ArduinoCode/helmet.ino` for the ESP32
- Alerts trigger when gas is dangerous, fever/fatigue is high, or SpO2 is critical.
- Notifications use the bundled alarm sound for urgent events.
