// Tipos de VeriMed BT v2.
// Van en un archivo aparte porque el Arduino IDE copia las declaraciones de las
// funciones al inicio del .ino, antes que estas definiciones (error
// "'Resultado' does not name a type").
#pragma once
#include <stdint.h>

struct Rect { int x, y, w, h; };

enum Pantalla { PRINCIPAL, AJUSTES, HISTORIAL, RESULTADO };
enum EstadoEnsayo { REPOSO = 0, ESPERA = 1, MIDIENDO = 2, LISTO = 3 };
enum Mensaje { M_LISTO, M_APP_ON, M_APP_OFF, M_BT_OFF, M_BT_ON, M_CANCELADO, M_GUARDADO };

struct Resultado {
  uint32_t id; float err; float eref; float emed; float seg;
  uint16_t pulsos; uint16_t kc; uint8_t clase; uint8_t aprobado;
};
