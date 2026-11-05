# Configuración de la app

## Dependencias (`app/pubspec.yaml`)

| Paquete | Uso |
|---|---|
| `flutter_blue_plus ^2.3.14` | Bluetooth LE (usa `License.nonprofit`: proyecto educativo) |
| `permission_handler ^12.0.2` | Permiso "Dispositivos cercanos" al iniciar |
| `crypto ^3.0.6` | Huella SHA-256 del informe y de la foto |
| `fl_chart` | Gráfico de potencia en vivo |
| `mobile_scanner ^7.4.0` | Escaneo del número de serie (código de barras / QR) |
| `image_picker ^1.2.0` | Foto del medidor |
| `geolocator ^14.1.0`, `geocoding ^5.0.0` | Ubicación GPS y dirección del ensayo |

> Si `flutter_blue_plus` pasa a uso comercial, la librería exige `License.commercial` (de pago).

## Android

`app/android/app/src/main/AndroidManifest.xml` ya incluye: Internet, Bluetooth (`BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT` y los heredados para Android ≤ 11), Cámara y Ubicación.

- Si aparece un error de `minSdk`: en `android/app/build.gradle.kts` → `defaultConfig { minSdk = 24 }`.
- Después de cambiar permisos: `flutter clean`, desinstalar la app del teléfono y volver a instalar.

## iOS (`ios/Runner/Info.plist`)

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>VeriMed BT usa Bluetooth para conectarse al equipo de medición.</string>
<key>NSCameraUsageDescription</key>
<string>VeriMed BT usa la cámara para leer el número de serie y fotografiar el medidor.</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>VeriMed BT registra la ubicación donde se realiza el ensayo.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>VeriMed BT guarda la foto del medidor junto al ensayo.</string>
```

## Archivos que NO se suben

- `app/lib/firebase_options.dart` y `app/android/app/google-services.json`: configuración de Firebase del proyecto.
- Cópialos manualmente en cada computador donde compiles.

## Solución de problemas

| Problema | Causa / solución |
|---|---|
| `Build failed due to use of deleted Android v1 embedding` | Falta `android/app/src/main/AndroidManifest.xml` o le falta `flutterEmbedding = 2`. |
| `adb: failed to install` sin motivo | Cable USB defectuoso, Bloqueador automático de Samsung activo o aviso pendiente en el teléfono. |
| No aparece "VeriMed BT" | Los equipos BLE no aparecen en Ajustes → Bluetooth; buscar desde la app. Revisar que la pantalla diga VISIBLE. |
| No pide permiso de Bluetooth | Falta declararlo en el `AndroidManifest.xml`. |
