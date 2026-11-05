// VeriMed BT - Escaneo del número de serie y foto del medidor con ubicación GPS.
//
// - EscanerSerieScreen: lee el código de barras / QR de la placa del medidor.
// - tomarFotoConUbicacion(): toma la foto del medidor y registra dónde y cuándo
//   se hizo el ensayo (coordenadas, precisión y dirección aproximada).

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';

// ======================================================================
//  Foto + ubicación
// ======================================================================

class CapturaTerreno {
  const CapturaTerreno({
    required this.fotoPath,
    required this.fotoBytes,
    required this.fotoSha256,
    required this.fecha,
    this.latitud,
    this.longitud,
    this.precisionM,
    this.direccion,
    this.avisoUbicacion,
  });

  final String fotoPath; // copia guardada en la carpeta de la app
  final Uint8List fotoBytes;
  final String fotoSha256; // huella de la foto (detecta si se reemplaza)
  final DateTime fecha;
  final double? latitud;
  final double? longitud;
  final double? precisionM; // radio de precisión del GPS en metros
  final String? direccion; // dirección aproximada (requiere internet)
  final String? avisoUbicacion; // por qué no hay ubicación, si falta

  bool get tieneUbicacion => latitud != null && longitud != null;
  String get coordenadas =>
      tieneUbicacion ? '${latitud!.toStringAsFixed(6)}, ${longitud!.toStringAsFixed(6)}' : 'No disponible';
  String get precisionTexto => precisionM == null ? '' : '±${precisionM!.toStringAsFixed(0)} m';
  String get enlaceMapa => 'https://www.google.com/maps?q=${latitud ?? 0},${longitud ?? 0}';
  String get fechaTexto =>
      '${_2(fecha.day)}/${_2(fecha.month)}/${fecha.year} ${_2(fecha.hour)}:${_2(fecha.minute)}';

  static String _2(int n) => n.toString().padLeft(2, '0');

  /// Campos que se guardan en cada ensayo del historial.
  Map<String, dynamic> aRegistro() => {
        'photoPath': fotoPath,
        'photoSha256': fotoSha256,
        'photoDate': fecha.toIso8601String(),
        'lat': latitud,
        'lon': longitud,
        'gpsAccuracy': precisionM,
        'address': direccion ?? (tieneUbicacion ? coordenadas : 'Sin ubicación'),
      };
}

/// Pide el permiso de ubicación. Devuelve null si todo está bien, o el motivo.
Future<String?> asegurarPermisoUbicacion() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return 'La ubicación (GPS) del teléfono está apagada.';
    }
    var permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) permiso = await Geolocator.requestPermission();
    if (permiso == LocationPermission.denied) return 'Permiso de ubicación rechazado.';
    if (permiso == LocationPermission.deniedForever) {
      return 'Permiso de ubicación bloqueado: actívalo en Ajustes de la app.';
    }
    return null;
  } catch (e) {
    return 'No se pudo revisar el permiso de ubicación.';
  }
}

/// Obtiene la posición actual (máx. 20 s); si falla, usa la última conocida.
Future<(Position?, String?)> _posicionActual() async {
  try {
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
    return (p, null);
  } catch (_) {
    try {
      final ultima = await Geolocator.getLastKnownPosition();
      if (ultima != null) return (ultima, 'Ubicación aproximada (última posición conocida).');
    } catch (_) {}
    return (null, 'No se pudo obtener la ubicación (sin señal GPS).');
  }
}

/// Dirección aproximada a partir de las coordenadas (necesita internet).
Future<String?> direccionDe(double latitud, double longitud) async {
  try {
    final lugares = await Geocoding(locale: const Locale('es', 'CL')).placemarkFromCoordinates(latitud, longitud);
    if (lugares.isEmpty) return null;
    final p = lugares.first;
    final calle = (p.thoroughfare != null && p.thoroughfare!.isNotEmpty)
        ? [p.thoroughfare, p.subThoroughfare].where((e) => e != null && e.isNotEmpty).join(' ')
        : (p.street ?? '');
    final partes = <String>[];
    for (final parte in [calle, p.subLocality, p.locality, p.administrativeArea]) {
      final t = (parte ?? '').trim();
      if (t.isNotEmpty && !partes.contains(t)) partes.add(t);
    }
    return partes.isEmpty ? null : partes.join(', ');
  } catch (_) {
    return null;
  }
}

