# Placa de medición (ESP32 DevKitC + 2 × AD71056)

Desde noviembre de 2026 la referencia de medición es la placa propia del equipo, en reemplazo del PZEM-004T.
La pantalla de 7" (`firmware/verimed7`) recibe las mediciones por UART desde esta placa (`firmware/verimed_placa`).

## Cómo mide

El AD71056 solo entrega pulsos de energía (no entrega tensión ni corriente). En esta placa cada chip recibe
la misma señal en sus dos entradas, así que la frecuencia de su salida CF es proporcional al cuadrado de esa señal:

| Chip | Entrada | Salida CF | GPIO del ESP32 |
|---|---|---|---|
| AD71056 de tensión | divisor de tensión | f ∝ V² (constante con o sin carga) | **GPIO21** |
| AD71056 de corriente | shunt | f ∝ I² (0 Hz con la carga apagada) | **GPIO19** |

```
V = √(KV · fV)     I = √(KI · fI)     P = V · I     E = ∫ P dt
```

- **P = V · I solo es válido con carga resistiva (FP ≈ 1).** La placa no mide la potencia activa real.
- **El factor de potencia no se puede medir** con esta configuración; la pantalla muestra "---".
  Mejora futura: un tercer AD71056 en conexión normal, o un chip medidor completo (ATM90E26 / ADE7953).
- El esquemático (PDF) **no coincide** con el PCB fabricado en los pines del ESP32: valen los de esta tabla.

## Pines

| Señal | Placa (ESP32 DevKitC) | Pantalla 7" (VIEWE, header J2) |
|---|---|---|
| Relé de la carga | GPIO18 (HIGH = carga conectada) | — |
| CF tensión | GPIO21 | — |
| CF corriente | GPIO19 | — |
| UART TX → | GPIO17 (J3 pin 2) | pin "18" (RX) |
| UART RX ← | GPIO16 (J3 pin 3) | pin "17" (TX) |
| GND | GND | GND |

No unir 3V3 entre placas: cada una tiene su propia alimentación (pantalla: 5 V ≥ 2 A por USB-C).
Pines libres del J2 de la pantalla: 10, 11, 12, 13, 17, 18, 38. No usar 4–7, 15, 16 (RGB), 19–20 (táctil/USB) ni RX/TX.

## Protocolo UART (115200 baud)

Placa → pantalla, 5 veces por segundo:

```
$VM,<P W>,<E Wh>,<pulsos>,<V>,<I A>,<rele 0/1>*CS
```

V e I valen −1 si no están calibrados. CS = XOR de los caracteres entre `$` y `*`, en hexadecimal.
Pantalla → placa: `$RELE,1*CS` / `$RELE,0*CS`.

## Relé de la carga (v2.3.1)

- Al energizar, la carga queda **apagada** (`RELE_AL_INICIO 0`).
- La pantalla la conecta al iniciar el ensayo y la desconecta al terminar o cancelar.
- Tras conectarla espera 5 s ("Conectando la carga…") antes de aceptar el primer pulso del medidor.
- Si la placa se reinicia en medio de un ensayo, la pantalla reenvía `RELE,1`.
- Seguridad: si el relé queda 10 min encendido, la placa lo apaga sola.
- Si el módulo de relé fuera activo en LOW: `RELE_ACTIVO_ALTO 0`.

## Calibración (una sola vez; queda guardada en la flash)

Monitor Serie a 115200 baud con final de línea "Both NL & CR". Con la carga de ensayo conectada:

1. `1` enciende la carga; esperar ~4 s y `v` para ver las lecturas en vivo (fV y fI > 0).
2. `cv221.5` con la tensión que marca el multímetro.
3. `ci4.35` con la corriente que marca la pinza.
4. `0` apaga la carga. `?` muestra el estado. `scan` busca en qué GPIO llegan pulsos.

Repetir solo si se cambia un componente de medición, se borra toda la flash o se cambia el ESP32.
Las constantes se guardan en Preferences `contrastador` (claves `KV`, `KI`), compatibles con el código de prueba original.

## Problemas encontrados y resueltos

| Problema | Causa | Solución |
|---|---|---|
| No aparecían V ni I y P se disparaba | Firmware con los pines del esquemático (26/25/27) | Pines reales tomados del código de prueba |
| La carga se encendía al energizar | `RELE_AL_INICIO 1` y la pantalla enviaba `RELE,1` al arrancar | Carga solo durante el ensayo (v2.3.1) |
| La pantalla apagaba la carga al calibrar | Forzaba `RELE,0` en reposo cada 0,5 s | Solo fuerza `RELE,1` durante el ensayo |
| fV se iba a 0 al apagar la carga | Canales de tensión y corriente cruzados | V = GPIO21, I = GPIO19 |
| "Comando no reconocido" | Final de línea del Monitor Serie / ruido del cable de la pantalla | Parser tolerante; ignora ruido de la pantalla |

## Pendientes de hardware

- S0, S1 y SCF de ambos AD71056 están unidos solo a condensadores de 10 nF (quedan al aire): conectarlos a VDD o GND, igual en los dos chips.
- Verificar que R7 / R29 (divisor de tensión) sean de 10 MΩ y no de 1 MΩ.
- Seguridad: programar sin 220 V conectados. El lado del AD71056 está vivo (GND_1 = fase).

## Calibración del 22-11-2026 (vigente)

Carga: resistencia de pistola de calor con ventilador (≈ 48,9 Ω, ≈ 1 kW). Medidor de comparación: medidor nuevo clase 1, Kc 1.600 imp/kWh.

| Paso | Corriente calibrada | Error del ensayo con el medidor nuevo |
|---|---|---|
| Calibración inicial con UT201 | 4,46 A | +4,49 % (60 s) |
| Recalibración con UT201 (216 V / 4,69 A) | 4,69 A | +2,80 % |
| Ajuste por comparación (+2,8 %) | 4,82 A | −1,49 %, −1,47 %, −1,30 % (60 s) |
| Ajuste final (−1,42 % promedio) | **4,75 A** | **+0,10 % (60 s), +0,30 % (15 s)** |

- Tensión calibrada con el UNI-T UT201.
- La corriente se ajustó por comparación con el medidor nuevo porque el UT201 es de respuesta media (no true RMS)
  y la corriente de la carga no es sinusoidal (motor del ventilador): con esa carga el UT201 marca de menos.
- Ese medidor queda como referencia; para demostrar la exactitud de VeriMed se usa otro medidor.
- Mejora futura: recalibrar con un instrumento true RMS de 0,5 % o mejor (analizador de energía).
- La placa no acepta `cv`/`ci` si la carga lleva menos de 6 s encendida o si la frecuencia es < 1 Hz
  (un `ci` escrito antes de tiempo con fI = 0,17 Hz dejó la corriente 6,8 veces más alta).
- La pantalla ignora dobles toques del botón PULSO (antes de la mitad del tiempo esperado entre pulsos).
