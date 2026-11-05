// Calibracion del tactil XPT2046 - ESP32-2432S028 (CYD 2.8" USB-C)
// Requiere las librerias: TFT_eSPI y XPT2046_Touchscreen (Paul Stoffregen)
//
// 1. Sube el sketch y toca el centro de cada cruz (4 esquinas).
// 2. Copia los valores que aparecen en pantalla / Monitor Serie (115200).
// 3. Despues puedes dibujar tocando la pantalla para comprobar la precision.

#include <SPI.h>
#include <TFT_eSPI.h>
#include <XPT2046_Touchscreen.h>

// Pines del tactil en el CYD (bus SPI separado de la pantalla)
#define XPT2046_IRQ  36
#define XPT2046_MOSI 32
#define XPT2046_MISO 39
#define XPT2046_CLK  25
#define XPT2046_CS   33

#define ROTACION_PANTALLA 1   // usa la misma rotacion que en tu proyecto
#define MARGEN 20             // distancia de las cruces al borde (px)

SPIClass touchSPI(HSPI);
XPT2046_Touchscreen ts(XPT2046_CS, XPT2046_IRQ);
TFT_eSPI tft = TFT_eSPI();

// Resultado de la calibracion
bool calSwapXY = false;
int calXMin, calXMax, calYMin, calYMax;

struct Raw { int x; int y; };

void dibujarCruz(int x, int y, uint16_t color) {
  tft.drawFastHLine(x - 12, y, 25, color);
  tft.drawFastVLine(x, y - 12, 25, color);
  tft.drawCircle(x, y, 6, color);
}

// Muestra una cruz, espera el toque y devuelve el promedio de lecturas crudas
Raw leerPunto(int px, int py) {
  while (true) {
    tft.fillScreen(TFT_BLACK);
    tft.setTextColor(TFT_WHITE, TFT_BLACK);
    tft.setTextDatum(MC_DATUM);
    tft.drawString("Toca el centro de la cruz", tft.width() / 2, tft.height() / 2, 2);
    dibujarCruz(px, py, TFT_WHITE);

    while (ts.touched()) delay(10);   // esperar a que suelte
    while (!ts.touched()) delay(10);  // esperar el toque
    delay(60);

    long sx = 0, sy = 0;
    int n = 0;
    while (ts.touched()) {
      TS_Point p = ts.getPoint();
      if (p.z > 200) { sx += p.x; sy += p.y; n++; }
      delay(10);
    }

    if (n >= 3) {
      dibujarCruz(px, py, TFT_GREEN);
      delay(300);
      return { (int)(sx / n), (int)(sy / n) };
    }
    // toque muy corto: repetir
  }
}

void calibrar() {
  int W = tft.width();
  int H = tft.height();

  Raw tl = leerPunto(MARGEN, MARGEN);
  Raw tr = leerPunto(W - MARGEN, MARGEN);
  Raw bl = leerPunto(MARGEN, H - MARGEN);
  Raw br = leerPunto(W - MARGEN, H - MARGEN);

  // Si al moverse en horizontal cambia mas el eje Y crudo, los ejes estan cruzados
  calSwapXY = abs(tr.x - tl.x) < abs(tr.y - tl.y);

  auto ax = [](Raw r) { return calSwapXY ? r.y : r.x; };
  auto ay = [](Raw r) { return calSwapXY ? r.x : r.y; };

  float izq = (ax(tl) + ax(bl)) / 2.0;
  float der = (ax(tr) + ax(br)) / 2.0;
  float arr = (ay(tl) + ay(tr)) / 2.0;
  float aba = (ay(bl) + ay(br)) / 2.0;

  // Extrapolar desde las cruces hasta el borde real de la pantalla
  float kx = (der - izq) / (W - 2 * MARGEN);
  float ky = (aba - arr) / (H - 2 * MARGEN);
  calXMin = izq - kx * MARGEN;
  calXMax = der + kx * MARGEN;
  calYMin = arr - ky * MARGEN;
  calYMax = aba + ky * MARGEN;
}

// Convierte un punto crudo a coordenadas de pantalla
bool leerToque(int &x, int &y) {
  if (!ts.touched()) return false;
  TS_Point p = ts.getPoint();
  if (p.z < 200) return false;
  int rx = calSwapXY ? p.y : p.x;
  int ry = calSwapXY ? p.x : p.y;
  x = constrain(map(rx, calXMin, calXMax, 0, tft.width() - 1), 0, tft.width() - 1);
  y = constrain(map(ry, calYMin, calYMax, 0, tft.height() - 1), 0, tft.height() - 1);
  return true;
}

void mostrarResultado() {
  Serial.println();
  Serial.println("===== CALIBRACION TACTIL - copia esto a tu proyecto =====");
  Serial.printf("#define TOUCH_SWAP_XY %d\n", calSwapXY ? 1 : 0);
  Serial.printf("#define TOUCH_X_MIN   %d\n", calXMin);
  Serial.printf("#define TOUCH_X_MAX   %d\n", calXMax);
  Serial.printf("#define TOUCH_Y_MIN   %d\n", calYMin);
  Serial.printf("#define TOUCH_Y_MAX   %d\n", calYMax);
  Serial.println("=========================================================");

  tft.fillScreen(TFT_BLACK);
  tft.setTextDatum(TL_DATUM);
  tft.setTextColor(TFT_GREEN, TFT_BLACK);
  tft.drawString("Calibracion lista:", 10, 10, 2);
  tft.setTextColor(TFT_WHITE, TFT_BLACK);
  tft.drawString("SWAP_XY = " + String(calSwapXY ? 1 : 0), 10, 35, 2);
  tft.drawString("X_MIN = " + String(calXMin) + "   X_MAX = " + String(calXMax), 10, 55, 2);
  tft.drawString("Y_MIN = " + String(calYMin) + "   Y_MAX = " + String(calYMax), 10, 75, 2);
  tft.setTextColor(TFT_YELLOW, TFT_BLACK);
  tft.drawString("Dibuja para probar. Toca BORRAR", 10, 105, 2);
  tft.drawString("para limpiar.", 10, 125, 2);
  dibujarBotonBorrar();
}

void dibujarBotonBorrar() {
  tft.fillRoundRect(tft.width() - 90, tft.height() - 40, 80, 30, 6, TFT_RED);
  tft.setTextColor(TFT_WHITE, TFT_RED);
  tft.setTextDatum(MC_DATUM);
  tft.drawString("BORRAR", tft.width() - 50, tft.height() - 25, 2);
  tft.setTextDatum(TL_DATUM);
}

void setup() {
  Serial.begin(115200);

  touchSPI.begin(XPT2046_CLK, XPT2046_MISO, XPT2046_MOSI, XPT2046_CS);
  ts.begin(touchSPI);
  ts.setRotation(1);   // lecturas crudas sin transformar; la calibracion resuelve la orientacion

  tft.init();
  tft.setRotation(ROTACION_PANTALLA);

  calibrar();
  mostrarResultado();
}

void loop() {
  int x, y;
  if (leerToque(x, y)) {
    bool enBoton = x > tft.width() - 90 && y > tft.height() - 40;
    if (enBoton) {
      tft.fillScreen(TFT_BLACK);
      dibujarBotonBorrar();
      delay(300);
    } else {
      tft.fillCircle(x, y, 3, TFT_CYAN);
    }
  }
  delay(5);
}
