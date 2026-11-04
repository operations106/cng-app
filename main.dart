import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as ll;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const String kServiceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
const String kCmdUuid = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
const String kDataUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

// Calibration / rename password
const String kPin = '9891';

// ---------- Light theme colors ----------
const Color kInk = Color(0xFF2B2145);
const Color kMuted = Color(0xFF7A6F99);
const Color kPink = Color(0xFFFF8FC4);
const Color kGreen = Color(0xFF12B886);
const Color kOrange = Color(0xFFFF9F43);
const Color kRed = Color(0xFFFF5C70);
const Color kBorder = Color(0xFFEFE6FA);

BoxDecoration cardDeco({Color color = Colors.white, double r = 24}) =>
    BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(r),
      border: Border.all(color: kBorder),
      boxShadow: const [
        BoxShadow(color: Color(0x1A8E7CFF), blurRadius: 16, offset: Offset(0, 6)),
      ],
    );

const BoxDecoration kBgDeco = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFF3F9), Color(0xFFEAF2FF)],
  ),
);

enum Mood { sleepy, happy, ok, worried, sad }

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
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
        brightness: Brightness.light,
        colorSchemeSeed: kPink,
        scaffoldBackgroundColor: const Color(0xFFFFF7FB),
        textTheme: ThemeData.light().textTheme.apply(
              bodyColor: kInk,
              displayColor: kInk,
            ),
      ),
      home: const SplashGate(),
    );
  }
}

// ---------- Logo ----------

class CngLogo extends StatelessWidget {
  final double size;
  final Animation<double>? anim;
  const CngLogo({super.key, this.size = 48, this.anim});

  @override
  Widget build(BuildContext context) {
    final a = anim;
    if (a == null) {
      return CustomPaint(
          size: Size.square(size), painter: const LogoPainter(0));
    }
    return AnimatedBuilder(
      animation: a,
      builder: (_, __) => CustomPaint(
          size: Size.square(size), painter: LogoPainter(a.value)),
    );
  }
}

class LogoPainter extends CustomPainter {
  final double t; // 0..1 loop
  const LogoPainter(this.t);

  Path _flame(double sway) {
    final p = Path()..moveTo(50 + sway, 6);
    p.cubicTo(62 + sway * 0.5, 26, 83, 40, 83, 64);
    p.cubicTo(83, 84, 68, 95, 50, 95);
    p.cubicTo(32, 95, 17, 84, 17, 64);
    p.cubicTo(17, 50, 27, 42, 34, 31);
    p.cubicTo(36, 40, 40, 45, 45, 45);
    p.cubicTo(42, 30, 46, 17, 50 + sway, 6);
    p.close();
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);

    final sway = math.sin(t * 2 * math.pi) * 3;
    final bob = math.sin(t * 2 * math.pi) * 1.2;

    // badge
    final badge =
        RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 100, 100), const Radius.circular(30));
    canvas.drawRRect(
      badge.shift(const Offset(0, 3)),
      Paint()..color = const Color(0x338E7CFF),
    );
    canvas.drawRRect(
      badge,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFC2DE), Color(0xFFC9B8FF)],
        ).createShader(const Rect.fromLTWH(0, 0, 100, 100)),
    );
    // glossy highlight
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(8, 6, 84, 34), const Radius.circular(26)),
      Paint()..color = Colors.white.withOpacity(0.22),
    );

    // flame
    canvas.save();
    canvas.translate(14, 11 + bob);
    canvas.scale(0.72);
    canvas.drawPath(
      _flame(sway),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF7FD6FF), Color(0xFF3FA9F5)],
        ).createShader(const Rect.fromLTWH(0, 0, 100, 100)),
    );
    // inner flame
    canvas.save();
    canvas.translate(50, 95);
    canvas.scale(0.58);
    canvas.translate(-50, -95);
    canvas.drawPath(_flame(sway * 0.6), Paint()..color = const Color(0xFFD9F4FF));
    canvas.restore();

    // face
    const ink = Color(0xFF2B2145);
    final inkFill = Paint()..color = ink;
    final white = Paint()..color = Colors.white;
    for (final sx in const [-1.0, 1.0]) {
      final ex = 50 + sx * 12.0;
      canvas.drawOval(
          Rect.fromCenter(center: Offset(ex, 64), width: 9, height: 12), inkFill);
      canvas.drawCircle(Offset(ex + 1.4, 61), 1.8, white);
    }
    final blush = Paint()..color = const Color(0xFFFF8FB8).withOpacity(0.6);
    canvas.drawCircle(const Offset(31, 74), 5, blush);
    canvas.drawCircle(const Offset(69, 74), 5, blush);
    canvas.drawPath(
      Path()
        ..moveTo(43, 73)
        ..quadraticBezierTo(50, 81, 57, 73),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3
        ..color = ink,
    );
    canvas.restore();

    // sparkles
    final sp = Paint()..color = Colors.white.withOpacity(0.85);
    void spark(Offset c, double r) {
      final p = Path()
        ..moveTo(c.dx, c.dy - r)
        ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
        ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
        ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
        ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r);
      canvas.drawPath(p, sp);
    }

    final s1 = 0.7 + 0.3 * math.sin(t * 2 * math.pi);
    final s2 = 0.7 + 0.3 * math.sin(t * 2 * math.pi + 2);
    spark(const Offset(18, 22), 6 * s1);
    spark(const Offset(84, 30), 5 * s2);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant LogoPainter old) => old.t != t;
}

