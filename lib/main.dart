import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const String esp32Url = "ws://10.12.80.50:81";

void main() {
  runApp(const MyApp());
}
// APP
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Helmet Monitor',
      theme: ThemeData.dark(useMaterial3: true),
      home: const SmartHelmetMonitorScreen(),
    );
  }
}
// SCREEN 
class SmartHelmetMonitorScreen extends StatefulWidget {
  const SmartHelmetMonitorScreen({super.key});

  @override
  State<SmartHelmetMonitorScreen> createState() =>
      _SmartHelmetMonitorScreenState();
}

class _SmartHelmetMonitorScreenState extends State<SmartHelmetMonitorScreen> {
  WebSocketChannel? channel;
  Timer? reconnectTimer;

  bool connected = false;
  bool alarmPlaying = false;

  final AudioPlayer _audioPlayer = AudioPlayer();
  late FlutterLocalNotificationsPlugin _notifications;

  // SENSOR VALUES 
  int mq2 = 0;
  int mq7 = 0;
  double bodyTemp = 0.0;
  double ambientTemp = 0.0;
  double heartRate = 0.0;
  double spo2 = 0.0;

  String gasStatus = "SAFE";
  String fatigueStatus = "LOW";
  String vitalStatus = "NORMAL"; 

  Color gasColor = Colors.green;
  Color fatigueColor = Colors.green;
  Color vitalColor = Colors.green; 

  List<String> alertLog = [];

