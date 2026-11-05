// =====================================================================
//  VERIMED BT v2 - Verificador de medidores monofasicos
//  ESP32-2432S028 (CYD 2.8" USB-C, ST7789) + Bluetooth LE
// =====================================================================
//  Librerias: TFT_eSPI 2.5.x (tu User_Setup.h), XPT2046_Touchscreen,
//             PZEM-004T-v30 (mandulaj) -> solo si USAR_PZEM = 1
//  Arduino IDE: Herramientas -> Partition Scheme ->
//               "Huge APP (3MB No OTA/1MB SPIFFS)"
//  Carpeta: verimed_v2/ con verimed_v2.ino, fuentes.h, iconos.h, tipos.h
//
//  COMO FUNCIONA EL ENSAYO
//   1. Se configura Kc (imp/kWh del medidor), N pulsos y la clase.
//   2. INICIAR -> espera el primer pulso del LED del medidor (sincroniza).
//   3. Desde ese pulso integra la energia de referencia (PZEM) hasta
//      completar N pulsos.  Emed = N * 1000 / Kc  [Wh]
//   4. Error % = (Emed - Eref) / Eref * 100  -> APROBADO si |error| <= clase
//
//  SIN HARDWARE (USAR_PZEM = 0 y USAR_SENSOR_PULSOS = 0) todo se simula:
//  un medidor virtual con un error aleatorio entre -1.5 % y +1.5 %.
// =====================================================================

// ------------------------- CONFIGURACION -----------------------------
#define USAR_PZEM            0   // 1 = referencia real con PZEM-004T v3
#define USAR_SENSOR_PULSOS   0   // 1 = sensor optico real en el LED del medidor
#define USAR_PARLANTE        1   // pitidos por el conector P4 (parlante 8 ohm)

#define NUMERO_SERIE   "VMBT-0001"
#define VERSION_FW     "2.0.0"
#define FECHA_CAL      "Sin calibrar"   // ej. "2026-11-20" tras calibrar

// Pines libres del CYD
#define PIN_PULSOS    35   // P3: salida digital del sensor optico (solo entrada)
#define FLANCO_PULSO  FALLING   // la mayoria de modulos baja la salida con luz
#define PZEM_RX       27   // CN1: ESP32 RX  <- TX del PZEM
#define PZEM_TX       22   // CN1: ESP32 TX  -> RX del PZEM
#define PIN_PARLANTE  26   // P4 (amplificador integrado)
#define LED_ROJO       4   // LED RGB de la placa (activo en LOW)
#define LED_VERDE     16
#define LED_AZUL      17

// Limites de alarma (red 220 V)
#define V_MIN        198.0   // -10 %
#define V_MAX        242.0   // +10 %
#define I_MAX         60.0   // A (rango de la pinza del PZEM: 100 A)

// Calibracion tactil: REEMPLAZA con tus valores
#define TOUCH_SWAP_XY 0
#define TOUCH_X_MIN   200
#define TOUCH_X_MAX   3700
#define TOUCH_Y_MIN   240
#define TOUCH_Y_MAX   3800
// ---------------------------------------------------------------------

#include <SPI.h>
#include <TFT_eSPI.h>
#include <XPT2046_Touchscreen.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <Preferences.h>
#if USAR_PZEM
#include <PZEM004Tv30.h>
PZEM004Tv30 pzem(Serial2, PZEM_RX, PZEM_TX);
#endif
#include "fuentes.h"
#include "iconos.h"
#include "tipos.h"

#define XPT2046_IRQ  36
#define XPT2046_MOSI 32
#define XPT2046_MISO 39
#define XPT2046_CLK  25
#define XPT2046_CS   33

// ---- Bluetooth (protocolo v2, compatible con verimed_ble.dart) ----
#define BLE_NOMBRE     "VeriMed BT"
#define UUID_SERVICIO  "7e5a0001-3c1d-4f2b-9a6e-1b2c3d4e5f60"
#define UUID_MEDICION  "7e5a0002-3c1d-4f2b-9a6e-1b2c3d4e5f60"  // READ+NOTIFY
#define UUID_COMANDO   "7e5a0003-3c1d-4f2b-9a6e-1b2c3d4e5f60"  // WRITE
#define UUID_INFO      "7e5a0004-3c1d-4f2b-9a6e-1b2c3d4e5f60"  // READ
// MEDICION: {"v","i","p","fp","f","wh","t","sim","sp","st","pul","np","kc","err","apr","alm"}
//   st: 0 reposo, 1 esperando 1er pulso, 2 midiendo, 3 resultado listo
//   sim: 1 = V/I/P simulados   sp: 1 = pulsos del medidor simulados
//   alm: bits 1 sobretension, 2 subtension, 4 sobrecorriente, 8 sin PZEM
// COMANDO: "INICIAR" | "DETENER" | "CFG:kc=1000;np=10;cl=1"
// INFO:    {"sn","fw","cal","pzem","sens"}

SPIClass touchSPI(HSPI);
XPT2046_Touchscreen ts(XPT2046_CS, XPT2046_IRQ);
TFT_eSPI tft = TFT_eSPI();
TFT_eSprite spr = TFT_eSprite(&tft);
Preferences prefs;

BLEServer *bleServer = nullptr;
BLECharacteristic *chMedicion = nullptr;
BLECharacteristic *chInfo = nullptr;
volatile bool bleHabilitado = true;
volatile bool bleConectado = false;
volatile bool bleCambioEstado = false;
char cmdBuf[64];
volatile bool cmdNuevo = false;

// ---------------------------- Colores --------------------------------
uint16_t C_BG, C_CARD, C_BORDE, C_AZUL, C_AZUL_BG, C_TEXTO, C_GRIS, C_GRIS_BG;
uint16_t C_VERDE, C_VERDE_BG, C_AMBAR, C_AMBAR_BG, C_ROJO, C_ROJO_BG, C_VIOLETA;