/// Toma la foto del medidor y registra la ubicación del ensayo.
/// Devuelve null si el usuario cancela la cámara.
Future<CapturaTerreno?> tomarFotoConUbicacion() async {
  // 1. Permiso de ubicación primero (para que el diálogo no tape la cámara).
  final avisoPermiso = await asegurarPermisoUbicacion();
  // 2. El GPS empieza a buscar mientras el técnico toma la foto.
  final Future<(Position?, String?)> futuraPosicion =
      avisoPermiso == null ? _posicionActual() : Future.value((null, avisoPermiso));

  final XFile? foto = await ImagePicker().pickImage(
    source: ImageSource.camera,
    maxWidth: 1600,
    imageQuality: 75,
  );
  if (foto == null) {
    unawaited(futuraPosicion.then((_) {}));
    return null;
  }

  final ahora = DateTime.now();
  final bytes = await foto.readAsBytes();
  // 3. Copia la foto a la carpeta de la app (la de la cámara es temporal).
  String ruta = foto.path;
  try {
    final docs = await getApplicationDocumentsDirectory();
    final carpeta = Directory('${docs.path}/fotos_ensayos');
    await carpeta.create(recursive: true);
    final destino = File('${carpeta.path}/medidor_${ahora.millisecondsSinceEpoch}.jpg');
    await destino.writeAsBytes(bytes, flush: true);
    ruta = destino.path;
  } catch (_) {}

  final (posicion, aviso) = await futuraPosicion;
  String? direccion;
  if (posicion != null) direccion = await direccionDe(posicion.latitude, posicion.longitude);

  return CapturaTerreno(
    fotoPath: ruta,
    fotoBytes: bytes,
    fotoSha256: sha256.convert(bytes).toString(),
    fecha: ahora,
    latitud: posicion?.latitude,
    longitud: posicion?.longitude,
    precisionM: posicion?.accuracy,
    direccion: direccion,
    avisoUbicacion: aviso,
  );
}

/// Abre los ajustes de ubicación o de la app (si el permiso quedó bloqueado).
Future<void> abrirAjustesUbicacion({required bool permisoBloqueado}) async {
  if (permisoBloqueado) {
    await Geolocator.openAppSettings();
  } else {
    await Geolocator.openLocationSettings();
  }
}

// ======================================================================
//  Escáner del número de serie
// ======================================================================

/// Pantalla que lee el código de barras o QR de la placa del medidor.
/// Devuelve el texto leído con Navigator.pop.
class EscanerSerieScreen extends StatefulWidget {
  const EscanerSerieScreen({super.key});

  @override
  State<EscanerSerieScreen> createState() => _EscanerSerieScreenState();
}

class _EscanerSerieScreenState extends State<EscanerSerieScreen> {
  final MobileScannerController _controlador = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _leido = false;
  bool _linterna = false;

  void _alDetectar(BarcodeCapture captura) {
    if (_leido) return;
    for (final codigo in captura.barcodes) {
      final valor = (codigo.rawValue ?? codigo.displayValue ?? '').trim();
      if (valor.isNotEmpty) {
        _leido = true;
        Navigator.of(context).pop(valor);
        return;
      }
    }
  }

  @override
  void dispose() {
    unawaited(_controlador.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.of(context).size.width * 0.8;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Escanear número de serie'),
        actions: [
          IconButton(
            tooltip: 'Linterna',
            icon: Icon(_linterna ? Icons.flash_on_rounded : Icons.flash_off_rounded),
            onPressed: () async {
              await _controlador.toggleTorch();
              if (mounted) setState(() => _linterna = !_linterna);
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controlador,
            onDetect: _alDetectar,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No se pudo abrir la cámara (${error.errorCode.name}).\n'
                  'Revisa el permiso de Cámara de la app en Ajustes.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          // Marco guía
          Center(
            child: Container(
              width: ancho,
              height: ancho * 0.55,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 40,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
              child: const Text(
                'Apunta al código de barras o QR de la placa del medidor.\n'
                'Si no tiene código, vuelve y escribe el número a mano.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, height: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
