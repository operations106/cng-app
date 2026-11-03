import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

const String kServiceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
const String kCmdUuid = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
const String kDataUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

enum Mood { sleepy, happy, ok, worried, sad }

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  runApp(const CngApp());
}

class CngApp extends StatelessWidget {
  const CngApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CNG Buddy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFFFF9EC7),
        scaffoldBackgroundColor: const Color(0xFF1E1747),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _cmdChar;
  StreamSubscription<List<int>>? _dataSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;

  late final AnimationController _loop;
  late final AnimationController _blink;
  late final AnimationController _jump;
  Timer? _blinkTimer;

  double _percent = 0;
  double _voltage = 0;
  bool _connected = false;
  bool _busy = false;
  String _status = 'Sleeping';

  @override
  void initState() {
    super.initState();
    _loop = AnimationController(vsync: this, duration: const Duration(seconds: 3))
      ..repeat();
    _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 130));
    _jump = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 3200), (_) {
      if (!mounted) return;
      _blink.forward().then((_) {
        if (mounted) _blink.reverse();
      });
    });
  }

  Mood get _mood {
    if (!_connected) return Mood.sleepy;
    if (_percent >= 60) return Mood.happy;
    if (_percent >= 30) return Mood.ok;
    if (_percent >= 15) return Mood.worried;
    return Mood.sad;
  }

  Color _levelColor(double p) {
    if (p < 15) return const Color(0xFFFF7B8A);
    if (p < 30) return const Color(0xFFFFC27A);
    return const Color(0xFF7CF5C2);
  }

  String get _message {
    if (!_connected) return 'Zzz... mujhe jagao 😴';
    if (_percent >= 75) return 'Mast full hai! 🎉';
    if (_percent >= 45) return 'Sab badhiya hai 😊';
    if (_percent >= 30) return 'Abhi chal jayega 🙂';
    if (_percent >= 15) return 'CNG kam ho rahi hai 🥺';
    return 'Bhookh lagi hai! Fill karwao 😭';
  }

  void _poke() => _jump.forward(from: 0);

  Future<void> _scanAndConnect() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = 'Searching...';
    });

    StreamSubscription<List<ScanResult>>? scanSub;
    try {
      if (!await FlutterBluePlus.isSupported) {
        throw 'Bluetooth is not supported on this phone';
      }
      if (Platform.isAndroid) {
        await FlutterBluePlus.turnOn();
      }

      BluetoothDevice? found;
      final done = Completer<void>();
      scanSub = FlutterBluePlus.onScanResults.listen((results) {
        if (results.isNotEmpty && found == null) {
          found = results.last.device;
          if (!done.isCompleted) done.complete();
        }
      });

      await FlutterBluePlus.startScan(
        withServices: [Guid(kServiceUuid)],
        timeout: const Duration(seconds: 10),
      );
      await Future.any([
        done.future,
        Future.delayed(const Duration(seconds: 10)),
      ]);
      await FlutterBluePlus.stopScan();
      await scanSub.cancel();
      scanSub = null;

      if (found == null) {
        throw 'CNG_Meter not found. ESP32 ON hai? Phir se try karo.';
      }

      setState(() => _status = 'Connecting...');
      final dev = found!;
      await dev.connect(timeout: const Duration(seconds: 10));
      _device = dev;

      _connSub?.cancel();
      _connSub = dev.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected && mounted) {
          setState(() {
            _connected = false;
            _status = 'Sleeping';
          });
        }
      });

      final services = await dev.discoverServices();
      final svc = services.firstWhere((s) => s.uuid == Guid(kServiceUuid));
      for (final c in svc.characteristics) {
        if (c.uuid == Guid(kDataUuid)) {
          await c.setNotifyValue(true);
          _dataSub?.cancel();
          _dataSub = c.onValueReceived.listen(_onData);
        } else if (c.uuid == Guid(kCmdUuid)) {
          _cmdChar = c;
        }
      }

      if (!mounted) return;
      setState(() {
        _connected = true;
        _status = 'Awake';
      });
      _poke();
    } catch (e) {
      await scanSub?.cancel();
      if (mounted) {
        setState(() {
          _connected = false;
          _status = 'Sleeping';
        });
        _snack(e.toString());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onData(List<int> value) {
    try {
      final parts = utf8.decode(value).trim().split(',');
      final p = double.parse(parts[0]);
      final v = parts.length > 1 ? double.parse(parts[1]) : 0.0;
      if (mounted) {
        setState(() {
          _percent = p.clamp(0, 100).toDouble();
          _voltage = v;
        });
      }
    } catch (_) {}
  }

  Future<void> _disconnect() async {
    await _dataSub?.cancel();
    await _device?.disconnect();
    if (mounted) {
      setState(() {
        _connected = false;
        _status = 'Sleeping';
      });
    }
  }

  Future<void> _sendCmd(String cmd, String label) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2E2563),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Text(
          cmd == 'RESET'
              ? 'Calibration default par reset hogi.'
              : 'Abhi ki sensor voltage (${_voltage.toStringAsFixed(2)} V) ko '
                  '${cmd == 'SETEMPTY' ? '0% (empty)' : '100% (full)'} set kiya jayega.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _cmdChar?.write(utf8.encode(cmd));
      _snack('Done ✨');
    } catch (e) {
      _snack('Command failed: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ));
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _loop.dispose();
    _blink.dispose();
    _jump.dispose();
    _dataSub?.cancel();
    _connSub?.cancel();
    _device?.disconnect();
    super.dispose();
  }

  Widget _mascot(double value) {
    return GestureDetector(
      onTap: _poke,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: Listenable.merge([_loop, _blink, _jump]),
          builder: (context, _) {
            final t = _loop.value;
            final jump = math.sin(math.pi * _jump.value);
            final dy = math.sin(t * 2 * math.pi) * 8 - 60 * jump;
            final shake =
                _mood == Mood.sad ? math.sin(t * 2 * math.pi * 10) * 0.03 : 0.0;
            return Transform.translate(
              offset: Offset(0, dy),
              child: Transform.rotate(
                angle: shake,
                child: Transform.scale(
                  scaleX: 1 - 0.05 * jump,
                  scaleY: 1 + 0.08 * jump,
                  child: SizedBox(
                    width: 260,
                    height: 290,
                    child: CustomPaint(
                      painter: TankPainter(
                        level: value.clamp(0.0, 1.0).toDouble(),
                        t: t,
                        blink: _blink.value,
                        color: _levelColor(value * 100),
                        mood: _mood,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final low = _connected && _percent < 15;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF2A1B5C), Color(0xFF16305E)],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _loop,
                builder: (_, __) =>
                    CustomPaint(painter: StarsPainter(_loop.value)),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('CNG Buddy ⛽',
                              style: TextStyle(
                                  fontSize: 26, fontWeight: FontWeight.w900)),
                          Text('tumhara cute gas meter',
                              style: TextStyle(fontSize: 12, color: Colors.white60)),
                        ],
                      ),
                      const Spacer(),
                      _StatusChip(connected: _connected, text: _status, anim: _loop),
                    ],
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    child: low
                        ? Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(top: 14),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0x33FF7B8A),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFFF7B8A)),
                            ),
                            child: const Row(
                              children: [
                                Text('🚨', style: TextStyle(fontSize: 20)),
                                SizedBox(width: 10),
                                Expanded(
                                    child: Text('CNG kam hai! Jaldi fill karwao.',
                                        style:
                                            TextStyle(fontWeight: FontWeight.w700))),
                              ],
                            ),
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                  Expanded(
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: _connected ? _percent / 100 : 0),
                          duration: const Duration(milliseconds: 1100),
                          curve: Curves.easeOutBack,
                          builder: (context, value, _) {
                            final shown = (value * 100).round().clamp(0, 100);
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _mascot(value),
                                const SizedBox(height: 6),
                                Text(
                                  _connected ? '$shown%' : '--',
                                  style: TextStyle(
                                    fontSize: 56,
                                    fontWeight: FontWeight.w900,
                                    color: _connected
                                        ? _levelColor(value * 100)
                                        : Colors.white38,
                                  ),
                                ),
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 400),
                                  transitionBuilder: (child, anim) => FadeTransition(
                                    opacity: anim,
                                    child: ScaleTransition(scale: anim, child: child),
                                  ),
                                  child: Text(
                                    _message,
                                    key: ValueKey(_message),
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white70),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _Pop(
                          ms: 700,
                          child: _InfoCard(
                            emoji: '⚡',
                            label: 'Sensor voltage',
                            value: _connected ? '${_voltage.toStringAsFixed(2)} V' : '--',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Pop(
                          ms: 950,
                          child: _InfoCard(
                            emoji: '📡',
                            label: 'Device',
                            value: _connected ? 'CNG_Meter' : 'Offline',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (_connected)
                    _Pop(
                      ms: 800,
                      child: Row(
                        children: [
                          Expanded(
                            child: _SoftButton(
                              label: '😴 Set Empty',
                              onTap: () => _sendCmd('SETEMPTY', 'Set Empty (0%)'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _SoftButton(
                              label: '😋 Set Full',
                              onTap: () => _sendCmd('SETFULL', 'Set Full (100%)'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 52,
                            child: _SoftButton(
                              label: '🔄',
                              onTap: () => _sendCmd('RESET', 'Reset calibration'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  _BouncyButton(
                    onTap: _busy ? null : (_connected ? _disconnect : _scanAndConnect),
                    child: Container(
                      width: double.infinity,
                      height: 58,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(29),
                        gradient: LinearGradient(
                          colors: _connected
                              ? const [Color(0xFF8E7CFF), Color(0xFFB892FF)]
                              : const [Color(0xFFFF8FC4), Color(0xFFFFB38A)],
                        ),
                        boxShadow: const [
                          BoxShadow(
                              color: Color(0x55FF8FC4),
                              blurRadius: 18,
                              offset: Offset(0, 8)),
                        ],
                      ),
                      child: _busy
                          ? const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.5, color: Colors.white)),
                                SizedBox(width: 12),
                                Text('Ruko zara...',
                                    style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white)),
                              ],
                            )
                          : Text(
                              _connected ? 'Bye bye 👋' : 'Connect karo 💚',
                              style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- Small widgets ----------

class _StatusChip extends StatelessWidget {
  final bool connected;
  final String text;
  final Animation<double> anim;
  const _StatusChip(
      {required this.connected, required this.text, required this.anim});

  @override
  Widget build(BuildContext context) {
    final c = connected ? const Color(0xFF7CF5C2) : Colors.white60;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: c.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: anim,
            builder: (_, __) {
              final s = connected ? 1 + 0.35 * math.sin(anim.value * 2 * math.pi) : 1.0;
              return Transform.scale(
                  scale: s, child: Icon(Icons.circle, size: 10, color: c));
            },
          ),
          const SizedBox(width: 7),
          Text(text,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c)),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String emoji;
  final String label;
  final String value;
  const _InfoCard({required this.emoji, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.white60)),
        ],
      ),
    );
  }
}

class _Pop extends StatelessWidget {
  final Widget child;
  final int ms;
  const _Pop({required this.child, required this.ms});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: ms),
      curve: Curves.elasticOut,
      builder: (context, v, c) => Transform.scale(
        scale: v,
        child: Opacity(opacity: v.clamp(0.0, 1.0).toDouble(), child: c),
      ),
      child: child,
    );
  }
}

class _BouncyButton extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget child;
  const _BouncyButton({required this.onTap, required this.child});

  @override
  State<_BouncyButton> createState() => _BouncyButtonState();
}

class _BouncyButtonState extends State<_BouncyButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.93 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: Opacity(opacity: widget.onTap == null ? 0.85 : 1, child: widget.child),
      ),
    );
  }
}

