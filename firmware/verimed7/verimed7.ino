// =====================================================================
//  VERIMED BT 7" - Verificador de medidores monofasicos
//  VIEWE UEDX80480070E-WB-A V1.1 (ESP32-S3-N16R8, 800x480 RGB, GT911)
// =====================================================================
//  Arduino IDE -> Herramientas:
//    Placa ESP32S3 Dev Module · PSRAM OPI PSRAM · Flash 16MB (128Mb)
//    Partition Scheme 16M Flash (3MB APP/9.9MB FATFS) · USB CDC On Boot: Disabled (puerto UART)
//  Librerias: LovyanGFX (lovyan03); PZEM-004T-v30 solo si USAR_PZEM = 1
//  Carpeta verimed7/: verimed7.ino, LGFX_VeriMed7.h, fuentes7.h, iconos7.h, tipos7.h
//
//  FLUIDEZ Y ESTABILIDAD: la pantalla RGB lee su imagen continuamente desde la
//  PSRAM; si el programa usa mucho la PSRAM, la imagen se corre o parpadea.
//  Por eso se dibuja en una "banda" de 800x40 en la RAM interna y cada zona que
//  cambia se escribe UNA sola vez en la pantalla (sin parpadeo ni dibujado a medias).
//  Botones con respuesta al presionar y accion al soltar.
//
//  Protocolo Bluetooth identico al firmware v2 del CYD: la app no cambia.
// =====================================================================

// ------------------------- CONFIGURACION -----------------------------
#define USAR_PZEM            0   // 1 = referencia real con PZEM-004T v3
#define USAR_SENSOR_PULSOS   0   // 1 = sensor optico real en el LED del medidor

#define NUMERO_SERIE   "VMBT7-0001"
#define VERSION_FW     "2.1.0"
#define FECHA_CAL      "Sin calibrar"

// Pines libres de esta placa: los de la ranura microSD (sin tarjeta insertada),
// accesibles con un adaptador "microSD a pines". Ver docs/HARDWARE.md.
#define PIN_PULSOS    12        // DO del sensor optico
#define FLANCO_PULSO  FALLING
#define PZEM_RX       13        // ESP32 RX <- TX del PZEM
#define PZEM_TX       11        // ESP32 TX -> RX del PZEM

#define V_MIN        198.0
#define V_MAX        242.0
#define I_MAX         60.0
// ---------------------------------------------------------------------

#include "LGFX_VeriMed7.h"
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <Preferences.h>
#if USAR_PZEM
#include <PZEM004Tv30.h>
PZEM004Tv30 pzem(Serial1, PZEM_RX, PZEM_TX);
#endif
#include "fuentes7.h"
#include "iconos7.h"
#include "tipos7.h"
#include <functional>
#include <esp_system.h>

// LovyanGFX copia cada caracter en la pila (alloca): el "%" de la fuente de 112 px
// ocupa ~9,7 KB y la pila por defecto del loop es de 8 KB -> la placa se reiniciaba.
SET_LOOP_TASK_STACK_SIZE(32 * 1024);

// ---- Bluetooth (protocolo v2, igual que el CYD) ----
#define BLE_NOMBRE     "VeriMed BT"
#define UUID_SERVICIO  "7e5a0001-3c1d-4f2b-9a6e-1b2c3d4e5f60"
#define UUID_MEDICION  "7e5a0002-3c1d-4f2b-9a6e-1b2c3d4e5f60"
#define UUID_COMANDO   "7e5a0003-3c1d-4f2b-9a6e-1b2c3d4e5f60"
#define UUID_INFO      "7e5a0004-3c1d-4f2b-9a6e-1b2c3d4e5f60"

LGFX_VeriMed7 tft;
LGFX_Sprite banda(&tft);      // franja de 800 x FILAS en RAM interna: aqui se dibuja
int FILAS = 40;               // alto de la franja (se reduce si falta memoria)
int16_t ox = 0, oy = 0;       // esquina de la pantalla que corresponde a la franja

// "Pincel": mismas funciones de dibujo que LovyanGFX, pero con coordenadas de
// pantalla. Traduce a la franja actual (lo que cae fuera se recorta solo).
struct Pincel {
  void fillScreen(uint16_t c) { banda.fillScreen(c); }
  void fillRect(int x, int y, int w, int h, uint16_t c) { banda.fillRect(x - ox, y - oy, w, h, c); }
  void drawFastHLine(int x, int y, int w, uint16_t c) { banda.drawFastHLine(x - ox, y - oy, w, c); }
  void drawFastVLine(int x, int y, int h, uint16_t c) { banda.drawFastVLine(x - ox, y - oy, h, c); }
  void drawPixel(int x, int y, uint16_t c) { banda.drawPixel(x - ox, y - oy, c); }
  uint16_t readPixel(int x, int y) { return banda.readPixel(x - ox, y - oy); }
  void fillSmoothRoundRect(int x, int y, int w, int h, int r, uint16_t c) { banda.fillSmoothRoundRect(x - ox, y - oy, w, h, r, c); }
  void drawWideLine(int x0, int y0, int x1, int y1, float r, uint16_t c) { banda.drawWideLine(x0 - ox, y0 - oy, x1 - ox, y1 - oy, r, c); }
  void drawString(const String &s, int x, int y) { banda.drawString(s, x - ox, y - oy); }
  void setTextColor(uint16_t c) { banda.setTextColor(c); }
  void setTextDatum(textdatum_t d) { banda.setTextDatum(d); }
  int32_t textWidth(const String &s) { return banda.textWidth(s); }
  void loadFont(const uint8_t *f) { banda.loadFont(f); }
  void unloadFont() { banda.unloadFont(); }
  uint16_t color565(uint8_t r, uint8_t g, uint8_t b) { return banda.color565(r, g, b); }
} g;
Preferences prefs;

BLEServer *bleServer = nullptr;
BLECharacteristic *chMedicion = nullptr;
BLECharacteristic *chInfo = nullptr;
volatile bool bleHabilitado = true;
volatile bool bleConectado = false;
volatile bool bleCambioEstado = false;
char cmdBuf[64];
volatile bool cmdNuevo = false;
String direccionBT = "";

// ----------------------------- Colores --------------------------------
uint16_t C_BG, C_CARD, C_BORDE, C_LINEA, C_AZUL, C_AZUL_BG, C_AZUL_OSC, C_TEXTO, C_GRIS, C_GRIS_BG;
uint16_t C_VERDE, C_VERDE_BG, C_AMBAR, C_AMBAR_BG, C_AMBAR_BAR, C_ROJO, C_ROJO_BG, C_ROJO_OSC, C_VIOLETA, C_AREA;