  final int mqGasThreshold = 2600; 
  final double highFeverThreshold = 38.5;
  final double lowSpo2Threshold = 90.0; 
  // INIT 
  @override
  void initState() {
    super.initState();
    _loadAlerts();
    _initNotifications();
    _connectWebSocket();
  }
  // WEBSOCKET 
  void _connectWebSocket() {
    try {
      channel = WebSocketChannel.connect(Uri.parse(esp32Url));

      channel!.stream.listen(
        (message) {
          setState(() => connected = true);
          _handleIncomingData(message);
        },
        onDone: _handleDisconnect,
        onError: (_) => _handleDisconnect(),
      );
    } catch (_) {
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    setState(() => connected = false);
    _stopAlarm(); 
    reconnectTimer?.cancel();
    reconnectTimer = Timer(const Duration(seconds: 3), _connectWebSocket);
  }
  // DATA HANDLING 
  void _handleIncomingData(String message) {
    final data = jsonDecode(message);

    setState(() {
      mq2 = data['mq2'] as int? ?? 0;
      mq7 = data['mq7'] as int? ?? 0;
      bodyTemp = (data['body_temp'] as num?)?.toDouble() ?? 0.0;
      ambientTemp = (data['ambient_temp'] as num?)?.toDouble() ?? 0.0;
      heartRate = (data['heart_rate'] as num?)?.toDouble() ?? 0.0;
      spo2 = (data['spo2'] as num?)?.toDouble() ?? 0.0;
      // --- ERROR CHECKS ---
      bool mq2Error = (mq2 == 0);
      bool mq7Error = (mq7 == 0);
      bool bodyTempError = (bodyTemp == 0.0);
      bool vitalError = (heartRate == 0.0 && spo2 == 0.0); 

      // Gas Status Logic
      if (mq2Error && mq7Error) {
          gasStatus = "ERROR";
      } else if (!mq2Error || !mq7Error && mq7 >= mqGasThreshold) {
          gasStatus = "DANGER";
      } else {
          gasStatus = "SAFE";
      }

      // Fatigue Status Logic
      if (bodyTempError) {
          fatigueStatus = "ERROR";
      } else {
          fatigueStatus = bodyTemp >= highFeverThreshold ? "HIGH" : "LOW";
      }
      // VITAL STATUS LOGIC 
      if (vitalError) {
          vitalStatus = "ERROR";
      } else if (spo2 > 0.0 && spo2 < lowSpo2Threshold) {
          vitalStatus = "CRITICAL";
      } else {
          vitalStatus = "NORMAL";
      }
      
      // COLOR LOGIC 
      gasColor = gasStatus == "ERROR" ? Colors.yellow : (gasStatus == "DANGER" ? Colors.red : Colors.green);
      fatigueColor = fatigueStatus == "ERROR" ? Colors.yellow : (fatigueStatus == "HIGH" ? Colors.red : Colors.green);
      
      // NEW VITAL COLOR LOGIC
      if (vitalStatus == "ERROR") {
          vitalColor = Colors.yellow;
      } else if (vitalStatus == "CRITICAL") {
          vitalColor = Colors.red;
      } else {
          vitalColor = Colors.green;
      }
    });

    _handleAlerts();
  }

  // ALERT LOGIC 

  void _handleAlerts() {
    // Alarm plays if there is a DANGER, HIGH, or CRITICAL status.
    if (gasStatus == "DANGER" || fatigueStatus == "HIGH" || vitalStatus == "CRITICAL") {
      _playAlarm();

      String notificationBody = "";
      String logMessage = "";
      
      if (gasStatus == "DANGER") {
          notificationBody = "Dangerous gas detected!";
          logMessage = "GAS DANGER";
      } else if (fatigueStatus == "HIGH") {
          notificationBody = "High fever/fatigue detected!";
          logMessage = "HIGH FEVER/FATIGUE";
      } else if (vitalStatus == "CRITICAL") {
          notificationBody = "Critical SpO2 level detected!";
          logMessage = "CRITICAL SpO2";
      }
      
      final alert = "${DateTime.now().toLocal()} | ALERT: $logMessage";
      _saveAlert(alert);

      _showNotification(
        "SAFETY ALERT",
        notificationBody,
      );
    } else {
      _stopAlarm();
    }
  }
  // ALERT STORAGE 
  Future<void> _saveAlert(String alert) async {
    setState(() {
      alertLog.insert(0, alert);
    });
    final prefs = await SharedPreferences.getInstance();
    prefs.setStringList("alerts", alertLog);
  }

  Future<void> _loadAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      alertLog = prefs.getStringList("alerts") ?? [];
    });
  }
  // SOUND 
  Future<void> _playAlarm() async {
    if (alarmPlaying) return;
    alarmPlaying = true;
    await _audioPlayer.play(AssetSource('sounds/alarm.mp3'), volume: 0.5);
  }

  Future<void> _stopAlarm() async {
    alarmPlaying = false;
    await _audioPlayer.stop();
  }
  // NOTIFICATIONS 
  void _initNotifications() {
    _notifications = FlutterLocalNotificationsPlugin();
    const android =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    _notifications.initialize(const InitializationSettings(android: android));
  }

  Future<void> _showNotification(String title, String body) async {
    const androidDetails = AndroidNotificationDetails(
      'danger',
      'Danger Alerts',
      importance: Importance.max,
      priority: Priority.high,
      sound: RawResourceAndroidNotificationSound('alarm'), 
    );

    await _notifications.show(
      0,
      title,
      body,
      const NotificationDetails(android: androidDetails),
    );
  }

  // UI 
  // Helper function to determine display value for ADC
  String getGasDisplay(int value, String status) {
    if (value == 0 && status != "DANGER") return "ERROR";
    return value.toString();
  }

  // Helper function to determine display value for Temp (DS18B20/DHT11)
  String getTempDisplay(double value) {
    if (value == 0.0) return "ERROR";
    return "${value.toStringAsFixed(1)} °C";
  }

  // Helper function for Vitals (Heart Rate/SpO2)
  String getVitalDisplay(double value) {
    if (value == 0.0 && vitalStatus != "CRITICAL") return "ERROR";
    return value.toStringAsFixed(value < 100 ? 1 : 0); // SpO2 needs 1 decimal, HR can be 0
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1B26),
      body: SafeArea(
        child: SingleChildScrollView( 
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("SMART HELMET MONITOR",
                  style: GoogleFonts.roboto(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF8A8FD8))),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.circle,
                      size: 10,
                      color: connected ? Colors.green : Colors.red),
                  const SizedBox(width: 8),
                  Text(
                    connected ? "Connected" : "Disconnected",
                    style: GoogleFonts.roboto(color: Colors.white70),
                  )
                ],
              ),
              const SizedBox(height: 20),
              // STATUS CARDS
              StatusCard(
                title: "GAS LEVEL",
                status: gasStatus,
                statusColor: gasColor,
                icon: Icons.warning,
              ),
              const SizedBox(height: 12),

              StatusCard(
                title: "FEVER/FATIGUE RISK",
                status: fatigueStatus,
                statusColor: fatigueColor,
                icon: Icons.bolt,
              ),
              const SizedBox(height: 12),

              StatusCard(
                title: "VITAL STATUS",
                status: vitalStatus,
                statusColor: vitalColor,
                icon: Icons.monitor_heart,
              ),
              const SizedBox(height: 12),
              
              // METRIC ROW 1 (MQ2 / BODY TEMP)
              Row(
                children: [
                  Expanded(
                      child: MetricCard(
                          title: "Methane GAS (ADC)", 
                          value: getGasDisplay(mq2, gasStatus))), 
                  const SizedBox(width: 12),
                  Expanded(
                      child: MetricCard(
                          title: "BODY TEMP",
                          value: getTempDisplay(bodyTemp))),
                ],
              ),
              const SizedBox(height: 12),

              // METRIC ROW 2 (MQ7 / AMBIENT TEMP)
              Row(
                children: [
                  Expanded(
                      child: MetricCard(
                          title: "CO GAS (ADC)", 
                          value: getGasDisplay(mq7, gasStatus))), 
                  const SizedBox(width: 12),
                  Expanded(
                      child: MetricCard(
                          title: "AMBIENT TEMP",
                          value: getTempDisplay(ambientTemp))),
                ],
              ),
              const SizedBox(height: 12),

              // NEW METRIC ROW 3 (HEART RATE / SpO2)
              Row(
                children: [
                  Expanded(
                      child: MetricCard(
                          title: "HEART RATE (BPM)",
                          value: heartRate == 0.0 && vitalStatus != "CRITICAL" 
                                ? "ERROR" 
                                : "${heartRate.toStringAsFixed(0)} bpm")), 
                  const SizedBox(width: 12),
                  Expanded(
                      child: MetricCard(
                          title: "Oxygen Saturation (%)",
                          value: spo2 == 0.0 && vitalStatus != "CRITICAL"
                                ? "ERROR" 
                                : "${spo2.toStringAsFixed(1)} %")),
                ],
              ),
              const SizedBox(height: 16),

              // ALERT LOG
              Text("Recent Alerts",
                  style: GoogleFonts.roboto(
                      fontSize: 16, color: Colors.white70)),
              const Divider(),

              Column( 
                crossAxisAlignment: CrossAxisAlignment.start,
                children: alertLog.map((alert) => AlertCard(alert: alert)).toList(),
              ),
              const SizedBox(height: 30), 
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    channel?.sink.close();
    _audioPlayer.stop(); 
    _audioPlayer.dispose();
    reconnectTimer?.cancel();
    super.dispose();
  }
}

// WIDGETS 

class StatusCard extends StatelessWidget {
  final String title;
  final String status;
  final Color statusColor;
  final IconData icon;

  const StatusCard({
    super.key,
    required this.title,
    required this.status,
    required this.statusColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: const Color(0xFF2D3142),
          borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            Text(title,
                style: GoogleFonts.roboto(color: Colors.white70)),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(4)),
              child: Text(status,
                  style: GoogleFonts.roboto(
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
            ),
          ]),
          Icon(icon, color: Colors.white)
        ],
      ),
    );
  }
}

class MetricCard extends StatelessWidget {
  final String title;
  final String value;

  const MetricCard({super.key, required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: const Color(0xFF2D3142),
          borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: GoogleFonts.roboto(color: Colors.white70)),
        const SizedBox(height: 8),
        Text(value,
            style: GoogleFonts.roboto(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
      ]),
    );
  }
}

class AlertCard extends StatelessWidget {
  final String alert;

  const AlertCard({super.key, required this.alert});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: const Color(0xFF2D3142),
          borderRadius: BorderRadius.circular(8)),
      child: Text(
        alert,
        style: GoogleFonts.roboto(fontSize: 14, color: Colors.white),
      ),
    );
  }
}