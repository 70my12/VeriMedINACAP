import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'package:fl_chart/fl_chart.dart';
import 'verimed_ble.dart';
import 'verimed_captura.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Object? firebaseInitError;
  try {
    // En Android toma la configuración de android/app/google-services.json.
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (error) {
    firebaseInitError = error;
  }
  runApp(VeriMedApp(firebaseInitError: firebaseInitError));
}

const Color vmNavy = Color(0xFF0B2545);
const Color vmBlue = Color(0xFF1E6FD9);
const Color vmInk = Color(0xFF0B2545);
const Color vmMuted = Color(0xFF6B7788);
const Color vmBackground = Color(0xFFEEF3F8);
const Color vmGreen = Color(0xFF12B886);
const Color vmYellow = Color(0xFFFFC233);
const Color vmRed = Color(0xFFE5484D);
const Color vmBorder = Color(0xFFD0D9E4);

// Configurar con la URL HTTPS de un backend propio que envíe correo.
// Nunca guardar claves SMTP/API dentro de la app móvil.
const String veriMedEmailEndpoint = 'https://script.google.com/macros/s/AKfycbyQvjf5Oz5nqZqSJHJB-sbwdkKYN5KFyquiaWMRSNaVIbjvNQG0VxiWPHke_QyQE5dL/exec';

class MyApp extends VeriMedApp {
  const MyApp({super.key});
}

class VeriMedApp extends StatelessWidget {
  const VeriMedApp({super.key, this.firebaseInitError});

  final Object? firebaseInitError;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VeriMed BT',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: vmBackground,
        colorScheme: ColorScheme.fromSeed(
          seedColor: vmNavy,
          primary: vmNavy,
          secondary: vmGreen,
          tertiary: vmYellow,
          surface: Colors.white,
        ),
        // Respuestas visuales consistentes y transiciones más suaves.
        splashFactory: InkRipple.splashFactory,
        pageTransitionsTheme: PageTransitionsTheme(
          builders: {
            TargetPlatform.android: ZoomPageTransitionsBuilder(),
            TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
            TargetPlatform.linux: ZoomPageTransitionsBuilder(),
            TargetPlatform.macOS: ZoomPageTransitionsBuilder(),
            TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          },
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: ButtonStyle(
            animationDuration: const Duration(milliseconds: 180),
            overlayColor: WidgetStatePropertyAll(vmBlue.withOpacity(0.10)),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ButtonStyle(
            animationDuration: const Duration(milliseconds: 180),
            overlayColor: WidgetStatePropertyAll(vmBlue.withOpacity(0.10)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: ButtonStyle(
            animationDuration: const Duration(milliseconds: 180),
            overlayColor: WidgetStatePropertyAll(vmBlue.withOpacity(0.08)),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: ButtonStyle(
            animationDuration: const Duration(milliseconds: 180),
            overlayColor: WidgetStatePropertyAll(vmBlue.withOpacity(0.08)),
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: ButtonStyle(
            animationDuration: const Duration(milliseconds: 180),
            overlayColor: WidgetStatePropertyAll(vmBlue.withOpacity(0.08)),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: vmNavy,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          surfaceTintColor: vmNavy,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: vmNavy,
          indicatorColor: vmBlue,
          iconTheme: const WidgetStatePropertyAll(IconThemeData(color: Colors.white)),
          labelTextStyle: const WidgetStatePropertyAll(TextStyle(color: Colors.white, fontSize: 11)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFEEF3F8),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: vmBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: vmBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: vmBlue, width: 1.5),
          ),
        ),
      ),
      home: firebaseInitError == null
          ? const VeriMedAuthGate()
          : FirebaseSetupRequiredScreen(error: firebaseInitError.toString()),
    );
  }
}

class VeriMedAuthGate extends StatelessWidget {
  const VeriMedAuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return FirebaseSetupRequiredScreen(error: snapshot.error.toString());
        }
        final user = snapshot.data;
        if (user == null) return const VeriMedLoginScreen();
        if (!user.emailVerified) return VeriMedVerifyEmailScreen(user: user);
        return const VeriMedHome();
      },
    );
  }
}

class FirebaseSetupRequiredScreen extends StatelessWidget {
  const FirebaseSetupRequiredScreen({super.key, required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _Brand(),
                  const SizedBox(height: 24),
                  const Icon(Icons.cloud_off_rounded, size: 54, color: vmBlue),
                  const SizedBox(height: 16),
                  const Text('Falta configurar Firebase', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: vmInk), textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  const Text('La autenticación real necesita el archivo google-services.json y Firebase Authentication habilitado en tu proyecto.', textAlign: TextAlign.center, style: TextStyle(color: vmMuted)),
                  const SizedBox(height: 14),
                  Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: vmBorder)), child: SelectableText(error, style: const TextStyle(fontSize: 12, color: vmMuted))),
                  const SizedBox(height: 14),
                  const Text('Configura Firebase y vuelve a ejecutar flutter run. Esta pantalla evita que la app falle sin explicar el motivo.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: vmMuted)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class VeriMedVerifyEmailScreen extends StatefulWidget {
  const VeriMedVerifyEmailScreen({super.key, required this.user});
  final User user;

  @override
  State<VeriMedVerifyEmailScreen> createState() => _VeriMedVerifyEmailScreenState();
}

class _VeriMedVerifyEmailScreenState extends State<VeriMedVerifyEmailScreen> {
  bool _busy = false;
  String? _message;