class _SoftButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SoftButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _BouncyButton(
      onTap: onTap,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.18)),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

// ---------- Painters ----------

class StarsPainter extends CustomPainter {
  final double t;
  StarsPainter(this.t);

  static final List<List<double>> _stars = _gen();

  static List<List<double>> _gen() {
    final r = math.Random(7);
    return List.generate(
      28,
      (_) => [r.nextDouble(), r.nextDouble(), 1 + r.nextDouble() * 2.2, r.nextDouble() * 6.28],
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in _stars) {
      final op = 0.15 + 0.6 * (0.5 + 0.5 * math.sin(t * 2 * math.pi + s[3]));
      canvas.drawCircle(
        Offset(s[0] * size.width, s[1] * size.height),
        s[2],
        Paint()..color = Colors.white.withOpacity(op),
      );
    }
  }

  @override
  bool shouldRepaint(covariant StarsPainter old) => old.t != t;
}

class TankPainter extends CustomPainter {
  final double level;
  final double t;
  final double blink;
  final Color color;
  final Mood mood;

  const TankPainter({
    required this.level,
    required this.t,
    required this.blink,
    required this.color,
    required this.mood,
  });

  static const Color ink = Color(0xFF2B2145);
  static const double tau = math.pi * 2;

  Path _wavePath(Rect r, double surface, double amp, double phase, double freq) {
    final p = Path()..moveTo(r.left, r.bottom + 2);
    for (double x = 0; x <= r.width; x += 4) {
      p.lineTo(r.left + x,
          surface + math.sin(x / r.width * tau * freq + phase) * amp);
    }
    p.lineTo(r.right, r.bottom + 2);
    p.close();
    return p;
  }

