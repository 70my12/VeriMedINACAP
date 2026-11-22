// =====================================================================
//  VERIMED BT - PLACA DE MEDICION (ESP32 DevKitC + 2 x AD71056)  v2
// =====================================================================
//  Arduino IDE -> Herramientas -> Placa: "ESP32 Dev Module". Sin librerias extra.
//
//  Pines y canales verificados en la placa real (codigo de prueba "Contrastador"):
//    GPIO19 <- CF del AD71056 de TENSION   (frecuencia ~ V^2)   pull-up 10k en la placa
//    GPIO21 <- CF del AD71056 de CORRIENTE (frecuencia ~ I^2)   pull-up 10k en la placa
//    GPIO18 -> rele de la carga (HIGH = carga conectada)
//    GPIO17 = TX -> J3 pin 2 -> pantalla J2 "18"
//    GPIO16 = RX <- J3 pin 3 <- pantalla J2 "17"
//
//  Calculo:
//    V = raiz(KV * fV)      I = raiz(KI * fI)      (si un canal fuera lineal: CUADRATICO_x = false)
//    P = V * I              (carga resistiva, FP ~ 1)
//    E = integral de P en el tiempo (Wh)
//  Usa las mismas constantes KV / KI que el codigo de prueba: si ya calibraron
//  con "cv" y "ci", la calibracion se conserva.
//
//  Mensaje a la pantalla (115200 baud, 5 por segundo):
//    $VM,<P W>,<E Wh>,<pulsos CF de I>,<V>,<I A>,<rele 0/1>*CS     (V, I = -1 sin calibrar)
//
//  Comandos (Monitor Serie 115200, "Nueva linea", o desde la pantalla):
//    1 / 0  (o RELE,1 / RELE,0)   carga ON / OFF
//    cv220.5  (o CALV,220.5)      calibra TENSION con lo que marca el multimetro (carga ON)
//    ci4.10   (o CALI,4.10)       calibra CORRIENTE con lo que marca la pinza (carga ON)
//    v        muestra / oculta lecturas en vivo     ? (o ESTADO)  resumen
//    CERO     reinicia la energia acumulada
// =====================================================================

#include <Arduino.h>
#include <Preferences.h>

// ------------------------- CONFIGURACION -----------------------------
#define PIN_RELE   18
#define PIN_CFV    21          // CF del AD71056 de TENSION (f ~ V^2): constante, no depende de la carga
#define PIN_CFI    19          // CF del AD71056 de CORRIENTE (f ~ I^2): 0 Hz con la carga apagada
#define PIN_LED     2          // LED azul del DevKit: destello con cada pulso de corriente
#define UART_RX    16          // J3 pin 3
#define UART_TX    17          // J3 pin 2
#define BAUDIOS    115200

const bool CUADRATICO_V = true;    // f ~ V^2  (false si f ~ V)
const bool CUADRATICO_I = true;    // f ~ I^2  (false si f ~ I)

#define RELE_AL_INICIO   0         // 0 = la carga queda APAGADA al encender (la pantalla la conecta al iniciar el ensayo)
#define RELE_ACTIVO_ALTO 1         // 1 = HIGH conecta la carga; pon 0 si tu modulo de rele se activa con LOW
#define RELE_MAX_MS      600000UL  // seguridad: el rele se apaga solo tras 10 min encendido
#define ANTIRREBOTE_US   2000      // igual que el codigo de prueba
#define VENTANA_MS       2000      // ventana para medir la frecuencia de cada CF
#define I_MIN_A          0.02f     // bajo esto se considera sin carga
// ---------------------------------------------------------------------

Preferences prefs;
HardwareSerial Pantalla(2);

volatile uint32_t pulsosV = 0, pulsosI = 0;
volatile uint32_t tUltV = 0, tUltI = 0;
void IRAM_ATTR isrV() { uint32_t t = micros(); if (t - tUltV < ANTIRREBOTE_US) return; tUltV = t; pulsosV++; }
void IRAM_ATTR isrI() { uint32_t t = micros(); if (t - tUltI < ANTIRREBOTE_US) return; tUltI = t; pulsosI++; }