// ---------------------------- Layout ---------------------------------
bool dentro(const Rect &r, int x, int y) {
  return x >= r.x && x < r.x + r.w && y >= r.y && y < r.y + r.h;
}
const Rect TARJETA[4] = { {8, 60, 148, 48}, {164, 60, 148, 48}, {8, 112, 148, 48}, {164, 112, 148, 48} };
const Rect ESTADO      = {8, 165, 304, 24};
const Rect BTN_INICIAR = {8, 194, 148, 42};
const Rect BTN_AJUSTES = {164, 194, 70, 42};
const Rect BTN_HIST    = {242, 194, 70, 42};
const Rect BTN_VOLVER  = {8, 194, 304, 42};
const Rect BTN_NUEVO   = {8, 194, 148, 42};
const Rect BTN_LISTO   = {164, 194, 148, 42};
const Rect PILDORA_BT  = {200, 12, 112, 18};
const Rect TOQUE_BT    = {190, 0, 130, 42};
// Ajustes: filas con botones - y +
const int FILA_Y[3] = {66, 106, 146};
const Rect BTN_MENOS[2] = { {176, 64, 36, 32}, {176, 104, 36, 32} };
const Rect BTN_MAS[2]   = { {268, 64, 36, 32}, {268, 104, 36, 32} };
const Rect BTN_CLASE[2] = { {176, 144, 60, 32}, {244, 144, 60, 32} };
const int VAL_W = 104, VAL_H = 27;

// ---------------------------- Estado ---------------------------------
Pantalla pantalla = PRINCIPAL;
EstadoEnsayo estado = REPOSO;

// Mensajes de la barra de estado
Mensaje mensaje = M_LISTO;

// Configuracion del ensayo (se guarda en flash)
const uint16_t LISTA_KC[] = {100, 200, 250, 400, 500, 800, 1000, 1200, 1600, 2000, 3200, 4000, 6400, 10000};
const int N_KC = sizeof(LISTA_KC) / sizeof(LISTA_KC[0]);
uint16_t cfgKc = 1000;
uint16_t cfgPulsos = 10;
uint8_t  cfgClase = 1;      // 1 -> +-1 %, 2 -> +-2 %

// Mediciones
float V = 220.0, I = 5.20, P = 1144, FP = 0.98, F = 50.0;
uint8_t alarmas = 0;
bool pzemOk = !USAR_PZEM;

// Ensayo en curso
double energiaWh = 0, energiaEnPulso = 0;
unsigned long tIntegracion = 0, tInicio = 0, tUltPulso = 0;
uint16_t pulsos = 0;
float duracionFinal = 0;

// Resultado / historial
const int MAX_HIST = 10;
Resultado hist[MAX_HIST];
int nHist = 0;
uint32_t proximoId = 1;
Resultado ultimo = {};
bool hayResultado = false;

// Pulsos del medidor (interrupcion)
volatile uint32_t pulsosISR = 0;
volatile unsigned long tPulsoISR = 0;
void IRAM_ATTR isrPulso() {
  unsigned long ahora = millis();
  if (ahora - tPulsoISR < 30) return;   // antirrebote
  tPulsoISR = ahora;
  pulsosISR++;
}
// Medidor simulado
float errSim = 0.0;
double energiaSimMedidor = 0;

// =========================== Utilidades ==============================
const uint8_t *fuenteActual = nullptr;
void fuente(const uint8_t *f) {
  if (f == fuenteActual) return;
  if (fuenteActual) tft.unloadFont();
  tft.loadFont(f);
  fuenteActual = f;
}
void texto(const String &s, int x, int y, const uint8_t *f, uint16_t fg, uint16_t bg, uint8_t datum = TL_DATUM) {
  fuente(f);
  tft.setTextColor(fg, bg);
  tft.setTextDatum(datum);
  tft.drawString(s, x, y);
  tft.setTextDatum(TL_DATUM);
}
void dibujarIcono(const Icono &ic, int x, int y, uint16_t fg, uint16_t bg) {
  static uint16_t buf[18 * 18];
  int n = ic.w * ic.h;
  for (int i = 0; i < n; i++) {
    uint8_t a = pgm_read_byte(ic.alfa + i);
    buf[i] = (a == 0) ? bg : (a == 255) ? fg : tft.alphaBlend(a, fg, bg);
  }
  tft.pushImage(x, y, ic.w, ic.h, buf);
}
void tarjetaConBorde(int x, int y, int w, int h, int r, uint16_t relleno, uint16_t borde, uint16_t fondo) {
  tft.fillSmoothRoundRect(x, y, w, h, r, borde, fondo);
  tft.fillSmoothRoundRect(x + 1, y + 1, w - 2, h - 2, r - 1, relleno, borde);
}
String miles(long n) {
  String s = String(n);
  for (int i = s.length() - 3; i > 0; i -= 3) s = s.substring(0, i) + "," + s.substring(i);
  return s;
}
String conSigno(float v, int dec) { return (v >= 0 ? "+" : "") + String(v, dec); }
float limiteClase() { return cfgClase == 1 ? 1.0 : 2.0; }

void led(bool r, bool g, bool b) {   // activos en LOW
  digitalWrite(LED_ROJO, r ? LOW : HIGH);
  digitalWrite(LED_VERDE, g ? LOW : HIGH);
  digitalWrite(LED_AZUL, b ? LOW : HIGH);
}
void pitido(unsigned int frec, unsigned long ms) {
#if USAR_PARLANTE
  tone(PIN_PARLANTE, frec, ms);
#endif
}

