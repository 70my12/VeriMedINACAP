# Estado del proyecto — noviembre 2026

Resumen de decisiones, datos de ensayo y trabajo hecho en noviembre de 2026, para retomarlo o pasarlo al informe.

## Decisiones

- Se trabaja con **una sola pantalla: la de 7" VIEWE (ESP32-S3)**, versión "normal" (sin funciones Pro).
- La referencia de medición es la **placa propia con 2 × AD71056** (ver [PLACA_MEDICION.md](PLACA_MEDICION.md)); el PZEM-004T queda fuera.
- **El sensor óptico ya no va:** el técnico cuenta los pulsos y el tiempo que indica la app/pantalla.
- Pulsos automáticos según Kc y potencia: `N = floor(t / Tp)`, `Tp = 3,6·10⁶ / (Kc · P)`, tiempo objetivo 15 / 30 / 60 s o manual.
  Ejemplo: Kc 1600 y 1 kW → Tp ≈ 2,25 s → 6 pulsos en ≈ 13,5 s (validado con un técnico de medidores).
- App: rediseño "B · Claro y limpio" con animaciones (`app/lib/verimed_ui.dart`), modo cronómetro manual,
  permisos de ubicación corregidos (manifest con `tools:node="replace"`, sin `maxSdkVersion`).
- Caja: **diseño A (cuña) con correa de hombro**, 260 × 190 × 88 mm, pantalla inclinada 18°, resistencia de carga en
  compartimento ventilado separado por lámina de aluminio. Modelo 3D: [diseno/caja/caja_verimed.html](diseno/caja/caja_verimed.html).

## Datos para el informe (ya disponibles)

| Dato | Valor |
|---|---|
| Instrumento de referencia | UNI-T UT201 (pinza amperimétrica con voltímetro) |
| Carga de ensayo | Resistencia de 48,88 Ω, 4,5 A, ≈ 1.000 W (elemento de pistola de calor con ventilador) |
| Medidor bajo prueba | Lexo DDS608, 220 V, 50 Hz, 10(50) A, Kc 1.600 imp/kWh, clase 1 |
| Ensayo esperado | 1 pulso cada 2,27 s → 6 pulsos en ≈ 13,6 s |
| Alcance Bluetooth | 10 m con obstáculos · 30 m sin obstáculos |
| Resistencia de carga (medidas) | tubo Ø38 × 127 mm, brida Ø60 mm, motor 75 mm |

Nota: 4,5 A está bajo la corriente base del Lexo (10 A); se menciona en el informe.

## Pendiente de medir

1. V, I y P del equipo junto a V e I del UT201 con la carga de 1 kW.
2. Tres ensayos contra el Lexo: pulsos, tiempo, error % y foto de la pantalla.
3. Capturas del PDF y del correo (tapando correo personal y dirección exacta).
4. Consumo del propio equipo en reposo y en ensayo.
5. Fotos del PCB montado y del equipo armado.
6. Confirmar con pie de metro: grosor de la brida y medidas del módulo de pantalla (para la caja).

## Ruta de certificación (resumen)

1. Medir potencia activa real (ATM90E26 / ADE7953 o tercer AD71056) antes de calibrar.
2. Consultar a la SEC (contacto@sec.cl) si el equipo está en el listado de certificación obligatoria.
3. Diseñar según IEC 61010-1 y usar componentes con sello SEC (fuente, cable, entrada de red).
4. Pre-ensayos de seguridad en un laboratorio (rigidez dieléctrica, aislación, fuga, calentamiento).
5. Certificación SEC con un organismo autorizado, si aplica (o autorización de comercialización SEC, sin costo, 18 meses).
6. SUBTEL: desde feb-2026 (Res. Ex. 737/2025) basta declaración de conformidad + informes del módulo ESP32 + QR en el empaque.
7. Calibración trazable en laboratorio acreditado ISO 17025, periódica.
8. Uso oficial: alianza con un laboratorio de verificación autorizado SEC; VeriMed como herramienta de terreno referencial.

Costos: no hay precios publicados; se cotizan con cada organismo/laboratorio.

## Material en este repositorio

| Ruta | Contenido |
|---|---|
| `firmware/verimed7/` | Pantalla 7" v2.3.1 (placa de medición, pulsos automáticos, carga solo en ensayo) |
| `firmware/verimed_placa/` | Placa de medición: V, I, P, relé, calibración, protocolo UART |
| `firmware/verimed_v2/` | Versión CYD 2,8" con pulsos automáticos (ya no es la principal) |
| `app/` | App Flutter con rediseño B, pulsos automáticos, cronómetro manual y permisos GPS |
| `docs/diseno/caja/` | Caja en 3D (4 diseños, 4 manijas, 8 colores) e imágenes |
| `docs/diseno/app/` | Bocetos del rediseño de la app (lienzo de diseño) |
| `docs/web/index.html` | Página web comercial (versión Netlify, formulario Formspree) |
| `docs/costos/VeriMed_BT_Costos.xlsx` | Planilla de costos del equipo |

Fuera del repositorio (no subir): `google-services.json`, `firebase_options.dart`.