// ----------------------------- Layout ---------------------------------
const Rect R_HEADER    = {0, 0, 800, 64};
const Rect R_PILDORAS  = {400, 12, 384, 40};
const Rect R_ESTADO    = {16, 76, 768, 40};
const Rect R_TARJETA[4] = {{16, 128, 246, 100}, {274, 128, 246, 100}, {16, 240, 246, 100}, {274, 240, 246, 100}};
const Rect R_GRAFICO   = {16, 352, 504, 112};
const Rect R_ENSAYO    = {536, 128, 248, 212};
const Rect R_INICIAR   = {536, 352, 248, 56};
const Rect R_AJUSTES   = {536, 418, 118, 46};
const Rect R_HIST      = {666, 418, 118, 46};
const Rect R_TOQUE_BT  = {560, 0, 240, 64};
// Ajustes
const int  FILA_Y[3]   = {100, 192, 284};
const Rect R_KC_MENOS  = {500, 118, 64, 56};
const Rect R_KC_MAS    = {704, 118, 64, 56};
const Rect R_NP_MENOS  = {500, 210, 64, 56};
const Rect R_NP_MAS    = {704, 210, 64, 56};
const Rect R_CLASE1    = {540, 302, 108, 56};
const Rect R_CLASE2    = {656, 302, 108, 56};
const Rect R_ABAJO     = {16, 408, 768, 56};    // GUARDAR / VOLVER
const Rect R_NUEVO     = {16, 408, 376, 56};
const Rect R_LISTO     = {408, 408, 376, 56};

bool dentro(const Rect &r, int x, int y) { return x >= r.x && x < r.x + r.w && y >= r.y && y < r.y + r.h; }

// ----------------------------- Estado ---------------------------------
Pantalla pantalla = PRINCIPAL;
EstadoEnsayo estado = REPOSO;
Mensaje mensaje = M_LISTO;

const uint16_t LISTA_KC[] = {100, 200, 250, 400, 500, 800, 1000, 1200, 1600, 2000, 3200, 4000, 6400, 10000};
const int N_KC = sizeof(LISTA_KC) / sizeof(LISTA_KC[0]);
uint16_t cfgKc = 1000, cfgPulsos = 10;
uint8_t cfgClase = 1;

float V = 220.0, I = 5.20, P = 1144, FP = 0.98, F = 50.0;
uint8_t alarmas = 0;
bool pzemOk = !USAR_PZEM;

double energiaWh = 0, energiaEnPulso = 0;
unsigned long tIntegracion = 0, tInicio = 0, tUltPulso = 0;
uint16_t pulsos = 0;
float duracionFinal = 0;

const int MAX_HIST = MAX_HIST_GUARDADO;
Resultado hist[MAX_HIST];
int nHist = 0;
uint32_t proximoId = 1;
Resultado ultimo = {};
bool hayResultado = false;

// Grafico: 120 muestras (60 s a 2 muestras por segundo)
const int N_MUESTRAS = 120;
float muestras[N_MUESTRAS];
int nMuestras = 0;

volatile uint32_t pulsosISR = 0;
volatile unsigned long tPulsoISR = 0;
void IRAM_ATTR isrPulso() {
  unsigned long ahora = millis();
  if (ahora - tPulsoISR < 30) return;
  tPulsoISR = ahora;
  pulsosISR++;
}
float errSim = 0.0;
double energiaSimMedidor = 0;

// Tactil
BotonId botonPresionado = B_NINGUNO;
unsigned long tPresion = 0, tRepeticion = 0;

// ========================== Dibujo basico =============================
uint16_t rgb(uint8_t r, uint8_t gg, uint8_t b) { return banda.color565(r, gg, b); }

// Dibuja la zona r por franjas en la RAM interna y escribe cada franja una sola
// vez en la pantalla. "dibujar" pinta usando coordenadas de pantalla (g.*).
void pintar(const Rect &r, const std::function<void()> &dibujar) {
  for (int y = r.y; y < r.y + r.h; y += FILAS) {
    int h = min(FILAS, r.y + r.h - y);
    ox = r.x; oy = y;
    banda.fillScreen(C_BG);
    dibujar();
    tft.setClipRect(r.x, y, r.w, h);
    banda.pushSprite(r.x, y);
    tft.clearClipRect();
  }
  ox = oy = 0;
}
const Rect R_TODO = {0, 0, 800, 480};

const uint8_t *fuenteActual = nullptr;
void fuente(const uint8_t *f) {
  if (f == fuenteActual) return;
  if (fuenteActual) g.unloadFont();
  g.loadFont(f);
  fuenteActual = f;
}
// Texto suavizado y transparente (se mezcla con lo que hay debajo)
void texto(const String &s, int x, int y, const uint8_t *f, uint16_t color, textdatum_t datum = top_left) {
  fuente(f);
  g.setTextColor(color);
  g.setTextDatum(datum);
  g.drawString(s, x, y);
}
int anchoTexto(const String &s, const uint8_t *f) { fuente(f); return g.textWidth(s); }

uint16_t mezclar(uint8_t a, uint16_t fg, uint16_t bg) {
  uint32_t rf = (fg >> 11) & 31, gf = (fg >> 5) & 63, bf = fg & 31;
  uint32_t rb = (bg >> 11) & 31, gb = (bg >> 5) & 63, bb = bg & 31;
  uint32_t r = (rf * a + rb * (255 - a)) / 255, g = (gf * a + gb * (255 - a)) / 255, b = (bf * a + bb * (255 - a)) / 255;
  return (r << 11) | (g << 5) | b;
}
// Icono con alfa de 8 bits: se mezcla con el fondo real del lienzo
void icono(const Icono &ic, int x, int y, uint16_t color) {
  for (int j = 0; j < ic.h; j++)
    for (int i = 0; i < ic.w; i++) {
      uint8_t a = pgm_read_byte(ic.alfa + j * ic.w + i);
      if (!a) continue;
      uint16_t c = (a == 255) ? color : mezclar(a, color, g.readPixel(x + i, y + j));
      g.drawPixel(x + i, y + j, c);
    }
}
void tarjeta(const Rect &r, int radio, uint16_t relleno, uint16_t borde) {
  g.fillSmoothRoundRect(r.x, r.y, r.w, r.h, radio, borde);
  g.fillSmoothRoundRect(r.x + 1, r.y + 1, r.w - 2, r.h - 2, radio - 1, relleno);
}
void limpiar(const Rect &r) { g.fillRect(r.x, r.y, r.w, r.h, C_BG); }

String miles(long n) {
  String s = String(n < 0 ? -n : n);
  for (int i = s.length() - 3; i > 0; i -= 3) s = s.substring(0, i) + "," + s.substring(i);
  if (n < 0) s = "-" + s;
  return s;
}
String conSigno(float v, int dec) { return String(v >= 0 ? "+" : "") + String(v, dec); }
float limiteClase() { return cfgClase == 1 ? 1.0 : 2.0; }