// =========================== Persistencia ============================
void cargarConfig() {
  cfgKc = prefs.getUShort("kc", 1000);
  cfgPulsos = prefs.getUShort("np", 10);
  cfgClase = prefs.getUChar("cl", 1);
  bleHabilitado = prefs.getBool("ble", true);
  proximoId = prefs.getUInt("nid", 1);
  nHist = prefs.getUChar("nh", 0);
  if (nHist > MAX_HIST) nHist = 0;
  if (nHist) prefs.getBytes("hist", hist, sizeof(Resultado) * nHist);
}
void guardarConfig() {
  prefs.putUShort("kc", cfgKc);
  prefs.putUShort("np", cfgPulsos);
  prefs.putUChar("cl", cfgClase);
}
void guardarResultado(const Resultado &r) {
  for (int k = min(nHist, MAX_HIST - 1); k > 0; k--) hist[k] = hist[k - 1];
  hist[0] = r;
  if (nHist < MAX_HIST) nHist++;
  prefs.putBytes("hist", hist, sizeof(Resultado) * nHist);
  prefs.putUChar("nh", nHist);
  prefs.putUInt("nid", proximoId);
}

// ========================= Componentes UI ============================
void dibujarEstadoBT() {
  const Rect &r = PILDORA_BT;
  tft.fillRect(r.x, r.y, r.w, r.h, C_BG);
  uint16_t bg = C_AZUL_BG, fg = C_AZUL;
  const char *txt = "VISIBLE";
  if (!bleHabilitado)    { bg = C_GRIS_BG;  fg = C_GRIS;  txt = "BT APAGADO"; }
  else if (bleConectado) { bg = C_VERDE_BG; fg = C_VERDE; txt = "CONECTADO"; }
  fuente(Inter_SB11);
  int ancho = 14 + 4 + tft.textWidth(txt) + 16;
  int x = r.x + r.w - ancho;
  tft.fillSmoothRoundRect(x, r.y, ancho, r.h, 9, bg, C_BG);
  dibujarIcono(ICO_BT_14, x + 7, r.y + 2, fg, bg);
  texto(txt, x + 25, r.y + r.h / 2 + 1, Inter_SB11, fg, bg, ML_DATUM);
}

void dibujarEncabezado(const char *seccion) {
  tft.fillRect(0, 0, 320, 44, C_BG);
  tft.fillSmoothRoundRect(8, 6, 30, 30, 8, C_AZUL, C_BG);
  dibujarIcono(ICO_ZAP_18, 14, 12, TFT_WHITE, C_AZUL);
  texto("VERIMED BT", 46, 5, Inter_B17, C_AZUL, C_BG);
  texto("VERIFICADOR MONOFÁSICO", 46, 25, Inter_SB11, C_GRIS, C_BG);
  dibujarEstadoBT();
  tft.drawFastHLine(8, 42, 304, C_BORDE);
  texto(seccion, 8, 47, Inter_SB11, C_GRIS, C_BG);
}

void dibujarTarjeta(int k, const char *etiqueta, const char *unidad, const Icono &ic, uint16_t colorIcono) {
  const Rect &r = TARJETA[k];
  tarjetaConBorde(r.x, r.y, r.w, r.h, 8, C_CARD, C_BORDE, C_BG);
  dibujarIcono(ic, r.x + 8, r.y + 6, colorIcono, C_CARD);
  texto(etiqueta, r.x + 26, r.y + 5, Inter_M12, C_GRIS, C_CARD);
  texto(unidad, r.x + r.w - 10, r.y + 41, Inter_M13, C_GRIS, C_CARD, R_BASELINE);
}

void dibujarValor(int k, const String &valor, uint16_t color) {
  const Rect &r = TARJETA[k];
  spr.fillSprite(C_CARD);
  spr.setTextColor(color, C_CARD);
  spr.drawString(valor, 0, 1);
  spr.pushSprite(r.x + 9, r.y + 20);
}

void dibujarValores() {
  bool vMal = alarmas & 3, iMal = alarmas & 4;
  dibujarValor(0, String(V, 1), vMal ? C_ROJO : C_TEXTO);
  dibujarValor(1, String(I, 2), iMal ? C_ROJO : C_TEXTO);
  dibujarValor(2, miles(lround(P)), C_TEXTO);
  dibujarValor(3, String(FP, 2), C_TEXTO);
}

// Barra de estado: mensaje, alarma o progreso del ensayo
void dibujarEstado() {
  const Rect &r = ESTADO;
  int cy = r.y + r.h / 2;
  uint16_t bg = C_VERDE_BG, fg = C_VERDE;
  const Icono *ic = &ICO_CHECK_16;
  String msg = "Listo · Kc " + String(cfgKc) + " · " + String(cfgPulsos) + " pulsos · Clase " + String(cfgClase);

  if (alarmas) {
    bg = C_ROJO_BG; fg = C_ROJO; ic = &ICO_ALERTA_16;
    if (alarmas & 8) msg = "Sin señal del PZEM (¿hay 220 V?)";
    else if (alarmas & 1) msg = "ALERTA: sobretensión " + String(V, 0) + " V";
    else if (alarmas & 2) msg = "ALERTA: tensión baja " + String(V, 0) + " V";
    else msg = "ALERTA: sobrecorriente " + String(I, 1) + " A";
  } else if (estado == ESPERA) {
    bg = C_AZUL_BG; fg = C_AZUL; ic = &ICO_PULSO_16;
    msg = "Esperando 1er pulso del medidor...";
  } else if (estado == MIDIENDO) {
    // barra de progreso dentro de la barra de estado
    tft.fillSmoothRoundRect(r.x, r.y, r.w, r.h, 8, C_AMBAR_BG, C_BG);
    int w = (int)((r.w - 4) * (float)pulsos / cfgPulsos);
    if (w > 12) tft.fillSmoothRoundRect(r.x + 2, r.y + 2, w, r.h - 4, 6, tft.color565(253, 224, 140), C_AMBAR_BG);
    String p = "Pulso " + String(pulsos) + " / " + String(cfgPulsos) + "  ·  " + String(energiaWh, 3) + " Wh";
    // el texto se dibuja sin fondo para que se vea sobre la barra
    fuente(Inter_SB14);
    tft.setTextColor(C_AMBAR);
    tft.setTextDatum(ML_DATUM);
    tft.drawString(p, r.x + 12, cy + 1);
    tft.setTextDatum(TL_DATUM);
    return;
  } else if (mensaje == M_APP_ON)    { bg = C_AZUL_BG; fg = C_AZUL; ic = &ICO_BT_14; msg = "App VeriMed conectada"; }
  else if (mensaje == M_APP_OFF)     { bg = C_AZUL_BG; fg = C_AZUL; ic = &ICO_BT_14; msg = "App desconectada · visible"; }
  else if (mensaje == M_BT_OFF)      { bg = C_GRIS_BG; fg = C_GRIS; ic = &ICO_BT_14; msg = "Bluetooth apagado"; }
  else if (mensaje == M_BT_ON)       { bg = C_AZUL_BG; fg = C_AZUL; ic = &ICO_BT_14; msg = "Bluetooth encendido · visible"; }
  else if (mensaje == M_CANCELADO)   { bg = C_GRIS_BG; fg = C_GRIS; ic = &ICO_EQUIS_16; msg = "Ensayo cancelado"; }
  else if (mensaje == M_GUARDADO)    { msg = "Resultado guardado en historial"; }

  tft.fillSmoothRoundRect(r.x, r.y, r.w, r.h, 8, bg, C_BG);
  dibujarIcono(*ic, r.x + 8 + (16 - ic->w) / 2, cy - ic->h / 2, fg, bg);
  texto(msg, r.x + 32, cy + 1, Inter_SB14, fg, bg, ML_DATUM);
}

