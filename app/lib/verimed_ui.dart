// =====================================================================
//  VeriMed BT · Componentes visuales animados (diseño "B · Claro y limpio")
// =====================================================================
//  Solo usa Flutter (sin paquetes extra). Todo respeta "reducir animaciones"
//  del teléfono: si está activo, las animaciones duran 0 ms.
// =====================================================================
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class VmColors {
  static const navy = Color(0xFF12263F);
  static const navyDeep = Color(0xFF0B1A2E);
  static const ink = Color(0xFF0B2545);
  static const muted = Color(0xFF5B6B80);
  static const bg = Color(0xFFF3F6FB);
  static const line = Color(0xFFE2E8F1);
  static const blue = Color(0xFF1E6FD9);
  static const blueSoft = Color(0xFFE6EFFC);
  static const green = Color(0xFF0E8A63); // texto verde (contraste sobre blanco)
  static const greenBright = Color(0xFF3DDC97); // puntos y acentos sobre azul oscuro
  static const greenSoft = Color(0xFFE3F6EE);
  static const amber = Color(0xFFF5B321);
  static const amberInk = Color(0xFFA76A00);
  static const amberSoft = Color(0xFFFFF4DC);
  static const red = Color(0xFFD23B41);
  static const redSoft = Color(0xFFF8D9DA);
  static const onNavyMuted = Color(0xFFA9BCD6);
}

/// true si el usuario pidió reducir animaciones en el teléfono.
bool vmSinAnimaciones(BuildContext context) => MediaQuery.maybeOf(context)?.disableAnimations ?? false;

Duration vmDur(BuildContext context, int ms) => vmSinAnimaciones(context) ? Duration.zero : Duration(milliseconds: ms);

/// Estilo de números grandes (cifras del mismo ancho para que no "salten").
TextStyle vmNumero(double size, {Color color = VmColors.ink, FontWeight weight = FontWeight.w800}) => TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: 1.0,
      letterSpacing: -0.5,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

String vmComa(double v, int decimales) => v.toStringAsFixed(decimales).replaceAll('.', ',');

/// Separador de miles chileno: 1.000
String vmMiles(num v) {
  final s = v.round().abs().toString();
  final b = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

// ---------------------------------------------------------------------
//  Entrada: aparece con fundido + desplazamiento, con retraso opcional.
//  Úsalo con delay creciente para listas escalonadas.
// ---------------------------------------------------------------------
class VmEntrance extends StatefulWidget {
  const VmEntrance({super.key, required this.child, this.delay = Duration.zero, this.offsetY = 18});
  final Widget child;
  final Duration delay;
  final double offsetY;

  @override
  State<VmEntrance> createState() => _VmEntranceState();
}

class _VmEntranceState extends State<VmEntrance> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 560));
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  bool _iniciado = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciado) return;
    _iniciado = true;
    if (vmSinAnimaciones(context)) {
      _c.value = 1;
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _t.value,
        child: Transform.translate(offset: Offset(0, widget.offsetY * (1 - _t.value)), child: child),
      ),
    );
  }
}

/// Retraso para el elemento n de una lista escalonada.
Duration vmStagger(int n, {int ms = 70}) => Duration(milliseconds: 60 + n * ms);

// ---------------------------------------------------------------------
//  Pulsable: se hunde levemente al tocar y da una vibración suave.
// ---------------------------------------------------------------------
class VmPressable extends StatefulWidget {
  const VmPressable({super.key, required this.child, this.onTap, this.semanticLabel});
  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  State<VmPressable> createState() => _VmPressableState();
}

class _VmPressableState extends State<VmPressable> {
  bool _abajo = false;

  @override
  Widget build(BuildContext context) {
    final activo = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: activo,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: activo ? (_) => setState(() => _abajo = true) : null,
        onTapCancel: activo ? () => setState(() => _abajo = false) : null,
        onTapUp: activo ? (_) => setState(() => _abajo = false) : null,
        onTap: activo
            ? () {
                HapticFeedback.lightImpact();
                widget.onTap!();
              }
            : null,
        child: AnimatedScale(
          scale: _abajo ? 0.965 : 1,
          duration: vmDur(context, 120),
          curve: Curves.easeOut,
          child: AnimatedOpacity(opacity: activo ? 1 : 0.55, duration: vmDur(context, 200), child: widget.child),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
//  Número animado: cuenta desde el valor anterior hasta el nuevo.
// ---------------------------------------------------------------------
class VmAnimatedNumber extends StatelessWidget {
  const VmAnimatedNumber({super.key, required this.value, required this.format, required this.style, this.durationMs = 650});
  final double value;
  final String Function(double) format;
  final TextStyle style;
  final int durationMs;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value),
      duration: vmDur(context, durationMs),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(format(v), style: style),
    );
  }
}