  Future<void> _resend() async {
    setState(() { _busy = true; _message = null; });
    try {
      await FirebaseAuth.instance.setLanguageCode('es');
      await widget.user.sendEmailVerification();
      if (mounted) setState(() => _message = 'Correo de verificación enviado. Revisa también la carpeta de spam.');
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _message = e.code == 'too-many-requests' ? 'Espera un momento antes de solicitar otro correo.' : 'No se pudo enviar el correo. Inténtalo de nuevo más tarde.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkVerified() async {
    setState(() { _busy = true; _message = null; });
    try {
      await widget.user.reload();
      final refreshed = FirebaseAuth.instance.currentUser;
      if (refreshed != null && refreshed.emailVerified) {
        // El flujo de autenticación escucha el cambio y abre la aplicación.
        if (mounted) setState(() => _message = 'Correo verificado. Abriendo VeriMed BT…');
      } else if (mounted) {
        setState(() => _message = 'Todavía no aparece como verificado. Abre el enlace del correo y vuelve a comprobar.');
      }
    } catch (_) {
      if (mounted) setState(() => _message = 'No se pudo comprobar la verificación. Revisa tu conexión.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: Image.asset('assets/verimed_logo_horizontal.png', width: 330, fit: BoxFit.contain)),
                  const SizedBox(height: 30),
                  const Icon(Icons.mark_email_read_outlined, color: vmBlue, size: 64),
                  const SizedBox(height: 18),
                  const Text('Verifica tu correo', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: vmInk)),
                  const SizedBox(height: 10),
                  Text('Enviamos un enlace a ${widget.user.email ?? 'tu correo'}. Debes verificar la dirección antes de entrar a VeriMed BT.', textAlign: TextAlign.center, style: const TextStyle(color: vmMuted, height: 1.45)),
                  const SizedBox(height: 24),
                  SizedBox(height: 50, child: FilledButton.icon(onPressed: _busy ? null : _checkVerified, icon: const Icon(Icons.verified_outlined), label: Text(_busy ? 'Comprobando…' : 'Ya verifiqué mi correo'))),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(onPressed: _busy ? null : _resend, icon: const Icon(Icons.forward_to_inbox_outlined), label: const Text('Reenviar correo')),
                  if (_message != null) ...[const SizedBox(height: 12), Text(_message!, textAlign: TextAlign.center, style: const TextStyle(color: vmMuted))],
                  const SizedBox(height: 12),
                  TextButton(onPressed: _busy ? null : () => FirebaseAuth.instance.signOut(), child: const Text('Cerrar sesión')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class VeriMedLoginScreen extends StatefulWidget {
  const VeriMedLoginScreen({super.key});

  @override
  State<VeriMedLoginScreen> createState() => _VeriMedLoginScreenState();
}

class _VeriMedLoginScreenState extends State<VeriMedLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _isRegister = false;
  bool _showPassword = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String _friendlyError(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-email': return 'El correo electrónico no tiene un formato válido.';
        case 'user-disabled': return 'Esta cuenta ha sido deshabilitada.';
        case 'user-not-found': return 'No existe una cuenta con ese correo.';
        case 'wrong-password':
        case 'invalid-credential': return 'El correo o la contraseña son incorrectos.';
        case 'email-already-in-use': return 'Ya existe una cuenta con ese correo.';
        case 'weak-password': return 'Usa una contraseña de al menos 6 caracteres.';
        case 'network-request-failed': return 'No hay conexión. Comprueba tu internet e inténtalo de nuevo.';
        case 'too-many-requests': return 'Hubo demasiados intentos. Espera un momento e inténtalo nuevamente.';
        case 'operation-not-allowed': return 'Activa Email/contraseña en Firebase Console > Authentication > Sign-in method.';
      }
    }
    return 'No se pudo completar la operación. Revisa la configuración de Firebase e inténtalo de nuevo.';
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    try {
      if (_isRegister) {
        await FirebaseAuth.instance.setLanguageCode('es');
        final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
        await credential.user?.sendEmailVerification();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cuenta creada. Enviamos un correo para verificar tu dirección.')));
        }
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Escribe tu correo en el campo correspondiente para recuperar la contraseña.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await FirebaseAuth.instance.setLanguageCode('es');
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Si el correo está registrado, recibirás instrucciones para restablecer la contraseña.')));
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: Image.asset('assets/verimed_logo_horizontal.png', width: 330, fit: BoxFit.contain)),
                    const SizedBox(height: 28),
                    Container(width: 76, height: 76, alignment: Alignment.center, decoration: BoxDecoration(color: vmBlue.withOpacity(.09), borderRadius: BorderRadius.circular(24)), child: const Icon(Icons.electric_meter_rounded, color: vmBlue, size: 42)),
                    const SizedBox(height: 22),
                    Text(_isRegister ? 'Crea tu cuenta' : 'Bienvenido a VeriMed BT', style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800, color: vmInk), textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text(_isRegister ? 'Regístrate para comenzar a utilizar la aplicación.' : 'Inicia sesión para acceder a tus herramientas de verificación.', style: const TextStyle(color: vmMuted, height: 1.4), textAlign: TextAlign.center),
                    const SizedBox(height: 28),
                    const _FieldLabel('Correo electrónico'),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.username, AutofillHints.email],
                      decoration: const InputDecoration(hintText: 'nombre@ejemplo.com', prefixIcon: Icon(Icons.email_outlined)),
                      validator: (value) {
                        final v = (value ?? '').trim();
                        if (v.isEmpty || !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v)) return 'Ingresa un correo electrónico válido.';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    const _FieldLabel('Contraseña'),
                    TextFormField(
                      controller: _password,
                      obscureText: !_showPassword,
                      textInputAction: TextInputAction.done,
                      autofillHints: _isRegister ? const [AutofillHints.newPassword] : const [AutofillHints.password],
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(hintText: _isRegister ? 'Mínimo 6 caracteres' : 'Tu contraseña', prefixIcon: const Icon(Icons.lock_outline_rounded), suffixIcon: IconButton(tooltip: _showPassword ? 'Ocultar contraseña' : 'Mostrar contraseña', onPressed: () => setState(() => _showPassword = !_showPassword), icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined))),
                      validator: (value) {
                        final v = value ?? '';
                        if (v.isEmpty) return 'Ingresa tu contraseña.';
                        if (_isRegister && v.length < 6) return 'Usa al menos 6 caracteres.';
                        return null;
                      },
                    ),
                    if (!_isRegister) Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _busy ? null : _resetPassword, child: const Text('¿Olvidaste tu contraseña?'))),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: vmRed.withOpacity(.08), borderRadius: BorderRadius.circular(12)), child: Text(_error!, style: const TextStyle(color: vmRed))),
                    ],
                    const SizedBox(height: 14),
                    SizedBox(height: 52, child: FilledButton.icon(onPressed: _busy ? null : _submit, icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Icon(_isRegister ? Icons.person_add_alt_1_rounded : Icons.login_rounded), label: Text(_busy ? 'Procesando…' : (_isRegister ? 'Crear cuenta' : 'Iniciar sesión')))),
                    const SizedBox(height: 12),
                    TextButton(onPressed: _busy ? null : () => setState(() { _isRegister = !_isRegister; _error = null; }), child: Text(_isRegister ? '¿Ya tienes cuenta? Inicia sesión' : '¿No tienes cuenta? Regístrate')),
                    const SizedBox(height: 18),
                    const _DemoNotice(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class VeriMedHome extends StatefulWidget {
  const VeriMedHome({super.key});

  @override
  State<VeriMedHome> createState() => _VeriMedHomeState();
}

class _VeriMedHomeState extends State<VeriMedHome> {
  int _selectedTab = 0;
  // Conexión real con el equipo VeriMed BT (ESP32) por Bluetooth LE.
  final VeriMedBle _ble = VeriMedBle();
  bool get _connected => _ble.conectado;
  DateTime _sinSyncHasta = DateTime.fromMillisecondsSinceEpoch(0);
  bool _equipoMidiendoAntes = false;
  // Energía y tiempo de referencia medidos por el equipo en el último ensayo.
  double? _medidoWh;
  double? _medidoSegundos;
  bool _medicionSimulada = true;
  bool _pulsosAutomaticos = false; // último ensayo con sensor óptico real
  bool _esperandoResultado = false; // se pidió DETENER y se espera el resultado del equipo
  CapturaTerreno? _captura; // foto del medidor + ubicación del ensayo
  bool _tomandoFoto = false;
  bool _testRunning = false;
  bool _testFinished = false;
  DateTime? _testStartedAt;
  double _lastTestDurationSeconds = _demoDurationSeconds;

  final TextEditingController _meterSerial = TextEditingController();
  final TextEditingController _kc = TextEditingController(text: '1000');
  final TextEditingController _pulseCount = TextEditingController(text: '6');
  final TextEditingController _technician = TextEditingController();
  final TextEditingController _reportEmail = TextEditingController();
  bool _sendingReport = false;
  String _accuracyClass = 'Clase 1';
  String _selectedMeterModel = '';

  // Historial local persistente: se conserva al cerrar y volver a abrir la app.
  final List<Map<String, dynamic>> _testHistory = [];
  bool _historyLoaded = false;
  String _historySearch = '';

  // Solo valor inicial de la interfaz; los ensayos usan el tiempo medido por el equipo.
  static const double _demoDurationSeconds = 0;

  double? get _kcValue => double.tryParse(_kc.text.trim().replaceAll(',', '.'));
  int? get _pulseValue => int.tryParse(_pulseCount.text.trim());
  // Energía de referencia = energía integrada por el ESP32 durante el ensayo.
  double get _referenceEnergyWh => _medidoWh ?? 0;
  double get _referencePowerW {
    final wh = _medidoWh, t = _medidoSegundos;
    if (wh == null || t == null || t <= 0) return 0;
    return wh * 3600.0 / t;
  }
  double? get _meterEnergyWh {
    final kc = _kcValue;
    final pulses = _pulseValue;
    if (kc == null || kc <= 0 || pulses == null || pulses < 0) return null;
    return pulses * 1000.0 / kc;
  }
  double? get _calculatedErrorPct {
    final meterEnergy = _meterEnergyWh;
    final referenceEnergy = _referenceEnergyWh;
    if (meterEnergy == null || referenceEnergy <= 0) return null;
    return ((meterEnergy - referenceEnergy) / referenceEnergy) * 100.0;
  }
  double get _acceptanceLimitPct => _accuracyClass == 'Clase 1' ? 1.0 : 2.0;
  String get _calculatedVerdict {
    final error = _calculatedErrorPct;
    if (error == null) return 'Datos inválidos';
    return error.abs() <= _acceptanceLimitPct ? 'Dentro del límite ilustrativo' : 'Fuera del límite ilustrativo';
  }
  // Catálogo inicial ampliado. Las fichas se muestran solo cuando
  // existen datos de referencia; siempre se deben validar contra la placa.
  final List<String> _meterModels = [
    'Hexing HXE110',
    'Hexing HXE115-KP',
    'Hexing HXE12DL',
    'Hexing HXE12-ES',
    'Hexing HXE130 (variante por confirmar)',
    'Landis+Gyr E150',
    'Landis+Gyr E430 (variante por confirmar)',
    'Landis+Gyr 5254F (variante por confirmar)',
    'Itron CENTRON II (variante por confirmar)',
    'Itron ACE (modelo por especificar)',
    'Elster / Honeywell (modelo por especificar)',
    'Iskraemeco (modelo por especificar)',
    'Schneider Electric (modelo por especificar)',
    'Medidor digital monofásico (modelo genérico)',
    'Medidor electromecánico monofásico (modelo genérico)',
    'Medidor inteligente monofásico (modelo genérico)',
  ];

  final Map<String, Map<String, String>> _meterSpecs = {
    'Hexing HXE110': {
      'Tipo': 'Monofásico, conexión directa, 1P2W',
      'Tensión nominal': '127 / 220 / 230 / 240 V (según versión)',
      'Corriente': '0,15–5 A con Imax 60 / 80 / 100 A; depende de la variante',
      'Frecuencia': '50 Hz ±5%',
      'Clase de energía activa': 'Clase 1 o clase B, según norma/versión',
      'Constante de pulso': '1000 imp/kWh (confirmar en placa/configuración)',
      'Comunicación': 'DLMS/COSEM; opciones de comunicación según módulo',
      'Nota técnica': 'Confirmar código completo, corriente máxima y constante en la placa.',
    },
    'Hexing HXE115-KP': {
      'Tipo': 'Monofásico prepago, conexión directa, 1P2W',
      'Tensión nominal': '127–240 V (según versión)',
      'Corriente': '0,15–5 A con Imax 60 / 80 A, o 0,3–10 A con Imax 60 / 80 A',
      'Frecuencia': '50 Hz ±5%',
      'Clase de energía activa': 'Clase 1 (IEC)',
      'Constante de pulso': '1000 imp/kWh (confirmar en placa/configuración)',
      'Comunicación': 'DLMS/COSEM; funciones de prepago',
      'Nota técnica': 'Confirmar variante y datos de placa antes de configurar el ensayo.',
    },
    'Hexing HXE12DL': {
      'Tipo': 'Monofásico, conexión directa',
      'Tensión nominal': '120–240 V',
      'Corriente base': '5 A',
      'Corriente máxima': '60 A o 100 A, según variante',
      'Frecuencia': '50 / 60 Hz',
      'Clase de energía activa': 'Clase 1',
      'Constante de pulso': 'Revisar placa o ficha de la variante',
      'Comunicación': 'Puerto óptico IEC 62056-21; RS-485 opcional',
      'Nota técnica': 'Los valores de corriente dependen de la versión exacta.',
    },
    'Hexing HXE12-ES': {
      'Tipo': 'Monofásico estático; conexión directa',
      'Tensión nominal': '220 V (ficha publicada)',
      'Corriente base / máxima': '5 A / 60 A',
      'Frecuencia': 'La ficha consultada indica 60 Hz ±2%',
      'Clase de energía activa': 'Clase 1',
      'Constante de pulso': 'Revisar placa o ficha de la variante',
      'Comunicación': 'Salida de pulsos óptica/eléctrica y pantalla LCD',
      'Nota técnica': 'Verificar compatibilidad con red de 50 Hz y variante instalada.',
    },
    'Landis+Gyr E150': {
      'Tipo': 'Monofásico estático, 1 fase / 2 hilos',
      'Tensión nominal': '240 V fase-neutro',
      'Corriente': 'Versiones 5–20 A, 5–30 A o 10–60 A',
      'Frecuencia': '50 Hz',
      'Clase de energía activa': 'Clase 1.0',
      'Constante de pulso': 'Confirmar en placa/configuración de la unidad',
      'Funciones': 'Registro de energía y parámetros de demanda',
      'Nota técnica': 'Confirmar el rango de corriente exacto de la unidad bajo prueba.',
    },
  };

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _ble.alPerderConexion = _alPerderConexion;
    _ble.addListener(_onBle);
    _ble.iniciar();
  }

  // Se ejecuta cada vez que cambia algo del Bluetooth o llega una lectura.
  void _onBle() {
    if (!mounted) return;
    final lectura = _ble.lectura;
    final equipoMidiendo = _ble.conectado && (lectura?.midiendo ?? false);
    final sincronizar = _ble.conectado && DateTime.now().isAfter(_sinSyncHasta);

    // El equipo terminó el ensayo (N pulsos, DETENER en la app o en su pantalla).
    if (_ble.conectado && lectura != null && lectura.resultadoListo &&
        (_esperandoResultado || (_testRunning && sincronizar))) {
      _esperandoResultado = false;
      _equipoMidiendoAntes = false;
      _guardarResultadoEquipo(lectura);
      return;
    }
    if (sincronizar) {
      // Ensayo iniciado con el botón de la pantalla del equipo.
      if (equipoMidiendo && !_equipoMidiendoAntes && !_testRunning) {
        _equipoMidiendoAntes = true;
        setState(() {
          _testRunning = true;
          _testFinished = false;
          _testStartedAt = DateTime.now();
          _selectedTab = 2;
        });
        _showMessage('Ensayo iniciado desde la pantalla del equipo.');
        return;
      }
      // Cancelado en el equipo antes del primer pulso (sin resultado).
      if (!equipoMidiendo && _equipoMidiendoAntes && _testRunning && !(lectura?.resultadoListo ?? false)) {
        _equipoMidiendoAntes = false;
        setState(() => _testRunning = false);
        _showMessage('El ensayo se canceló en el equipo.');
        return;
      }
    }
    _equipoMidiendoAntes = equipoMidiendo;
    setState(() {});
  }

  void _alPerderConexion() {
    if (!mounted) return;
    final estabaMidiendo = _testRunning;
    setState(() => _testRunning = false);
    _showMessage(estabaMidiendo
        ? 'Se perdió la conexión con el equipo. El ensayo se canceló.'
        : 'Se perdió la conexión con el equipo VeriMed BT.');
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('verimed_test_history_v1');
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final loaded = <Map<String, dynamic>>[];
          for (final item in decoded) {
            if (item is! Map) continue;
            final record = Map<String, dynamic>.from(item);
            final dateValue = record['date'];
            record['date'] = dateValue is String
                ? (DateTime.tryParse(dateValue) ?? DateTime.now())
                : DateTime.now();
            for (final key in ['kc', 'referenceWh', 'meterWh', 'errorPct', 'durationSeconds', 'lat', 'lon', 'gpsAccuracy']) {
              final value = record[key];
              if (value is int) record[key] = value.toDouble();
              if (value is String) record[key] = double.tryParse(value);
            }
            if (record['pulses'] is String) {
              record['pulses'] = int.tryParse(record['pulses'] as String);
            }
            loaded.add(record);
          }
          if (mounted) {
            setState(() {
              _testHistory
                ..clear()
                ..addAll(loaded);
              _historyLoaded = true;
            });
            return;
          }
        }
      }
    } catch (_) {
      // Si los datos locales están dañados, la app sigue funcionando.
    }
    if (mounted) setState(() => _historyLoaded = true);
  }

  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serializable = _testHistory.map((record) {
        final copy = Map<String, dynamic>.from(record);
        final date = copy['date'];
        copy['date'] = date is DateTime ? date.toIso8601String() : date.toString();
        return copy;
      }).toList();
      await prefs.setString('verimed_test_history_v1', jsonEncode(serializable));
    } catch (_) {
      if (mounted) _showMessage('El ensayo se guardó en pantalla, pero no se pudo persistir el historial local.');
    }
  }

  @override
  void dispose() {
    _meterSerial.dispose();
    _kc.dispose();
    _pulseCount.dispose();
    _technician.dispose();
    _reportEmail.dispose();
    _ble.removeListener(_onBle);
    _ble.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _showReportSentDialog(String email, {bool redirectResponse = false}) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: const BoxDecoration(color: Color(0xFFE5F8EF), shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, color: Color(0xFF12B886), size: 48),
            ),
            const SizedBox(height: 18),
            Text(redirectResponse ? 'Solicitud procesada' : '¡Informe enviado!', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(redirectResponse ? 'El servicio respondió con una redirección. Comprueba la recepción en la bandeja del destinatario:' : 'El servicio aceptó la solicitud de envío para el siguiente correo:', textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(color: const Color(0xFFEEF3F8), borderRadius: BorderRadius.circular(12)),
              child: SelectableText(email, textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF0B2545), fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0B2545),
              minimumSize: const Size(double.infinity, 46),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  void _startTest() {
    if (!_connected) {
      _showMessage('Conecta el equipo VeriMed BT antes de iniciar el ensayo.');
      setState(() => _selectedTab = 1);
      return;
    }
    setState(() => _selectedTab = 2);
    _iniciarEnsayo();
  }

  Future<void> _iniciarEnsayo() async {
    if (!_connected) {
      _showMessage('Primero conecta el equipo en la pestaña Conexión.');
      setState(() => _selectedTab = 1);
      return;
    }
    final kc = (_kcValue ?? 0).round();
    final np = _pulseValue ?? 0;
    if (kc <= 0 || np <= 0) {
      _showMessage('Revisa la constante Kc y el número de pulsos antes de iniciar.');
      return;
    }
    _sinSyncHasta = DateTime.now().add(const Duration(seconds: 2));
    try {
      // El equipo recibe Kc, N pulsos y clase, y se detiene solo al completar N pulsos.
      await _ble.enviarConfiguracion(kc: kc, pulsos: np, clase: _accuracyClass == 'Clase 1' ? 1 : 2);
      await _ble.enviarComando('INICIAR');
      if (!mounted) return;
      setState(() {
        _testRunning = true;
        _testFinished = false;
        _testStartedAt = DateTime.now();
      });
    } catch (e) {
      _showMessage('No se pudo iniciar el ensayo en el equipo. Revisa la conexión.');
    }
  }

  /// Cancela el ensayo sin guardarlo en el historial de la app.
  Future<void> _cancelarEnsayo() async {
    _sinSyncHasta = DateTime.now().add(const Duration(seconds: 2));
    setState(() => _testRunning = false);
    try {
      await _ble.enviarComando('DETENER');
    } catch (_) {}
    _showMessage('Ensayo cancelado; no se guardó en el historial de la app.');
  }

  /// "Finalizar": pide al equipo cerrar el ensayo con los pulsos contados.
  /// El resultado llega por Bluetooth y se guarda en _guardarResultadoEquipo.
  Future<void> _finishTest({bool desdeEquipo = false}) async {
    if (!_connected) {
      setState(() => _testRunning = false);
      _showMessage('El equipo no está conectado; no se pudo cerrar el ensayo.');
      return;
    }
    _esperandoResultado = true;
    _sinSyncHasta = DateTime.now().add(const Duration(seconds: 2));
    try {
      await _ble.enviarComando('DETENER');
    } catch (_) {
      _esperandoResultado = false;
      _showMessage('No se pudo enviar DETENER al equipo. Revisa la conexión.');
      return;
    }
    // Si el equipo aún no contaba pulsos, no hay resultado que guardar.
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (mounted && _esperandoResultado) {
        _esperandoResultado = false;
        setState(() => _testRunning = false);
        _showMessage('El equipo no registró pulsos del medidor; el ensayo se canceló sin resultado.');
      }
    });
  }

  /// Guarda en el historial el resultado calculado por el equipo.
  void _guardarResultadoEquipo(VeriMedLectura l) {
    _pulseCount.text = '${l.pulsos}';
    if (l.kc > 0) _kc.text = '${l.kc}';
    _medidoWh = l.energiaWh;
    _medidoSegundos = l.segundos;
    _medicionSimulada = l.simulada || l.pulsosSimulados;
    _pulsosAutomaticos = !l.pulsosSimulados;
    final now = DateTime.now();
    final error = _calculatedErrorPct;
    final record = <String, dynamic>{
      'id': _reportId(),
      'date': now,
      'serial': _meterSerial.text.trim().isEmpty ? 'No especificado' : _meterSerial.text.trim(),
      'model': _selectedMeterModel.isEmpty ? 'No especificado' : _selectedMeterModel,
      'technician': _technician.text.trim().isEmpty ? 'No especificado' : _technician.text.trim(),
      'kc': _kcValue,
      'pulses': _pulseValue,
      'referenceWh': _referenceEnergyWh,
      'meterWh': _meterEnergyWh,
      'errorPct': error,
      'class': _accuracyClass,
      'verdict': _calculatedVerdict,
      'mode': _medicionSimulada ? 'ESP32 · DATOS SIMULADOS' : 'ESP32 · MEDICIÓN',
      'durationSeconds': l.segundos,
      'deviceSerial': _ble.info?.serie ?? 'No informado',
      'firmware': _ble.info?.firmware ?? 'No informado',
      ...?_captura?.aRegistro(),
    };
    setState(() {
      _testHistory.insert(0, record);
      _testRunning = false;
      _testFinished = true;
      _lastTestDurationSeconds = l.segundos;
      _selectedTab = 3;
    });
    _saveHistory();
    final txtError = error == null ? '' : ' (${error >= 0 ? '+' : ''}${error.toStringAsFixed(2)} %)';
    _showMessage('Ensayo guardado: ${error != null && error.abs() <= _acceptanceLimitPct ? 'dentro del límite' : 'fuera del límite'}$txtError.');
  }

  /// Abre la cámara para leer el código de barras / QR del número de serie.
  Future<void> _escanearSerie() async {
    final codigo = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const EscanerSerieScreen()),
    );
    if (!mounted || codigo == null || codigo.isEmpty) return;
    setState(() => _meterSerial.text = codigo);
    _showMessage('Número de serie leído: $codigo');
  }

  /// Toma la foto del medidor y registra dónde y cuándo se hace el ensayo.
  Future<void> _tomarFoto() async {
    setState(() => _tomandoFoto = true);
    try {
      final captura = await tomarFotoConUbicacion();
      if (!mounted) return;
      if (captura != null) {
        setState(() => _captura = captura);
        _showMessage(captura.tieneUbicacion
            ? 'Foto guardada con la ubicación del ensayo.'
            : 'Foto guardada sin ubicación: ${captura.avisoUbicacion ?? ''}');
      }
    } catch (_) {
      _showMessage('No se pudo tomar la foto. Revisa el permiso de Cámara de la app.');
    } finally {
      if (mounted) setState(() => _tomandoFoto = false);
    }
  }

  Widget _panelFotoUbicacion() {
    final c = _captura;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.photo_camera_outlined, color: vmBlue),
              SizedBox(width: 8),
              Expanded(child: Text('Foto y ubicación del ensayo', style: TextStyle(fontWeight: FontWeight.w700))),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Toma una foto del medidor: queda registrado dónde y cuándo se hizo la prueba.',
            style: TextStyle(color: vmMuted, fontSize: 12),
          ),
          if (c != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(c.fotoBytes, height: 180, width: double.infinity, fit: BoxFit.cover),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.location_on_rounded, color: c.tieneUbicacion ? vmRed : vmMuted, size: 22),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.direccion ?? (c.tieneUbicacion ? 'Dirección no disponible (sin internet)' : 'Sin ubicación'),
                        style: const TextStyle(fontWeight: FontWeight.w700, color: vmInk),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        c.tieneUbicacion ? 'GPS ${c.coordenadas}  ${c.precisionTexto}' : (c.avisoUbicacion ?? ''),
                        style: const TextStyle(color: vmMuted, fontSize: 12),
                      ),
                      Text('Foto: ${c.fechaTexto}', style: const TextStyle(color: vmMuted, fontSize: 12)),
                      if (c.tieneUbicacion && c.avisoUbicacion != null)
                        Text(c.avisoUbicacion!, style: const TextStyle(color: vmNavy, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
            if (!c.tieneUbicacion)
              TextButton.icon(
                onPressed: () => abrirAjustesUbicacion(permisoBloqueado: (c.avisoUbicacion ?? '').contains('bloqueado')),
                icon: const Icon(Icons.settings_rounded),
                label: const Text('Activar ubicación'),
              ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _tomandoFoto ? null : _tomarFoto,
              icon: _tomandoFoto
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(c == null ? Icons.photo_camera_rounded : Icons.refresh_rounded),
              label: Text(_tomandoFoto ? 'Obteniendo ubicación…' : (c == null ? 'Tomar foto del medidor' : 'Repetir foto')),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
            ),
          ),
        ],
      ),
    );
  }

  /// Aviso rojo cuando el equipo informa una alarma eléctrica.
  Widget _bannerAlarma() {
    final alarma = _connected ? _ble.lectura?.textoAlarma : null;
    if (alarma == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: vmRed.withOpacity(.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: vmRed.withOpacity(.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: vmRed),
          const SizedBox(width: 10),
          Expanded(child: Text('Alarma del equipo: $alarma', style: const TextStyle(color: vmRed, fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  /// Gráfico en vivo de la potencia de referencia durante el ensayo.
  Widget _graficoPotencia() {
    final spots = [for (final m in _ble.muestras) FlSpot(m.segundos, m.potencia)];
    final ys = spots.map((e) => e.y);
    final minY = ys.reduce(math.min);
    final maxY = ys.reduce(math.max);
    final margen = math.max(5.0, (maxY - minY) * 0.25);
    return LineChart(
      LineChartData(
        minY: minY - margen,
        maxY: maxY + margen,
        gridData: const FlGridData(drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: vmBlue,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: vmBlue.withOpacity(0.12)),
          ),
        ],
      ),
      duration: Duration.zero,
    );
  }

  String _csvEscape(Object? value) {
    final text = (value ?? '').toString();
    return '"${text.replaceAll('"', '""')}"';
  }

  Future<void> _exportCsv() async {
    if (_testHistory.isEmpty) {
      _showMessage('Todavía no hay ensayos en el historial para exportar.');
      return;
    }
    final rows = <List<String>>[
      ['ID', 'Fecha', 'Modo', 'Serie', 'Modelo', 'Técnico', 'Kc_imp_kWh', 'Pulsos_contados', 'Eref_Wh', 'Emed_Wh', 'Error_pct', 'Clase', 'Resultado', 'Ubicacion', 'Latitud', 'Longitud'],
      ..._testHistory.map((r) => <String>[
        r['id'].toString(),
        (r['date'] as DateTime).toIso8601String(),
        r['mode'].toString(),
        r['serial'].toString(),
        r['model'].toString(),
        r['technician'].toString(),
        r['kc']?.toString() ?? '',
        r['pulses']?.toString() ?? '',
        (r['referenceWh'] as double).toStringAsFixed(5),
        r['meterWh'] == null ? '' : (r['meterWh'] as double).toStringAsFixed(5),
        r['errorPct'] == null ? '' : (r['errorPct'] as double).toStringAsFixed(4),
        r['class'].toString(),
        r['verdict'].toString(),
        (r['address'] ?? '').toString(),
        r['lat']?.toString() ?? '',
        r['lon']?.toString() ?? '',
      ]),
    ];
    final csv = rows.map((row) => row.map(_csvEscape).join(';')).join('\r\n');
    await Clipboard.setData(ClipboardData(text: csv));
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('CSV preparado'),
        content: Text('Se copiaron ${_testHistory.length} ensayos al portapapeles en formato CSV. Pega el contenido en un archivo .csv o en Excel. Los registros están marcados como simulaciones.'),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Entendido'))],
      ),
    );
  }

  Future<void> _showHistory() async {
    _historySearch = '';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Historial de ensayos'),
        content: SizedBox(
          width: 480,
          child: _testHistory.isEmpty
              ? const Text('Aún no hay ensayos. Ejecuta y finaliza un ensayo para guardar el primer registro. Los ensayos quedan guardados localmente en este dispositivo.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar por modelo o número de serie', border: OutlineInputBorder()),
                      onChanged: (value) => setState(() => _historySearch = value.trim().toLowerCase()),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 330,
                      child: Builder(builder: (context) {
                        final filtered = _testHistory.where((r) => '${r['model']} ${r['serial']} ${r['id']}'.toLowerCase().contains(_historySearch)).toList();
                        if (filtered.isEmpty) return const Center(child: Text('No hay resultados para esa búsqueda.'));
                        return ListView.separated(
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, index) {
                    final r = filtered[index];
                    final date = r['date'] as DateTime;
                    final error = r['errorPct'] as double?;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(child: Icon(Icons.science_outlined)),
                      title: Text('${r['serial']} • ${r['model']}', maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}${r['address'] != null ? ' · ${r['address']}' : ''}\n${r['mode']} • ${r['verdict']}'),
                      trailing: Text(error == null ? '—' : '${error >= 0 ? '+' : ''}${error.toStringAsFixed(2)}%', style: const TextStyle(fontWeight: FontWeight.w800)),
                      isThreeLine: true,
                    );
                  },
                );
                      }),
                    ),
                  ],
                ),
        ),
        actions: [
          if (_testHistory.isNotEmpty) TextButton(onPressed: () { Navigator.pop(dialogContext); _exportCsv(); }, child: const Text('Exportar CSV')),
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  Future<void> _showDemoChart() async {
    if (_testHistory.isEmpty) {
      _showMessage('Finaliza al menos un ensayo para mostrar el gráfico.');
      return;
    }
    final recent = _testHistory.take(8).toList().reversed.toList();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tendencia del error calculado'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Error calculado en los últimos ensayos guardados.'),
              const SizedBox(height: 18),
              ...recent.asMap().entries.map((entry) {
                final index = entry.key;
                final r = entry.value;
                final error = (r['errorPct'] as double?) ?? 0.0;
                final scale = (error.abs() / 10).clamp(0.03, 1.0).toDouble();
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    SizedBox(width: 24, child: Text('${index + 1}')),
                    Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: scale, minHeight: 12, color: error.abs() <= _acceptanceLimitPct ? vmGreen : vmRed, backgroundColor: vmBorder))),
                    const SizedBox(width: 10),
                    SizedBox(width: 72, child: Text('${error >= 0 ? '+' : ''}${error.toStringAsFixed(2)}%', textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w700))),
                  ]),
                );
              }),
              const SizedBox(height: 8),
              Text('Referencia visual: ±${_acceptanceLimitPct.toStringAsFixed(1)}% ilustrativo; no equivale a certificación normativa.', style: const TextStyle(fontSize: 12, color: vmMuted)),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cerrar'))],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _buildHome(),
      _buildConnection(),
      _buildTest(),
      _buildResults(),
      _buildMore(),
    ];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 18,
        title: const _Brand(inverted: true),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: PopupMenuButton<String>(
              tooltip: 'Cuenta',
              icon: const Icon(Icons.account_circle_outlined),
              onSelected: (value) async {
                if (value == 'account') {
                  final email = FirebaseAuth.instance.currentUser?.email ?? 'Sin correo';
                  if (!mounted) return;
                  showDialog<void>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Cuenta de VeriMed BT'),
                      content: Text('Sesión iniciada como\n$email'),
                      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cerrar'))],
                    ),
                  );
                } else if (value == 'logout') {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Cerrar sesión'),
                      content: const Text('¿Quieres cerrar tu sesión de VeriMed BT?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
                        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Cerrar sesión')),
                      ],
                    ),
                  );
                  if (confirm == true) await FirebaseAuth.instance.signOut();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'account', child: ListTile(leading: Icon(Icons.person_outline), title: Text('Mi cuenta'), contentPadding: EdgeInsets.zero)),
                PopupMenuItem(value: 'logout', child: ListTile(leading: Icon(Icons.logout_rounded), title: Text('Cerrar sesión'), contentPadding: EdgeInsets.zero)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Estado del equipo',
            onPressed: () => _showMessage(
              !_connected
                  ? 'Equipo VeriMed BT desconectado.'
                  : (_ble.lectura?.simulada ?? true)
                      ? 'Conectado al ESP32. El equipo está enviando datos SIMULADOS (sin sensor).'
                      : 'Conectado al ESP32. Mediciones del sensor del equipo.',
            ),
            icon: const Icon(Icons.info_outline_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(index: _selectedTab, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        height: 68,
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) {
          setState(() => _selectedTab = index);
        },
        backgroundColor: vmNavy,
        indicatorColor: vmBlue,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.bluetooth_searching_rounded),
            selectedIcon: Icon(Icons.bluetooth_connected_rounded),
            label: 'Conexión',
          ),
          NavigationDestination(
            icon: Icon(Icons.play_circle_outline_rounded),
            selectedIcon: Icon(Icons.play_circle_fill_rounded),
            label: 'Ensayo',
          ),
          NavigationDestination(
            icon: Icon(Icons.fact_check_outlined),
            selectedIcon: Icon(Icons.fact_check_rounded),
            label: 'Resultados',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz_rounded),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'Más',
          ),
        ],
      ),
    );
  }

  Widget _buildHome() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const _SectionHeading(
          title: 'Panel principal',
          subtitle: 'Verificación monofásica',
        ),
        const SizedBox(height: 14),
        _Panel(
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: vmBlue.withOpacity(0.09),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.memory_rounded,
                  color: vmBlue,
                  size: 29,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Estado del equipo',
                      style: TextStyle(color: vmMuted, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _connected ? vmGreen : vmMuted,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          _connected ? 'Conectado' : 'Desconectado',
                          style: TextStyle(
                            color: _connected ? vmGreen : vmInk,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _connected
                          ? '${_ble.nombreConectado}${(_ble.lectura?.simulada ?? false) ? ' • datos simulados' : ''}'
                          : 'Toca Conexión para buscar el equipo',
                      style: const TextStyle(color: vmMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(
                _connected
                    ? Icons.bluetooth_connected_rounded
                    : Icons.bluetooth_disabled_rounded,
                color: _connected ? vmBlue : vmMuted,
                size: 25,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Builder(builder: (context) {
          final l = _connected ? _ble.lectura : null;
          return Row(
            children: [
              Expanded(child: _MetricCard(icon: Icons.speed_rounded, value: l == null ? '— V' : '${l.tension.toStringAsFixed(1)} V', label: 'Tensión')),
              const SizedBox(width: 10),
              Expanded(child: _MetricCard(icon: Icons.bolt_rounded, value: l == null ? '— A' : '${l.corriente.toStringAsFixed(2)} A', label: 'Corriente')),
              const SizedBox(width: 10),
              Expanded(child: _MetricCard(icon: Icons.flash_on_rounded, value: l == null ? '— W' : '${l.potencia.toStringAsFixed(0)} W', label: 'Potencia')),
            ],
          );
        }),
        const SizedBox(height: 6),
        Text(
          !_connected
              ? 'Conecta el equipo VeriMed BT para ver las mediciones en vivo.'
              : (_ble.lectura?.simulada ?? true)
                  ? 'Valores en vivo del ESP32 · el equipo indica DATOS SIMULADOS (aún sin sensor).'
                  : 'Valores en vivo del equipo VeriMed BT · FP ${_ble.lectura!.factorPotencia.toStringAsFixed(2)}',
          style: const TextStyle(color: vmMuted, fontSize: 11),
        ),
        const SizedBox(height: 14),
        _bannerAlarma(),
        FilledButton.icon(
          onPressed: _startTest,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Nuevo ensayo'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: vmBlue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),
        ),
        const SizedBox(height: 18),
        _SectionHeading(title: 'Último ensayo', subtitle: _testHistory.isEmpty ? 'Aún no hay registros' : 'Último registro guardado'),
        const SizedBox(height: 10),
        _Panel(
          child: Column(
            children: [
              _DataRow(label: 'Fecha', value: _testHistory.isEmpty ? (_historyLoaded ? 'Sin ensayos guardados' : 'Cargando historial…') : _formatRecordDate(_testHistory.first['date'])),
              const Divider(height: 18, color: vmBorder),
              _DataRow(label: 'Error porcentual', value: _testHistory.isEmpty || _testHistory.first['errorPct'] == null ? '—' : '${(_testHistory.first['errorPct'] as num).toDouble().toStringAsFixed(2)} %'),
              const Divider(height: 18, color: vmBorder),
              _DataRow(label: 'Veredicto', value: _testHistory.isEmpty ? '—' : '${_testHistory.first['verdict']}'),
              const Divider(height: 18, color: vmBorder),
              _DataRow(label: 'Modo', value: _testHistory.isEmpty ? '—' : '${_testHistory.first['mode']}'),
            ],
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(onPressed: _showHistory, icon: const Icon(Icons.history_rounded), label: const Text('Ver historial y buscar ensayos')),
        const SizedBox(height: 12),
        const _DemoNotice(),
      ],
    );
  }

  Widget _buildConnection() {
    final ble = _ble;
    final btOn = ble.bluetoothEncendido;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const _SectionHeading(
          title: 'Conexión',
          subtitle: 'Bluetooth Low Energy (BLE)',
        ),
        const SizedBox(height: 14),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    ble.conectado ? Icons.bluetooth_connected_rounded : (btOn ? Icons.bluetooth_rounded : Icons.bluetooth_disabled_rounded),
                    color: ble.conectado ? vmGreen : (btOn ? vmBlue : vmMuted),
                    size: 34,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ble.conectado ? ble.nombreConectado : 'VeriMed BT',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          ble.conectado
                              ? 'Conectado · ${ble.equipo?.remoteId.str ?? ''}'
                              : ble.conectando
                                  ? 'Conectando…'
                                  : !btOn
                                      ? 'El Bluetooth del teléfono está apagado'
                                      : 'No hay ningún equipo conectado',
                          style: TextStyle(color: ble.conectado ? vmGreen : vmMuted, fontWeight: ble.conectado ? FontWeight.w600 : FontWeight.normal),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (ble.conectado && ble.lectura != null) ...[
                const SizedBox(height: 12),
                const Divider(color: vmBorder),
                _DataRow(label: 'Tensión', value: '${ble.lectura!.tension.toStringAsFixed(1)} V'),
                const SizedBox(height: 6),
                _DataRow(label: 'Corriente', value: '${ble.lectura!.corriente.toStringAsFixed(2)} A'),
                const SizedBox(height: 6),
                _DataRow(label: 'Potencia activa', value: '${ble.lectura!.potencia.toStringAsFixed(1)} W'),
                const SizedBox(height: 6),
                _DataRow(label: 'Factor de potencia', value: ble.lectura!.factorPotencia.toStringAsFixed(2)),
                const SizedBox(height: 6),
                _DataRow(label: 'Referencia (V, I, P)', value: ble.lectura!.simulada ? 'Simulada' : 'Medidor PZEM-004T'),
                const SizedBox(height: 6),
                _DataRow(label: 'Pulsos del medidor', value: ble.lectura!.pulsosSimulados ? 'Simulados' : 'Sensor óptico'),
                if (ble.info != null) ...[
                  const SizedBox(height: 6),
                  _DataRow(label: 'Equipo', value: '${ble.info!.serie} · FW ${ble.info!.firmware}'),
                  const SizedBox(height: 6),
                  _DataRow(label: 'Calibración', value: ble.info!.calibracion),
                ],
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ble.conectado
                    ? OutlinedButton.icon(
                        onPressed: () async {
                          await ble.desconectar();
                          if (mounted) setState(() => _testRunning = false);
                          _showMessage('Equipo desconectado.');
                        },
                        icon: const Icon(Icons.link_off_rounded),
                        label: const Text('Desconectar'),
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), foregroundColor: vmRed),
                      )
                    : !btOn
                        ? FilledButton.icon(
                            onPressed: ble.encenderBluetooth,
                            icon: const Icon(Icons.bluetooth_rounded),
                            label: const Text('Activar Bluetooth'),
                            style: FilledButton.styleFrom(backgroundColor: vmBlue, minimumSize: const Size.fromHeight(48)),
                          )
                        : FilledButton.icon(
                            onPressed: ble.conectando
                                ? null
                                : () {
                                    if (ble.buscando) {
                                      ble.detenerBusqueda();
                                    } else {
                                      ble.buscar();
                                    }
                                  },
                            icon: ble.buscando
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.bluetooth_searching_rounded),
                            label: Text(ble.buscando ? 'Buscando… (toca para detener)' : 'Buscar equipo VeriMed BT'),
                            style: FilledButton.styleFrom(backgroundColor: vmBlue, minimumSize: const Size.fromHeight(48)),
                          ),
              ),
              if (ble.error != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: vmRed.withOpacity(.08), borderRadius: BorderRadius.circular(10)),
                  child: Text(ble.error!, style: const TextStyle(color: vmRed, fontSize: 12)),
                ),
              ],
              if (!ble.permisosOk) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: ble.permisosBloqueados ? ble.abrirAjustesApp : ble.pedirPermisos,
                    icon: Icon(ble.permisosBloqueados ? Icons.settings_rounded : Icons.verified_user_outlined),
                    label: Text(ble.permisosBloqueados ? 'Abrir ajustes de la app' : 'Dar permiso de Bluetooth'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (!ble.conectado) ...[
          const SizedBox(height: 14),
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Equipos encontrados', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                if (ble.encontrados.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      ble.buscando
                          ? 'Buscando equipos cercanos…'
                          : 'Toca "Buscar equipo VeriMed BT". En la pantalla del equipo la etiqueta Bluetooth debe decir VISIBLE.',
                      style: const TextStyle(color: vmMuted, fontSize: 12),
                    ),
                  )
                else
                  ...ble.encontrados.map((r) {
                    final nombre = r.advertisementData.advName.isNotEmpty
                        ? r.advertisementData.advName
                        : (r.device.platformName.isNotEmpty ? r.device.platformName : VeriMedBle.nombreEquipo);
                    return InkWell(
                      onTap: ble.conectando ? null : () => ble.conectar(r.device),
                      borderRadius: BorderRadius.circular(10),
                      child: _DeviceRow(
                        name: nombre,
                        detail: '${r.device.remoteId.str} • señal ${r.rssi} dBm • toca para conectar',
                        active: true,
                      ),
                    );
                  }),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('¿No aparece el equipo?', style: TextStyle(fontWeight: FontWeight.w700)),
                SizedBox(height: 8),
                Text(
                  '• En la pantalla del equipo toca la etiqueta Bluetooth hasta que diga VISIBLE.\n'
                  '• Acepta los permisos de Bluetooth (y Ubicación en Android antiguos).\n'
                  '• El equipo no aparece en Ajustes > Bluetooth del teléfono: solo se conecta desde esta app.\n'
                  '• Si otro teléfono está conectado, el equipo deja de ser visible hasta que se desconecte.',
                  style: TextStyle(color: vmMuted, fontSize: 12, height: 1.45),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        const _DemoNotice(),
      ],
    );
  }

  Future<void> _showMeterDetails(
    String model, {
    required void Function(String) onSelect,
  }) async {
    final specs = _meterSpecs[model] ??
        <String, String>{
          'Estado de la ficha': 'Ficha técnica pendiente de completar',
          'Qué revisar': 'Tensión nominal, corriente base y máxima, frecuencia, clase de exactitud y constante de pulsos.',
          'Recomendación': 'Lee la placa del medidor y usa la ficha oficial de la variante exacta antes de configurar la prueba.',
        };

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(dialogContext).size.height * 0.78,
            maxWidth: 520,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: vmBlue.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(Icons.speed_rounded, color: vmBlue),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        model,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: vmInk,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: vmBorder),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  children: [
                    const Text(
                      'Características del medidor',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    ...specs.entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.key,
                              style: const TextStyle(
                                color: vmMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              entry.value,
                              style: const TextStyle(
                                color: vmInk,
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 7),
                            const Divider(height: 1, color: vmBorder),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: vmYellow.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: vmYellow.withOpacity(0.65)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.warning_amber_rounded, color: vmNavy, size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Ficha de referencia. Las variantes pueden diferir: confirma los datos en la placa y documentación oficial del medidor instalado.',
                              style: TextStyle(
                                color: vmNavy,
                                fontSize: 11,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      onSelect(model);
                    },
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Seleccionar este medidor'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: vmBlue,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectMeterModel() async {
    final searchController = TextEditingController();
    String query = '';
    String? selected = _selectedMeterModel.isEmpty ? null : _selectedMeterModel;

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final filtered = _meterModels
                .where((model) => model.toLowerCase().contains(query.toLowerCase()))
                .toList();

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                height: MediaQuery.of(context).size.height * 0.78,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: vmBorder,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Seleccionar medidor',
                                style: TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  color: vmInk,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(sheetContext),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          controller: searchController,
                          autofocus: true,
                          decoration: const InputDecoration(
                            hintText: 'Buscar por marca o modelo...',
                            prefixIcon: Icon(Icons.search_rounded),
                          ),
                          onChanged: (value) => setSheetState(() => query = value),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${filtered.length} opciones del catálogo inicial',
                            style: const TextStyle(color: vmMuted, fontSize: 12),
                          ),
                        ),
                      ),
                      Expanded(
                        child: filtered.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.search_off_rounded, size: 36, color: vmMuted),
                                      const SizedBox(height: 8),
                                      Text(
                                        'No encontramos “$query” en el catálogo.',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(color: vmMuted),
                                      ),
                                      const SizedBox(height: 12),
                                      FilledButton.icon(
                                        onPressed: () => Navigator.pop(
                                          sheetContext,
                                          'PERSONALIZADO:$query',
                                        ),
                                        icon: const Icon(Icons.add_rounded),
                                        label: const Text('Usar este modelo'),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                itemCount: filtered.length + 1,
                                separatorBuilder: (_, __) => const Divider(height: 1, color: vmBorder),
                                itemBuilder: (context, index) {
                                  if (index == filtered.length) {
                                    return ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                                      leading: CircleAvatar(
                                        backgroundColor: vmBlue.withOpacity(0.10),
                                        child: Icon(Icons.add_rounded, color: vmBlue),
                                      ),
                                      title: const Text(
                                        'Ingresar otro modelo',
                                        style: TextStyle(fontWeight: FontWeight.w700),
                                      ),
                                      subtitle: const Text('Escribe un modelo que no esté en la lista'),
                                      onTap: () => Navigator.pop(
                                        sheetContext,
                                        'PERSONALIZADO:${query.trim()}',
                                      ),
                                    );
                                  }

                                  final model = filtered[index];
                                  final isSelected = selected == model;
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                                    leading: CircleAvatar(
                                      backgroundColor: isSelected
                                          ? vmBlue.withOpacity(0.12)
                                          : vmBackground,
                                      child: Icon(
                                        Icons.electric_meter_outlined,
                                        color: isSelected ? vmBlue : vmMuted,
                                      ),
                                    ),
                                    title: Text(
                                      model,
                                      style: TextStyle(
                                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                        color: vmInk,
                                      ),
                                    ),
                                    subtitle: const Text('Toca para seleccionar'),
                                    trailing: IconButton(
                                      tooltip: 'Ver características',
                                      icon: const Icon(Icons.chevron_right_rounded, color: vmBlue),
                                      onPressed: () {
                                        _showMeterDetails(
                                          model,
                                          onSelect: (selectedModel) {
                                            Navigator.pop(sheetContext, selectedModel);
                                          },
                                        );
                                      },
                                    ),
                                    onTap: () => Navigator.pop(sheetContext, model),
                                  );
                                },
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: const Text(
                          'Catálogo inicial editable: puedes buscar o introducir cualquier modelo.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, color: vmMuted),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    // The bottom-sheet route may still be detaching its TextField/focus dependents.
    // Defer controller disposal to avoid Flutter's _dependents.isEmpty assertion.
    Future<void>.delayed(const Duration(milliseconds: 250), searchController.dispose);
    if (result == null || !mounted) return;

    if (result.startsWith('PERSONALIZADO:')) {
      final typedModel = result.substring('PERSONALIZADO:'.length).trim();
      final customController = TextEditingController(text: typedModel);
      final customModel = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Ingresar modelo'),
          content: TextField(
            controller: customController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Marca y modelo del medidor',
              hintText: 'Ej. marca, serie o referencia',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                customController.text.trim(),
              ),
              child: const Text('Guardar modelo'),
            ),
          ],
        ),
      );
      // Let the dialog finish its reverse transition before disposing the controller.
      Future<void>.delayed(const Duration(milliseconds: 250), customController.dispose);

      if (customModel != null && customModel.isNotEmpty && mounted) {
        setState(() {
          _selectedMeterModel = customModel;
          if (!_meterModels.contains(customModel)) {
            _meterModels.add(customModel);
          }
        });
      }
      return;
    }

    setState(() => _selectedMeterModel = result);
  }

  Widget _buildTest() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const _SectionHeading(
          title: 'Configuración del ensayo',
          subtitle: 'Parámetros del medidor monofásico',
        ),
        const SizedBox(height: 14),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _FieldLabel('N.º de serie del medidor'),
              TextField(
                controller: _meterSerial,
                decoration: InputDecoration(
                  hintText: 'Ej. 12345678',
                  suffixIcon: IconButton(
                    tooltip: 'Escanear código de la placa',
                    icon: const Icon(Icons.qr_code_scanner_rounded, color: vmBlue),
                    onPressed: _escanearSerie,
                  ),
                ),
              ),
              const SizedBox(height: 13),
              const _FieldLabel('Marca y modelo del medidor'),
              InkWell(
                onTap: _selectMeterModel,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: vmBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: vmBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.electric_meter_outlined, color: vmBlue),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _selectedMeterModel.isEmpty
                              ? 'Seleccionar o buscar modelo'
                              : _selectedMeterModel,
                          style: TextStyle(
                            color: _selectedMeterModel.isEmpty ? vmMuted : vmInk,
                            fontWeight: _selectedMeterModel.isEmpty
                                ? FontWeight.normal
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                      const Icon(Icons.search_rounded, color: vmMuted),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 13),
              const _FieldLabel('Constante del medidor (Kc)'),
              TextField(
                controller: _kc,
                onChanged: (_) => setState(() {}),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  suffixText: 'imp/kWh',
                  hintText: '1000',
                ),
              ),
              const SizedBox(height: 13),
              const _FieldLabel('Clase de exactitud'),
              DropdownButtonFormField<String>(
                value: _accuracyClass,
                decoration: const InputDecoration(),
                items: const [
                  DropdownMenuItem(value: 'Clase 1', child: Text('Clase 1')),
                  DropdownMenuItem(value: 'Clase 2', child: Text('Clase 2')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _accuracyClass = value);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _panelFotoUbicacion(),
        const SizedBox(height: 12),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Datos del técnico', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              const _FieldLabel('Nombre del técnico'),
              TextField(
                controller: _technician,
                decoration: const InputDecoration(hintText: 'Nombre y apellido'),
              ),
              const SizedBox(height: 13),
              const _FieldLabel('Número de pulsos del ensayo'),
              TextField(
                controller: _pulseCount,
                onChanged: (_) => setState(() {}),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: '6'),
              ),
              const SizedBox(height: 10),
              const Text(
                'El equipo cuenta los pulsos del LED del medidor y se detiene solo al llegar a este número.',
                style: TextStyle(color: vmMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _bannerAlarma(),
        if (_testRunning) ...[
          Builder(builder: (context) {
            final l = _ble.lectura;
            final esperando = l == null || l.estado == EstadoEnsayo.esperandoPulso;
            final objetivo = (l != null && l.pulsosObjetivo > 0) ? l.pulsosObjetivo : (_pulseValue ?? 0);
            final double? progreso = (esperando || objetivo <= 0) ? null : (l!.pulsos / objetivo).clamp(0.0, 1.0).toDouble();
            return _Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.circle, color: esperando ? vmBlue : vmGreen, size: 11),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          esperando ? 'Esperando el primer pulso del medidor…' : 'Pulso ${l!.pulsos} de $objetivo',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  if (l != null && (l.simulada || l.pulsosSimulados))
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('Datos simulados por el equipo', style: TextStyle(color: vmMuted, fontSize: 11)),
                    ),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(value: progreso, minHeight: 7),
                  const SizedBox(height: 12),
                  _DataRow(label: 'Tiempo', value: l == null ? '—' : '${l.segundos.toStringAsFixed(1)} s'),
                  const SizedBox(height: 6),
                  _DataRow(label: 'Energía de referencia', value: l == null ? '—' : '${l.energiaWh.toStringAsFixed(4)} Wh'),
                  const SizedBox(height: 6),
                  _DataRow(label: 'Potencia activa', value: l == null ? '—' : '${l.potencia.toStringAsFixed(1)} W'),
                  const SizedBox(height: 6),
                  _DataRow(label: 'Tensión / corriente', value: l == null ? '—' : '${l.tension.toStringAsFixed(1)} V · ${l.corriente.toStringAsFixed(2)} A'),
                  if (_ble.muestras.length >= 2) ...[
                    const SizedBox(height: 14),
                    const Text('Potencia de referencia durante el ensayo (W)', style: TextStyle(color: vmMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    SizedBox(height: 140, child: _graficoPotencia()),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    (l?.pulsosSimulados ?? true)
                        ? 'Los pulsos del medidor se simulan en el equipo (aún sin sensor óptico).'
                        : 'El sensor óptico cuenta los pulsos del LED del medidor automáticamente.',
                    style: const TextStyle(color: vmMuted, fontSize: 12),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _cancelarEnsayo,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Cancelar ensayo'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              foregroundColor: vmRed,
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _finishTest,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text('Finalizar y guardar ensayo'),
          ),
        ] else
          FilledButton.icon(
            onPressed: _iniciarEnsayo,
            icon: Icon(_connected ? Icons.play_arrow_rounded : Icons.bluetooth_disabled_rounded),
            label: Text(_connected ? 'Iniciar ensayo' : 'Conecta el equipo para iniciar'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: vmBlue,
            ),
          ),
        const SizedBox(height: 12),
        const _DemoNotice(),
      ],
    );
  }

  String _reportId() => 'VM-${DateTime.now().toUtc().millisecondsSinceEpoch}';

  Future<pw.Document> _createReportPdf() async {
    final doc = pw.Document();
    final now = DateTime.now();
    final kc = _kcValue ?? 0;
    final pulseCount = _pulseValue ?? 0;
    // Energía y tiempo medidos por el equipo VeriMed BT en el último ensayo.
    final pRef = _referencePowerW;
    final seconds = _medidoSegundos ?? 0;
    final eRef = _referenceEnergyWh;
    final eMeter = kc > 0 ? pulseCount * 1000.0 / kc : double.nan;
    final errorPct = eRef > 0 && eMeter.isFinite
        ? ((eMeter - eRef) / eRef) * 100.0
        : double.nan;
    final verdict = errorPct.isFinite
        ? (errorPct.abs() <= _acceptanceLimitPct ? 'DENTRO DEL LÍMITE ILUSTRATIVO' : 'FUERA DEL LÍMITE ILUSTRATIVO')
        : 'ENSAYO INVÁLIDO: revisar Kc y pulsos';
    final reportId = _reportId();
    final rows = <List<String>>[
      ['Identificador del informe', reportId],
      ['Estado de los datos', _medicionSimulada ? 'DATOS SIMULADOS POR EL EQUIPO — NO ES UNA MEDICIÓN REAL' : 'Medición del equipo VeriMed BT (prototipo sin calibración certificada)'],
      ['Fecha y hora local', '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}'],
      ['Técnico', _technician.text.trim().isEmpty ? 'No especificado' : _technician.text.trim()],
      ['Serie del medidor', _meterSerial.text.trim().isEmpty ? 'No especificada' : _meterSerial.text.trim()],
      ['Marca / modelo', _selectedMeterModel.isEmpty ? 'No especificado' : _selectedMeterModel],
      ['Clase configurada', _accuracyClass],
      ['Constante Kc', '${kc.toStringAsFixed(0)} imp/kWh'],
      ['Pulsos configurados', '$pulseCount'],
      ['Potencia de referencia media', '${pRef.toStringAsFixed(1)} W'],
      ['Duración del ensayo', '${seconds.toStringAsFixed(1)} s'],
      ['Energía de referencia calculada', '${eRef.toStringAsFixed(4)} Wh'],
      ['Energía del medidor calculada', eMeter.isFinite ? '${eMeter.toStringAsFixed(4)} Wh' : 'No calculable'],
      ['Error porcentual calculado', errorPct.isFinite ? '${errorPct >= 0 ? '+' : ''}${errorPct.toStringAsFixed(2)} %' : 'No calculable'],
      ['Límite ilustrativo de aceptación', '±${_acceptanceLimitPct.toStringAsFixed(1)} % (${_accuracyClass}); validar según norma/procedimiento'],
      ['Resultado matemático ilustrativo', verdict],
      ['Fórmula de energía de referencia', 'Eref (Wh) = Pref (W) × t (s) / 3600'],
      ['Fórmula de energía del medidor', 'Emed (Wh) = pulsos × 1000 / Kc (imp/kWh)'],
      ['Fórmula de error', 'Error (%) = (Emed − Eref) / Eref × 100'],
      ['Método de medición', _medicionSimulada ? 'ESP32 VeriMed BT por Bluetooth (datos simulados en el equipo)' : 'ESP32 VeriMed BT por Bluetooth; energía integrada en el equipo'],
      ['Conteo de pulsos', _pulsosAutomaticos ? 'Automático (sensor óptico en el LED del medidor)' : 'Simulado en el equipo (sin sensor óptico)'],
      ['Equipo VeriMed BT (serie)', _ble.info?.serie ?? 'No informado'],
      ['Firmware / calibración del equipo', _ble.info == null ? 'No informado' : 'v${_ble.info!.firmware} · calibración: ${_ble.info!.calibracion}'],
      ['Ubicación del ensayo', _captura == null
          ? 'No registrada (sin foto)'
          : (_captura!.direccion ?? (_captura!.tieneUbicacion ? 'Dirección no disponible' : (_captura!.avisoUbicacion ?? 'Sin ubicación')))],
      ['Coordenadas GPS', (_captura?.tieneUbicacion ?? false) ? '${_captura!.coordenadas} (${_captura!.precisionTexto})' : 'No disponible'],
      ['Foto del medidor', _captura == null ? 'No tomada' : 'Tomada el ${_captura!.fechaTexto} · SHA-256 ${_captura!.fotoSha256}'],
    ];
    // Huella SHA-256 de todos los datos del informe: si alguien cambia un valor, la huella no coincide.
    final huella = sha256.convert(utf8.encode(rows.map((r) => '${r[0]}=${r[1]}').join('|'))).toString();
    rows.add(['Huella SHA-256 de los datos', huella]);
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (context) => [
        pw.Container(
          padding: const pw.EdgeInsets.all(16),
          decoration: pw.BoxDecoration(color: PdfColor.fromHex('#0B2545'), borderRadius: pw.BorderRadius.circular(8)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('VeriMed BT', style: pw.TextStyle(color: PdfColors.white, fontSize: 24, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('Informe técnico de verificación monofásica', style: const pw.TextStyle(color: PdfColors.white, fontSize: 12)),
          ]),
        ),
        pw.SizedBox(height: 16),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(color: PdfColor.fromHex('#FFF4D6'), border: pw.Border.all(color: PdfColor.fromHex('#E9B949'))),
          child: pw.Text(_medicionSimulada ? 'DOCUMENTO DE DEMOSTRACIÓN. El equipo VeriMed BT envió datos SIMULADOS: los resultados no proceden de una medición real.' : 'PROTOTIPO. Datos medidos por el equipo VeriMed BT, que aún no cuenta con calibración certificada.', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ),
        pw.SizedBox(height: 18),
        pw.Text('1. Identificación y configuración', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headers: const ['Campo', 'Valor'],
          data: rows,
          headerDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#EAF2FF')),
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
          cellStyle: const pw.TextStyle(fontSize: 8.5),
          cellPadding: const pw.EdgeInsets.all(7),
          border: pw.TableBorder.all(color: PdfColor.fromHex('#DCE4EF'), width: 0.5),
        ),
        pw.SizedBox(height: 18),
        pw.Text('2. Interpretación', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.Text('El valor de error y el veredicto son únicamente demostrativos. No deben utilizarse para certificar, ajustar o declarar conforme un medidor real. Los criterios de aceptación deben validarse según la clase del medidor, el procedimiento aprobado y la normativa aplicable.', style: const pw.TextStyle(fontSize: 9.5)),
        pw.SizedBox(height: 18),
        pw.Text('3. Trazabilidad y limitaciones', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.Text('Los datos del equipo (serie, firmware y calibración), la foto y la ubicación quedan registrados, y la huella SHA-256 permite detectar cualquier cambio posterior en el informe. La calibración del equipo debe certificarse contra un patrón trazable.', style: const pw.TextStyle(fontSize: 9.5)),
        if (_captura != null) ...[
          pw.SizedBox(height: 18),
          pw.Text('4. Registro fotográfico y ubicación', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Center(child: pw.Image(pw.MemoryImage(_captura!.fotoBytes), height: 260, fit: pw.BoxFit.contain)),
          pw.SizedBox(height: 8),
          pw.Text('Ubicación: ${_captura!.direccion ?? (_captura!.tieneUbicacion ? _captura!.coordenadas : 'No disponible')}', style: const pw.TextStyle(fontSize: 9.5)),
          pw.Text('Foto tomada el ${_captura!.fechaTexto}', style: const pw.TextStyle(fontSize: 9.5)),
          if (_captura!.tieneUbicacion)
            pw.UrlLink(
              destination: _captura!.enlaceMapa,
              child: pw.Text(
                'Ver en Google Maps: ${_captura!.coordenadas} (${_captura!.precisionTexto})',
                style: pw.TextStyle(fontSize: 9.5, color: PdfColors.blue700, decoration: pw.TextDecoration.underline),
              ),
            ),
        ],
        pw.SizedBox(height: 24),
        pw.Divider(color: PdfColor.fromHex('#DCE4EF')),
        pw.Text('VeriMed BT · Prototipo de software · Informe generado localmente', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      ],
    ));
    return doc;
  }

  Future<void> _showSendReportDialog() async {
    _reportEmail.clear();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enviar informe técnico'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Se generará un PDF completo marcado como DEMOSTRACIÓN.'),
          const SizedBox(height: 14),
          const _FieldLabel('Correo del destinatario'),
          TextField(controller: _reportEmail, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(hintText: 'destinatario@empresa.cl')),
          const SizedBox(height: 12),
          const Text('El envío automático requiere configurar un backend HTTPS seguro. No se almacenan claves de correo en esta aplicación.', style: TextStyle(color: vmMuted, fontSize: 12)),
        ]),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _previewReportPdf();
            },
            child: const Text('Previsualizar PDF'),
          ),
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
          FilledButton.icon(
            onPressed: _sendingReport ? null : () async {
              final email = _reportEmail.text.trim();
              if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
                _showMessage('Ingresa un correo válido.');
                return;
              }
              Navigator.pop(dialogContext);
              await _sendReportAutomatically(email);
            },
            icon: const Icon(Icons.send_rounded),
            label: const Text('Generar y enviar'),
          ),
        ],
      ),
    );
  }

  Future<void> _previewReportPdf() async {
    try {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (previewContext) => Scaffold(
          appBar: AppBar(
            title: const Text('Vista previa del informe'),
            backgroundColor: vmNavy,
            foregroundColor: Colors.white,
          ),
          body: Column(
            children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: vmYellow.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: vmYellow),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.science_outlined, color: vmNavy),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'VISTA PREVIA · DEMOSTRACIÓN. Los valores son ilustrativos y no provienen de una medición real.',
                        style: TextStyle(color: vmNavy, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PdfPreview(
                  build: (format) async {
                    final doc = await _createReportPdf();
                    return doc.save();
                  },
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                  allowPrinting: false,
                  allowSharing: false,
                  pdfFileName: 'VeriMed_BT_informe_demo.pdf',
                  loadingWidget: const Center(child: CircularProgressIndicator()),
                  onError: (context, error) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('No se pudo cargar la vista previa: $error'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ));
    } catch (e) {
      _showMessage('No se pudo abrir la vista previa del informe: $e');
    }
  }

  Future<void> _sendReportAutomatically(String email) async {
    if (veriMedEmailEndpoint.isEmpty) {
      _showMessage('PDF preparado para la función de envío. Falta configurar el endpoint HTTPS del servicio de correo seguro.');
      // Se genera localmente para validar el contenido aunque el backend aún no esté configurado.
      try {
        final doc = await _createReportPdf();
        final bytes = await doc.save();
        if (mounted) {
          await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
            title: const Text('Informe PDF generado'),
            content: Text('Se generó ${bytes.length} bytes para $email. El envío no se ejecutó porque aún no existe un servicio HTTPS configurado.\n\nEl informe está marcado como DEMOSTRACIÓN.'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido'))],
          ));
        }
      } catch (e) {
        _showMessage('No se pudo generar el PDF: $e');
      }
      return;
    }
    setState(() => _sendingReport = true);
    try {
      final doc = await _createReportPdf();
      final bytes = await doc.save();
      final response = await http.post(
        Uri.parse(veriMedEmailEndpoint),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'recipient': email,
          'subject': 'VeriMed BT - Informe técnico de demostración',
          'message': 'Adjuntamos el informe técnico de demostración de VeriMed BT. Los resultados son ilustrativos y no corresponden a una medición real.',
          'filename': 'VeriMed_BT_informe_demo.pdf',
          'pdf_base64': base64Encode(bytes),
          'report_type': 'SIMULATED_DEMO',
        }),
      ).timeout(const Duration(seconds: 25));
      if (response.statusCode == 302) {
        // Apps Script puede redirigir la respuesta después de procesar doPost.
        // El código 302 no verifica por sí solo la entrega del correo.
        await _showReportSentDialog(email, redirectResponse: true);
      } else if (response.statusCode >= 200 && response.statusCode < 300) {
        var acceptedByService = true;
        var serviceError = '';
        try {
          final payload = jsonDecode(response.body);
          if (payload is Map<String, dynamic> && payload['ok'] == false) {
            acceptedByService = false;
            serviceError = '${payload['error'] ?? 'respuesta no válida'}';
          }
        } catch (_) {
          // Algunas implementaciones de Apps Script no devuelven JSON legible.
        }
        if (acceptedByService) {
          await _showReportSentDialog(email);
        } else {
          _showMessage('El servicio no confirmó el envío: $serviceError.');
        }
      } else {
        _showMessage('El servicio rechazó el envío (${response.statusCode}). Revisa la configuración.');
      }
    } catch (e) {
      _showMessage('Error al enviar el informe. Verifica conexión y servicio HTTPS.');
    } finally {
      if (mounted) setState(() => _sendingReport = false);
    }
  }

  String _formatRecordDate(dynamic value) {
    final date = value is DateTime ? value : DateTime.tryParse('$value');
    if (date == null) return 'Fecha no disponible';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _formatElapsed(double seconds) {
    final wholeSeconds = seconds.isFinite && seconds >= 0 ? seconds.round() : 0;
    final minutes = (wholeSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (wholeSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$secs s';
  }

  Widget _buildResultHero() {
    final errorValue = _calculatedErrorPct;
    final valid = errorValue != null && errorValue.isFinite;
    final safeError = errorValue ?? 0.0;
    final conforms = valid && safeError.abs() <= _acceptanceLimitPct;
    final statusColor = conforms ? vmGreen : vmRed;
    final errorText = valid
        ? '${safeError >= 0 ? '+' : ''}${safeError.toStringAsFixed(2).replaceAll('.', ',')} %'
        : '—';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
      decoration: BoxDecoration(
        color: vmBackground,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: vmNavy.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'ENSAYO · MEDIDOR ${_accuracyClass.toUpperCase()}',
              style: const TextStyle(
                color: vmMuted,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.15,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _formatElapsed(_lastTestDurationSeconds),
            style: const TextStyle(
              color: vmNavy,
              fontSize: 42,
              height: 1.1,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.2,
            ),
          ),
          const SizedBox(height: 18),
          AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            width: 116,
            height: 116,
            decoration: BoxDecoration(
              color: conforms ? vmGreen : vmRed,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: statusColor.withOpacity(0.18),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              conforms ? Icons.check_rounded : Icons.close_rounded,
              color: Colors.white,
              size: 74,
            ),
          ),
          const SizedBox(height: 18),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              errorText,
              style: const TextStyle(
                color: vmNavy,
                fontSize: 43,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.2,
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            !valid ? 'DATOS INVÁLIDOS' : (conforms ? 'CONFORME' : 'FUERA DE LÍMITE'),
            style: TextStyle(
              color: statusColor,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(17),
            ),
            child: const Text(
              'Registro de ensayo · Informe PDF disponible',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: vmMuted,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _medicionSimulada ? 'DATOS SIMULADOS POR EL EQUIPO: resultado ilustrativo, no corresponde a una medición real.' : 'Medición del prototipo VeriMed BT (sin calibración certificada).',
            textAlign: TextAlign.center,
            style: TextStyle(color: vmMuted, fontSize: 11, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const _SectionHeading(
          title: 'Resultados',
          subtitle: 'Resumen de los ensayos',
        ),
        const SizedBox(height: 14),
        if (_testFinished) ...[
          _buildResultHero(),
          const SizedBox(height: 14),
        ],
        _Panel(
          child: Column(
            children: [
              Icon(
                _testFinished ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                color: _testFinished ? vmGreen : vmBlue,
                size: 46,
              ),
              const SizedBox(height: 8),
              Text(
                _testFinished ? 'Ensayo finalizado' : 'Aún no hay resultados',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                _testFinished ? (_medicionSimulada ? 'Calculado con datos simulados del equipo' : 'Calculado con la medición del equipo') : 'Completa un ensayo para ver el resumen.',
                style: TextStyle(
                  color: _testFinished ? vmGreen : vmMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              const Divider(color: vmBorder),
              _DataRow(label: 'N.º de serie', value: _meterSerial.text.trim().isEmpty ? 'No especificado' : _meterSerial.text.trim()),
              const Divider(height: 18, color: vmBorder),
              _DataRow(label: 'Modelo', value: _selectedMeterModel.isEmpty ? 'No seleccionado' : _selectedMeterModel),
              const Divider(height: 18, color: vmBorder),
              _DataRow(label: 'Constante Kc', value: _kcValue == null || _kcValue! <= 0 ? 'Dato inválido' : '${_kcValue!.toStringAsFixed(0)} imp/kWh'),
              const Divider(height: 18, color: vmBorder),
              _DataRow(label: 'Pulsos del medidor', value: _pulseValue == null || _pulseValue! < 0 ? 'Dato inválido' : '$_pulseValue'),
              const Divider(height: 18, color: vmBorder),
              _DataRow(label: 'Energía de referencia', value: '${_referenceEnergyWh.toStringAsFixed(4)} Wh'),
              const Divider(height: 18, color: vmBorder),
              _DataRow(label: 'Energía del medidor', value: _meterEnergyWh == null ? 'No calculable' : '${_meterEnergyWh!.toStringAsFixed(4)} Wh'),
              const Divider(height: 18, color: vmBorder),
              _DataRow(label: 'Error porcentual calculado', value: _calculatedErrorPct == null ? 'No calculable' : '${_calculatedErrorPct! >= 0 ? '+' : ''}${_calculatedErrorPct!.toStringAsFixed(2)} %'),
              const Divider(height: 18, color: vmBorder),
              _DataRow(label: 'Límite ilustrativo', value: '±${_acceptanceLimitPct.toStringAsFixed(1)} % (${_accuracyClass})'),
              const Divider(height: 18, color: vmBorder),
              _DataRow(label: 'Resultado matemático', value: _calculatedVerdict),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _testFinished ? _showSendReportDialog : null,
          icon: const Icon(Icons.picture_as_pdf_rounded),
          label: const Text('Generar y enviar informe PDF'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
        ),
        const SizedBox(height: 8),
        Text(
          _testFinished
              ? (_medicionSimulada ? 'El informe indicará que el equipo envió datos simulados.' : 'El informe incluirá la medición del equipo VeriMed BT.')
              : 'Finaliza un ensayo para habilitar el informe.',
          style: const TextStyle(color: vmMuted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        const _DemoNotice(),
      ],
    );
  }

  Future<void> _showAboutVeriMed() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: vmBlue.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.electric_meter_rounded, color: vmBlue, size: 36),
                  ),
                ),
                const SizedBox(height: 14),
                const Center(
                  child: Text(
                    'VeriMed BT',
                    style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: vmInk),
                  ),
                ),
                const SizedBox(height: 4),
                const Center(
                  child: Text(
                    'Verificador rápido monofásico',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: vmMuted, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                    decoration: BoxDecoration(
                      color: vmBlue.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: const Text(
                      'Prototipo 0.1 · Modo demostración',
                      style: TextStyle(color: vmBlue, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                const _AboutSectionTitle(title: 'Desarrollo'),
                const SizedBox(height: 9),
                const _AboutPersonRow(name: 'Tomás Quezada', role: 'Desarrollo del proyecto'),
                const SizedBox(height: 8),
                const _AboutPersonRow(name: 'Felipe Martínez', role: 'Desarrollo del proyecto'),
                const SizedBox(height: 18),
                const _AboutSectionTitle(title: 'Aviso legal y uso'),
                const SizedBox(height: 7),
                const Text(
                  'Esta aplicación forma parte de un prototipo en desarrollo. En su versión actual, la conexión y los valores mostrados son simulados y no representan mediciones reales de un equipo VeriMed BT.',
                  style: TextStyle(color: vmMuted, fontSize: 12, height: 1.45),
                ),
                const SizedBox(height: 9),
                const Text(
                  'Los resultados de demostración no deben utilizarse para certificar, ajustar ni declarar conforme un medidor eléctrico. Cualquier ensayo real requiere integrar y validar el hardware, el procedimiento de medición y las medidas de seguridad aplicables.',
                  style: TextStyle(color: vmMuted, fontSize: 12, height: 1.45),
                ),
                const SizedBox(height: 9),
                const Text(
                  'Las marcas y nombres de productos mencionados pertenecen a sus respectivos titulares y se incluyen únicamente con fines de referencia técnica.',
                  style: TextStyle(color: vmMuted, fontSize: 12, height: 1.45),
                ),
                const SizedBox(height: 16),
                const Divider(color: vmBorder),
                const SizedBox(height: 8),
                const Center(
                  child: Text(
                    '© 2026 · Proyecto VeriMed BT',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: vmMuted, fontSize: 11),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cerrar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMore() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const _SectionHeading(title: 'Más', subtitle: 'Herramientas y configuración'),
        const SizedBox(height: 14),
        _Panel(
          child: Column(
            children: [
              _MoreRow(
                icon: Icons.history_rounded,
                title: 'Historial de ensayos',
                subtitle: '${_testHistory.length} registro(s) de esta sesión',
                onTap: _showHistory,
              ),
              const Divider(color: vmBorder),
              _MoreRow(
                icon: Icons.show_chart_rounded,
                title: 'Gráfico de error',
                subtitle: 'Comparación visual de los últimos ensayos simulados',
                onTap: _showDemoChart,
              ),
              const Divider(color: vmBorder),
              _MoreRow(
                icon: Icons.file_download_outlined,
                title: 'Exportar datos CSV',
                subtitle: 'Copiar registros para abrirlos en Excel',
                onTap: _exportCsv,
              ),
              const Divider(color: vmBorder),
              _MoreRow(
                icon: Icons.settings_outlined,
                title: 'Ajustes',
                subtitle: 'Unidades e información de la aplicación',
                onTap: () => _showMessage('VeriMed BT • prototipo Flutter • modo demostración.'),
              ),
              const Divider(color: vmBorder),
              _MoreRow(
                icon: Icons.info_outline_rounded,
                title: 'Acerca de VeriMed BT',
                subtitle: 'Desarrollo, información legal y versión',
                onTap: _showAboutVeriMed,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const _DemoNotice(),
      ],
    );
  }
}

class _AboutSectionTitle extends StatelessWidget {
  const _AboutSectionTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: vmInk),
    );
  }
}

class _AboutPersonRow extends StatelessWidget {
  const _AboutPersonRow({required this.name, required this.role});
  final String name;
  final String role;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: vmBlue.withOpacity(0.09),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.person_outline_rounded, color: vmBlue, size: 21),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: vmInk)),
              const SizedBox(height: 2),
              Text(role, style: const TextStyle(fontSize: 11, color: vmMuted)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({this.inverted = false});
  final bool inverted;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.asset(
            'assets/verimed_isotipo.png',
            width: 31,
            height: 31,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => const Icon(
              Icons.electric_meter_rounded,
              color: vmGreen,
              size: 28,
            ),
          ),
        ),
        const SizedBox(width: 8),
        RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.5),
            children: [
              TextSpan(text: 'VeriMed ', style: TextStyle(color: inverted ? Colors.white : vmNavy)),
              const TextSpan(text: 'BT', style: TextStyle(color: vmGreen)),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: vmInk)),
        const SizedBox(height: 3),
        Text(subtitle, style: const TextStyle(fontSize: 13, color: vmMuted)),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: vmBorder),
        boxShadow: const [
          BoxShadow(color: Color(0x080D2742), blurRadius: 12, offset: Offset(0, 3)),
        ],
      ),
      child: child,
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.icon, required this.value, required this.label});
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: vmBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, color: vmBlue, size: 22),
          const SizedBox(height: 9),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: vmInk)),
          ),
          const SizedBox(height: 3),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: vmMuted)),
        ],
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  const _DataRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(color: vmMuted, fontSize: 13))),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(color: vmInk, fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.name, required this.detail, this.active = false});
  final String name;
  final String detail;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Icon(Icons.bluetooth_rounded, color: active ? vmBlue : vmMuted, size: 25),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(detail, style: const TextStyle(color: vmMuted, fontSize: 11)),
              ],
            ),
          ),
          if (active) const Icon(Icons.signal_cellular_alt_rounded, color: vmBlue),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: vmInk)),
    );
  }
}

class _DemoNotice extends StatelessWidget {
  const _DemoNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: vmBlue.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: vmBlue.withOpacity(0.30)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: vmBlue, size: 19),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              'Prototipo: la app se conecta al equipo VeriMed BT por Bluetooth. Mientras el equipo indique datos simulados, los resultados son ilustrativos y no sirven para certificar un medidor.',
              style: TextStyle(color: vmNavy, fontSize: 12, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoreRow extends StatelessWidget {
  const _MoreRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: vmBlue.withOpacity(0.09),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: vmBlue),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(color: vmMuted, fontSize: 12)),
      trailing: const Icon(Icons.chevron_right_rounded, color: vmMuted),
      onTap: onTap,
    );
  }
}