void dibujarBoton(const Rect &r, bool relleno, uint16_t color, const char *txt, const Icono &ic, bool chico = false) {
  uint16_t fg = relleno ? TFT_WHITE : color;
  uint16_t bg = relleno ? color : C_CARD;
  tft.fillSmoothRoundRect(r.x, r.y, r.w, r.h, 9, color, C_BG);
  if (!relleno) tft.fillSmoothRoundRect(r.x + 2, r.y + 2, r.w - 4, r.h - 4, 7, C_CARD, color);
  int cx = r.x + r.w / 2;
  dibujarIcono(ic, cx - ic.w / 2, r.y + 5, fg, bg);
  texto(txt, cx, r.y + 30, chico ? Inter_SB11 : Inter_SB14, fg, bg, MC_DATUM);
}

void dibujarBotonesPrincipal() {
  if (estado == ESPERA || estado == MIDIENDO) dibujarBoton(BTN_INICIAR, true, C_ROJO, "DETENER", ICO_STOP_18);
  else dibujarBoton(BTN_INICIAR, true, C_AZUL, "INICIAR ENSAYO", ICO_PLAY_18);
  dibujarBoton(BTN_AJUSTES, false, C_AZUL, "AJUSTES", ICO_AJUSTES_18, true);
  dibujarBoton(BTN_HIST, false, C_AZUL, "HISTORIAL", ICO_HISTORIAL_18, true);
}

// ============================ Pantallas ==============================
void pantallaPrincipal() {
  pantalla = PRINCIPAL;
  tft.fillScreen(C_BG);
  dibujarEncabezado("MEDICIONES ELÉCTRICAS");
  dibujarTarjeta(0, "TENSIÓN",         "V",  ICO_ZAP_14,       C_AZUL);
  dibujarTarjeta(1, "CORRIENTE",       "A",  ICO_ACTIVIDAD_14, C_VERDE);
  dibujarTarjeta(2, "POTENCIA ACTIVA", "W",  ICO_MEDIDOR_14,   C_AMBAR);
  dibujarTarjeta(3, "FACTOR DE POT.",  "FP", ICO_ONDA_14,      C_VIOLETA);
  dibujarValores();
  dibujarEstado();
  dibujarBotonesPrincipal();
}

void dibujarFilaAjuste(int fila) {
  int y = FILA_Y[fila];
  tft.fillRect(16, y - 2, 290, 36, C_CARD);
  const char *etiquetas[3] = {"Constante Kc", "Pulsos de ensayo", "Clase del medidor"};
  const char *ayudas[3] = {"imp/kWh (ver placa)", "más pulsos, más preciso", "límite de error aceptado"};
  texto(etiquetas[fila], 18, y + 1, Inter_SB14, C_TEXTO, C_CARD);
  texto(ayudas[fila], 18, y + 19, Inter_SB11, C_GRIS, C_CARD);
  if (fila < 2) {
    tarjetaConBorde(BTN_MENOS[fila].x, BTN_MENOS[fila].y, 36, 32, 8, C_AZUL_BG, C_AZUL_BG, C_CARD);
    tarjetaConBorde(BTN_MAS[fila].x, BTN_MAS[fila].y, 36, 32, 8, C_AZUL_BG, C_AZUL_BG, C_CARD);
    texto("-", BTN_MENOS[fila].x + 18, y + 15, Inter_B17, C_AZUL, C_AZUL_BG, MC_DATUM);
    texto("+", BTN_MAS[fila].x + 18, y + 15, Inter_B17, C_AZUL, C_AZUL_BG, MC_DATUM);
    String v = fila == 0 ? String(cfgKc) : String(cfgPulsos);
    texto(v, 240, y + 16, Inter_B17, C_TEXTO, C_CARD, MC_DATUM);
  } else {
    for (int c = 0; c < 2; c++) {
      bool sel = (cfgClase == c + 1);
      const Rect &b = BTN_CLASE[c];
      tarjetaConBorde(b.x, b.y, b.w, b.h, 8, sel ? C_AZUL : C_CARD, sel ? C_AZUL : C_BORDE, C_CARD);
      texto(c == 0 ? "±1 %" : "±2 %", b.x + b.w / 2, b.y + 16, Inter_SB14, sel ? TFT_WHITE : C_TEXTO, sel ? C_AZUL : C_CARD, MC_DATUM);
    }
  }
}

