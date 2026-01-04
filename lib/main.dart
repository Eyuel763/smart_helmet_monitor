import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const String esp32Url = "ws://10.212.39.50:81";

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
  double bodyTemp = 0;
  double ambientTemp = 0;

  String gasStatus = "SAFE";
  String fatigueStatus = "LOW";
  String mq2Display = "0";
  String mq7Display = "0";

  Color gasColor = Colors.green;
  Color fatigueColor = Colors.green;

  List<String> alertLog = [];
  final int mqGasThreshold = 1500;
  final double bodyTempThreshold = 38.5;

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
      mq2 = data['mq2'];
      mq7 = data['mq7'];
      bodyTemp = (data['body_temp'] as num).toDouble();
      ambientTemp = (data['ambient_temp'] as num).toDouble();

      gasStatus = mq2 > 400 ? "DANGER" : "SAFE";
      fatigueStatus = bodyTemp > 38 ? "HIGH" : "LOW";

      gasColor = gasStatus == "DANGER" ? Colors.red : Colors.green;
      fatigueColor = fatigueStatus == "HIGH" ? Colors.red : Colors.green;

      if (mq2 == 0) {
        mq2Display = "ERROR";
        gasStatus = mq7 > mqGasThreshold ? "DANGER" : "SAFE";
      } else {
        mq2Display = mq2.toString();
        gasStatus = mq2 > mqGasThreshold ? "DANGER" : "SAFE";
      }
      
      if (mq7 == 0) {
        mq7Display = "ERROR";
        if (mq2 == 0) {
          gasStatus = "ERROR";
        } else {
          gasStatus = gasStatus;
        }
      } else {
        mq7Display = mq7.toString();
        if (gasStatus != "DANGER") gasStatus = mq7 > mqGasThreshold ? "DANGER" : "SAFE";
      }
      if (mq2 == 0 && mq7 == 0) gasStatus = "ERROR";

      fatigueStatus = bodyTemp >= bodyTempThreshold ? "HIGH" : "LOW";
      if (bodyTemp == 0.0) fatigueStatus = "ERROR"; 

      if (gasStatus == "ERROR") {
        gasColor = Colors.yellow;
      } else {
        gasColor = gasStatus == "DANGER" ? Colors.red : Colors.green;
      }
      
      if (fatigueStatus == "ERROR") {
        fatigueColor = Colors.yellow;
      } else {
        fatigueColor = fatigueStatus == "HIGH" ? Colors.red : Colors.green;
      }
    });

    _handleAlerts();
  }

  // ALERT LOGIC 

  void _handleAlerts() {
    if (gasStatus == "DANGER" || fatigueStatus == "HIGH") {
      _playAlarm();

      final alert =
          "${DateTime.now().toLocal()} | Gas: $gasStatus | Fatigue: $fatigueStatus";

      _saveAlert(alert);

      _showNotification(
        "SAFETY ALERT",
        gasStatus == "DANGER"
            ? "Dangerous gas detected!"
            : "High fatigue detected!",
      );
    } else {
      _stopAlarm();
    }
  }

  // ALERT STORAGE 

  Future<void> _saveAlert(String alert) async {
    alertLog.insert(0, alert);
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
    await _audioPlayer.play(AssetSource('sounds/alarm.mp3'));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1B26),
      body: SafeArea(
        child: Padding(
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

              StatusCard(
                title: "GAS LEVEL",
                status: gasStatus,
                statusColor: gasColor,
                icon: Icons.warning,
              ),
              const SizedBox(height: 12),

              StatusCard(
                title: "FATIGUE RISK",
                status: fatigueStatus,
                statusColor: fatigueColor,
                icon: Icons.bolt,
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                      child: MetricCard(
                          title: "MQ2 GAS", value: mq2Display)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: MetricCard(
                          title: "BODY TEMP",
                          value: bodyTemp == 0.0 ? "ERROR" : "${bodyTemp.toStringAsFixed(1)} °C")),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                      child: MetricCard(
                          title: "MQ7 GAS", value: mq7Display)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: MetricCard(
                          title: "AMBIENT TEMP",
                          value:
                              ambientTemp == 0.0 ? "ERROR" : "${ambientTemp.toStringAsFixed(1)} °C")),
                ],
              ),
              const SizedBox(height: 16),

              Text("Recent Alerts",
                  style: GoogleFonts.roboto(
                      fontSize: 16, color: Colors.white70)),
              const Divider(),

              Expanded(
                child: ListView.builder(
                  itemCount: alertLog.length,
                  itemBuilder: (_, i) => AlertCard(alert: alertLog[i]),
                ),
              )
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

  const StatusCard(
      {super.key,
      required this.title,
      required this.status,
      required this.statusColor,
      required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: statusColor.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: GoogleFonts.roboto(color: Colors.white70)),
            Text(status,
                style: GoogleFonts.roboto(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
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

    final color = alert.contains("DANGER") || alert.contains("HIGH") || alert.contains("ERROR")
        ? const Color(0xFF7D3C3C) // Reddish for danger/error
        : const Color(0xFF3C7D4D); // Greenish for normal
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8)),
      child: Text(alert,
          style: GoogleFonts.roboto(color: Colors.white)),
    );
  }
}