// Boton: relleno (primario) o con borde; "presionado" lo oscurece
void boton(const Rect &r, bool relleno, uint16_t color, uint16_t colorOsc, const char *txt,
           const Icono &ic, const uint8_t *f, int gap, bool presionado) {
  limpiar(r);
  uint16_t fg;
  if (relleno) {
    g.fillSmoothRoundRect(r.x, r.y, r.w, r.h, 12, presionado ? colorOsc : color);
    fg = TFT_WHITE;
  } else {
    g.fillSmoothRoundRect(r.x, r.y, r.w, r.h, 12, color);
    g.fillSmoothRoundRect(r.x + 2, r.y + 2, r.w - 4, r.h - 4, 10, presionado ? C_AZUL_BG : C_CARD);
    fg = color;
  }
  int tw = anchoTexto(txt, f);
  int total = ic.w + gap + tw;
  int x0 = r.x + (r.w - total) / 2;
  icono(ic, x0, r.y + (r.h - ic.h) / 2, fg);
  texto(txt, x0 + ic.w + gap, r.y + r.h / 2 + 1, f, fg, middle_left);
}

// ========================== Persistencia ==============================
ConfigGuardada cfgEnFlash = {0, 0, 0, 0};   // copia de lo que esta en la flash

void cargarConfig() {
  ConfigGuardada c;
  if (prefs.getBytesLength("cfg") == sizeof(c) && prefs.getBytes("cfg", &c, sizeof(c)) == sizeof(c)) {
    cfgKc = c.kc; cfgPulsos = c.np; cfgClase = c.clase; bleHabilitado = c.ble;
    cfgEnFlash = c;
  } else if (prefs.isKey("kc")) {            // formato anterior (version 2.1.0)
    cfgKc = prefs.getUShort("kc", 1000);
    cfgPulsos = prefs.getUShort("np", 10);
    cfgClase = prefs.getUChar("cl", 1);
    bleHabilitado = prefs.getBool("ble", true);
  }
  HistorialGuardado h;
  if (prefs.getBytesLength("h2") == sizeof(h) && prefs.getBytes("h2", &h, sizeof(h)) == sizeof(h) && h.n <= MAX_HIST) {
    proximoId = h.proximoId; nHist = h.n;
    memcpy(hist, h.r, sizeof(hist));
  } else if (prefs.isKey("nh")) {            // historial en el formato anterior
    proximoId = prefs.getUInt("nid", 1);
    nHist = prefs.getUChar("nh", 0);
    if (nHist > MAX_HIST) nHist = 0;
    if (nHist) prefs.getBytes("hist", hist, sizeof(Resultado) * nHist);
  }
}
bool configCambio() {
  ConfigGuardada c = {cfgKc, cfgPulsos, cfgClase, (uint8_t)(bleHabilitado ? 1 : 0)};
  return memcmp(&c, &cfgEnFlash, sizeof(c)) != 0;
}
// Guarda la configuracion SOLO si cambio (la app la envia al iniciar cada ensayo)
void guardarConfig() {
  ConfigGuardada c = {cfgKc, cfgPulsos, cfgClase, (uint8_t)(bleHabilitado ? 1 : 0)};
  if (memcmp(&c, &cfgEnFlash, sizeof(c)) == 0) return;
  prefs.putBytes("cfg", &c, sizeof(c));
  cfgEnFlash = c;
}
void guardarResultado(const Resultado &r) {
  for (int k = min(nHist, MAX_HIST - 1); k > 0; k--) hist[k] = hist[k - 1];
  hist[0] = r;
  if (nHist < MAX_HIST) nHist++;
  HistorialGuardado h;
  h.proximoId = proximoId; h.n = nHist;
  memcpy(h.r, hist, sizeof(h.r));
  prefs.putBytes("h2", &h, sizeof(h));      // una sola escritura
}

// Mientras se escribe la flash la imagen pierde el sincronismo un instante:
// se baja la luz, se hace la tarea y se vuelve a subir (transicion suave).
void conPantallaOculta(const std::function<void()> &tarea) {
  for (int b = 255; b > 0; b -= 64) { tft.setBrightness(b); delay(10); }
  tft.setBrightness(0);
  tarea();
  delay(60);                                 // ~2 cuadros: la imagen se resincroniza
  for (int b = 0; b < 255; b += 32) { tft.setBrightness(b); delay(12); }
  tft.setBrightness(255);
}

// ========================= Componentes UI =============================
void dibujarPildoras() {
  limpiar(R_PILDORAS);
  // Bluetooth
  uint16_t bg = C_AZUL_BG, fg = C_AZUL;
  const char *t = "VISIBLE";
  if (!bleHabilitado)    { bg = C_GRIS_BG;  fg = C_GRIS;  t = "BT APAGADO"; }
  else if (bleConectado) { bg = C_VERDE_BG; fg = C_VERDE; t = "CONECTADO"; }
  int an = 12 + 20 + 8 + anchoTexto(t, F7_SB14) + 14;
  int x = 784 - an;
  if (botonPresionado == B_BT) bg = C_BORDE;
  g.fillSmoothRoundRect(x, 17, an, 30, 15, bg);
  icono(I7_BT_20, x + 12, 22, fg);
  texto(t, x + 40, 32, F7_SB14, fg, middle_left);
  // Modo de medicion
  bool sim = !USAR_PZEM || !USAR_SENSOR_PULSOS;
  const char *t2 = sim ? "SIMULACIÓN" : "MEDICIÓN REAL";
  int an2 = anchoTexto(t2, F7_SB14) + 28;
  int x2 = x - 10 - an2;
  g.fillSmoothRoundRect(x2, 17, an2, 30, 15, sim ? C_AMBAR_BG : C_VERDE_BG);
  texto(t2, x2 + an2 / 2, 32, F7_SB14, sim ? C_AMBAR : C_VERDE, middle_center);
}

void dibujarEncabezado() {
  limpiar(R_HEADER);
  g.fillSmoothRoundRect(16, 12, 40, 40, 10, C_AZUL);
  icono(I7_ZAP_30, 21, 17, TFT_WHITE);
  texto("VERIMED BT", 68, 12, F7_B24, C_AZUL);
  texto("VERIFICADOR MONOFÁSICO", 68, 41, F7_SB14, C_GRIS);
  dibujarPildoras();
  g.drawFastHLine(16, 64, 768, C_BORDE);
}

