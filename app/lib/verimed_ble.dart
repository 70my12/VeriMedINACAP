// Conexión Bluetooth Low Energy con el equipo VeriMed BT (ESP32 CYD) - protocolo v2.
//
// Debe coincidir con verimed_v2.ino:
//   Servicio  7e5a0001-3c1d-4f2b-9a6e-1b2c3d4e5f60
//   MEDICION  7e5a0002-...  READ + NOTIFY  JSON:
//     {"v","i","p","fp","f","wh","t","sim","sp","st","pul","np","kc","err","apr","alm"}
//     st: 0 reposo, 1 esperando 1er pulso, 2 midiendo, 3 resultado listo
//   COMANDO   7e5a0003-...  WRITE  "INICIAR" | "DETENER" | "CFG:kc=1000;np=10;cl=1"
//   INFO      7e5a0004-...  READ   {"sn","fw","cal","pzem","sens"}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Estados del ensayo en el equipo.
enum EstadoEnsayo { reposo, esperandoPulso, midiendo, resultadoListo }

/// Una lectura enviada por el ESP32.
class VeriMedLectura {
  const VeriMedLectura({
    required this.tension,
    required this.corriente,
    required this.potencia,
    required this.factorPotencia,
    required this.frecuencia,
    required this.energiaWh,
    required this.segundos,
    required this.simulada,
    required this.pulsosSimulados,
    required this.estado,
    required this.pulsos,
    required this.pulsosObjetivo,
    required this.kc,
    required this.errorPct,
    required this.aprobado,
    required this.alarmas,
  });

  final double tension; // V
  final double corriente; // A
  final double potencia; // W
  final double factorPotencia;
  final double frecuencia; // Hz
  final double energiaWh; // energía de referencia del ensayo (Wh)
  final double segundos; // duración del ensayo
  final bool simulada; // V/I/P simulados (sin PZEM)
  final bool pulsosSimulados; // pulsos del medidor simulados (sin sensor óptico)
  final EstadoEnsayo estado;
  final int pulsos; // pulsos contados del medidor
  final int pulsosObjetivo; // N pulsos configurados
  final int kc; // constante del medidor (imp/kWh)
  final double errorPct; // error del último resultado
  final bool aprobado;
  final int alarmas; // bits: 1 sobretensión, 2 subtensión, 4 sobrecorriente, 8 sin PZEM

  bool get midiendo => estado == EstadoEnsayo.esperandoPulso || estado == EstadoEnsayo.midiendo;
  bool get resultadoListo => estado == EstadoEnsayo.resultadoListo;

  String? get textoAlarma {
    if (alarmas == 0) return null;
    if (alarmas & 8 != 0) return 'Sin señal del medidor de referencia (¿hay 220 V?).';
    if (alarmas & 1 != 0) return 'Sobretensión: ${tension.toStringAsFixed(0)} V.';
    if (alarmas & 2 != 0) return 'Tensión baja: ${tension.toStringAsFixed(0)} V.';
    return 'Sobrecorriente: ${corriente.toStringAsFixed(1)} A.';
  }

  static double _num(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
  static int _int(Object? v) => _num(v).round();

  factory VeriMedLectura.fromJson(Map<String, dynamic> j) {
    // Compatibilidad con firmware v1 (campo "run" en vez de "st").
    final st = j.containsKey('st') ? _int(j['st']) : (_int(j['run']) == 1 ? 2 : 0);
    return VeriMedLectura(
      tension: _num(j['v']),
      corriente: _num(j['i']),
      potencia: _num(j['p']),
      factorPotencia: _num(j['fp']),
      frecuencia: _num(j['f']),
      energiaWh: _num(j['wh']),
      segundos: _num(j['t']),
      simulada: _int(j['sim']) == 1,
      pulsosSimulados: j.containsKey('sp') ? _int(j['sp']) == 1 : true,
      estado: EstadoEnsayo.values[st.clamp(0, 3)],
      pulsos: _int(j['pul']),
      pulsosObjetivo: _int(j['np']),
      kc: _int(j['kc']),
      errorPct: _num(j['err']),
      aprobado: _int(j['apr']) == 1,
      alarmas: _int(j['alm']),
    );
  }
}

/// Identificación del equipo (para el informe y la trazabilidad).
class VeriMedInfo {
  const VeriMedInfo({required this.serie, required this.firmware, required this.calibracion, required this.conPzem, required this.conSensor});
  final String serie;
  final String firmware;
  final String calibracion;
  final bool conPzem;
  final bool conSensor;