// ---------------------------------------------------------------------
//  Punto "en vivo": late con un halo (equipo conectado, midiendo…).
// ---------------------------------------------------------------------
class VmLiveDot extends StatefulWidget {
  const VmLiveDot({super.key, this.color = VmColors.greenBright, this.size = 9, this.activo = true});
  final Color color;
  final double size;
  final bool activo;

  @override
  State<VmLiveDot> createState() => _VmLiveDotState();
}

class _VmLiveDotState extends State<VmLiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _actualizar();
  }

  @override
  void didUpdateWidget(covariant VmLiveDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _actualizar();
  }

  void _actualizar() {
    if (widget.activo && !vmSinAnimaciones(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s * 2.6,
      height: s * 2.6,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Stack(
          alignment: Alignment.center,
          children: [
            if (widget.activo)
              Container(
                width: s + s * 1.6 * _c.value,
                height: s + s * 1.6 * _c.value,
                decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withOpacity(0.45 * (1 - _c.value))),
              ),
            Container(width: s, height: s, decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
//  Pestañas con transición: mantiene el estado de cada página (como
//  IndexedStack) y al cambiar hace un fundido con leve desplazamiento.
// ---------------------------------------------------------------------
class VmFadeIndexedStack extends StatefulWidget {
  const VmFadeIndexedStack({super.key, required this.index, required this.children});
  final int index;
  final List<Widget> children;

  @override
  State<VmFadeIndexedStack> createState() => _VmFadeIndexedStackState();
}

class _VmFadeIndexedStackState extends State<VmFadeIndexedStack> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 320), value: 1);
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  late final Animation<Offset> _desliz = Tween<Offset>(begin: const Offset(0, 0.025), end: Offset.zero).animate(_t);

  @override
  void didUpdateWidget(covariant VmFadeIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      if (vmSinAnimaciones(context)) {
        _c.value = 1;
      } else {
        _c.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _t,
      child: SlideTransition(
        position: _desliz,
        child: IndexedStack(index: widget.index, children: widget.children),
      ),
    );
  }
}

// ---------------------------------------------------------------------
//  Tarjeta blanca redondeada (estilo B)
// ---------------------------------------------------------------------
class VmCard extends StatelessWidget {
  const VmCard({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.color = Colors.white, this.sombra = false, this.radius = 22});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final bool sombra;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: sombra
            ? [BoxShadow(color: VmColors.ink.withOpacity(0.10), blurRadius: 30, offset: const Offset(0, 12), spreadRadius: -10)]
            : null,
      ),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------
//  Barra de progreso animada (null = indeterminada)
// ---------------------------------------------------------------------
class VmProgressBar extends StatelessWidget {
  const VmProgressBar({super.key, required this.value, this.color = VmColors.blue, this.height = 12});
  final double? value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: value == null
            ? LinearProgressIndicator(backgroundColor: const Color(0xFFE6EDF6), color: color)
            : TweenAnimationBuilder<double>(
                tween: Tween<double>(end: value!.clamp(0.0, 1.0).toDouble()),
                duration: vmDur(context, 500),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => Stack(
                  children: [
                    Container(color: const Color(0xFFE6EDF6)),
                    FractionallySizedBox(
                      widthFactor: v,
                      child: Container(
                        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(height / 2)),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
//  Pasos del ensayo: Configurar → 1er pulso → Midiendo → Resultado
// ---------------------------------------------------------------------
class VmStepper extends StatelessWidget {
  const VmStepper({super.key, required this.pasos, required this.actual});
  final List<String> pasos;
  final int actual; // índice del paso en curso (los anteriores quedan listos)

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < pasos.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: vmDur(context, 400),
                  curve: Curves.easeOut,
                  height: 5,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: i < actual ? VmColors.green : (i == actual ? VmColors.blue : const Color(0xFFD5DFEC)),
                  ),
                ),
                const SizedBox(height: 6),
                AnimatedDefaultTextStyle(
                  duration: vmDur(context, 300),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: i <= actual ? FontWeight.w700 : FontWeight.w500,
                    color: i < actual ? VmColors.green : (i == actual ? VmColors.blue : VmColors.muted),
                  ),
                  child: Text(pasos[i], maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------
//  Línea de tiempo de pulsos: cada pulso que llega "salta" en la línea.
//  Con muchos pulsos (>16) muestra solo la línea y el contador.
// ---------------------------------------------------------------------
class VmPulseTimeline extends StatelessWidget {
  const VmPulseTimeline({super.key, required this.total, required this.hechos, required this.duracionTexto});
  final int total;
  final int hechos;
  final String duracionTexto; // "13,5 s"

  @override
  Widget build(BuildContext context) {
    final n = math.max(total, 1);
    final frac = (hechos / n).clamp(0.0, 1.0).toDouble();
    final conPuntos = n <= 16;
    return SizedBox(
      height: 58,
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(left: 0, right: 0, top: 26, child: Container(height: 3, color: const Color(0xFFE6EDF6))),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(end: frac),
              duration: vmDur(context, 600),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => Positioned(left: 0, top: 26, child: Container(width: w * v, height: 3, color: VmColors.blue)),
            ),
            if (conPuntos)
              for (var i = 0; i <= n; i++)
                Positioned(
                  left: w * i / n - 9,
                  top: 18.5,
                  child: _PuntoPulso(estado: i < hechos ? 2 : (i == hechos ? 1 : 0)),
                ),
            Positioned(left: 0, top: 42, child: const Text('0 s', style: TextStyle(fontSize: 11, color: VmColors.muted))),
            Positioned(right: 0, top: 42, child: Text(duracionTexto, style: const TextStyle(fontSize: 11, color: VmColors.muted))),
            if (hechos > 0 && hechos < n)
              Positioned(
                left: (w * hechos / n - 18).clamp(0.0, math.max(0.0, w - 40)).toDouble(),
                top: 0,
                child: const Text('ahora', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: VmColors.amberInk)),
              ),
          ],
        );
      }),
    );
  }
}

class _PuntoPulso extends StatelessWidget {
  const _PuntoPulso({required this.estado}); // 0 pendiente, 1 actual, 2 listo
  final int estado;

  @override
  Widget build(BuildContext context) {
    final listo = estado == 2, actual = estado == 1;
    return SizedBox(
      width: 18,
      height: 18,
      child: Center(
        child: TweenAnimationBuilder<double>(
          key: ValueKey(estado),
          tween: Tween<double>(begin: listo ? 0.4 : 1, end: 1),
          duration: vmDur(context, listo ? 500 : 1),
          curve: Curves.elasticOut,
          builder: (context, s, child) => Transform.scale(scale: s, child: child),
          child: AnimatedContainer(
            duration: vmDur(context, 300),
            width: actual ? 18 : 14,
            height: actual ? 18 : 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: listo ? VmColors.blue : (actual ? VmColors.amber : Colors.white),
              border: listo || actual ? null : Border.all(color: const Color(0xFFC9D6E6), width: 2),
              boxShadow: actual ? [BoxShadow(color: VmColors.amber.withOpacity(0.35), blurRadius: 0, spreadRadius: 6)] : null,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
//  Aguja tipo velocímetro: de −2×límite a +2×límite, banda verde ±límite.
//  La aguja entra desde la izquierda y rebota hasta el error.
// ---------------------------------------------------------------------
class VmErrorGauge extends StatelessWidget {
  const VmErrorGauge({super.key, required this.error, required this.limite, this.width = 300});
  final double? error;
  final double limite;
  final double width;

  @override
  Widget build(BuildContext context) {
    final rango = limite * 2;
    final destino = (error ?? 0).clamp(-rango, rango).toDouble();
    final h = width * 0.56;
    String etiqueta(double v) => '${v > 0 ? '+' : (v < 0 ? '−' : '')}${vmComa(v.abs(), v.abs() < 10 && v != v.roundToDouble() ? 1 : 0)} %';
    return SizedBox(
      width: width,
      height: h,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: -rango, end: destino),
        duration: vmDur(context, 1700),
        curve: Curves.elasticOut,
        builder: (context, v, _) => Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _GaugePainter(valor: v, rango: rango, limite: limite, sinDato: error == null))),
            Positioned(left: 0, bottom: 0, child: Text(etiqueta(-rango), style: const TextStyle(fontSize: 12, color: VmColors.muted))),
            Positioned(right: 0, bottom: 0, child: Text(etiqueta(rango), style: const TextStyle(fontSize: 12, color: VmColors.muted))),
          ],
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.valor, required this.rango, required this.limite, required this.sinDato});
  final double valor, rango, limite;
  final bool sinDato;

  @override
  void paint(Canvas canvas, Size size) {
    const grosor = 22.0;
    final cx = size.width / 2;
    final r = math.min(size.width / 2 - grosor / 2 - 8, size.height - grosor / 2 - 22);
    final cy = r + grosor / 2 + 4;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);
    final fondo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = grosor
      ..strokeCap = StrokeCap.round
      ..color = VmColors.redSoft;
    canvas.drawArc(rect, math.pi, math.pi, false, fondo);
    final banda = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = grosor
      ..color = const Color(0xFFBFE9D8);
    final inicio = math.pi + (rango - limite) / (2 * rango) * math.pi;
    canvas.drawArc(rect, inicio, limite / rango * math.pi, false, banda);
    // marcas cada medio límite
    final marca = Paint()
      ..color = Colors.white
      ..strokeWidth = 2;
    for (var k = -4; k <= 4; k++) {
      final a = math.pi + (k / 4 + 1) / 2 * math.pi;
      canvas.drawLine(
        Offset(cx + (r - grosor / 2) * math.cos(a), cy + (r - grosor / 2) * math.sin(a)),
        Offset(cx + (r + grosor / 2) * math.cos(a), cy + (r + grosor / 2) * math.sin(a)),
        marca,
      );
    }
    if (sinDato) return;
    final t = ((valor + rango) / (2 * rango)).clamp(0.0, 1.0).toDouble();
    final a = math.pi + t * math.pi;
    final aguja = Paint()
      ..color = VmColors.ink
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx, cy), Offset(cx + (r - 18) * math.cos(a), cy + (r - 18) * math.sin(a)), aguja);
    canvas.drawCircle(Offset(cx, cy), 10, Paint()..color = VmColors.ink);
    canvas.drawCircle(Offset(cx, cy), 4, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) => old.valor != valor || old.limite != limite || old.sinDato != sinDato;
}

// ---------------------------------------------------------------------
//  Insignia del veredicto: aparece con rebote.
// ---------------------------------------------------------------------
class VmVerdictPill extends StatelessWidget {
  const VmVerdictPill({super.key, required this.aprobado, required this.texto});
  final bool aprobado;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final fg = aprobado ? const Color(0xFF0B6E4F) : const Color(0xFFB42328);
    final bg = aprobado ? VmColors.greenSoft : VmColors.redSoft;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: vmDur(context, 900),
      curve: const Interval(0.45, 1, curve: Curves.elasticOut),
      builder: (context, s, child) => Transform.scale(scale: s, child: child),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(aprobado ? Icons.check_rounded : Icons.close_rounded, size: 18, color: fg),
            const SizedBox(width: 6),
            Text(texto, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.6)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
//  Barras de la semana (crecen escalonadas al aparecer)
// ---------------------------------------------------------------------
class VmWeekBars extends StatelessWidget {
  const VmWeekBars({super.key, required this.valores, required this.etiquetas, this.alto = 70});
  final List<int> valores;
  final List<String> etiquetas;
  final double alto;

  @override
  Widget build(BuildContext context) {
    final maximo = valores.fold<int>(1, (m, v) => math.max(m, v));
    return SizedBox(
      height: alto + 20,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < valores.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: 1),
                    duration: vmDur(context, 700 + i * 90),
                    curve: Interval(math.min(0.6, i * 0.08), 1, curve: Curves.easeOutBack),
                    builder: (context, k, _) => Container(
                      height: math.max(4.0, alto * valores[i] / maximo * k),
                      decoration: BoxDecoration(
                        color: valores[i] == 0 ? const Color(0xFFD5DFEC) : VmColors.blue,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(etiquetas[i], style: const TextStyle(fontSize: 11, color: VmColors.muted)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
//  Acceso rápido (ícono en cuadro de color + texto)
// ---------------------------------------------------------------------
class VmQuickAction extends StatelessWidget {
  const VmQuickAction({super.key, required this.icon, required this.label, required this.fondo, required this.color, this.onTap});
  final IconData icon;
  final String label;
  final Color fondo, color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return VmPressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: color, size: 23),
            ),
            const SizedBox(height: 8),
            Text(label, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: VmColors.ink)),
          ],
        ),
      ),
    );
  }
}
