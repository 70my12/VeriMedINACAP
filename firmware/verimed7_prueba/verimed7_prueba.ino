// =====================================================================
//  VERIMED BT - PRUEBA DE PANTALLA 7" (VIEWE UEDX80480070E-WB-A V1.1)
// =====================================================================
//  Arduino IDE -> Herramientas:
//    Placa ............ ESP32S3 Dev Module
//    PSRAM ............ OPI PSRAM            <- IMPRESCINDIBLE (sin esto: pantalla negra)
//    Flash Mode ....... QIO 80MHz
//    Flash Size ....... 16MB (128Mb)
//    Partition Scheme . 16M Flash (3MB APP/9.9MB FATFS)
//    USB CDC On Boot .. Enabled  (si conectas por el USB nativo; Disabled si es por UART)
//  Libreria: LovyanGFX (lovyan03)
//
//  Que comprueba:
//   1. PSRAM detectada (se informa en pantalla y en el Monitor Serie 115200)
//   2. Marco blanco en los 4 bordes  -> la imagen ocupa toda la pantalla
//   3. Barras ROJO / VERDE / AZUL     -> el orden de colores es correcto
//   4. Tactil: dibuja donde tocas y muestra las coordenadas (boton BORRAR)
// =====================================================================

#include "LGFX_VeriMed7.h"

LGFX_VeriMed7 tft;

const int BTN_X = 660, BTN_Y = 410, BTN_W = 124, BTN_H = 54;

void pantallaPrueba() {
  tft.fillScreen(TFT_BLACK);
  tft.drawRect(0, 0, tft.width(), tft.height(), TFT_WHITE);
  tft.drawRect(1, 1, tft.width() - 2, tft.height() - 2, TFT_WHITE);

  tft.setTextColor(TFT_WHITE, TFT_BLACK);
  tft.setFont(&fonts::DejaVu40);
  tft.setTextDatum(top_left);
  tft.drawString("VERIMED BT - 7 pulgadas", 24, 18);

  tft.setFont(&fonts::DejaVu24);
  tft.drawString("Resolucion: " + String(tft.width()) + " x " + String(tft.height()), 24, 76);
  uint32_t psram = ESP.getPsramSize();
  tft.setTextColor(psram ? TFT_GREEN : TFT_RED, TFT_BLACK);
  String txtPsram;
  if (psram) txtPsram = "PSRAM OK: " + String(psram / 1024 / 1024) + " MB";
  else       txtPsram = "SIN PSRAM (activa OPI PSRAM)";
  tft.drawString(txtPsram, 24, 108);

  // Barras de color con su nombre: si no coinciden, el orden RGB esta mal
  const char *nombres[3] = {"ROJO", "VERDE", "AZUL"};
  const uint16_t colores[3] = {TFT_RED, TFT_GREEN, TFT_BLUE};
  for (int k = 0; k < 3; k++) {
    int x = 24 + k * 250;
    tft.fillRoundRect(x, 160, 230, 110, 14, colores[k]);
    tft.setTextColor(TFT_WHITE, colores[k]);
    tft.setTextDatum(middle_center);
    tft.drawString(nombres[k], x + 115, 215);
  }
  // Degradado de grises: muestra si hay saltos de color
  for (int x = 24; x < 774; x++) {
    uint8_t g = map(x, 24, 773, 0, 255);
    tft.drawFastVLine(x, 290, 40, tft.color565(g, g, g));
  }

  tft.setTextDatum(top_left);
  tft.setTextColor(TFT_YELLOW, TFT_BLACK);
  tft.drawString("Toca la pantalla para dibujar", 24, 350);
  tft.fillRoundRect(BTN_X, BTN_Y, BTN_W, BTN_H, 12, TFT_RED);
  tft.setTextColor(TFT_WHITE, TFT_RED);
  tft.setTextDatum(middle_center);
  tft.drawString("BORRAR", BTN_X + BTN_W / 2, BTN_Y + BTN_H / 2);
  tft.setTextDatum(top_left);
}

void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.printf("\nVeriMed BT 7\" - PSRAM: %u bytes, Flash: %u bytes\n", ESP.getPsramSize(), ESP.getFlashChipSize());
  if (!ESP.getPsramSize()) Serial.println("ERROR: sin PSRAM. Herramientas -> PSRAM -> OPI PSRAM");

  tft.init();
  tft.setBrightness(255);
  tft.setRotation(0);      // 800 x 480 horizontal
  pantallaPrueba();
}

void loop() {
  static int32_t xAnt = -1, yAnt = -1;          // punto anterior del trazo
  static unsigned long tTexto = 0, tSinToque = 0;
  int32_t x, y;

  if (tft.getTouch(&x, &y)) {
    tSinToque = millis();
    if (x >= BTN_X && x < BTN_X + BTN_W && y >= BTN_Y && y < BTN_Y + BTN_H) {
      pantallaPrueba();
      xAnt = yAnt = -1;
      delay(300);
      return;
    }
    // Une la lectura anterior con la actual: trazo continuo aunque el dedo se mueva rapido
    if (xAnt >= 0) tft.drawWideLine(xAnt, yAnt, x, y, 3.5f, TFT_CYAN);
    else           tft.fillCircle(x, y, 4, TFT_CYAN);
    xAnt = x; yAnt = y;

    // Las coordenadas se actualizan solo 10 veces por segundo (dibujar texto es lento)
    if (millis() - tTexto > 100) {
      tTexto = millis();
      tft.setFont(&fonts::DejaVu24);
      tft.setTextColor(TFT_CYAN, TFT_BLACK);
      tft.setTextPadding(260);
      tft.drawString("x=" + String(x) + "  y=" + String(y), 24, 420);
      tft.setTextPadding(0);
      Serial.printf("toque x=%d y=%d\n", (int)x, (int)y);
    }
  } else if (xAnt >= 0 && millis() - tSinToque > 40) {
    xAnt = yAnt = -1;                            // dedo levantado: el proximo toque empieza un trazo nuevo
  }
  delay(2);
}
