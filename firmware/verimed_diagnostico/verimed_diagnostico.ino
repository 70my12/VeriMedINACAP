// =====================================================================
//  VERIMED BT - DIAGNOSTICO DE HARDWARE (PZEM-004T + sensor optico)
//  ESP32-2432S028 (CYD 2.8") - usa tu mismo User_Setup.h
// =====================================================================
//  Sirve para probar las conexiones ANTES de usar el firmware completo.
//  Muestra en pantalla y en el Monitor Serie (115200):
//   - PZEM: tension, corriente, potencia, FP, frecuencia, energia y
//           si responde o no (contador de lecturas buenas / fallidas).
//   - Sensor: estado del pin en vivo (para ajustar el potenciometro),
//             pulsos contados, intervalo entre pulsos y la potencia que
//             "ve" el medidor segun sus pulsos (para comparar con el PZEM).
//  Boton BOOT de la placa: reinicia los contadores.
//
//  Librerias: TFT_eSPI y "PZEM-004T-v30" (Jakub Mandula).
//  Si aun no tienes el PZEM, pon USAR_PZEM 0 y prueba solo el sensor.
// =====================================================================

#define USAR_PZEM      1
#define KC_MEDIDOR     1000      // imp/kWh de la placa del medidor bajo prueba
#define PIN_PULSOS     35        // P3: salida DO del sensor optico
#define FLANCO_PULSO   FALLING   // si cuenta mal, prueba RISING
#define ANTIRREBOTE_MS 30
#define PZEM_RX        27        // CN1: ESP32 RX <- TX del PZEM
#define PZEM_TX        22        // CN1: ESP32 TX -> RX del PZEM
#define PIN_BOOT        0
#define LED_ROJO        4        // LED RGB de la placa (activo en LOW)
#define LED_VERDE      16
#define LED_AZUL       17

#include <SPI.h>
#include <TFT_eSPI.h>
#if USAR_PZEM
#include <PZEM004Tv30.h>
PZEM004Tv30 pzem(Serial2, PZEM_RX, PZEM_TX);
#endif

TFT_eSPI tft = TFT_eSPI();

// ---- Pulsos (interrupcion) ----
volatile uint32_t pulsos = 0;
volatile unsigned long tUltimo = 0, intervaloMs = 0;
void IRAM_ATTR isrPulso() {
  unsigned long t = millis();
  if (t - tUltimo < ANTIRREBOTE_MS) return;
  if (tUltimo != 0) intervaloMs = t - tUltimo;
  tUltimo = t;
  pulsos++;
}

// ---- PZEM ----
float V = NAN, I = NAN, P = NAN, FP = NAN, F = NAN, E = NAN;
uint32_t lecturasOk = 0, lecturasFallidas = 0;

// ---- Pantalla ----
const uint16_t FONDO = TFT_BLACK;
void rotulo(const String &t, int x, int y) {
  tft.setTextColor(TFT_DARKGREY, FONDO);
  tft.setTextDatum(TL_DATUM);
  tft.drawString(t, x, y, 2);
}
void valor(const String &t, int x, int y, uint16_t color, int ancho) {
  tft.setTextColor(color, FONDO);
  tft.setTextDatum(TL_DATUM);
  tft.setTextPadding(ancho);           // borra el texto anterior sin parpadeo
  tft.drawString(t, x, y, 4);
  tft.setTextPadding(0);
}
String num(float v, int dec, const char *unidad) {
  if (isnan(v)) return String("---");
  return String(v, dec) + " " + unidad;
}

void dibujarFijo() {
  tft.fillScreen(FONDO);
  tft.setTextColor(TFT_CYAN, FONDO);
  tft.drawString("VERIMED BT - DIAGNOSTICO", 6, 4, 2);
  tft.drawFastHLine(0, 22, 320, TFT_DARKGREY);
  rotulo("PZEM-004T", 6, 26);
  rotulo("Tension", 6, 44);    rotulo("Corriente", 112, 44); rotulo("Potencia", 218, 44);
  rotulo("FP", 6, 88);         rotulo("Frecuencia", 112, 88); rotulo("Energia", 218, 88);
  tft.drawFastHLine(0, 134, 320, TFT_DARKGREY);
  rotulo("SENSOR OPTICO (IO35)", 6, 138);
  rotulo("Pin ahora", 6, 156); rotulo("Pulsos", 112, 156); rotulo("Intervalo", 218, 156);
  rotulo("Potencia segun pulsos (Kc " + String(KC_MEDIDOR) + ")", 6, 200);
}