  factory VeriMedInfo.fromJson(Map<String, dynamic> j) => VeriMedInfo(
        serie: '${j['sn'] ?? '—'}',
        firmware: '${j['fw'] ?? '—'}',
        calibracion: '${j['cal'] ?? '—'}',
        conPzem: '${j['pzem']}' == '1',
        conSensor: '${j['sens']}' == '1',
      );
}

/// Muestra para el gráfico en vivo.
class MuestraEnsayo {
  const MuestraEnsayo(this.segundos, this.potencia, this.tension);
  final double segundos;
  final double potencia;
  final double tension;
}

/// Estado y control de la conexión BLE. Escúchalo con addListener.
class VeriMedBle extends ChangeNotifier {
  static const String nombreEquipo = 'VeriMed BT';
  static final Guid uuidServicio = Guid('7e5a0001-3c1d-4f2b-9a6e-1b2c3d4e5f60');
  static final Guid uuidMedicion = Guid('7e5a0002-3c1d-4f2b-9a6e-1b2c3d4e5f60');
  static final Guid uuidComando = Guid('7e5a0003-3c1d-4f2b-9a6e-1b2c3d4e5f60');
  static final Guid uuidInfo = Guid('7e5a0004-3c1d-4f2b-9a6e-1b2c3d4e5f60');
  static const String _claveUltimo = 'verimed_ultimo_equipo';

  BluetoothAdapterState estadoAdaptador = BluetoothAdapterState.unknown;
  bool buscando = false;
  bool conectando = false;
  bool conectado = false;
  bool soportado = true;
  List<ScanResult> encontrados = [];
  BluetoothDevice? equipo;
  VeriMedLectura? lectura;
  VeriMedInfo? info;
  DateTime? ultimaLectura;
  String? error;
  String? ultimoEquipoId;

  /// Muestras del ensayo en curso (para el gráfico).
  final List<MuestraEnsayo> muestras = [];

  /// Permisos de Bluetooth ("Dispositivos cercanos" en Android 12+).
  bool permisosOk = true;
  bool permisosBloqueados = false;

  /// Se llama cuando el equipo se desconecta sin que el usuario lo pidiera.
  VoidCallback? alPerderConexion;

  BluetoothCharacteristic? _chComando;
  StreamSubscription<BluetoothAdapterState>? _subAdaptador;
  StreamSubscription<bool>? _subBuscando;
  StreamSubscription<List<ScanResult>>? _subResultados;
  StreamSubscription<BluetoothConnectionState>? _subConexion;
  StreamSubscription<List<int>>? _subDatos;
  bool _desconexionPedida = false;
  bool _liberado = false;
  bool _reconexionIntentada = false;

  bool get bluetoothEncendido => estadoAdaptador == BluetoothAdapterState.on;
  String get nombreConectado {
    final d = equipo;
    if (d == null) return nombreEquipo;
    return d.platformName.isNotEmpty ? d.platformName : (d.advName.isNotEmpty ? d.advName : nombreEquipo);
  }

  void _avisar() {
    if (!_liberado) notifyListeners();
  }