float KV = 0, KI = 0;              // constantes de calibracion (flash, mismas que el codigo de prueba)
bool rele = false, enVivo = true;
float fV = 0, fI = 0;              // frecuencias de la ultima ventana (Hz)
float Vmed = -1, Imed = -1, Pmed = 0;
double energiaWh = 0;

float aVoltaje(float f)   { if (KV <= 0) return -1; return CUADRATICO_V ? sqrtf(KV * f) : KV * f; }
float aCorriente(float f) { if (KI <= 0) return -1; return CUADRATICO_I ? sqrtf(KI * f) : KI * f; }

void leerPulsos(uint32_t &v, uint32_t &i) { noInterrupts(); v = pulsosV; i = pulsosI; interrupts(); }

uint32_t tReleOn = 0;
void fijarRele(bool on) {
  if (on && !rele) tReleOn = millis();
  rele = on;
  digitalWrite(PIN_RELE, (on == RELE_ACTIVO_ALTO) ? HIGH : LOW);
}

// Frecuencias en ventanas de 2 s, contadas entre pulsos reales (mas exacto que
// dividir por la ventana fija). Se llama seguido desde loop().
void actualizarFrecuencias() {
  static uint32_t tPrev = 0, vPrev = 0, iPrev = 0;
  static uint32_t tPrimV = 0, tPrimI = 0;
  uint32_t ahora = millis();
  if (tPrev == 0) { tPrev = ahora; leerPulsos(vPrev, iPrev); noInterrupts(); tPrimV = tUltV; tPrimI = tUltI; interrupts(); return; }
  if (ahora - tPrev < VENTANA_MS) return;
  uint32_t v, i, tv, ti;
  noInterrupts(); v = pulsosV; i = pulsosI; tv = tUltV; ti = tUltI; interrupts();
  float dt = (ahora - tPrev) / 1000.0f;
  // Frecuencia = pulsos de la ventana / tiempo desde el ultimo pulso de la ventana anterior
  // hasta el ultimo pulso de esta (periodos completos, sin error de ventana)
  fV = (v - vPrev) >= 2 && tv != tPrimV ? (v - vPrev) / ((tv - tPrimV) / 1e6f) : (v - vPrev) / dt;
  fI = (i - iPrev) >= 2 && ti != tPrimI ? (i - iPrev) / ((ti - tPrimI) / 1e6f) : (i - iPrev) / dt;
  tPrev = ahora; vPrev = v; iPrev = i; tPrimV = tv; tPrimI = ti;

  Vmed = aVoltaje(fV);
  Imed = aCorriente(fI);
  if (Imed >= 0 && Imed < I_MIN_A) Imed = 0;
  Pmed = (Vmed > 0 && Imed > 0) ? Vmed * Imed : 0;
}

// Energia: integra la potencia cada 100 ms
void integrarEnergia() {
  static uint32_t tPrev = 0;
  uint32_t ahora = millis();
  if (tPrev == 0) { tPrev = ahora; return; }
  if (ahora - tPrev < 100) return;
  energiaWh += Pmed * (ahora - tPrev) / 3600000.0;
  tPrev = ahora;
}

// ----------------------------- Envio ---------------------------------
void enviarMedicion() {
  uint32_t v, i; leerPulsos(v, i);
  char cuerpo[120];
  snprintf(cuerpo, sizeof(cuerpo), "VM,%.1f,%.4f,%lu,%.1f,%.3f,%d",
           Pmed, energiaWh, (unsigned long)i, Vmed, Imed, rele ? 1 : 0);
  uint8_t cs = 0;
  for (const char *p = cuerpo; *p; p++) cs ^= (uint8_t)*p;
  Pantalla.printf("$%s*%02X\n", cuerpo, cs);
}

// --------------------------- Calibracion ------------------------------
void calibrar(char canal, float real) {
  if (!rele) { Serial.println("Activa la carga (1) y espera 4 s antes de calibrar."); return; }
  float f = (canal == 'v') ? fV : fI;
  if (f <= 0 || real <= 0) { Serial.println("No llegan pulsos en ese canal o el valor es invalido."); return; }
  if (millis() - tReleOn < 6000) { Serial.println("Espera 6 s con la carga encendida: la frecuencia aun no es estable."); return; }
  if (f < 1.0) { Serial.printf("Frecuencia muy baja (%.3f Hz): revisa que la carga este conectada y vuelve a intentar.\n", f); return; }
  bool cuad = (canal == 'v') ? CUADRATICO_V : CUADRATICO_I;
  float K = cuad ? (real * real / f) : (real / f);
  if (canal == 'v') { KV = K; prefs.putFloat("KV", KV); }
  else              { KI = K; prefs.putFloat("KI", KI); }
  Serial.printf("Calibrado %s: f = %.3f Hz -> %.3f %s  (K = %.6g, guardado)\n",
                canal == 'v' ? "TENSION" : "CORRIENTE", f, real, canal == 'v' ? "V" : "A", K);
}