  void _star(Canvas canvas, Offset c, double r, Paint paint) {
    final p = Path();
    for (int i = 0; i < 8; i++) {
      final a = i * math.pi / 4 - math.pi / 2;
      final rad = i.isEven ? r : r * 0.35;
      final pt = Offset(c.dx + math.cos(a) * rad, c.dy + math.sin(a) * rad);
      if (i == 0) {
        p.moveTo(pt.dx, pt.dy);
      } else {
        p.lineTo(pt.dx, pt.dy);
      }
    }
    p.close();
    canvas.drawPath(p, paint);
  }

  void _text(Canvas canvas, String s, Offset o, double fs, double op) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
            color: Colors.white.withOpacity(op),
            fontSize: fs,
            fontWeight: FontWeight.w900),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, o);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final cx = w / 2;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(30, 46, w - 60, size.height - 76),
      const Radius.circular(84),
    );
    final pink = Paint()..color = const Color(0xFFFFA8C8);

    // feet
    canvas.drawOval(
        Rect.fromCenter(center: Offset(cx - 48, body.bottom + 6), width: 56, height: 26),
        pink);
    canvas.drawOval(
        Rect.fromCenter(center: Offset(cx + 48, body.bottom + 6), width: 56, height: 26),
        pink);

    // cap
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx, 36), width: 60, height: 30),
          const Radius.circular(12)),
      Paint()..color = const Color(0xFFFFD166),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx, 32), width: 36, height: 6),
          const Radius.circular(3)),
      Paint()..color = Colors.white.withOpacity(0.6),
    );

    // hands (behind body)
    final happy = mood == Mood.happy;
    final baseY = happy ? 150.0 : 190.0;
    final amp = happy ? 14.0 : 5.0;
    final f = happy ? 2.0 : 1.0;
    canvas.drawCircle(
        Offset(body.left + 2, baseY + math.sin(tau * t * f) * amp), 15, pink);
    canvas.drawCircle(
        Offset(body.right - 2, baseY + math.sin(tau * t * f + math.pi) * amp), 15, pink);

    // glass body
    canvas.drawRRect(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFE6E0FF)],
        ).createShader(body.outerRect),
    );

    // liquid
    final surface = body.bottom - body.height * level;
    if (level > 0.005) {
      canvas.save();
      canvas.clipRRect(body);
      final rect = body.outerRect;
      canvas.drawPath(
        _wavePath(rect, surface, 6, tau * t + 1.5, 1.5),
        Paint()..color = color.withOpacity(0.5),
      );
      canvas.drawPath(
        _wavePath(rect, surface, 6, -tau * t, 1.0),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color, Color.lerp(color, Colors.black, 0.2)!],
          ).createShader(Rect.fromLTRB(
              rect.left, surface - 8, rect.right, rect.bottom)),
      );

      // bubbles
      if (level > 0.12) {
        final bp = Paint()..color = Colors.white.withOpacity(0.5);
        const xs = [0.22, 0.36, 0.5, 0.64, 0.78, 0.43];
        for (int i = 0; i < xs.length; i++) {
          final p = (t * (i % 2 + 1) + i * 0.17) % 1.0;
          final y = body.bottom - 10 - p * (body.bottom - surface - 20);
          if (y < surface + 8) continue;
          final x = rect.left + rect.width * xs[i] + math.sin(tau * (t * 2 + i)) * 4;
          canvas.drawCircle(Offset(x, y), 3.0 + (i % 3) * 2, bp);
        }
      }
      canvas.restore();
    }

    // outline + shine
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = Colors.white.withOpacity(0.7),
    );
    final shine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 6
      ..color = Colors.white.withOpacity(0.55);
    canvas.drawLine(Offset(body.left + 22, body.top + 62),
        Offset(body.left + 22, body.top + 104), shine);
    canvas.drawCircle(Offset(body.left + 22, body.top + 44), 3.5,
        Paint()..color = Colors.white.withOpacity(0.55));

    // face
    final eyeY = body.top + 100;
    final mouthY = eyeY + 36;
    final inkFill = Paint()..color = ink;
    final inkLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4.5
      ..color = ink;
    final white = Paint()..color = Colors.white;

    // blush
    final blush = Paint()..color = const Color(0xFFFF8FB8).withOpacity(0.55);
    canvas.drawCircle(Offset(cx - 64, eyeY + 24), 10, blush);
    canvas.drawCircle(Offset(cx + 64, eyeY + 24), 10, blush);

    // eyes
    for (final sx in const [-1.0, 1.0]) {
      final ex = cx + sx * 40;
      if (mood == Mood.sleepy) {
        canvas.drawArc(Rect.fromCenter(center: Offset(ex, eyeY), width: 22, height: 14),
            0.15, math.pi - 0.3, false, inkLine);
      } else {
        final ry = 14 * (1 - blink) + 1.5;
        canvas.drawOval(
            Rect.fromCenter(center: Offset(ex, eyeY), width: 20, height: ry * 2),
            inkFill);
        if (ry > 7) {
          canvas.drawCircle(Offset(ex + 3, eyeY - 5), 3.5, white);
          canvas.drawCircle(Offset(ex - 3, eyeY + 4), 1.8, white);
        }
      }
    }

    // brows when worried / sad
    if (mood == Mood.worried || mood == Mood.sad) {
      final brow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 4
        ..color = ink;
      canvas.drawLine(Offset(cx - 54, eyeY - 22), Offset(cx - 28, eyeY - 31), brow);
      canvas.drawLine(Offset(cx + 54, eyeY - 22), Offset(cx + 28, eyeY - 31), brow);
    }

    // mouth
    switch (mood) {
      case Mood.happy:
        final m = Path()
          ..addArc(Rect.fromCenter(center: Offset(cx, mouthY - 4), width: 40, height: 30),
              0, math.pi)
          ..close();
        canvas.drawPath(m, inkFill);
        canvas.drawOval(
            Rect.fromCenter(center: Offset(cx, mouthY + 6), width: 18, height: 9),
            Paint()..color = const Color(0xFFFF8FB8));
        break;
      case Mood.ok:
        final m = Path()
          ..moveTo(cx - 15, mouthY - 2)
          ..quadraticBezierTo(cx, mouthY + 12, cx + 15, mouthY - 2);
        canvas.drawPath(m, inkLine);
        break;
      case Mood.worried:
        final m = Path()
          ..moveTo(cx - 16, mouthY + 4)
          ..cubicTo(cx - 8, mouthY - 4, cx + 2, mouthY + 10, cx + 16, mouthY + 2);
        canvas.drawPath(m, inkLine);
        break;
      case Mood.sad:
        final m = Path()
          ..moveTo(cx - 13, mouthY + 8)
          ..quadraticBezierTo(cx, mouthY - 6, cx + 13, mouthY + 8);
        canvas.drawPath(m, inkLine);
        // sweat drop
        final dy = ((t * 2) % 1.0) * 12;
        final dx = cx + 66;
        final dyy = eyeY - 30 + dy;
        final drop = Path()
          ..moveTo(dx, dyy - 12)
          ..cubicTo(dx + 10, dyy, dx + 8, dyy + 10, dx, dyy + 10)
          ..cubicTo(dx - 8, dyy + 10, dx - 10, dyy, dx, dyy - 12);
        canvas.drawPath(drop, Paint()..color = const Color(0xFF8FD3FF));
        break;
      case Mood.sleepy:
        canvas.drawOval(
            Rect.fromCenter(center: Offset(cx, mouthY), width: 12, height: 10),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3.5
              ..color = ink);
        for (int i = 0; i < 3; i++) {
          final p = (t + i / 3) % 1.0;
          _text(canvas, 'Z', Offset(cx + 66 + i * 12, eyeY - 38 - p * 54),
              14.0 + i * 4, 1 - p);
        }
        break;
    }

    // sparkles when happy
    if (happy) {
      final sp = Paint()..color = const Color(0xFFFFE066);
      final spots = [
        Offset(body.left - 12, 96),
        Offset(body.right + 14, 112),
        Offset(cx + 78, 30),
      ];
      for (int i = 0; i < spots.length; i++) {
        final s = 0.6 + 0.4 * math.sin(tau * (t * 2 + i / 3));
        _star(canvas, spots[i], 11 * s + 3, sp);
      }
    }
  }

  @override
  bool shouldRepaint(covariant TankPainter old) => true;
}