void pantallaAjustes() {
  pantalla = AJUSTES;
  tft.fillScreen(C_BG);
  dibujarEncabezado("AJUSTES DEL ENSAYO");
  tarjetaConBorde(8, 58, 304, 126, 8, C_CARD, C_BORDE, C_BG);
  for (int f = 0; f < 3; f++) dibujarFilaAjuste(f);
  tft.drawFastHLine(16, 100, 288, C_BORDE);
  tft.drawFastHLine(16, 140, 288, C_BORDE);
  dibujarBoton(BTN_VOLVER, false, C_AZUL, "GUARDAR Y VOLVER", ICO_VOLVER_18);
}

void pantallaHistorial() {
  pantalla = HISTORIAL;
  tft.fillScreen(C_BG);
  dibujarEncabezado("HISTORIAL DE ENSAYOS");
  tarjetaConBorde(8, 58, 304, 130, 8, C_CARD, C_BORDE, C_BG);
  const int col[5] = {16, 52, 132, 206, 262};
  const char *cab[5] = {"N.º", "ERROR", "RESULTADO", "PULSOS", "KC"};
  for (int c = 0; c < 5; c++) texto(cab[c], col[c], 65, Inter_SB11, C_GRIS, C_CARD);
  tft.drawFastHLine(14, 80, 292, C_BORDE);
  if (nHist == 0) {
    texto("Sin ensayos guardados", 160, 132, Inter_M13, C_GRIS, C_CARD, MC_DATUM);
  } else {
    for (int k = 0; k < min(nHist, 6); k++) {
      const Resultado &r = hist[k];
      int y = 85 + k * 17;
      uint16_t c = r.aprobado ? C_VERDE : C_ROJO;
      texto(String(r.id), col[0], y, Inter_SB14, C_TEXTO, C_CARD);
      texto(conSigno(r.err, 2) + " %", col[1], y, Inter_SB14, c, C_CARD);
      dibujarIcono(r.aprobado ? ICO_CHECK_16 : ICO_EQUIS_16, col[2], y, c, C_CARD);
      texto(r.aprobado ? "OK" : "NO", col[2] + 20, y, Inter_SB14, c, C_CARD);
      texto(String(r.pulsos), col[3], y, Inter_SB14, C_TEXTO, C_CARD);
      texto(String(r.kc), col[4], y, Inter_SB14, C_TEXTO, C_CARD);
    }
  }
  dibujarBoton(BTN_VOLVER, false, C_AZUL, "VOLVER", ICO_VOLVER_18);
}

void pantallaResultado() {
  pantalla = RESULTADO;
  const Resultado &r = ultimo;
  bool ok = r.aprobado;
  uint16_t fg = ok ? C_VERDE : C_ROJO, bgc = ok ? C_VERDE_BG : C_ROJO_BG;
  tft.fillScreen(C_BG);
  dibujarEncabezado("RESULTADO DEL ENSAYO");

  // Veredicto
  tft.fillSmoothRoundRect(8, 58, 304, 82, 10, bgc, C_BG);
  dibujarIcono(ok ? ICO_CHECK_18 : ICO_EQUIS_18, 20, 66, fg, bgc);
  texto(ok ? "APROBADO" : "RECHAZADO", 44, 67, Inter_B17, fg, bgc);
  texto("Clase " + String(r.clase) + " · límite ±" + String(r.clase == 1 ? 1 : 2) + " %", 300, 69, Inter_SB11, fg, bgc, TR_DATUM);
  texto(conSigno(r.err, 2) + "%", 160, 113, Inter_B40, fg, bgc, MC_DATUM);

  // Detalle
  tarjetaConBorde(8, 144, 304, 44, 8, C_CARD, C_BORDE, C_BG);
  texto("Eref " + String(r.eref, 4) + " Wh", 18, 150, Inter_SB14, C_TEXTO, C_CARD);
  texto("Emed " + String(r.emed, 4) + " Wh", 302, 150, Inter_SB14, C_TEXTO, C_CARD, TR_DATUM);
  texto(String(r.pulsos) + " pulsos · Kc " + String(r.kc) + " · " + String(r.seg, 1) + " s · Ensayo N.º " + String(r.id),
        160, 176, Inter_SB11, C_GRIS, C_CARD, MC_DATUM);

  dibujarBoton(BTN_NUEVO, true, C_AZUL, "NUEVO ENSAYO", ICO_PLAY_18);
  dibujarBoton(BTN_LISTO, false, C_AZUL, "LISTO", ICO_VOLVER_18);
}

// ============================ Mediciones =============================
void leerReferencia() {
#if USAR_PZEM
  float v = pzem.voltage();
  if (isnan(v)) { pzemOk = false; return; }
  pzemOk = true;
  V = v;
  float i = pzem.current(), p = pzem.power(), fp = pzem.pf(), f = pzem.frequency();
  if (!isnan(i)) I = i;
  if (!isnan(p)) P = p;
  if (!isnan(fp)) FP = fp;
  if (!isnan(f)) F = f;
#else
  V  = 220.0 + random(-30, 31) / 10.0;
  I  = 5.20 + random(-20, 21) / 100.0;
  FP = 0.96 + random(0, 4) / 100.0;
  F  = 50.0 + random(-2, 3) / 100.0;
  P  = V * I * FP;
#endif
}

uint8_t calcularAlarmas() {
  uint8_t a = 0;
  if (!pzemOk) return 8;
  if (V > V_MAX) a |= 1;
  if (V < V_MIN && V > 20) a |= 2;   // < 20 V = sin red conectada, no es alarma
  if (I > I_MAX) a |= 4;
  return a;
}