  /// Pide los permisos de Bluetooth al usuario (solo Android).
  /// En iPhone el sistema los pide solo la primera vez que se usa Bluetooth.
  Future<bool> pedirPermisos() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      permisosOk = true;
      return true;
    }
    try {
      final estados = await [Permission.bluetoothScan, Permission.bluetoothConnect].request();
      permisosOk = estados.values.every((e) => e.isGranted || e.isLimited);
      permisosBloqueados = estados.values.any((e) => e.isPermanentlyDenied);
    } catch (e) {
      permisosOk = false;
      error = 'No se pudieron pedir los permisos de Bluetooth. Revisa AndroidManifest.xml.';
    }
    if (permisosOk) {
      if (error != null && error!.contains('permiso')) error = null;
    } else {
      error = permisosBloqueados
          ? 'Permiso "Dispositivos cercanos" bloqueado. Actívalo en Ajustes de la app.'
          : 'VeriMed BT necesita el permiso "Dispositivos cercanos" para buscar el equipo.';
    }
    _avisar();
    return permisosOk;
  }

  Future<void> abrirAjustesApp() async {
    await openAppSettings();
  }

  Future<void> iniciar() async {
    await pedirPermisos();
    try {
      soportado = await FlutterBluePlus.isSupported;
    } catch (_) {
      soportado = false;
    }
    if (!soportado) {
      error = 'Este dispositivo no tiene Bluetooth Low Energy.';
      _avisar();
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      ultimoEquipoId = prefs.getString(_claveUltimo);
    } catch (_) {}
    _subAdaptador = FlutterBluePlus.adapterState.listen((s) {
      estadoAdaptador = s;
      if (s != BluetoothAdapterState.on && conectado) _marcarDesconectado(inesperado: true);
      if (s == BluetoothAdapterState.on) reconectarUltimo();
      _avisar();
    });
    _subBuscando = FlutterBluePlus.isScanning.listen((b) {
      buscando = b;
      _avisar();
    });
  }

  /// Intenta conectarse al último equipo usado (una vez por sesión).
  Future<void> reconectarUltimo() async {
    final id = ultimoEquipoId;
    if (_reconexionIntentada || id == null || conectado || conectando || !permisosOk) return;
    _reconexionIntentada = true;
    await conectar(BluetoothDevice.fromId(id), silencioso: true);
  }

  /// Un resultado es un VeriMed si anuncia el servicio o el nombre del equipo.
  static bool esVeriMed(ScanResult r) {
    final ad = r.advertisementData;
    return ad.serviceUuids.contains(uuidServicio) ||
        ad.advName == nombreEquipo ||
        r.device.platformName == nombreEquipo;
  }

  Future<void> encenderBluetooth() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        await FlutterBluePlus.turnOn();
      } else {
        error = 'Activa el Bluetooth desde el Centro de control o Ajustes.';
        _avisar();
      }
    } catch (e) {
      error = 'No se pudo activar el Bluetooth. Actívalo manualmente.';
      _avisar();
    }
  }

  Future<void> buscar({Duration duracion = const Duration(seconds: 12)}) async {
    error = null;
    encontrados = [];
    _avisar();
    if (!soportado) {
      error = 'Este dispositivo no tiene Bluetooth Low Energy.';
      _avisar();
      return;
    }
    if (!permisosOk && !await pedirPermisos()) return;
    if (!bluetoothEncendido) {
      error = 'Activa el Bluetooth del teléfono para buscar el equipo.';
      _avisar();
      return;
    }
    await _subResultados?.cancel();
    _subResultados = FlutterBluePlus.onScanResults.listen((resultados) {
      final lista = resultados.where(esVeriMed).toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
      encontrados = lista;
      _avisar();
    }, onError: (e) {
      error = 'Error al buscar: $e';
      _avisar();
    });
    try {
      // Sin filtro por hardware: el nombre y el servicio viajan en paquetes
      // distintos del anuncio, así que se filtra en la app (esVeriMed).
      await FlutterBluePlus.startScan(timeout: duracion);
    } catch (e) {
      error = _mensajeError(e, 'No se pudo iniciar la búsqueda');
      _avisar();
    }
  }

  Future<void> detenerBusqueda() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
  }

  Future<void> conectar(BluetoothDevice d, {bool silencioso = false}) async {
    if (conectando) return;
    if (!silencioso) error = null;
    conectando = true;
    _desconexionPedida = false;
    _avisar();
    await detenerBusqueda();
    try {
      await _subConexion?.cancel();
      _subConexion = d.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected && conectado && equipo == d) {
          _marcarDesconectado(inesperado: !_desconexionPedida);
        }
      });

      // En Android pide MTU 512 automáticamente (el JSON mide ~170 bytes).
      await d.connect(license: License.nonprofit, timeout: Duration(seconds: silencioso ? 8 : 15));

      final servicios = await d.discoverServices();
      BluetoothCharacteristic? chMedicion;
      BluetoothCharacteristic? chComando;
      BluetoothCharacteristic? chInfo;
      for (final s in servicios) {
        if (s.uuid != uuidServicio) continue;
        for (final c in s.characteristics) {
          if (c.uuid == uuidMedicion) chMedicion = c;
          if (c.uuid == uuidComando) chComando = c;
          if (c.uuid == uuidInfo) chInfo = c;
        }
      }
      if (chMedicion == null || chComando == null) {
        throw StateError('El dispositivo no tiene el servicio VeriMed. ¿Es el equipo correcto?');
      }

      await _subDatos?.cancel();
      _subDatos = chMedicion.onValueReceived.listen(_procesarDatos);
      d.cancelWhenDisconnected(_subDatos!);
      await chMedicion.setNotifyValue(true);
      try {
        _procesarDatos(await chMedicion.read());
      } catch (_) {}
      info = null;
      if (chInfo != null) {
        try {
          final datos = jsonDecode(utf8.decode(await chInfo.read()));
          if (datos is Map<String, dynamic>) info = VeriMedInfo.fromJson(datos);
        } catch (_) {}
      }

      _chComando = chComando;
      equipo = d;
      conectado = true;
      ultimoEquipoId = d.remoteId.str;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_claveUltimo, d.remoteId.str);
      } catch (_) {}
    } catch (e) {
      if (!silencioso) error = _mensajeError(e, 'No se pudo conectar');
      try {
        await d.disconnect();
      } catch (_) {}
      conectado = false;
      equipo = null;
    } finally {
      conectando = false;
      _avisar();
    }
  }

  Future<void> desconectar() async {
    _desconexionPedida = true;
    final d = equipo;
    _marcarDesconectado(inesperado: false);
    if (d != null) {
      try {
        await d.disconnect();
      } catch (_) {}
    }
  }

  /// Envía "INICIAR", "DETENER" o "CFG:..." al ESP32.
  Future<void> enviarComando(String comando) async {
    final c = _chComando;
    if (!conectado || c == null) throw StateError('El equipo no está conectado.');
    await c.write(utf8.encode(comando));
  }

  /// Configura el ensayo en el equipo: constante Kc, N pulsos y clase (1 o 2).
  Future<void> enviarConfiguracion({required int kc, required int pulsos, required int clase}) =>
      enviarComando('CFG:kc=$kc;np=$pulsos;cl=$clase');

  void _procesarDatos(List<int> bytes) {
    if (bytes.isEmpty) return;
    try {
      final datos = jsonDecode(utf8.decode(bytes));
      if (datos is Map<String, dynamic>) {
        final anterior = lectura;
        final l = VeriMedLectura.fromJson(datos);
        if (l.estado == EstadoEnsayo.esperandoPulso && anterior?.estado != EstadoEnsayo.esperandoPulso) {
          muestras.clear();
        }
        if (l.estado == EstadoEnsayo.midiendo) {
          muestras.add(MuestraEnsayo(l.segundos, l.potencia, l.tension));
          if (muestras.length > 600) muestras.removeAt(0);
        }
        lectura = l;
        ultimaLectura = DateTime.now();
        _avisar();
      }
    } catch (_) {
      // Paquete incompleto (MTU pequeño) o dañado: se ignora y llega el siguiente.
    }
  }

  void _marcarDesconectado({required bool inesperado}) {
    final estabaConectado = conectado;
    conectado = false;
    equipo = null;
    _chComando = null;
    _subDatos?.cancel();
    _subDatos = null;
    _avisar();
    if (inesperado && estabaConectado) alPerderConexion?.call();
  }

  String _mensajeError(Object e, String prefijo) {
    final txt = e.toString();
    if (txt.contains('permission') || txt.contains('Permission')) {
      return '$prefijo: faltan permisos de Bluetooth. Acéptalos en Ajustes > Aplicaciones > VeriMed BT.';
    }
    if (txt.contains('Location') || txt.contains('location')) {
      return '$prefijo: activa la Ubicación del teléfono (Android la exige para buscar dispositivos).';
    }
    if (e is StateError) return e.message;
    if (txt.contains('Timed out') || txt.contains('timeout')) {
      return '$prefijo: el equipo no respondió. Acércate y revisa que en la pantalla diga VISIBLE.';
    }
    return '$prefijo. ($txt)';
  }

  @override
  void dispose() {
    _liberado = true;
    _subAdaptador?.cancel();
    _subBuscando?.cancel();
    _subResultados?.cancel();
    _subConexion?.cancel();
    _subDatos?.cancel();
    equipo?.disconnect();
    super.dispose();
  }
}