void dibujarEstado() {
  const Rect &r = R_ESTADO;
  limpiar(r);
  int cy = r.y + r.h / 2 + 1;
  if (!alarmas && estado == MIDIENDO) {
    g.fillSmoothRoundRect(r.x, r.y, r.w, r.h, 10, C_AMBAR_BG);
    int fw = (int)((r.w - 6) * (float)pulsos / cfgPulsos);
    if (fw > 20) g.fillSmoothRoundRect(r.x + 3, r.y + 3, fw, r.h - 6, 8, C_AMBAR_BAR);
    icono(I7_PULSO_24, r.x + 12, r.y + 8, C_AMBAR);
    texto("Midiendo · pulso " + String(pulsos) + " de " + String(cfgPulsos) + " · " + String(energiaWh, 3) + " Wh",
          r.x + 46, cy, F7_SB18, C_AMBAR, middle_left);
    return;
  }
  uint16_t bg = C_VERDE_BG, fg = C_VERDE;
  const Icono *ic = &I7_CHECK_24;
  String msg = "Listo para medir · Kc " + String(cfgKc) + " · " + String(cfgPulsos) + " pulsos · clase " + String(cfgClase);
  if (alarmas) {
    bg = C_ROJO_BG; fg = C_ROJO; ic = &I7_ALERTA_24;
    if (alarmas & 8) msg = "Sin señal del medidor de referencia (¿hay 220 V?)";
    else if (alarmas & 1) msg = "ALERTA: sobretensión " + String(V, 0) + " V";
    else if (alarmas & 2) msg = "ALERTA: tensión baja " + String(V, 0) + " V";
    else msg = "ALERTA: sobrecorriente " + String(I, 1) + " A";
  } else if (estado == ESPERA) {
    bg = C_AZUL_BG; fg = C_AZUL; ic = &I7_PULSO_24; msg = "Esperando el primer pulso del LED del medidor...";
  } else if (mensaje == M_APP_ON)  { bg = C_AZUL_BG; fg = C_AZUL; ic = &I7_BT_20; msg = "App VeriMed conectada"; }
  else if (mensaje == M_APP_OFF)   { bg = C_AZUL_BG; fg = C_AZUL; ic = &I7_BT_20; msg = "App desconectada · el equipo sigue visible"; }
  else if (mensaje == M_BT_OFF)    { bg = C_GRIS_BG; fg = C_GRIS; ic = &I7_BT_20; msg = "Bluetooth apagado · toca la etiqueta para encenderlo"; }
  else if (mensaje == M_BT_ON)     { bg = C_AZUL_BG; fg = C_AZUL; ic = &I7_BT_20; msg = "Bluetooth encendido · visible para la app"; }
  else if (mensaje == M_CANCELADO) { bg = C_GRIS_BG; fg = C_GRIS; ic = &I7_EQUIS_24; msg = "Ensayo cancelado"; }
  else if (mensaje == M_GUARDADO)  { msg = "Resultado guardado en el historial"; }
  g.fillSmoothRoundRect(r.x, r.y, r.w, r.h, 10, bg);
  icono(*ic, r.x + 12 + (24 - ic->w) / 2, r.y + (r.h - ic->h) / 2, fg);
  texto(msg, r.x + 46, cy, F7_SB18, fg, middle_left);
}

const char *ETIQ[4] = {"TENSIÓN", "CORRIENTE", "POTENCIA ACTIVA", "FACTOR DE POTENCIA"};
const char *UNID[4] = {"V", "A", "W", ""};

void dibujarTarjeta(int k) {
  const Rect &r = R_TARJETA[k];
  limpiar(r);
  tarjeta(r, 14, C_CARD, C_BORDE);
  const Icono *ics[4] = {&I7_ZAP_24, &I7_ACTIVIDAD_24, &I7_MEDIDOR_24, &I7_ONDA_24};
  uint16_t cols[4] = {C_AZUL, C_VERDE, C_AMBAR, C_VIOLETA};
  icono(*ics[k], r.x + 16, r.y + 12, cols[k]);
  texto(ETIQ[k], r.x + 48, r.y + 15, F7_M17, C_GRIS);
  if (UNID[k][0]) texto(UNID[k], r.x + r.w - 18, r.y + r.h - 18, F7_SB21, C_GRIS, baseline_right);
  dibujarValorTarjeta(k);
}
void dibujarValorTarjeta(int k) {
  const Rect &r = R_TARJETA[k];
  String v;
  uint16_t col = C_TEXTO;
  switch (k) {
    case 0: v = String(V, 1); if (alarmas & 3) col = C_ROJO; break;
    case 1: v = String(I, 2); if (alarmas & 4) col = C_ROJO; break;
    case 2: v = miles(lround(P)); break;
    default: v = String(FP, 2); break;
  }
  if (!pzemOk) { v = "---"; col = C_GRIS; }
  g.fillRect(r.x + 12, r.y + 34, 192, 62, C_CARD);
  texto(v, r.x + 16, r.y + 38, F7_B56, col);
}
// Zona del numero dentro de cada tarjeta (lo unico que cambia cada 0,5 s)
Rect zonaValor(int k) { const Rect &r = R_TARJETA[k]; return {(int16_t)(r.x + 12), (int16_t)(r.y + 34), 192, 62}; }

void dibujarGrafico() {
  const Rect &r = R_GRAFICO;
  limpiar(r);
  tarjeta(r, 14, C_CARD, C_BORDE);
  texto("POTENCIA ACTIVA · ÚLTIMOS 60 s", r.x + 16, r.y + 12, F7_SB14, C_GRIS);
  dibujarEtiquetaGrafico();
  dibujarCurva();
}
const Rect R_GRAF_ETIQ  = {380, 362, 124, 22};
const Rect R_GRAF_CURVA = {30, 384, 476, 72};
void dibujarEtiquetaGrafico() {
  g.fillRect(R_GRAF_ETIQ.x, R_GRAF_ETIQ.y, R_GRAF_ETIQ.w, R_GRAF_ETIQ.h, C_CARD);
  if (nMuestras) texto(miles(lround(muestras[nMuestras - 1])) + " W", 504, 364, F7_SB14, C_AZUL, top_right);
}
void dibujarCurva() {
  const Rect &r = R_GRAFICO;
  g.fillRect(R_GRAF_CURVA.x, R_GRAF_CURVA.y, R_GRAF_CURVA.w, R_GRAF_CURVA.h, C_CARD);
  int px = r.x + 16, py = r.y + 36, pw = r.w - 32, ph = r.h - 48;
  for (int k = 0; k < 3; k++) g.drawFastHLine(px, py + k * ph / 2, pw, C_LINEA);
  if (nMuestras < 2) return;
  float lo = muestras[0], hi = muestras[0];
  for (int i = 1; i < nMuestras; i++) { lo = min(lo, muestras[i]); hi = max(hi, muestras[i]); }
  float m = max(5.0f, (hi - lo) * 0.25f);
  lo -= m; hi += m;
  auto xs = [&](int i) { return px + (float)i * (pw - 1) / (N_MUESTRAS - 1); };
  auto ys = [&](float v) { return py + ph - 1 - (v - lo) / (hi - lo) * (ph - 1); };
  // Area bajo la curva
  for (int i = 0; i < nMuestras - 1; i++) {
    float x0 = xs(i), x1 = xs(i + 1), y0 = ys(muestras[i]), y1 = ys(muestras[i + 1]);
    for (int x = (int)x0; x <= (int)x1; x++) {
      float t = (x1 > x0) ? (x - x0) / (x1 - x0) : 0;
      int y = (int)(y0 + (y1 - y0) * t);
      g.drawFastVLine(x, y, py + ph - y, C_AREA);
    }
  }
  // Linea suavizada
  for (int i = 0; i < nMuestras - 1; i++)
    g.drawWideLine((int32_t)xs(i), (int32_t)ys(muestras[i]), (int32_t)xs(i + 1), (int32_t)ys(muestras[i + 1]), 1.5f, C_AZUL);
}