// Integra la potencia de referencia hasta el instante t (ms)
void integrarHasta(unsigned long t) {
  long dt = (long)(t - tIntegracion);
  energiaWh += P * dt / 3600000.0;
  tIntegracion = t;
}

// ============================== Ensayo ===============================
void iniciarEnsayo() {
  if (estado == ESPERA || estado == MIDIENDO) return;
  estado = ESPERA;
  pulsos = 0;
  energiaWh = energiaEnPulso = 0;
  duracionFinal = 0;
  energiaSimMedidor = 0;
  errSim = random(-150, 151) / 100.0;    // medidor virtual: -1.5 % .. +1.5 %
  noInterrupts(); pulsosISR = 0; interrupts();
  tInicio = tUltPulso = millis();
  led(false, false, true);
  pitido(1800, 60);
  if (pantalla != PRINCIPAL) pantallaPrincipal();
  else { dibujarEstado(); dibujarBotonesPrincipal(); }
}

void finalizarEnsayo() {
  Resultado r;
  r.id = proximoId++;
  r.pulsos = pulsos;
  r.kc = cfgKc;
  r.clase = cfgClase;
  r.seg = (tUltPulso - tInicio) / 1000.0;
  r.eref = energiaEnPulso;
  r.emed = pulsos * 1000.0 / cfgKc;
  r.err = r.eref > 0 ? (r.emed - r.eref) / r.eref * 100.0 : 0;
  r.aprobado = fabs(r.err) <= limiteClase();
  ultimo = r;
  hayResultado = true;
  duracionFinal = r.seg;
  energiaWh = r.eref;
  estado = LISTO;
  guardarResultado(r);
  if (r.aprobado) { led(false, true, false); pitido(2400, 120); delay(160); pitido(2400, 120); }
  else            { led(true, false, false); pitido(600, 500); }
  pantallaResultado();
}

void detenerEnsayo() {
  if (estado != ESPERA && estado != MIDIENDO) return;
  if (estado == MIDIENDO && pulsos >= 1) { finalizarEnsayo(); return; }  // resultado parcial
  estado = REPOSO;
  mensaje = M_CANCELADO;
  led(false, false, false);
  if (pantalla == PRINCIPAL) { dibujarEstado(); dibujarBotonesPrincipal(); }
}

// Se llama por cada pulso del LED del medidor (real o simulado)
void procesarPulso(unsigned long tPulso) {
  if (estado == ESPERA) {               // 1er pulso: arranca la medicion
    estado = MIDIENDO;
    pulsos = 0;
    energiaWh = energiaEnPulso = 0;
    tIntegracion = tInicio = tUltPulso = tPulso;
  } else if (estado == MIDIENDO) {
    integrarHasta(tPulso);
    pulsos++;
    energiaEnPulso = energiaWh;
    tUltPulso = tPulso;
    if (pulsos >= cfgPulsos) { finalizarEnsayo(); return; }
  } else return;
  pitido(3000, 25);
  if (pantalla == PRINCIPAL) dibujarEstado();
}

void revisarPulsos(unsigned long ahora) {
#if USAR_SENSOR_PULSOS
  static uint32_t vistos = 0;
  uint32_t n; unsigned long t;
  noInterrupts(); n = pulsosISR; t = tPulsoISR; interrupts();
  if (n != vistos) {                   // si llegaron varios, se procesan con el ultimo instante
    while (vistos < n) { vistos++; procesarPulso(t); }
  }
#else
  // Medidor virtual: emite un pulso cada 1000/Kc Wh, con su error errSim
  static unsigned long tSim = 0;
  if (tSim == 0) tSim = ahora;
  if (estado == ESPERA || estado == MIDIENDO) {
    energiaSimMedidor += P * (1.0 + errSim / 100.0) * (ahora - tSim) / 3600000.0;
    double wPorPulso = 1000.0 / cfgKc;
    if (estado == ESPERA && ahora - tInicio > 800) energiaSimMedidor = wPorPulso;  // 1er pulso rapido
    if (energiaSimMedidor >= wPorPulso) {
      energiaSimMedidor -= wPorPulso;
      procesarPulso(ahora);
    }
  }
  tSim = ahora;
#endif
}

// ============================ Bluetooth ==============================
float segundosEnsayo() {
  if (estado == MIDIENDO) return (millis() - tInicio) / 1000.0;
  if (estado == LISTO) return duracionFinal;
  return 0;
}

void enviarMedicion() {
  if (!chMedicion) return;
  char json[200];
  snprintf(json, sizeof(json),
    "{\"v\":%.1f,\"i\":%.2f,\"p\":%.1f,\"fp\":%.2f,\"f\":%.1f,\"wh\":%.4f,\"t\":%.1f,\"sim\":%d,\"sp\":%d,"
    "\"st\":%d,\"pul\":%u,\"np\":%u,\"kc\":%u,\"err\":%.3f,\"apr\":%d,\"alm\":%u}",
    V, I, P, FP, F, estado == LISTO ? ultimo.eref : energiaWh, segundosEnsayo(),
    USAR_PZEM ? 0 : 1, USAR_SENSOR_PULSOS ? 0 : 1, (int)estado,
    (unsigned)(estado == LISTO ? ultimo.pulsos : pulsos), (unsigned)cfgPulsos, (unsigned)cfgKc,
    hayResultado ? ultimo.err : 0.0, hayResultado && ultimo.aprobado ? 1 : 0, (unsigned)alarmas);
  chMedicion->setValue((uint8_t *)json, strlen(json));
  if (bleConectado) chMedicion->notify();
}

void actualizarInfo() {
  if (!chInfo) return;
  char json[160];
  snprintf(json, sizeof(json), "{\"sn\":\"%s\",\"fw\":\"%s\",\"cal\":\"%s\",\"pzem\":%d,\"sens\":%d}",
           NUMERO_SERIE, VERSION_FW, FECHA_CAL, USAR_PZEM, USAR_SENSOR_PULSOS);
  chInfo->setValue((uint8_t *)json, strlen(json));
}

class ServidorCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *s) override { bleConectado = true; bleCambioEstado = true; }
  void onDisconnect(BLEServer *s) override {
    bleConectado = false; bleCambioEstado = true;
    if (bleHabilitado) BLEDevice::startAdvertising();
  }
};

class ComandoCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *c) override {
    String v = String(c->getValue().c_str());
    strncpy(cmdBuf, v.c_str(), sizeof(cmdBuf) - 1);
    cmdBuf[sizeof(cmdBuf) - 1] = 0;
    cmdNuevo = true;
  }
};

// "CFG:kc=1000;np=10;cl=1"
void aplicarConfig(const String &s) {
  int i = s.indexOf("kc=");  if (i >= 0) { long v = s.substring(i + 3).toInt(); if (v >= 1 && v <= 65000) cfgKc = v; }
  i = s.indexOf("np=");      if (i >= 0) { long v = s.substring(i + 3).toInt(); if (v >= 1 && v <= 500) cfgPulsos = v; }
  i = s.indexOf("cl=");      if (i >= 0) { long v = s.substring(i + 3).toInt(); if (v == 1 || v == 2) cfgClase = v; }
  guardarConfig();
  if (pantalla == AJUSTES) pantallaAjustes();
  else if (pantalla == PRINCIPAL) dibujarEstado();
}

void procesarComando() {
  if (!cmdNuevo) return;
  cmdNuevo = false;
  String cmd = String(cmdBuf);
  cmd.trim();
  String may = cmd; may.toUpperCase();
  if (may == "INICIAR" || may == "START") iniciarEnsayo();
  else if (may == "DETENER" || may == "STOP") detenerEnsayo();
  else if (may.startsWith("CFG:")) aplicarConfig(cmd.substring(4));
  enviarMedicion();
}

