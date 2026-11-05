# Hardware — qué comprar y cómo conectarlo

Con solo el ESP32-2432S028 y la app, todo funciona en **modo simulación**. Para mediciones reales:

## Imprescindible

| Componente | Para qué | Firmware |
|---|---|---|
| **PZEM-004T v3.0 (100 A)**, ideal con transformador de núcleo partido | Medidor de referencia: V, I, P, FP y frecuencia por UART (≈ ±0,5 %) | `USAR_PZEM 1` + librería `PZEM-004T-v30` (Jakub Mandula) |
| **Sensor óptico** con fotodiodo/fototransistor y comparador **LM393**, salida digital `DO` | Contar los pulsos del LED "imp/kWh" del medidor. **Evitar el de LDR** (lento, pierde pulsos) | `USAR_SENSOR_PULSOS 1` |
| 2 cables **Molex PicoBlade 1,25 mm, 4 pines** + cables dupont | Conectores CN1 y P3 del CYD | — |
| Cinta negra / tubito opaco / soporte con ventosa | Aislar el sensor de la luz ambiente | — |

## Banco de ensayo (220 V) — con supervisión del laboratorio

- Carga resistiva de 1–2 kW (hervidor, estufa o banco de ampolletas).
- Fusible y portafusible, interruptor, terminales, cable de 2,5 mm² y caja ABS cerrada.

## Opcional

- Parlante 8 Ω 1–2 W con conector de 1,25 mm y 2 pines (conector P4).
- Batería: power bank USB-C, o 18650 + TP4056 con protección + elevador MT3608 a 5 V.
- Caja impresa en 3D.

## Conexiones en el CYD

| Conector CYD | Pin | Va a |
|---|---|---|
| **CN1** | GND | GND del PZEM |
| CN1 | IO22 | RX del PZEM (ESP32 transmite) |
| CN1 | IO27 | TX del PZEM (ESP32 recibe) |
| CN1 | 3.3V | 5V del PZEM (funciona a 3,3 V en el lado TTL) y VCC del sensor |
| **P3** | GND | GND del sensor |
| P3 | IO35 | `DO` del sensor (solo entrada, sin pull-up interno) |
| P3 | IO21 | **No usar**: es la retroiluminación de la pantalla |
| **P4** | — | Parlante (opcional) |

LED RGB de la placa: azul = esperando pulso · verde = aprobado · rojo = rechazado o alarma.

## Montaje del ensayo

```
Red 220 V → fusible → interruptor → MEDIDOR BAJO PRUEBA → carga
                                        ↑ sensor óptico sobre su LED
PZEM: bornes de tensión en paralelo a la red;
      transformador de corriente abrazando la fase que va a la carga.
```

La misma corriente circula por el medidor bajo prueba y por el PZEM, por eso se pueden comparar.

## Paso a paso al recibir los componentes

1. Instala la librería `PZEM-004T-v30`.
2. Prueba con `firmware/verimed_diagnostico`: el PZEM debe decir **RESPONDE** y la "potencia según pulsos" debe parecerse a la del PZEM.
3. En el módulo LM393 ajusta el potenciómetro hasta que su LED parpadee junto con el LED del medidor. Si cuenta mal, cambia `FLANCO_PULSO` a `RISING`.
4. En `verimed_v2`: `USAR_PZEM 1` y `USAR_SENSOR_PULSOS 1`.
5. Primer ensayo con carga fija y 10 pulsos.
6. Calibra contra un medidor patrón y anota la fecha en `FECHA_CAL` (aparece en el informe PDF).

## Nota sobre el AD71056

El AD71056 solo entrega **pulsos de energía (CF)**: no informa tensión, corriente ni factor de potencia. Por eso el diseño actual usa el PZEM-004T. Si el proyecto debe usar el AD71056, se puede leer su salida CF en un pin libre, pero se pierden las lecturas de V, I y FP en pantalla.