void dibujarPanelEnsayo() {
  const Rect &r = R_ENSAYO;
  limpiar(r);
  tarjeta(r, 14, C_CARD, C_BORDE);
  texto("ENSAYO", r.x + 16, r.y + 14, F7_SB14, C_GRIS);
  const char *chip = "EN REPOSO"; uint16_t cb = C_GRIS_BG, cf = C_GRIS;
  if (estado == ESPERA)   { chip = "ESPERANDO"; cb = C_AZUL_BG;  cf = C_AZUL; }
  if (estado == MIDIENDO) { chip = "MIDIENDO";  cb = C_AMBAR_BG; cf = C_AMBAR; }
  int cw = anchoTexto(chip, F7_SB14) + 20;
  g.fillSmoothRoundRect(r.x + r.w - 16 - cw, r.y + 10, cw, 26, 13, cb);
  texto(chip, r.x + r.w - 16 - cw / 2, r.y + 23, F7_SB14, cf, middle_center);
  dibujarDatosEnsayo();
}
const Rect R_DATOS_ENSAYO = {537, 166, 246, 172};   // debajo de la etiqueta de estado (y 138-164)
void dibujarDatosEnsayo() {
  const Rect &r = R_ENSAYO;
  g.fillRect(R_DATOS_ENSAYO.x, R_DATOS_ENSAYO.y, R_DATOS_ENSAYO.w, R_DATOS_ENSAYO.h, C_CARD);
  uint16_t p = (estado == MIDIENDO) ? pulsos : 0;
  texto(String(p) + " / " + String(cfgPulsos), r.x + r.w / 2, r.y + 70, F7_B44, C_TEXTO, middle_center);
  texto("pulsos del medidor", r.x + r.w / 2, r.y + 102, F7_SB14, C_GRIS, middle_center);
  g.fillSmoothRoundRect(r.x + 16, r.y + 118, r.w - 32, 12, 6, C_GRIS_BG);
  int fw = (int)((r.w - 32) * (float)p / cfgPulsos);
  if (fw > 12) g.fillSmoothRoundRect(r.x + 16, r.y + 118, fw, 12, 6, C_AZUL);

  String filas[3][2] = {
    {"Kc", String(cfgKc) + " imp/kWh"},
    {"Clase", String(cfgClase) + "  ·  ±" + String(cfgClase) + " %"},
    {"Energía ref.", "-"}};
  if (estado == MIDIENDO) filas[2][1] = String(energiaWh, 3) + " Wh";
  for (int k = 0; k < 3; k++) {
    int y = r.y + 144 + k * 22;
    texto(filas[k][0], r.x + 16, y, F7_M17, C_GRIS);
    texto(filas[k][1], r.x + r.w - 16, y, F7_SB18, C_TEXTO, top_right);
  }
}

bool ensayoActivo() { return estado == ESPERA || estado == MIDIENDO; }

void dibujarBotonesPrincipal() {
  if (ensayoActivo()) boton(R_INICIAR, true, C_ROJO, C_ROJO_OSC, "DETENER", I7_STOP_28, F7_B24, 10, botonPresionado == B_INICIAR);
  else boton(R_INICIAR, true, C_AZUL, C_AZUL_OSC, "INICIAR ENSAYO", I7_PLAY_28, F7_SB21, 10, botonPresionado == B_INICIAR);
  boton(R_AJUSTES, false, C_AZUL, C_AZUL, "AJUSTES", I7_AJUSTES_28, F7_SB14, 6, botonPresionado == B_AJUSTES);
  boton(R_HIST, false, C_AZUL, C_AZUL, "HISTORIAL", I7_HISTORIAL_28, F7_SB14, 6, botonPresionado == B_HISTORIAL);
}

// ============================ Pantallas ===============================
void dibujarPantallaPrincipal() {
  dibujarEncabezado();
  dibujarEstado();
  for (int k = 0; k < 4; k++) dibujarTarjeta(k);
  dibujarGrafico();
  dibujarPanelEnsayo();
  dibujarBotonesPrincipal();
}
void pantallaPrincipal() {
  pantalla = PRINCIPAL;
  pintar(R_TODO, dibujarPantallaPrincipal);
}

void dibujarFilaAjuste(int fila) {
  int y = FILA_Y[fila];
  g.fillRect(24, y + 2, 752, 88, C_CARD);
  if (fila) g.drawFastHLine(32, y, 736, C_BORDE);
  const char *et[3] = {"Constante Kc", "Pulsos de ensayo", "Clase del medidor"};
  const char *ay[3] = {"Impulsos por kWh: está en la placa del medidor", "Más pulsos, resultado más preciso", "Límite de error aceptado"};
  texto(et[fila], 36, y + 20, F7_B24, C_TEXTO);
  texto(ay[fila], 36, y + 54, F7_M17, C_GRIS);
  if (fila < 2) {
    const Rect &menos = fila == 0 ? R_KC_MENOS : R_NP_MENOS;
    const Rect &mas = fila == 0 ? R_KC_MAS : R_NP_MAS;
    BotonId bm = fila == 0 ? B_KC_MENOS : B_NP_MENOS, bp = fila == 0 ? B_KC_MAS : B_NP_MAS;
    g.fillSmoothRoundRect(menos.x, menos.y, menos.w, menos.h, 12, botonPresionado == bm ? C_BORDE : C_AZUL_BG);
    g.fillSmoothRoundRect(mas.x, mas.y, mas.w, mas.h, 12, botonPresionado == bp ? C_BORDE : C_AZUL_BG);
    texto("-", menos.x + menos.w / 2, menos.y + menos.h / 2, F7_B30, C_AZUL, middle_center);
    texto("+", mas.x + mas.w / 2, mas.y + mas.h / 2, F7_B30, C_AZUL, middle_center);
    texto(String(fila == 0 ? cfgKc : cfgPulsos), 634, y + 46, F7_B44, C_TEXTO, middle_center);
  } else {
    const Rect *bs[2] = {&R_CLASE1, &R_CLASE2};
    for (int c = 0; c < 2; c++) {
      bool sel = cfgClase == c + 1;
      tarjeta(*bs[c], 12, sel ? C_AZUL : C_CARD, sel ? C_AZUL : C_BORDE);
      texto(c == 0 ? "±1 %" : "±2 %", bs[c]->x + bs[c]->w / 2, bs[c]->y + bs[c]->h / 2, F7_B24, sel ? TFT_WHITE : C_TEXTO, middle_center);
    }
  }
}

