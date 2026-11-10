// Tipos de VeriMed BT 7" (archivo aparte: el Arduino IDE declara las funciones
// al inicio del .ino, antes de estas definiciones).
#pragma once
#include <stdint.h>

struct Rect { int16_t x, y, w, h; };

enum Pantalla { PRINCIPAL, AJUSTES, HISTORIAL, RESULTADO };
enum EstadoEnsayo { REPOSO = 0, ESPERA = 1, MIDIENDO = 2, LISTO = 3 };
enum Mensaje { M_LISTO, M_APP_ON, M_APP_OFF, M_BT_OFF, M_BT_ON, M_CANCELADO, M_GUARDADO };

// Botones tactiles (se resaltan al presionar y actuan al soltar)
enum BotonId {
  B_NINGUNO = 0,
  B_INICIAR, B_AJUSTES, B_HISTORIAL, B_BT,
  B_KC_MENOS, B_KC_MAS, B_NP_MENOS, B_NP_MAS, B_CLASE1, B_CLASE2, B_GUARDAR,
  B_VOLVER, B_NUEVO, B_LISTO
};

struct Resultado {
  uint32_t id; float err; float eref; float emed; float seg;
  uint16_t pulsos; uint16_t kc; uint8_t clase; uint8_t aprobado;
};

// Lo que se guarda en la memoria flash, en UN solo bloque cada uno
// (cada escritura en flash pausa un instante la imagen de la pantalla).
#define MAX_HIST_GUARDADO 10
struct ConfigGuardada { uint16_t kc; uint16_t np; uint8_t clase; uint8_t ble; };
struct HistorialGuardado { uint32_t proximoId; uint8_t n; Resultado r[MAX_HIST_GUARDADO]; };
