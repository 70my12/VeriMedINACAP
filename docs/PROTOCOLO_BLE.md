# Protocolo Bluetooth LE — VeriMed BT (v2)

El equipo actúa como **servidor GATT** y se anuncia con el nombre **`VeriMed BT`**.

- Anuncio: flags + nombre (15 bytes). Respuesta de escaneo: UUID del servicio (18 bytes).
- La app filtra los resultados por nombre **o** por UUID del servicio.
- MTU solicitado: 185 (Android pide 512 automáticamente).
- Solo admite una conexión a la vez; mientras hay una app conectada deja de anunciarse.

## Servicio

| Nombre | UUID | Propiedades |
|---|---|---|
| Servicio VeriMed | `7e5a0001-3c1d-4f2b-9a6e-1b2c3d4e5f60` | — |
| MEDICION | `7e5a0002-3c1d-4f2b-9a6e-1b2c3d4e5f60` | READ, NOTIFY |
| COMANDO | `7e5a0003-3c1d-4f2b-9a6e-1b2c3d4e5f60` | WRITE, WRITE NO RESPONSE |
| INFO | `7e5a0004-3c1d-4f2b-9a6e-1b2c3d4e5f60` | READ |

## MEDICION (JSON, cada 0,5 s midiendo / 2 s en reposo)

```json
{"v":220.1,"i":5.20,"p":1121.6,"fp":0.98,"f":50.0,"wh":6.0241,"t":21.6,
 "sim":1,"sp":1,"st":2,"pul":6,"np":10,"kc":1000,"err":-0.350,"apr":1,"alm":0}
```

| Campo | Significado |
|---|---|
| `v`, `i`, `p`, `fp`, `f` | Tensión (V), corriente (A), potencia activa (W), factor de potencia, frecuencia (Hz) |
| `wh` | Energía de referencia del ensayo (Wh) |
| `t` | Duración del ensayo (s) |
| `sim` | 1 = V/I/P simulados (sin PZEM) |
| `sp` | 1 = pulsos del medidor simulados (sin sensor óptico) |
| `st` | 0 reposo · 1 esperando el primer pulso · 2 midiendo · 3 resultado listo |
| `pul`, `np` | Pulsos contados / pulsos objetivo |
| `kc` | Constante del medidor (imp/kWh) |
| `err`, `apr` | Error % y veredicto (1 = aprobado) del último resultado |
| `alm` | Alarmas (bits): 1 sobretensión · 2 tensión baja · 4 sobrecorriente · 8 sin PZEM |

## COMANDO (texto)

| Comando | Acción |
|---|---|
| `INICIAR` | Comienza el ensayo (espera el primer pulso) |
| `DETENER` | Cierra el ensayo; con ≥ 1 pulso entrega resultado parcial, si no, lo cancela |
| `CFG:kc=1000;np=10;cl=1` | Configura Kc, N pulsos y clase (1 = ±1 %, 2 = ±2 %) |

## INFO (JSON)

```json
{"sn":"VMBT-0001","fw":"2.0.0","cal":"Sin calibrar","pzem":0,"sens":0}
```

Número de serie, versión de firmware, fecha de calibración y si el equipo usa PZEM y sensor óptico reales.

## Secuencia de un ensayo desde la app

```
App                                   Equipo
 |-- CFG:kc=1000;np=10;cl=1 --------->|
 |-- INICIAR ------------------------>|  st=1 (espera 1er pulso)
 |<-------- MEDICION (st=2, pul=...) -|  cada 0,5 s
 |<-------- MEDICION (st=3, err, apr)-|  al completar N pulsos
 |  guarda el resultado en el historial y genera el PDF
```