// ---------- Splash ----------

class SplashGate extends StatefulWidget {
  const SplashGate({super.key});

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))
      ..forward();
    Future.delayed(const Duration(milliseconds: 2100), () {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: _done
          ? const Shell(key: ValueKey('shell'))
          : Scaffold(
              key: const ValueKey('splash'),
              body: Container(
                decoration: kBgDeco,
                alignment: Alignment.center,
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (_, __) {
                    final pop = Curves.elasticOut
                        .transform((_c.value / 0.6).clamp(0.0, 1.0).toDouble());
                    final fade = Curves.easeOut
                        .transform(((_c.value - 0.4) / 0.4).clamp(0.0, 1.0).toDouble());
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Transform.scale(
                          scale: pop,
                          child: CngLogo(size: 150, anim: _c),
                        ),
                        const SizedBox(height: 18),
                        Opacity(
                          opacity: fade,
                          child: const Column(
                            children: [
                              Text('CNG Buddy',
                                  style: TextStyle(
                                      fontSize: 32, fontWeight: FontWeight.w900)),
                              SizedBox(height: 4),
                              Text('tumhara cute gas meter',
                                  style: TextStyle(fontSize: 13, color: kMuted)),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
    );
  }
}

// ---------- Shell (bottom tabs) ----------

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _i = 0;
  bool _radarOpened = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _i,
        children: [
          const HomePage(),
          _radarOpened ? const RadarPage() : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: const Color(0xFFFFD9EA),
        onDestinationSelected: (v) => setState(() {
          _i = v;
          if (v == 1) _radarOpened = true;
        }),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.local_gas_station_rounded), label: 'Meter'),
          NavigationDestination(icon: Icon(Icons.map_rounded), label: 'Radar'),
        ],
      ),
    );
  }
}

