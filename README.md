# VeriMed BT
 
Verificador rápido monofásico portátil para medidores de energía, controlado 100% desde una app móvil vía Bluetooth.
 
Proyecto de Título — INACAP, asignatura HIPI02.
 
---
 
## El problema
 
Verificar que un medidor de energía esté midiendo dentro de su margen de error permitido requiere hoy equipos que son caros, o que dependen de teclados y pantallas propias que aumentan el costo de fabricación y los puntos de falla. Las empresas distribuidoras eléctricas medianas y pequeñas necesitan equipar a varios técnicos de terreno sin disparar el presupuesto.
 
**VeriMed BT** propone eliminar el hardware de interfaz: toda la configuración, ejecución del ensayo y lectura de resultados ocurre desde una app móvil, y el equipo se limita a la electrónica de medición.
 
## Cómo funciona
 
1. El equipo se conecta en paralelo al medidor bajo prueba y a una carga de referencia de valor conocido.
2. Un patrón interno (ESP32 + AD71056) compara el conteo de pulsos del medidor contra el valor de referencia.
3. El resultado y el % de error se envían por Bluetooth de baja energía (BLE) a la app móvil, donde el técnico configura el ensayo y revisa los resultados.
```
Medidor bajo prueba ──┐
                       ├── VeriMed BT (ESP32 + AD71056) ──BLE──> App móvil
Carga de referencia ───┘
```
 
## Stack técnico
 
- **Microcontrolador:** ESP32
- **Medición:** AD71056 (medidor de energía monofásico)
- **Comunicación:** Bluetooth Low Energy (BLE)
- **Interfaz:** App móvil (sin teclado ni pantalla propios en el equipo)
## Estado del proyecto
 
- [x] ES1 — Ingeniería conceptual: problemática, alternativas de diseño, selección de alternativa
- [x] ES2 — Ingeniería básica y de detalle: alcance, proveedores, métodos constructivos, ensayos
- [ ] ES3 — Implementación
- [ ] ES4 — Validación y cierre
## Estructura del repositorio
 
```
VeriMed-BT/
├── docs/           Informe de ingeniería y presentaciones (técnica y comercial)
├── firmware/       Código del ESP32
├── app/            Código de la app móvil
├── hardware/       Esquemáticos y diagramas del circuito
└── media/          Fotos y video del prototipo
```
 
## Documentación
 
- [PreeInforme de Proyecto de Título(FORMATIVO)](docs/Informe_Proyecto_de_Titulo.pdf)
- [Presentación técnica](docs/VeriMed_BT_Presentacion.pdf)
- [Presentación comercial](docs/VeriMed_BT_Comercializacion.pdf)
## Equipo
 
- Felipe Martínez
- Tomás Quezada
- Docente guía: Carlos Castillo (HIPI02)
 
## Licencia
 
Este proyecto está bajo la licencia MIT — ver el archivo [LICENSE](LICENSE) para más detalles.