void setup() {
  Serial.begin(115200);
  pinMode(PIN_PULSOS, INPUT);          // IO35 no tiene pull-up: lo trae el modulo
  pinMode(PIN_BOOT, INPUT_PULLUP);
  pinMode(LED_ROJO, OUTPUT); pinMode(LED_VERDE, OUTPUT); pinMode(LED_AZUL, OUTPUT);
  digitalWrite(LED_ROJO, HIGH); digitalWrite(LED_VERDE, HIGH); digitalWrite(LED_AZUL, HIGH);
  attachInterrupt(digitalPinToInterrupt(PIN_PULSOS), isrPulso, FLANCO_PULSO);

  tft.init();
  tft.setRotation(1);
  dibujarFijo();

  Serial.println();
  Serial.println("VeriMed BT - diagnostico de hardware");
  Serial.println("t_s;V;A;W;FP;Hz;kWh;pzem_ok;pzem_fallas;pin;pulsos;intervalo_ms;W_segun_pulsos");
}

void loop() {
  static unsigned long tLectura = 0;
  static uint32_t pulsosVistos = 0;
  unsigned long ahora = millis();

  // Boton BOOT: reinicia contadores
  if (digitalRead(PIN_BOOT) == LOW) {
    noInterrupts(); pulsos = 0; intervaloMs = 0; tUltimo = 0; interrupts();
    pulsosVistos = 0; lecturasOk = lecturasFallidas = 0;
    Serial.println("# Contadores reiniciados");
    while (digitalRead(PIN_BOOT) == LOW) delay(10);
  }

  // Estado del pin en vivo (para ajustar el potenciometro del modulo)
  int pin = digitalRead(PIN_PULSOS);
  static int pinAnterior = -1;
  if (pin != pinAnterior) {
    pinAnterior = pin;
    valor(pin == LOW ? "LOW" : "HIGH", 6, 172, pin == LOW ? TFT_YELLOW : TFT_WHITE, 100);
  }

  // Pulso nuevo: LED azul y actualiza pantalla
  uint32_t n; unsigned long iv;
  noInterrupts(); n = pulsos; iv = intervaloMs; interrupts();
  if (n != pulsosVistos) {
    pulsosVistos = n;
    digitalWrite(LED_AZUL, LOW); delay(15); digitalWrite(LED_AZUL, HIGH);
    valor(String(n), 112, 172, TFT_YELLOW, 100);
    valor(iv ? String(iv / 1000.0, 2) + " s" : String("---"), 218, 172, TFT_WHITE, 100);
    // Cada pulso = 1000/Kc Wh  ->  P = (1000/Kc Wh) / (intervalo h)
    float pMed = iv ? (1000.0 / KC_MEDIDOR) * 3600000.0 / iv : NAN;
    valor(num(pMed, 1, "W"), 6, 216, TFT_YELLOW, 200);
  }

  // PZEM cada 1 s
  if (ahora - tLectura >= 1000) {
    tLectura = ahora;
#if USAR_PZEM
    float v = pzem.voltage();
    if (isnan(v)) {
      lecturasFallidas++;
      V = I = P = FP = F = E = NAN;
    } else {
      lecturasOk++;
      V = v; I = pzem.current(); P = pzem.power(); FP = pzem.pf(); F = pzem.frequency(); E = pzem.energy();
    }
    bool ok = !isnan(V);
    digitalWrite(LED_VERDE, ok ? LOW : HIGH);
    digitalWrite(LED_ROJO, ok ? HIGH : LOW);
    tft.setTextColor(ok ? TFT_GREEN : TFT_RED, FONDO);
    tft.setTextPadding(220);
    String estadoPzem = ok ? String("RESPONDE  ok:") + String(lecturasOk) + " fallas:" + String(lecturasFallidas)
                           : String("SIN RESPUESTA (revisa cables y 220 V)");
    tft.drawString(estadoPzem, 96, 26, 2);
    tft.setTextPadding(0);
#else
    tft.setTextColor(TFT_DARKGREY, FONDO);
    tft.drawString("desactivado (USAR_PZEM 0)", 96, 26, 2);
#endif
    valor(num(V, 1, "V"), 6, 60, TFT_WHITE, 100);
    valor(num(I, 2, "A"), 112, 60, TFT_WHITE, 100);
    valor(num(P, 0, "W"), 218, 60, TFT_WHITE, 100);
    valor(num(FP, 2, ""), 6, 104, TFT_WHITE, 100);
    valor(num(F, 1, "Hz"), 112, 104, TFT_WHITE, 100);
    valor(num(isnan(E) ? NAN : E * 1000.0, 0, "Wh"), 218, 104, TFT_WHITE, 100);

    // Linea CSV para el Monitor Serie (se puede copiar a Excel)
    float pMed = iv ? (1000.0 / KC_MEDIDOR) * 3600000.0 / iv : NAN;
    Serial.printf("%.1f;%.1f;%.3f;%.1f;%.2f;%.1f;%.3f;%u;%u;%d;%u;%lu;%.1f\n",
                  ahora / 1000.0, V, I, P, FP, F, E, (unsigned)lecturasOk, (unsigned)lecturasFallidas,
                  pin, (unsigned)n, iv, pMed);
  }
  delay(5);
}