// ---------- Meter page ----------

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
  Timer? _retry;

  double _percent = 0;
  double _voltage = 0;
  bool _connected = false;
  bool _busy = false;
  bool _manual = false; // user ne khud disconnect kiya
  bool _named = false;
  bool _askedName = false;
  String? _savedId;
  String _name = 'CNG Meter';
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
    _init();
  }

  Future<void> _init() async {
    final sp = await SharedPreferences.getInstance();
    _savedId = sp.getString('dev_id');
    _name = sp.getString('dev_name') ?? _name;
    _named = sp.getBool('named') ?? false;
    if (mounted) setState(() {});
    _retry = Timer.periodic(const Duration(seconds: 12), (_) {
      if (mounted && !_connected && !_busy && !_manual) {
        _scanAndConnect(silent: true);
      }
    });
    _scanAndConnect(silent: true);
  }

  Mood get _mood {
    if (!_connected) return Mood.sleepy;
    if (_percent >= 60) return Mood.happy;
    if (_percent >= 30) return Mood.ok;
    if (_percent >= 15) return Mood.worried;
    return Mood.sad;
  }

  Color _levelColor(double p) {
    if (p < 15) return kRed;
    if (p < 30) return kOrange;
    return kGreen;
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

  Future<void> _scanAndConnect({bool silent = false}) async {
    if (_busy) return;
    if (!silent) _manual = false;
    setState(() {
      _busy = true;
      _status = 'Searching...';
    });

    StreamSubscription<List<ScanResult>>? scanSub;
    try {
      if (!await FlutterBluePlus.isSupported) {
        throw 'Bluetooth is not supported on this phone';
      }
      if (Platform.isAndroid &&
          FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
        if (silent) throw 'bluetooth off';
        await FlutterBluePlus.turnOn();
      }

      final secs = silent ? 6 : 10;
      final wanted = silent ? _savedId : null;
      BluetoothDevice? found;
      final done = Completer<void>();
      scanSub = FlutterBluePlus.onScanResults.listen((results) {
        for (final r in results) {
          if (found == null &&
              (wanted == null || r.device.remoteId.str == wanted)) {
            found = r.device;
            if (!done.isCompleted) done.complete();
          }
        }
      });

      await FlutterBluePlus.startScan(
        withServices: [Guid(kServiceUuid)],
        timeout: Duration(seconds: secs),
      );
      await Future.any([
        done.future,
        Future.delayed(Duration(seconds: secs)),
      ]);
      await FlutterBluePlus.stopScan();
      await scanSub.cancel();
      scanSub = null;

      if (found == null) {
        throw 'Meter nahi mila. Meter ON hai? Paas aake phir try karo.';
      }

      setState(() => _status = 'Connecting...');
      final dev = found!;
      await dev.connect(timeout: const Duration(seconds: 10));
      _device = dev;

      final sp = await SharedPreferences.getInstance();
      await sp.setString('dev_id', dev.remoteId.str);
      _savedId = dev.remoteId.str;
      if (!_named && dev.platformName.isNotEmpty) _name = dev.platformName;

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

      if (!_named && !_askedName) {
        _askedName = true;
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _askRename(first: true));
      }
    } catch (e) {
      await scanSub?.cancel();
      if (mounted) {
        setState(() {
          _connected = false;
          _status = 'Sleeping';
        });
        if (!silent) _snack(e.toString());
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
    _manual = true;
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
    final pinC = TextEditingController();
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cmd == 'RESET'
                    ? 'Calibration default par reset hogi.'
                    : 'Abhi ki sensor voltage (${_voltage.toStringAsFixed(2)} V) ko '
                        '${cmd == 'SETEMPTY' ? '0% (empty)' : '100% (full)'} set kiya jayega.',
              ),
              const SizedBox(height: 14),
              TextField(
                controller: pinC,
                obscureText: true,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: InputDecoration(
                  labelText: 'Password 🔒',
                  errorText: err,
                  counterText: '',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (pinC.text == kPin) {
                  Navigator.pop(ctx, true);
                } else {
                  setD(() => err = 'Galat password');
                }
              },
              child: const Text('OK'),
            ),
          ],
        ),
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

  Future<void> _askRename({required bool first}) async {
    if (!mounted) return;
    final nameC = TextEditingController(text: first ? '' : _name);
    final pinC = TextEditingController();
    String? err;
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          title: Text(first ? 'Apne meter ka naam rakho 🏷️' : 'Naam badlo ✏️',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameC,
                maxLength: 20,
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: 'Naam', hintText: 'jaise: Swift CNG'),
              ),
              if (!first)
                TextField(
                  controller: pinC,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  decoration: const InputDecoration(
                      labelText: 'Password 🔒', counterText: ''),
                ),
              if (err != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(err!, style: const TextStyle(color: kRed)),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(first ? 'Baad mein' : 'Cancel')),
            FilledButton(
              onPressed: () {
                final n = nameC.text
                    .trim()
                    .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '');
                if (n.isEmpty) {
                  setD(() => err = 'Naam likho (sirf letters/numbers)');
                  return;
                }
                if (!first && pinC.text != kPin) {
                  setD(() => err = 'Galat password');
                  return;
                }
                Navigator.pop(ctx, n);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    final sp = await SharedPreferences.getInstance();
    if (first) {
      await sp.setBool('named', true);
      _named = true;
    }
    if (res == null) return;

    await sp.setString('dev_name', res);
    await sp.setBool('named', true);
    _named = true;
    try {
      await _cmdChar?.write(utf8.encode('SETNAME:$res'));
    } catch (_) {}
    if (mounted) {
      setState(() => _name = res);
      _snack('Naam save ✨ Meter restart hoke apne aap connect hoga');
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
    _retry?.cancel();
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
          const Positioned.fill(child: DecoratedBox(decoration: kBgDeco)),
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
                      CngLogo(size: 46, anim: _loop),
                      const SizedBox(width: 10),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('CNG Buddy',
                              style: TextStyle(
                                  fontSize: 24, fontWeight: FontWeight.w900)),
                          Text('tumhara cute gas meter',
                              style: TextStyle(fontSize: 12, color: kMuted)),
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
                              color: const Color(0xFFFFE9EC),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: kRed),
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
                                        : const Color(0xFFC4BBDC),
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
                                        color: kMuted),
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
                          child: GestureDetector(
                            onTap: _connected
                                ? () => _askRename(first: false)
                                : null,
                            child: _InfoCard(
                              emoji: '📡',
                              label: _connected ? 'Tap karke naam badlo' : 'Device',
                              value: _connected ? _name : 'Offline',
                            ),
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

// ---------- CNG Radar (OpenStreetMap, no backend) ----------

class Station {
  final String id;
  final String name;
  final ll.LatLng pos;
  final String? brand;
  final String? phone;
  final String? hours;
  double km = 0;
  double? rate;
  int? queue;
  DateTime? reportedAt;
  Station({
    required this.id,
    required this.name,
    required this.pos,
    this.brand,
    this.phone,
    this.hours,
  });
}

double? _num(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'abhi';
  if (d.inMinutes < 60) return '${d.inMinutes} min pehle';
  if (d.inHours < 24) return '${d.inHours} ghante pehle';
  return '${d.inDays} din pehle';
}

class RadarPage extends StatefulWidget {
  const RadarPage({super.key});

  @override
  State<RadarPage> createState() => _RadarPageState();
}

class _RadarPageState extends State<RadarPage> {
  static const List<String> _mirrors = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
  ];

  final fm.MapController _map = fm.MapController();
  ll.LatLng _me = const ll.LatLng(28.6139, 77.2090);
  bool _mapReady = false;
  bool _loading = true;
  bool _failed = false;
  bool _located = false;
  List<Station> _stations = [];
  Station? _sel;

  @override
  void initState() {
    super.initState();
    _load(recenter: true);
  }

  Future<ll.LatLng?> _locate() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      return ll.LatLng(p.latitude, p.longitude);
    } catch (_) {
      return null;
    }
  }

  Future<List<Station>?> _fetchOsm(ll.LatLng c) async {
    final q =
        '[out:json][timeout:20];nwr["amenity"="fuel"]["fuel:cng"="yes"](around:10000,${c.latitude},${c.longitude});out center 60;';
    for (final url in _mirrors) {
      try {
        final r = await http.post(
          Uri.parse(url),
          headers: {'User-Agent': 'CNGBuddy/1.0'},
          body: {'data': q},
        ).timeout(const Duration(seconds: 25));
        if (r.statusCode != 200) continue;
        final d = jsonDecode(r.body);
        final out = <Station>[];
        for (final e in (d['elements'] as List)) {
          final tags = (e['tags'] ?? {}) as Map;
          final lat = _num(e['lat'] ?? (e['center'] != null ? e['center']['lat'] : null));
          final lon = _num(e['lon'] ?? (e['center'] != null ? e['center']['lon'] : null));
          if (lat == null || lon == null) continue;
          out.add(Station(
            id: '${e['type']}${e['id']}',
            name: (tags['name'] ?? tags['brand'] ?? tags['operator'] ?? 'CNG Pump')
                .toString(),
            pos: ll.LatLng(lat, lon),
            brand: tags['brand']?.toString(),
            phone: (tags['phone'] ?? tags['contact:phone'])?.toString(),
            hours: tags['opening_hours']?.toString(),
          ));
        }
        return out;
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Future<void> _load({bool recenter = false}) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }
    if (recenter || !_located) {
      final loc = await _locate();
      if (loc != null) {
        _me = loc;
        _located = true;
        if (_mapReady) _map.move(_me, 13.5);
      }
    }
    final list = await _fetchOsm(_me);
    if (!mounted) return;
    if (list == null) {
      setState(() {
        _loading = false;
        _failed = true;
      });
      return;
    }

    const dist = ll.Distance();
    final sp = await SharedPreferences.getInstance();
    for (final s in list) {
      s.km = dist.as(ll.LengthUnit.Kilometer, _me, s.pos);
      final raw = sp.getString('rep_${s.id}');
      if (raw != null) {
        try {
          final m = jsonDecode(raw);
          s.rate = _num(m['rate']);
          s.queue = _num(m['queue'])?.round();
          s.reportedAt = DateTime.fromMillisecondsSinceEpoch(m['ts'] as int);
        } catch (_) {}
      }
    }
    list.sort((a, b) => a.km.compareTo(b.km));
    if (!mounted) return;
    setState(() {
      _stations = list;
      _loading = false;
    });
  }

  void _select(Station s) {
    setState(() => _sel = s);
    if (_mapReady) _map.move(s.pos, 15);
    _openSheet(s);
  }

  Future<void> _go(Uri u) async {
    try {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Open nahi ho paya')));
      }
    }
  }

  Future<void> _openSheet(Station s) async {
    final rateC = TextEditingController(text: s.rate?.toString() ?? '');
    final qC = TextEditingController(text: s.queue?.toString() ?? '');
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('⛽', style: TextStyle(fontSize: 30)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.name,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w900)),
                        Text('${s.km.toStringAsFixed(1)} km door',
                            style: const TextStyle(fontSize: 12, color: kMuted)),
                      ],
                    ),
                  ),
                ],
              ),
              if (s.hours != null) ...[
                const SizedBox(height: 10),
                Text('🕒 ${s.hours}',
                    style: const TextStyle(fontSize: 13, color: kMuted)),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _go(Uri.parse(
                          'https://www.google.com/maps/dir/?api=1&destination=${s.pos.latitude},${s.pos.longitude}')),
                      icon: const Icon(Icons.navigation_rounded),
                      label: const Text('Navigate'),
                    ),
                  ),
                  if (s.phone != null) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _go(Uri(
                            scheme: 'tel',
                            path: s.phone!.split(';').first.trim())),
                        icon: const Icon(Icons.call_rounded),
                        label: const Text('Call'),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 18),
              Text(
                s.reportedAt != null
                    ? 'Aapki last report (${_ago(s.reportedAt!)})'
                    : 'Rate / line update karo',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: rateC,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Rate ₹/kg', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: qC,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Line (gaadi)', border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    final rate = _num(rateC.text.trim());
                    final q = _num(qC.text.trim())?.round();
                    if (rate == null && q == null) {
                      Navigator.pop(ctx);
                      return;
                    }
                    final now = DateTime.now();
                    final sp = await SharedPreferences.getInstance();
                    await sp.setString(
                        'rep_${s.id}',
                        jsonEncode({
                          'rate': rate,
                          'queue': q,
                          'ts': now.millisecondsSinceEpoch,
                        }));
                    if (mounted) {
                      setState(() {
                        s.rate = rate;
                        s.queue = q;
                        s.reportedAt = now;
                      });
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _queueColor(int? q) {
    if (q == null) return kMuted;
    if (q <= 3) return kGreen;
    if (q <= 8) return const Color(0xFFF08C00);
    return kRed;
  }

  @override
  Widget build(BuildContext context) {
    final markers = <fm.Marker>[
      fm.Marker(
        point: _me,
        width: 26,
        height: 26,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF4C8DFF),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [BoxShadow(color: Color(0x554C8DFF), blurRadius: 8)],
          ),
        ),
      ),
      for (final s in _stations)
        fm.Marker(
          point: s.pos,
          width: 44,
          height: 44,
          child: GestureDetector(
            onTap: () => _select(s),
            child: Icon(
              Icons.location_on,
              size: identical(s, _sel) ? 46 : 38,
              color: s.reportedAt != null ? kGreen : const Color(0xFFFF8F3C),
            ),
          ),
        ),
    ];

    return Scaffold(
      body: Container(
        decoration: kBgDeco,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              children: [
                Row(
                  children: [
                    const CngLogo(size: 40),
                    const SizedBox(width: 10),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('CNG Radar 📡',
                            style: TextStyle(
                                fontSize: 22, fontWeight: FontWeight.w900)),
                        Text('paas ke CNG pump (OpenStreetMap)',
                            style: TextStyle(fontSize: 12, color: kMuted)),
                      ],
                    ),
                    const Spacer(),
                    _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5))
                        : IconButton(
                            onPressed: () => _load(recenter: true),
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  height: 240,
                  decoration: cardDeco(),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: fm.FlutterMap(
                      mapController: _map,
                      options: fm.MapOptions(
                        initialCenter: _me,
                        initialZoom: 13,
                        onMapReady: () {
                          _mapReady = true;
                          if (_located) _map.move(_me, 13.5);
                        },
                      ),
                      children: [
                        fm.TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.cngmeter.cng_meter',
                        ),
                        fm.MarkerLayer(markers: markers),
                        const fm.RichAttributionWidget(
                          attributions: [
                            fm.TextSourceAttribution('© OpenStreetMap contributors'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _stations.isEmpty
                      ? Center(
                          child: Text(
                            _loading
                                ? 'Pump dhoondh raha hu... 🔍'
                                : _failed
                                    ? 'Internet check karo 🌐 phir refresh dabao'
                                    : 'Paas mein CNG pump nahi mila 🥲',
                            style: const TextStyle(color: kMuted),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 12),
                          itemCount: _stations.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final s = _stations[i];
                            final q = s.queue;
                            return _Pop(
                              ms: 400 + (i < 6 ? i : 6) * 80,
                              child: GestureDetector(
                                onTap: () => _select(s),
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: cardDeco(
                                    color: identical(s, _sel)
                                        ? const Color(0xFFFFE9F3)
                                        : Colors.white,
                                    r: 22,
                                  ),
                                  child: Row(
                                    children: [
                                      const Text('⛽', style: TextStyle(fontSize: 26)),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