// Diagnostico: cuenta flancos durante 3 s en todos los GPIO libres, para saber
// en que pin llegan realmente los pulsos de cada AD71056.
void escanearPines() {
  const uint8_t pines[] = {4, 5, 13, 14, 19, 21, 22, 23, 25, 26, 27, 32, 33, 34, 35, 36, 39};
  const int n = sizeof(pines);
  uint32_t flancos[n] = {0}; uint8_t prev[n];
  detachInterrupt(digitalPinToInterrupt(PIN_CFV));
  detachInterrupt(digitalPinToInterrupt(PIN_CFI));
  for (int k = 0; k < n; k++) { pinMode(pines[k], INPUT); prev[k] = digitalRead(pines[k]); }
  Serial.println("Escaneando 3 s (deja la carga encendida)...");
  uint32_t t0 = millis();
  while (millis() - t0 < 3000) {
    for (int k = 0; k < n; k++) { uint8_t s = digitalRead(pines[k]); if (s != prev[k]) { flancos[k]++; prev[k] = s; } }
  }
  for (int k = 0; k < n; k++)
    Serial.printf("  GPIO%-2d  nivel %d  flancos %lu%s\n", pines[k], prev[k], (unsigned long)flancos[k],
                  flancos[k] > 0 ? "   <-- llegan pulsos" : "");
  pinMode(PIN_CFV, INPUT); pinMode(PIN_CFI, INPUT);
  attachInterrupt(digitalPinToInterrupt(PIN_CFV), isrV, FALLING);
  attachInterrupt(digitalPinToInterrupt(PIN_CFI), isrI, FALLING);
}

void estado() {
  Serial.printf("\nfV = %.3f Hz  fI = %.3f Hz\n", fV, fI);
  Serial.printf("V = %s   I = %s   P = %.1f W   E = %.4f Wh   rele %s\n",
                KV > 0 ? (String(Vmed, 1) + " V").c_str() : "SIN CALIBRAR (cv)",
                KI > 0 ? (String(Imed, 3) + " A").c_str() : "SIN CALIBRAR (ci)",
                Pmed, energiaWh, rele ? "ON" : "OFF");
  Serial.println("Comandos: 1 / 0 carga  |  cv<V> calibra tension  |  ci<A> calibra corriente  |  v en vivo  |  CERO  |  scan (busca pulsos)");
}

// ---------------------------- Comandos --------------------------------
void ejecutar(String crudo, bool desdeUsb) {
  // Limpia el texto: solo letras, numeros, punto, coma y signo; sin espacios.
  // Asi "cv 221,5", "CV=221.5" o "cv221.5" funcionan igual.
  String s = crudo;
  if (s.indexOf('$') >= 0) { int a = s.indexOf('$'), b = s.indexOf('*'); s = s.substring(a + 1, b > a ? b : s.length()); }
  String limpio;
  for (unsigned k = 0; k < s.length(); k++) {
    char c = s[k];
    if (c >= 'A' && c <= 'Z') c += 32;
    if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '.' || c == ',' || c == '?' || c == '-') limpio += c;
  }
  s = limpio;
  // "cv221,5" -> "cv221.5" (coma decimal); "calv,221.5" conserva su coma de separador
  if (s.startsWith("cv") || s.startsWith("ci")) s.replace(',', '.');
  if (s.length() == 0) return;
  if (s == "1" || s == "rele,1")      { fijarRele(true);  Serial.println(">>> CARGA ACTIVADA"); }
  else if (s == "0" || s == "rele,0") { fijarRele(false); Serial.println(">>> CARGA DESACTIVADA"); }
  else if (s.startsWith("calv,"))     calibrar('v', s.substring(5).toFloat());
  else if (s.startsWith("cali,"))     calibrar('i', s.substring(5).toFloat());
  else if (s.startsWith("cv"))        calibrar('v', s.substring(2).toFloat());
  else if (s.startsWith("ci"))        calibrar('i', s.substring(2).toFloat());
  else if (s == "v")                  { enVivo = !enVivo; Serial.printf("En vivo: %s\n", enVivo ? "ON" : "OFF"); }
  else if (s == "scan")               escanearPines();
  else if (s == "cero")               { energiaWh = 0; Serial.println("Energia en cero"); }
  else if (s == "?" || s == "estado") estado();
  else if (desdeUsb) {
    Serial.printf("Comando no reconocido: \"%s\" (bytes:", crudo.c_str());
    for (unsigned k = 0; k < crudo.length(); k++) Serial.printf(" %02X", (uint8_t)crudo[k]);
    Serial.println("). Escribe ?");
  }   // lo que llega por el cable de la pantalla y no se entiende es ruido: se ignora
}