void iniciarBLE() {
  BLEDevice::init(BLE_NOMBRE);
  BLEDevice::setMTU(185);
  BLEDevice::setPower(ESP_PWR_LVL_P9);
  BLEDevice::setPower(ESP_PWR_LVL_P9, ESP_BLE_PWR_TYPE_ADV);
  bleServer = BLEDevice::createServer();
  bleServer->setCallbacks(new ServidorCallbacks());
  BLEService *servicio = bleServer->createService(UUID_SERVICIO);
  chMedicion = servicio->createCharacteristic(UUID_MEDICION,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  chMedicion->addDescriptor(new BLE2902());
  BLECharacteristic *chComando = servicio->createCharacteristic(UUID_COMANDO,
      BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  chComando->setCallbacks(new ComandoCallbacks());
  chInfo = servicio->createCharacteristic(UUID_INFO, BLECharacteristic::PROPERTY_READ);
  servicio->start();

  // Anuncio: flags + nombre (15 B). Respuesta de escaneo: UUID del servicio (18 B)
  BLEAdvertisementData anuncio;
  anuncio.setFlags(0x06);
  anuncio.setName(BLE_NOMBRE);
  BLEAdvertisementData respuesta;
  respuesta.setCompleteServices(BLEUUID(UUID_SERVICIO));
  BLEAdvertising *adv = BLEDevice::getAdvertising();
  adv->setAdvertisementData(anuncio);
  adv->setScanResponseData(respuesta);
  adv->setScanResponse(true);
  adv->setMinPreferred(0x06);
  adv->setMinPreferred(0x12);
  if (bleHabilitado) BLEDevice::startAdvertising();

  actualizarInfo();
  enviarMedicion();
  Serial.print("Direccion Bluetooth: ");
  Serial.println(BLEDevice::getAddress().toString().c_str());
}

void cambiarBLE(bool encender) {
  bleHabilitado = encender;
  prefs.putBool("ble", encender);
  if (encender) BLEDevice::startAdvertising();
  else {
    BLEDevice::stopAdvertising();
    if (bleConectado) bleServer->disconnect(bleServer->getConnId());
  }
  mensaje = encender ? M_BT_ON : M_BT_OFF;
  dibujarEstadoBT();
  if (pantalla == PRINCIPAL && estado != MIDIENDO && estado != ESPERA) dibujarEstado();
}

// ============================== Tactil ===============================
bool leerToque(int &x, int &y) {
  if (!ts.touched()) return false;
  TS_Point p = ts.getPoint();
  if (p.z < 200) return false;
  int rx = TOUCH_SWAP_XY ? p.y : p.x;
  int ry = TOUCH_SWAP_XY ? p.x : p.y;
  x = constrain(map(rx, TOUCH_X_MIN, TOUCH_X_MAX, 0, tft.width() - 1), 0, tft.width() - 1);
  y = constrain(map(ry, TOUCH_Y_MIN, TOUCH_Y_MAX, 0, tft.height() - 1), 0, tft.height() - 1);
  return true;
}
void esperarSoltar() { while (ts.touched()) delay(10); delay(60); }

int indiceKc() {
  for (int k = 0; k < N_KC; k++) if (LISTA_KC[k] >= cfgKc) return k;
  return N_KC - 1;
}
void cambiarAjuste(int fila, int dir) {
  if (fila == 0) {
    int k = constrain(indiceKc() + dir, 0, N_KC - 1);
    cfgKc = LISTA_KC[k];
  } else {
    int paso = (cfgPulsos + (dir > 0 ? 0 : -1)) >= 10 ? 5 : 1;
    cfgPulsos = constrain((int)cfgPulsos + dir * paso, 1, 100);
  }
  dibujarFilaAjuste(fila);
  pitido(2200, 15);
}

void manejarToque(int x, int y) {
  if (dentro(TOQUE_BT, x, y)) { cambiarBLE(!bleHabilitado); return; }
  switch (pantalla) {
    case PRINCIPAL:
      if (dentro(BTN_INICIAR, x, y)) {
        if (estado == ESPERA || estado == MIDIENDO) detenerEnsayo(); else iniciarEnsayo();
      } else if (estado != ESPERA && estado != MIDIENDO) {
        if (dentro(BTN_AJUSTES, x, y)) pantallaAjustes();
        else if (dentro(BTN_HIST, x, y)) pantallaHistorial();
      }
      break;
    case AJUSTES:
      for (int f = 0; f < 2; f++) {
        if (dentro(BTN_MENOS[f], x, y)) cambiarAjuste(f, -1);
        if (dentro(BTN_MAS[f], x, y)) cambiarAjuste(f, +1);
      }
      for (int c = 0; c < 2; c++)
        if (dentro(BTN_CLASE[c], x, y)) { cfgClase = c + 1; dibujarFilaAjuste(2); }
      if (dentro(BTN_VOLVER, x, y)) { guardarConfig(); mensaje = M_LISTO; pantallaPrincipal(); }
      break;
    case HISTORIAL:
      if (dentro(BTN_VOLVER, x, y)) pantallaPrincipal();
      break;
    case RESULTADO:
      if (dentro(BTN_NUEVO, x, y)) { estado = REPOSO; led(false, false, false); iniciarEnsayo(); }
      else if (dentro(BTN_LISTO, x, y)) { estado = REPOSO; mensaje = M_GUARDADO; led(false, false, false); pantallaPrincipal(); }
      break;
  }
}

// ============================== Setup ================================
void setup() {
  Serial.begin(115200);
  randomSeed(esp_random());
  pinMode(LED_ROJO, OUTPUT); pinMode(LED_VERDE, OUTPUT); pinMode(LED_AZUL, OUTPUT);
  led(false, false, false);
#if USAR_SENSOR_PULSOS
  pinMode(PIN_PULSOS, INPUT);   // IO35 no tiene pull-up: el modulo debe traerlo
  attachInterrupt(digitalPinToInterrupt(PIN_PULSOS), isrPulso, FLANCO_PULSO);
#endif

  touchSPI.begin(XPT2046_CLK, XPT2046_MISO, XPT2046_MOSI, XPT2046_CS);
  ts.begin(touchSPI);
  ts.setRotation(1);
  tft.init();
  tft.setRotation(1);
  tft.setSwapBytes(true);

  C_BG       = tft.color565(244, 247, 252);
  C_CARD     = TFT_WHITE;
  C_BORDE    = tft.color565(214, 224, 236);
  C_AZUL     = tft.color565(18, 98, 204);
  C_AZUL_BG  = tft.color565(224, 236, 252);
  C_TEXTO    = tft.color565(23, 37, 64);
  C_GRIS     = tft.color565(90, 104, 125);
  C_GRIS_BG  = tft.color565(230, 234, 240);
  C_VERDE    = tft.color565(22, 128, 61);
  C_VERDE_BG = tft.color565(222, 243, 229);
  C_AMBAR    = tft.color565(160, 82, 6);
  C_AMBAR_BG = tft.color565(254, 243, 199);
  C_ROJO     = tft.color565(205, 45, 45);
  C_ROJO_BG  = tft.color565(253, 228, 228);
  C_VIOLETA  = tft.color565(124, 58, 237);

  spr.createSprite(VAL_W, VAL_H);
  spr.loadFont(Inter_B26);
  spr.setTextDatum(TL_DATUM);

  prefs.begin("verimed", false);
  cargarConfig();
  if (!bleHabilitado) mensaje = M_BT_OFF;

  iniciarBLE();
  leerReferencia();
  alarmas = calcularAlarmas();
  pantallaPrincipal();
  Serial.printf("VeriMed BT %s listo. PZEM=%d sensor=%d\n", VERSION_FW, USAR_PZEM, USAR_SENSOR_PULSOS);
}

// =============================== Loop ================================
void loop() {
  static unsigned long tLectura = 0, tEnvio = 0, tBarra = 0, tParpadeo = 0;
  unsigned long ahora = millis();

  if (bleCambioEstado) {
    bleCambioEstado = false;
    if (bleHabilitado) mensaje = bleConectado ? M_APP_ON : M_APP_OFF;
    dibujarEstadoBT();
    if (pantalla == PRINCIPAL && estado != MIDIENDO && estado != ESPERA) dibujarEstado();
    if (bleConectado) enviarMedicion();
  }
  procesarComando();

  // Referencia: lectura cada 500 ms (integrando la potencia anterior)
  if (ahora - tLectura >= 500) {
    tLectura = ahora;
    if (estado == MIDIENDO) integrarHasta(ahora);
    leerReferencia();
    uint8_t a = calcularAlarmas();
    if (a != alarmas) {
      if (a && !alarmas) { pitido(900, 300); led(true, false, false); }
      if (!a && estado != LISTO) led(false, false, estado == ESPERA || estado == MIDIENDO);
      alarmas = a;
      if (pantalla == PRINCIPAL) dibujarEstado();
    }
    if (pantalla == PRINCIPAL) dibujarValores();
  }

  revisarPulsos(ahora);

  // Barra de progreso (energia acumulada) cada 1 s
  if (estado == MIDIENDO && pantalla == PRINCIPAL && !alarmas && ahora - tBarra >= 1000) {
    tBarra = ahora;
    dibujarEstado();
  }
  // LED azul parpadeando mientras espera el 1er pulso
  if (estado == ESPERA && ahora - tParpadeo >= 400) {
    tParpadeo = ahora;
    static bool on = false; on = !on;
    led(false, false, on);
  }

  if (bleHabilitado && bleConectado && ahora - tEnvio >= ((estado == ESPERA || estado == MIDIENDO) ? 500UL : 2000UL)) {
    tEnvio = ahora;
    enviarMedicion();
  }

  int x, y;
  if (leerToque(x, y)) { manejarToque(x, y); esperarSoltar(); }
}
