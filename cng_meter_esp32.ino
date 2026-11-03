/*
  CNG Meter - ESP32 (BLE)
  Board: ESP32 Dev Module   |   Sensor pin: GPIO34 (ADC1)

  DEMO MODE  : USE_DIVIDER = false, cell/potentiometer 0 - 3.3V seedha GPIO34 pe
  REAL SENSOR: USE_DIVIDER = true,  sensor signal -> R1 -> GPIO34 -> R2 -> GND
               (R1 = 10k, R2 = 15k, 5V ko 3.0V bana deta hai)

  Data format (notify): "percent,voltage"   e.g. "72,2.38"
  Commands (write)    : SETEMPTY, SETFULL, RESET
*/

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <Preferences.h>

#define DEVICE_NAME  "CNG_Meter"
#define SERVICE_UUID "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
#define CMD_UUID     "6e400002-b5a3-f393-e0a9-e50e24dcca9e"  // app -> ESP32
#define DATA_UUID    "6e400003-b5a3-f393-e0a9-e50e24dcca9e"  // ESP32 -> app

// ---------- Settings ----------
const int   SENSOR_PIN  = 34;
const bool  USE_DIVIDER = false;      // real sensor lagate waqt true kar dena
const float R1 = 10000.0;
const float R2 = 15000.0;

// Default calibration (sensor voltage). App se SETEMPTY / SETFULL karke badal sakte ho.
const float DEFAULT_EMPTY_V = 0.0;    // demo. Real sensor: approx 0.5
const float DEFAULT_FULL_V  = 3.3;    // demo. Real sensor: approx 4.5 - 5.0

const int   SEND_INTERVAL_MS = 500;
const float SMOOTHING        = 0.3;   // 0..1 (chhota = zyada smooth)

// ---------- Globals ----------
Preferences prefs;
BLECharacteristic *dataChar = nullptr;
bool  clientConnected = false;
float emptyV = DEFAULT_EMPTY_V;
float fullV  = DEFAULT_FULL_V;
float smoothV = -1;

float readSensorVoltage() {
  long sum = 0;
  for (int i = 0; i < 32; i++) {
    sum += analogReadMilliVolts(SENSOR_PIN);
    delay(2);
  }
  float pinV = (sum / 32.0) / 1000.0;
  if (USE_DIVIDER) return pinV * (R1 + R2) / R2;
  return pinV;
}

float voltageToPercent(float v) {
  if (fullV - emptyV < 0.05) return 0;
  float p = (v - emptyV) * 100.0 / (fullV - emptyV);
  return constrain(p, 0.0, 100.0);
}

class ServerCB : public BLEServerCallbacks {
  void onConnect(BLEServer *s) override {
    clientConnected = true;
    Serial.println("App connected");
  }
  void onDisconnect(BLEServer *s) override {
    clientConnected = false;
    Serial.println("App disconnected");
    BLEDevice::startAdvertising();
  }
};

class CmdCB : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *c) override {
    String cmd = String(c->getValue().c_str());
    cmd.trim();
    Serial.println("Command: " + cmd);

    if (cmd == "SETEMPTY" && smoothV >= 0) {
      emptyV = smoothV;
      prefs.putFloat("empty", emptyV);
    } else if (cmd == "SETFULL" && smoothV >= 0) {
      fullV = smoothV;
      prefs.putFloat("full", fullV);
    } else if (cmd == "RESET") {
      emptyV = DEFAULT_EMPTY_V;
      fullV  = DEFAULT_FULL_V;
      prefs.putFloat("empty", emptyV);
      prefs.putFloat("full", fullV);
    }
    Serial.printf("Calibration -> empty: %.2fV, full: %.2fV\n", emptyV, fullV);
  }
};

void setup() {
  Serial.begin(115200);
  analogSetPinAttenuation(SENSOR_PIN, ADC_11db);

  prefs.begin("cng", false);
  emptyV = prefs.getFloat("empty", DEFAULT_EMPTY_V);
  fullV  = prefs.getFloat("full",  DEFAULT_FULL_V);

  BLEDevice::init(DEVICE_NAME);
  BLEServer *server = BLEDevice::createServer();
  server->setCallbacks(new ServerCB());

  BLEService *service = server->createService(SERVICE_UUID);

  dataChar = service->createCharacteristic(
      DATA_UUID, BLECharacteristic::PROPERTY_NOTIFY | BLECharacteristic::PROPERTY_READ);
  dataChar->addDescriptor(new BLE2902());

  BLECharacteristic *cmdChar = service->createCharacteristic(
      CMD_UUID, BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  cmdChar->setCallbacks(new CmdCB());

  service->start();

  BLEAdvertising *adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->setScanResponse(true);
  BLEDevice::startAdvertising();

  Serial.println("CNG Meter ready. BLE name: " DEVICE_NAME);
}

void loop() {
  float v = readSensorVoltage();
  smoothV = (smoothV < 0) ? v : (smoothV + SMOOTHING * (v - smoothV));

  float percent = voltageToPercent(smoothV);

  Serial.printf("Voltage: %.2fV  CNG: %.0f%%\n", smoothV, percent);

  if (clientConnected) {
    char buf[24];
    snprintf(buf, sizeof(buf), "%d,%.2f", (int)(percent + 0.5), smoothV);
    dataChar->setValue((uint8_t *)buf, strlen(buf));
    dataChar->notify();
  }

  delay(SEND_INTERVAL_MS);
}