void dibujarPantallaAjustes() {
  dibujarEncabezado();
  texto("AJUSTES DEL ENSAYO", 16, 76, F7_SB14, C_GRIS);
  tarjeta({16, 100, 768, 276}, 14, C_CARD, C_BORDE);
  for (int f = 0; f < 3; f++) dibujarFilaAjuste(f);
  texto("Equipo " NUMERO_SERIE " · Firmware " VERSION_FW " · Bluetooth " + direccionBT, 16, 386, F7_SB14, C_GRIS);
  boton(R_ABAJO, false, C_AZUL, C_AZUL, "GUARDAR Y VOLVER", I7_VOLVER_28, F7_B24, 10, false);
}
void pantallaAjustes() {
  pantalla = AJUSTES;
  pintar(R_TODO, dibujarPantallaAjustes);
}

void dibujarPantallaHistorial() {
  dibujarEncabezado();
  texto("HISTORIAL DE ENSAYOS · se guarda aunque se apague el equipo", 16, 76, F7_SB14, C_GRIS);
  tarjeta({16, 100, 768, 296}, 14, C_CARD, C_BORDE);
  const int col[7] = {36, 96, 196, 372, 462, 552, 672};
  const char *cab[7] = {"N.º", "ERROR", "RESULTADO", "PULSOS", "KC", "Eref (Wh)", "TIEMPO"};
  for (int c = 0; c < 7; c++) texto(cab[c], col[c], 114, F7_SB14, C_GRIS);
  g.drawFastHLine(32, 138, 736, C_BORDE);
  if (!nHist) texto("Aún no hay ensayos guardados", 400, 260, F7_SB21, C_GRIS, middle_center);
  for (int k = 0; k < nHist; k++) {
    const Resultado &h = hist[k];
    int y = 146 + k * 24;
    uint16_t c = h.aprobado ? C_VERDE : C_ROJO;
    texto(String(h.id), col[0], y, F7_SB18, C_TEXTO);
    texto(conSigno(h.err, 2) + " %", col[1], y, F7_SB18, c);
    icono(h.aprobado ? I7_CHECK_24 : I7_EQUIS_24, col[2], y - 2, c);
    texto(h.aprobado ? "APROBADO" : "RECHAZADO", col[2] + 30, y, F7_SB18, c);
    texto(String(h.pulsos), col[3], y, F7_SB18, C_TEXTO);
    texto(String(h.kc), col[4], y, F7_SB18, C_TEXTO);
    texto(String(h.eref, 4), col[5], y, F7_SB18, C_TEXTO);
    texto(String(h.seg, 1) + " s", col[6], y, F7_SB18, C_TEXTO);
  }
  boton(R_ABAJO, false, C_AZUL, C_AZUL, "VOLVER", I7_VOLVER_28, F7_B24, 10, false);
}
void pantallaHistorial() {
  pantalla = HISTORIAL;
  pintar(R_TODO, dibujarPantallaHistorial);
}

void dibujarPantallaResultado() {
  const Resultado &r = ultimo;
  bool ok = r.aprobado;
  uint16_t fg = ok ? C_VERDE : C_ROJO, bgc = ok ? C_VERDE_BG : C_ROJO_BG;
  dibujarEncabezado();
  g.fillSmoothRoundRect(16, 76, 768, 252, 16, bgc);
  icono(ok ? I7_CHECK_44 : I7_EQUIS_44, 40, 96, fg);
  texto(ok ? "APROBADO" : "RECHAZADO", 96, 101, F7_B30, fg);
  texto("Clase " + String(r.clase) + " · Kc " + String(r.kc) + " · límite ±" + String(r.clase == 1 ? 1 : 2) + " %", 760, 108, F7_SB18, fg, top_right);
  texto(conSigno(r.err, 2) + "%", 400, 220, F7_B112, fg, middle_center);
  texto("error del medidor · ensayo N.º " + String(r.id), 400, 300, F7_SB18, fg, middle_center);
  tarjeta({16, 338, 768, 58}, 14, C_CARD, C_BORDE);
  texto("Eref  " + String(r.eref, 4) + " Wh", 144, 367, F7_SB18, C_TEXTO, middle_center);
  texto("Emed  " + String(r.emed, 4) + " Wh", 400, 367, F7_SB18, C_TEXTO, middle_center);
  texto(String(r.pulsos) + " pulsos · " + String(r.seg, 1) + " s", 656, 367, F7_SB18, C_TEXTO, middle_center);
  g.drawFastVLine(272, 350, 34, C_BORDE);
  g.drawFastVLine(528, 350, 34, C_BORDE);
  boton(R_NUEVO, true, C_AZUL, C_AZUL_OSC, "NUEVO ENSAYO", I7_PLAY_28, F7_B24, 10, botonPresionado == B_NUEVO);
  boton(R_LISTO, false, C_AZUL, C_AZUL, "LISTO", I7_VOLVER_28, F7_B24, 10, botonPresionado == B_LISTO);
}
void pantallaResultado() {
  pantalla = RESULTADO;
  pintar(R_TODO, dibujarPantallaResultado);
}

// Redibuja solo lo que cambio en la pantalla principal
void refrescarEstado() { if (pantalla == PRINCIPAL) pintar(R_ESTADO, dibujarEstado); }
void refrescarPanel()  { if (pantalla == PRINCIPAL) pintar(R_ENSAYO, dibujarPanelEnsayo); }
void refrescarBotones(){ if (pantalla == PRINCIPAL) pintar({536, 352, 248, 112}, dibujarBotonesPrincipal); }
void refrescarPildoras(){ pintar(R_PILDORAS, dibujarPildoras); }

// ============================ Mediciones ==============================
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
  if (!pzemOk) return 8;
  uint8_t a = 0;
  if (V > V_MAX) a |= 1;
  if (V < V_MIN && V > 20) a |= 2;
  if (I > I_MAX) a |= 4;
  return a;
}
void integrarHasta(unsigned long t) {
  long dt = (long)(t - tIntegracion);
  energiaWh += P * dt / 3600000.0;
  tIntegracion = t;
}
void agregarMuestra(float p) {
  if (nMuestras < N_MUESTRAS) muestras[nMuestras++] = p;
  else { memmove(muestras, muestras + 1, sizeof(float) * (N_MUESTRAS - 1)); muestras[N_MUESTRAS - 1] = p; }
}

// ============================== Ensayo ================================
void iniciarEnsayo() {
  if (ensayoActivo()) return;
  estado = ESPERA;
  pulsos = 0;
  energiaWh = energiaEnPulso = 0;
  duracionFinal = 0;
  energiaSimMedidor = 0;
  errSim = random(-150, 151) / 100.0;
  noInterrupts(); pulsosISR = 0; interrupts();
  tInicio = tUltPulso = millis();
  if (pantalla != PRINCIPAL) pantallaPrincipal();
  else { refrescarEstado(); refrescarPanel(); refrescarBotones(); }
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
  conPantallaOculta([&] { guardarResultado(r); pantallaResultado(); });
}

void detenerEnsayo() {
  if (!ensayoActivo()) return;
  if (estado == MIDIENDO && pulsos >= 1) { finalizarEnsayo(); return; }
  estado = REPOSO;
  mensaje = M_CANCELADO;
  refrescarEstado(); refrescarPanel(); refrescarBotones();
}