String bufUsb, bufPantalla;
void leerComandos() {
  while (Serial.available()) {
    char ch = Serial.read();
    if (ch == '\n' || ch == '\r') { if (bufUsb.length()) ejecutar(bufUsb, true); bufUsb = ""; }
    else if (bufUsb.length() < 80) bufUsb += ch;
  }
  while (Pantalla.available()) {
    char ch = Pantalla.read();
    if (ch == '\n' || ch == '\r') { if (bufPantalla.length()) ejecutar(bufPantalla, false); bufPantalla = ""; }
    else if (bufPantalla.length() < 80) bufPantalla += ch;
  }
}

// ------------------------------ Inicio ---------------------------------
void setup() {
  Serial.begin(115200);
  Pantalla.begin(BAUDIOS, SERIAL_8N1, UART_RX, UART_TX);
  digitalWrite(PIN_RELE, RELE_ACTIVO_ALTO ? LOW : HIGH);   // nivel de apagado antes de habilitar la salida
  pinMode(PIN_RELE, OUTPUT);
  pinMode(PIN_LED, OUTPUT);
  fijarRele(RELE_AL_INICIO);

  pinMode(PIN_CFV, INPUT);         // pull-up 10k de la placa
  pinMode(PIN_CFI, INPUT);
  attachInterrupt(digitalPinToInterrupt(PIN_CFV), isrV, FALLING);
  attachInterrupt(digitalPinToInterrupt(PIN_CFI), isrI, FALLING);

  prefs.begin("contrastador", false);   // mismo espacio que el codigo de prueba: conserva KV y KI
  KV = prefs.getFloat("KV", 0);
  KI = prefs.getFloat("KI", 0);

  delay(300);
  Serial.println("\nVeriMed BT - placa de medicion v2 (V^2 en GPIO19, I^2 en GPIO21, rele GPIO18)");
  Serial.printf("KV %s   KI %s\n", KV > 0 ? "OK" : "SIN CALIBRAR", KI > 0 ? "OK" : "SIN CALIBRAR");
  estado();
}

void loop() {
  static uint32_t tEnvio = 0, tVivo = 0, tLed = 0, nLed = 0;
  uint32_t ahora = millis();
  leerComandos();
  actualizarFrecuencias();
  integrarEnergia();

  if (ahora - tEnvio >= 200) { tEnvio = ahora; enviarMedicion(); }

  if (rele && ahora - tReleOn >= RELE_MAX_MS) {     // nadie lo apago: se corta por seguridad
    fijarRele(false);
    Serial.println("Rele apagado por seguridad (10 min encendido)");
  }

  uint32_t n = pulsosI;
  if (n != nLed) { nLed = n; tLed = ahora; digitalWrite(PIN_LED, HIGH); }
  if (ahora - tLed > 40) digitalWrite(PIN_LED, LOW);

  if (enVivo && ahora - tVivo >= 2000) {
    tVivo = ahora;
    Serial.printf("[vivo] fV=%.2f Hz  fI=%.2f Hz | V=%.1f  I=%.3f A  P=%.1f W  E=%.4f Wh  rele %d\n",
                  fV, fI, Vmed, Imed, Pmed, energiaWh, rele ? 1 : 0);
  }
}
