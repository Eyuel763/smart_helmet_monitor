#include <WiFi.h>
#include <Wire.h>
#include <DHT.h>
#include <OneWire.h>
#include <DallasTemperature.h>
#include "MAX30100_PulseOximeter.h"
#include <WebSocketsServer.h> 
// WIFI 
const char* ssid = "Hot";
const char* password = "0987654321";
// STATIC IP 
IPAddress local_IP(10, 12, 80, 50);
IPAddress gateway(10, 12, 80, 1);
IPAddress subnet(255, 255, 255, 0);
// PINS 
#define MQ2_PIN 34 
#define MQ7_PIN 35 
#define DHT_PIN 4
#define DHTTYPE DHT11
#define DS_PIN 5 
#define BUZZER 12 
#define LED 13 
#define MQ_GAS_THRESHOLD 1500 
#define BODY_TEMP_CRITICAL 38.5  
#define AMBIENT_TEMP_CRITICAL 35.0 

unsigned long buzzerTimer = 0;
bool buzzerState = false;


// Sensor Objects
DHT dht(DHT_PIN, DHTTYPE); // 
OneWire oneWire(DS_PIN); 
DallasTemperature sensors(&oneWire); 

// MAX30100 Variables and RTOS Handle 
PulseOximeter pox;
float heartRate = 0;
float spo2 = 0;
TaskHandle_t max30100TaskHandle;

// WebSocket server on port 81
WebSocketsServer webSocket = WebSocketsServer(81);

void webSocketEvent(uint8_t num, WStype_t type, uint8_t * payload, size_t length) {
  switch(type) {
    case WStype_DISCONNECTED:
      Serial.printf("[%u] Disconnected\n", num);
      break;
    case WStype_CONNECTED: {
      IPAddress ip = webSocket.remoteIP(num);
      Serial.printf("[%u] Connected from %d.%d.%d.%d\n",
                    num, ip[0], ip[1], ip[2], ip[3]);
      break;
    }
    default:
      break;
  }
}

// (Core 1) 
// Dedicated task for continuous MAX30100 updates
void max30100Task(void *parameter) {
  while (true) {
    pox.update();
    heartRate = pox.getHeartRate(); 
    spo2 = pox.getSpO2(); 

    vTaskDelay(10 / portTICK_PERIOD_MS); // ~100Hz (10ms delay)
  }
}

void setup() {
  Serial.begin(115200);

  pinMode(BUZZER, OUTPUT);
  pinMode(LED, OUTPUT);
  digitalWrite(LED, LOW);
  digitalWrite(BUZZER, LOW);

  dht.begin(); 
  sensors.begin(); 

  // Initialize I2C for MAX30100
  Wire.begin(21, 22); 
  if (!pox.begin()) {
    Serial.println("MAX30100 INIT FAILED");
  } else {
    Serial.println("MAX30100 INIT SUCCESS"); 
  }

  // Create MAX30100 Task on Core 1 
  xTaskCreatePinnedToCore(
    max30100Task,        // Task function
    "MAX30100_Task",     // Name
    4096,                // Stack size
    NULL,                // Parameter
    1,                   // Priority
    &max30100TaskHandle, // Task handle
    1                    // Core 1
  );

  Serial.println("Configuring static IP...");
  if (!WiFi.config(local_IP, gateway, subnet)) {
    Serial.println("Static IP configuration failed");
  }
  // WIFI CONNECT 
  WiFi.begin(ssid, password);
  Serial.print("Connecting to WiFi");
  while (WiFi.status() != WL_CONNECTED) { 
    delay(500);
    Serial.print(".");
  }

  Serial.println();
  Serial.print("Connected! ESP32 IP: ");
  Serial.println(WiFi.localIP());
  webSocket.begin();
  webSocket.onEvent(webSocketEvent);
  Serial.println(" WebSocket server running on port 81");
}

void loop() {
  webSocket.loop();
  const int ADC_MAX_VALUE = 4095;
  
  // Readings for non-RTOS sensors
  int mq2Value = analogRead(MQ2_PIN); 
  int mq7Value = analogRead(MQ7_PIN);
  sensors.requestTemperatures();
  float bodyTemp = sensors.getTempCByIndex(0);
  float ambientTemp = dht.readTemperature();
  
  // MQ SENSOR FAILURE DETECTION 
  bool mq2Failed = false;
  if (mq2Value == 0 || mq2Value == ADC_MAX_VALUE) {
    Serial.println("MQ2 read failed (Stuck at 0 or 4095)!");
    mq2Failed = true;
    mq2Value = 0; // Set to 0 to prevent false alarm if stuck at max ADC
  }
  bool mq7Failed = false;
  if (mq7Value == 0 || mq7Value == ADC_MAX_VALUE) {
    Serial.println("MQ7 read failed (Stuck at 0 or 4095)!");
    mq7Failed = true;
    mq7Value = 0; 
  }

  // DS18B20 Failure Check
  if (bodyTemp == DEVICE_DISCONNECTED_C) {
    Serial.println("DS18B20 not connected!");
    bodyTemp = 0;
  }

  // DHT11 Failure Check
  if (isnan(ambientTemp)) {
    Serial.println("DHT11 read failed!");
    ambientTemp = 0;
  }
  
  // ALARM LOGIC (Buzzer & LED) 
  bool alarmActive = false;
  
  // Gas Alarms
  if (!mq2Failed && mq2Value > MQ_GAS_THRESHOLD) {
    Serial.println("!!! MQ2 GAS DANGER DETECTED !!!");
    alarmActive = true;
  }
  if (!mq7Failed && mq7Value > MQ_GAS_THRESHOLD) {
    Serial.println("!!! MQ7 GAS DANGER DETECTED !!!");
    alarmActive = true;
  }
  
  // Body Temperature Alarm Check 
  if (bodyTemp > 0 && bodyTemp >= BODY_TEMP_CRITICAL) {
    Serial.printf("!!! CRITICAL BODY TEMP: %.1f C !!!\n", bodyTemp);
    alarmActive = true;
  }
  
  // Ambient Temperature Alarm Check (Overheating/Fire)
  if (ambientTemp >= AMBIENT_TEMP_CRITICAL) {
    Serial.printf("!!! CRITICAL AMBIENT TEMP: %.1f C !!!\n", ambientTemp);
    alarmActive = true;
  }
  
  if (spo2 > 0 && spo2 < 90.0) {
      Serial.printf("!!! CRITICAL SpO2: %.1f %% !!!\n", spo2);
      alarmActive = true;
  }
  
  // Control the Buzzer and LED based on the alarm state
  if (alarmActive) {
  if (millis() - buzzerTimer >= 500) {
    buzzerTimer = millis();
    buzzerState = !buzzerState;
    digitalWrite(BUZZER, buzzerState);
    digitalWrite(LED, buzzerState);
  }
} else {
  digitalWrite(BUZZER, LOW);
  digitalWrite(LED, LOW);
  buzzerState = false;
}

  
  // CREATE JSON 
  String payload = "{";
  payload += "\"mq2\": " + String(mq2Value) + ", ";
  payload += "\"mq7\": " + String(mq7Value) + ", ";
  payload += "\"body_temp\": " + String(bodyTemp, 1) + ", ";
  payload += "\"ambient_temp\": " + String(ambientTemp, 1) + ", ";
  payload += "\"heart_rate\": " + String(heartRate, 0) + ", "; 
  payload += "\"spo2\": " + String(spo2, 1); 
  payload += "}";
  
  // SEND TO FLUTTER 
  webSocket.broadcastTXT(payload);
  Serial.println(payload);
  
}