void procesarPulso(unsigned long tPulso) {
  if (estado == ESPERA) {
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
  refrescarEstado(); refrescarPanel();
}

void revisarPulsos(unsigned long ahora) {
#if USAR_SENSOR_PULSOS
  static uint32_t vistos = 0;
  uint32_t n; unsigned long t;
  noInterrupts(); n = pulsosISR; t = tPulsoISR; interrupts();
  if (n < vistos) vistos = 0;
  while (vistos < n) { vistos++; procesarPulso(t); }
#else
  static unsigned long tSim = 0;
  if (tSim == 0) tSim = ahora;
  if (ensayoActivo()) {
    energiaSimMedidor += P * (1.0 + errSim / 100.0) * (ahora - tSim) / 3600000.0;
    double whPulso = 1000.0 / cfgKc;
    if (estado == ESPERA && ahora - tInicio > 800) energiaSimMedidor = whPulso;
    if (energiaSimMedidor >= whPulso) { energiaSimMedidor -= whPulso; procesarPulso(ahora); }
  }
  tSim = ahora;
#endif
}

// ============================ Bluetooth ===============================
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

void aplicarConfig(const String &s) {
  int i = s.indexOf("kc="); if (i >= 0) { long v = s.substring(i + 3).toInt(); if (v >= 1 && v <= 65000) cfgKc = v; }
  i = s.indexOf("np=");     if (i >= 0) { long v = s.substring(i + 3).toInt(); if (v >= 1 && v <= 500) cfgPulsos = v; }
  i = s.indexOf("cl=");     if (i >= 0) { long v = s.substring(i + 3).toInt(); if (v == 1 || v == 2) cfgClase = v; }
  if (configCambio()) conPantallaOculta([] { guardarConfig(); });   // solo si la app cambio algo
  if (pantalla == AJUSTES) pantallaAjustes();
  else { refrescarEstado(); refrescarPanel(); }
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

  direccionBT = String(BLEDevice::getAddress().toString().c_str());
  actualizarInfo();
  enviarMedicion();
  Serial.println("Direccion Bluetooth: " + direccionBT);
}

void cambiarBLE(bool encender) {
  bleHabilitado = encender;
  conPantallaOculta([] { guardarConfig(); });
  if (encender) BLEDevice::startAdvertising();
  else {
    BLEDevice::stopAdvertising();
    if (bleConectado) bleServer->disconnect(bleServer->getConnId());
  }
  mensaje = encender ? M_BT_ON : M_BT_OFF;
  refrescarPildoras();
  if (!ensayoActivo()) refrescarEstado();
}

// ============================== Tactil ================================
// Que boton hay bajo el dedo en la pantalla actual
BotonId botonEn(int x, int y) {
  if (dentro(R_TOQUE_BT, x, y)) return B_BT;
  switch (pantalla) {
    case PRINCIPAL:
      if (dentro(R_INICIAR, x, y)) return B_INICIAR;
      if (!ensayoActivo() && dentro(R_AJUSTES, x, y)) return B_AJUSTES;
      if (!ensayoActivo() && dentro(R_HIST, x, y)) return B_HISTORIAL;
      break;
    case AJUSTES:
      if (dentro(R_KC_MENOS, x, y)) return B_KC_MENOS;
      if (dentro(R_KC_MAS, x, y)) return B_KC_MAS;
      if (dentro(R_NP_MENOS, x, y)) return B_NP_MENOS;
      if (dentro(R_NP_MAS, x, y)) return B_NP_MAS;
      if (dentro(R_CLASE1, x, y)) return B_CLASE1;
      if (dentro(R_CLASE2, x, y)) return B_CLASE2;
      if (dentro(R_ABAJO, x, y)) return B_GUARDAR;
      break;
    case HISTORIAL:
      if (dentro(R_ABAJO, x, y)) return B_VOLVER;
      break;
    case RESULTADO:
      if (dentro(R_NUEVO, x, y)) return B_NUEVO;
      if (dentro(R_LISTO, x, y)) return B_LISTO;
      break;
  }
  return B_NINGUNO;
}

// Redibuja un boton en estado normal o presionado
void pintarBoton(BotonId b) {
  switch (b) {
    case B_INICIAR: case B_AJUSTES: case B_HISTORIAL: refrescarBotones(); break;
    case B_BT: refrescarPildoras(); break;
    case B_KC_MENOS: case B_KC_MAS: pintar({24, 102, 752, 88}, [] { dibujarFilaAjuste(0); }); break;
    case B_NP_MENOS: case B_NP_MAS: pintar({24, 194, 752, 88}, [] { dibujarFilaAjuste(1); }); break;
    case B_GUARDAR:
      pintar(R_ABAJO, [] { boton(R_ABAJO, false, C_AZUL, C_AZUL, "GUARDAR Y VOLVER", I7_VOLVER_28, F7_B24, 10, botonPresionado == B_GUARDAR); });
      break;
    case B_VOLVER:
      pintar(R_ABAJO, [] { boton(R_ABAJO, false, C_AZUL, C_AZUL, "VOLVER", I7_VOLVER_28, F7_B24, 10, botonPresionado == B_VOLVER); });
      break;
    case B_NUEVO:
      pintar(R_NUEVO, [] { boton(R_NUEVO, true, C_AZUL, C_AZUL_OSC, "NUEVO ENSAYO", I7_PLAY_28, F7_B24, 10, botonPresionado == B_NUEVO); });
      break;
    case B_LISTO:
      pintar(R_LISTO, [] { boton(R_LISTO, false, C_AZUL, C_AZUL, "LISTO", I7_VOLVER_28, F7_B24, 10, botonPresionado == B_LISTO); });
      break;
    default: break;
  }
}

int indiceKc() {
  for (int k = 0; k < N_KC; k++) if (LISTA_KC[k] >= cfgKc) return k;
  return N_KC - 1;
}
void cambiarAjuste(BotonId b) {
  if (b == B_KC_MENOS || b == B_KC_MAS) {
    int k = constrain(indiceKc() + (b == B_KC_MAS ? 1 : -1), 0, N_KC - 1);
    cfgKc = LISTA_KC[k];
  } else {
    int dir = (b == B_NP_MAS) ? 1 : -1;
    int paso = (cfgPulsos + (dir > 0 ? 0 : -1)) >= 10 ? 5 : 1;
    cfgPulsos = constrain((int)cfgPulsos + dir * paso, 1, 100);
  }
  pintarBoton(b);
}

// Accion al soltar el dedo sobre el boton
void accion(BotonId b) {
  switch (b) {
    case B_BT: cambiarBLE(!bleHabilitado); break;
    case B_INICIAR: if (ensayoActivo()) detenerEnsayo(); else iniciarEnsayo(); break;
    case B_AJUSTES: pantallaAjustes(); break;
    case B_HISTORIAL: pantallaHistorial(); break;
    case B_CLASE1: cfgClase = 1; pintar({24, 286, 752, 88}, [] { dibujarFilaAjuste(2); }); break;
    case B_CLASE2: cfgClase = 2; pintar({24, 286, 752, 88}, [] { dibujarFilaAjuste(2); }); break;
    case B_GUARDAR: mensaje = M_LISTO; conPantallaOculta([] { guardarConfig(); pantallaPrincipal(); }); break;
    case B_VOLVER: pantallaPrincipal(); break;
    case B_NUEVO: estado = REPOSO; iniciarEnsayo(); break;
    case B_LISTO: estado = REPOSO; mensaje = M_GUARDADO; pantallaPrincipal(); break;
    default: break;   // +/- ya actuaron al presionar
  }
}

bool esRepetible(BotonId b) { return b == B_KC_MENOS || b == B_KC_MAS || b == B_NP_MENOS || b == B_NP_MAS; }

void manejarTactil(unsigned long ahora) {
  static unsigned long tUltimoToque = 0;
  static BotonId bajoDedo = B_NINGUNO;
  int32_t x, y;
  bool tocando = tft.getTouch(&x, &y);

  if (tocando) {
    tUltimoToque = ahora;
    BotonId b = botonEn(x, y);
    if (botonPresionado == B_NINGUNO && b != B_NINGUNO) {
      // Dedo abajo: resalta el boton al instante
      botonPresionado = b;
      bajoDedo = b;
      tPresion = tRepeticion = ahora;
      pintarBoton(b);
      if (esRepetible(b)) cambiarAjuste(b);   // +/- responden al presionar
    } else if (botonPresionado != B_NINGUNO) {
      bajoDedo = b;
      // Mantener +/- presionado repite el cambio
      if (esRepetible(botonPresionado) && b == botonPresionado &&
          ahora - tPresion > 450 && ahora - tRepeticion > 110) {
        tRepeticion = ahora;
        cambiarAjuste(botonPresionado);
      }
    }
  } else if (botonPresionado != B_NINGUNO && ahora - tUltimoToque > 40) {
    // Dedo arriba: si sigue sobre el mismo boton, se ejecuta la accion
    BotonId b = botonPresionado;
    botonPresionado = B_NINGUNO;
    pintarBoton(b);
    if (bajoDedo == b) accion(b);
    bajoDedo = B_NINGUNO;
  }
}

// =============================== Setup ================================
void setup() {
  Serial.begin(115200);
  delay(200);
  Serial.printf("\nVeriMed BT 7\" - motivo del ultimo reinicio: %d (1=encendido, 3=software, 4=fallo/panic, 6=watchdog)\n",
                (int)esp_reset_reason());
  randomSeed(esp_random());
#if USAR_SENSOR_PULSOS
  pinMode(PIN_PULSOS, INPUT_PULLUP);
  attachInterrupt(digitalPinToInterrupt(PIN_PULSOS), isrPulso, FLANCO_PULSO);
#endif

  tft.init();
  tft.setRotation(0);
  tft.setBrightness(0);          // sin luz hasta tener la primera pantalla lista
  tft.fillScreen(TFT_BLACK);

  if (!ESP.getPsramSize()) Serial.println("ERROR: sin PSRAM. Herramientas -> PSRAM -> OPI PSRAM");
  banda.setColorDepth(16);
  banda.setPsram(false);                       // RAM interna: no compite con la pantalla
  while (FILAS > 8 && !banda.createSprite(800, FILAS)) FILAS /= 2;

  C_BG = rgb(244, 247, 252);  C_CARD = TFT_WHITE;          C_BORDE = rgb(214, 224, 236); C_LINEA = rgb(236, 241, 247);
  C_AZUL = rgb(18, 98, 204);  C_AZUL_BG = rgb(224, 236, 252); C_AZUL_OSC = rgb(12, 72, 160);
  C_TEXTO = rgb(23, 37, 64);  C_GRIS = rgb(90, 104, 125);  C_GRIS_BG = rgb(230, 234, 240);
  C_VERDE = rgb(22, 128, 61); C_VERDE_BG = rgb(222, 243, 229);
  C_AMBAR = rgb(160, 82, 6);  C_AMBAR_BG = rgb(254, 243, 199); C_AMBAR_BAR = rgb(253, 224, 140);
  C_ROJO = rgb(205, 45, 45);  C_ROJO_BG = rgb(253, 228, 228);  C_ROJO_OSC = rgb(160, 30, 30);
  C_VIOLETA = rgb(124, 58, 237); C_AREA = rgb(232, 240, 252);

  prefs.begin("verimed", false);
  cargarConfig();
  if (!bleHabilitado) mensaje = M_BT_OFF;

  iniciarBLE();
  leerReferencia();
  alarmas = calcularAlarmas();
  agregarMuestra(P);
  pantallaPrincipal();
  for (int b = 0; b <= 255; b += 15) { tft.setBrightness(b); delay(12); }   // encendido suave
  tft.setBrightness(255);
  Serial.printf("VeriMed BT 7\" %s listo. Franja 800x%d en RAM interna\n", VERSION_FW, FILAS);
}

// =============================== Loop =================================
void loop() {
  static unsigned long tLectura = 0, tEnvio = 0;
  unsigned long ahora = millis();

  manejarTactil(ahora);

  if (bleCambioEstado) {
    bleCambioEstado = false;
    if (bleHabilitado) mensaje = bleConectado ? M_APP_ON : M_APP_OFF;
    refrescarPildoras();
    if (!ensayoActivo()) refrescarEstado();
    if (bleConectado) enviarMedicion();
  }
  procesarComando();

  // Referencia y pantalla cada 500 ms (solo se copian las zonas que cambian)
  if (ahora - tLectura >= 500) {
    tLectura = ahora;
    if (estado == MIDIENDO) integrarHasta(ahora);
    leerReferencia();
    agregarMuestra(P);
    uint8_t a = calcularAlarmas();
    bool cambioAlarma = a != alarmas;
    alarmas = a;
    if (pantalla == PRINCIPAL) {
      // Solo los numeros, la curva y los datos del ensayo: menos lectura de fuentes
      // desde la flash y menos escritura en la PSRAM (pantalla mas estable).
      for (int k = 0; k < 4; k++) pintar(zonaValor(k), [k] { dibujarValorTarjeta(k); });
      pintar(R_GRAF_CURVA, dibujarCurva);
      pintar(R_GRAF_ETIQ, dibujarEtiquetaGrafico);
      if (estado == MIDIENDO || cambioAlarma) refrescarEstado();
      if (estado == MIDIENDO) pintar(R_DATOS_ENSAYO, dibujarDatosEnsayo);
    }
  }

  revisarPulsos(ahora);

  if (bleHabilitado && bleConectado && ahora - tEnvio >= (ensayoActivo() ? 500UL : 2000UL)) {
    tEnvio = ahora;
    enviarMedicion();
  }
  delay(1);
}
