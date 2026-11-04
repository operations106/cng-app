import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show ValueListenable;
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

// Settings (sensor voltage) password
const String kSettingsPin = '1234';

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
          NavigationDestination(icon: Icon(Icons.map_rounded), label: 'CNG Pump'),
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
  final ValueNotifier<double> _vN = ValueNotifier<double>(0);
  final ValueNotifier<bool> _connN = ValueNotifier<bool>(false);
  bool get _connected => _connN.value;
  set _connected(bool v) => _connN.value = v;
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
        _vN.value = v;
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

  Future<void> _openSettings() async {
    final ok = await askPin(context, kSettingsPin, title: 'Settings 🔒');
    if (!ok || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SettingsPage(voltage: _vN, connected: _connN, name: _name),
    ));
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
    _vN.dispose();
    _connN.dispose();
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
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('CNG Buddy',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 24, fontWeight: FontWeight.w900)),
                            Text('tumhara cute gas meter',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: kMuted)),
                          ],
                        ),
                      ),
                      _StatusChip(connected: _connected, text: _status, anim: _loop),
                      IconButton(
                        onPressed: _openSettings,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.settings_rounded, color: kMuted),
                      ),
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
                          ms: 950,
                          child: GestureDetector(
                            onTap: _connected
                                ? () => _askRename(first: false)
                                : null,
                            child: _InfoCard(
                              emoji: '🚗',
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

// ---------- Password dialog + Settings ----------

Future<bool> askPin(BuildContext context, String pin,
    {String title = 'Password 🔒'}) async {
  final c = TextEditingController();
  String? err;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: c,
          obscureText: true,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 4,
          decoration: InputDecoration(
            labelText: 'Password',
            errorText: err,
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (c.text == pin) {
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
  return ok == true;
}

class SettingsPage extends StatelessWidget {
  final ValueListenable<double> voltage;
  final ValueListenable<bool> connected;
  final String name;
  const SettingsPage({
    super.key,
    required this.voltage,
    required this.connected,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings ⚙️',
            style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: false,
      body: Container(
        decoration: kBgDeco,
        width: double.infinity,
        height: double.infinity,
        padding: const EdgeInsets.all(20),
        child: ValueListenableBuilder<bool>(
          valueListenable: connected,
          builder: (_, on, __) => ValueListenableBuilder<double>(
            valueListenable: voltage,
            builder: (_, v, __) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoCard(
                  emoji: '⚡',
                  label: 'Sensor voltage (live)',
                  value: on ? '${v.toStringAsFixed(2)} V' : '--',
                ),
                const SizedBox(height: 12),
                _InfoCard(
                  emoji: '🚗',
                  label: 'Device',
                  value: on ? name : 'Offline',
                ),
                const SizedBox(height: 16),
                Text(
                  on
                      ? 'Voltage meter se live aa raha hai. Calibration (Set Empty / Set Full) Home screen par hai.'
                      : 'Meter connect nahi hai. Home par connect karo, phir yahan voltage dikhega.',
                  style: const TextStyle(fontSize: 13, color: kMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- CNG Pump (OpenStreetMap + OSRM routing, no backend) ----------

class Station {
  final String id;
  final String name;
  final ll.LatLng pos;
  final String? brand;
  final String? phone;
  final String? hours;
  final bool custom; // user ne khud add kiya
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
    this.custom = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lat': pos.latitude,
        'lon': pos.longitude,
        'brand': brand,
        'phone': phone,
        'hours': hours,
      };

  static Station? fromJson(dynamic m, {bool custom = false}) {
    try {
      final lat = _num(m['lat']);
      final lon = _num(m['lon']);
      if (lat == null || lon == null) return null;
      return Station(
        id: m['id'].toString(),
        name: (m['name'] ?? 'CNG Pump').toString(),
        pos: ll.LatLng(lat, lon),
        brand: m['brand']?.toString(),
        phone: m['phone']?.toString(),
        hours: m['hours']?.toString(),
        custom: custom,
      );
    } catch (_) {
      return null;
    }
  }
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

String _fmtDist(double m) =>
    m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';

String _fmtMin(double sec) {
  final m = (sec / 60).round();
  if (m < 60) return '$m min';
  return '${m ~/ 60} ghanta ${m % 60} min';
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
    'https://overpass.private.coffee/api/interpreter',
  ];

  // India me bahut se CNG pump OSM par "fuel:cng" tag ke bina hote hain,
  // isliye naam / brand / operator se bhi dhoondhte hain.
  static const String _brands =
      'CNG|IGL|MGL|Indraprastha|Mahanagar|Adani|Torrent|Green Gas|Think Gas|'
      'Gujarat Gas|Sabarmati|Bharat Gas Resources|AG&P|Haryana City Gas|'
      'Maharashtra Natural|Vadodara Gas|Central UP Gas|Assam Gas|Unison|'
      'Siti Energy|Aavantika|Megha Gas|Bhagyanagar|GAIL Gas|IOAGPL';

  final fm.MapController _map = fm.MapController();
  ll.LatLng _me = const ll.LatLng(28.6139, 77.2090);
  bool _mapReady = false;
  bool _loading = true;
  bool _failed = false;
  bool _located = false;
  bool _fromCache = false;
  List<Station> _stations = [];
  Station? _sel;

  // route state
  bool _routing = false;
  bool _showSteps = false;
  List<ll.LatLng> _routePts = [];
  List<String> _routeSteps = [];
  double? _routeM;
  double? _routeSec;
  Station? _routeTo;

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

  String _query(ll.LatLng c, int r) {
    final a = '(around:$r,${c.latitude},${c.longitude})';
    return '[out:json][timeout:25];('
        'nwr["amenity"="fuel"]["fuel:cng"="yes"]$a;'
        'nwr["amenity"="fuel"]["fuel:compressed_natural_gas"="yes"]$a;'
        'nwr["amenity"="fuel"]["name"~"$_brands",i]$a;'
        'nwr["amenity"="fuel"]["brand"~"$_brands",i]$a;'
        'nwr["amenity"="fuel"]["operator"~"$_brands",i]$a;'
        ');out center 150;';
  }

  Future<List<Station>?> _overpass(String q) async {
    for (final url in _mirrors) {
      try {
        final r = await http.post(
          Uri.parse(url),
          headers: {'User-Agent': 'CNGBuddy/1.0'},
          body: {'data': q},
        ).timeout(const Duration(seconds: 28));
        if (r.statusCode != 200) continue;
        final d = jsonDecode(r.body);
        final seen = <String>{};
        final out = <Station>[];
        for (final e in (d['elements'] as List)) {
          final tags = (e['tags'] ?? {}) as Map;
          final lat =
              _num(e['lat'] ?? (e['center'] != null ? e['center']['lat'] : null));
          final lon =
              _num(e['lon'] ?? (e['center'] != null ? e['center']['lon'] : null));
          if (lat == null || lon == null) continue;
          final id = '${e['type']}${e['id']}';
          if (!seen.add(id)) continue;
          out.add(Station(
            id: id,
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

  // pehle 10 km, kam mile to 25 km tak badhao
  Future<List<Station>?> _fetchOsm(ll.LatLng c) async {
    List<Station>? best;
    for (final r in const [10000, 25000]) {
      final got = await _overpass(_query(c, r));
      if (got == null) break;
      best = got;
      if (got.length >= 3) break;
    }
    return best;
  }

  Future<List<Station>> _loadCustom(SharedPreferences sp) async {
    final raw = sp.getString('custom_stations');
    if (raw == null) return [];
    try {
      return [
        for (final m in (jsonDecode(raw) as List))
          if (Station.fromJson(m, custom: true) != null)
            Station.fromJson(m, custom: true)!
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveCustom(SharedPreferences sp) async {
    await sp.setString('custom_stations',
        jsonEncode([for (final s in _stations.where((s) => s.custom)) s.toJson()]));
  }

  void _applyReports(SharedPreferences sp, Iterable<Station> list) {
    const dist = ll.Distance();
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
  }

  Future<void> _load({bool recenter = false}) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _failed = false;
        _fromCache = false;
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
    final sp = await SharedPreferences.getInstance();
    var list = await _fetchOsm(_me);
    var cached = false;

    if (list != null) {
      await sp.setString(
          'osm_cache',
          jsonEncode({
            'lat': _me.latitude,
            'lon': _me.longitude,
            'list': [for (final s in list) s.toJson()],
          }));
    } else {
      // internet / server fail: pichla saved data dikhao (agar paas ka ho)
      final raw = sp.getString('osm_cache');
      if (raw != null) {
        try {
          final m = jsonDecode(raw);
          final d = const ll.Distance().as(ll.LengthUnit.Kilometer, _me,
              ll.LatLng(_num(m['lat'])!, _num(m['lon'])!));
          if (d < 20) {
            list = [
              for (final e in (m['list'] as List))
                if (Station.fromJson(e) != null) Station.fromJson(e)!
            ];
            cached = true;
          }
        } catch (_) {}
      }
    }

    final customs = await _loadCustom(sp);
    if (!mounted) return;
    if (list == null && customs.isEmpty) {
      setState(() {
        _loading = false;
        _failed = true;
      });
      return;
    }

    final all = <Station>[...?list, ...customs];
    _applyReports(sp, all);
    all.sort((a, b) => a.km.compareTo(b.km));
    setState(() {
      _stations = all;
      _loading = false;
      _failed = list == null;
      _fromCache = cached;
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
      _snack('Open nahi ho paya');
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(m),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ));
  }

  // ---------- route (OSRM free server) ----------

  String? _stepText(dynamic st) {
    final m = st['maneuver'] as Map;
    final type = m['type']?.toString() ?? '';
    final mod = m['modifier']?.toString();
    final name = (st['name'] ?? '').toString();
    final dist = _num(st['distance']) ?? 0;
    if (type == 'arrive') return 'Pump pahunch gaye 🎉';
    final act = switch (type) {
      'depart' => 'Shuru karo',
      'roundabout' || 'rotary' => 'Roundabout se nikalo',
      _ => switch (mod) {
          'left' => 'Left mudo',
          'right' => 'Right mudo',
          'slight left' => 'Halka left',
          'slight right' => 'Halka right',
          'sharp left' => 'Sharp left',
          'sharp right' => 'Sharp right',
          'uturn' => 'U-turn lo',
          _ => 'Seedhe chalo',
        },
    };
    return '$act${name.isNotEmpty ? ' • $name' : ''}  (${_fmtDist(dist)})';
  }

  Future<void> _planRoute(Station s) async {
    setState(() => _routing = true);
    try {
      final u = Uri.parse(
          'https://router.project-osrm.org/route/v1/driving/${_me.longitude},${_me.latitude};${s.pos.longitude},${s.pos.latitude}?overview=full&geometries=geojson&steps=true');
      final r = await http
          .get(u, headers: {'User-Agent': 'CNGBuddy/1.0'})
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) throw 'route';
      final d = jsonDecode(r.body);
      final rt = (d['routes'] as List).first;
      final pts = <ll.LatLng>[
        for (final c in (rt['geometry']['coordinates'] as List))
          ll.LatLng(_num(c[1])!, _num(c[0])!)
      ];
      final steps = <String>[];
      for (final leg in (rt['legs'] as List)) {
        for (final st in (leg['steps'] as List)) {
          final t = _stepText(st);
          if (t != null) steps.add(t);
        }
      }
      if (!mounted) return;
      setState(() {
        _routePts = pts;
        _routeSteps = steps;
        _routeM = _num(rt['distance']);
        _routeSec = _num(rt['duration']);
        _routeTo = s;
        _showSteps = false;
      });
      if (_mapReady && pts.length > 1) {
        _map.fitCamera(fm.CameraFit.bounds(
          bounds: fm.LatLngBounds.fromPoints(pts),
          padding: const EdgeInsets.all(36),
        ));
      }
    } catch (_) {
      _snack('Route nahi mila. Internet check karo ya Google Maps se chalo.');
    } finally {
      if (mounted) setState(() => _routing = false);
    }
  }

  void _clearRoute() {
    setState(() {
      _routePts = [];
      _routeSteps = [];
      _routeTo = null;
      _routeM = null;
      _routeSec = null;
      _showSteps = false;
    });
    if (_mapReady) _map.move(_me, 13.5);
  }

  // ---------- pump add / delete (jab OSM me pump na ho) ----------

  Future<void> _addCustom(ll.LatLng p) async {
    final nameC = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: const Text('Yahan CNG pump add karein? ⛽',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: nameC,
          autofocus: true,
          maxLength: 30,
          decoration: const InputDecoration(
              labelText: 'Pump ka naam', hintText: 'jaise: IGL Sector 12'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final n = nameC.text.trim();
              Navigator.pop(ctx, n.isEmpty ? 'CNG Pump' : n);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (name == null) return;
    final s = Station(
      id: 'c${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      pos: p,
      custom: true,
    );
    final sp = await SharedPreferences.getInstance();
    _applyReports(sp, [s]);
    if (!mounted) return;
    setState(() {
      _stations = [..._stations, s]..sort((a, b) => a.km.compareTo(b.km));
    });
    await _saveCustom(sp);
    _snack('Pump add ho gaya ✨');
  }

  Future<void> _deleteCustom(Station s) async {
    final sp = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _stations = _stations.where((e) => e.id != s.id).toList();
      if (identical(_sel, s)) _sel = null;
      if (_routeTo?.id == s.id) {
        _routePts = [];
        _routeSteps = [];
        _routeTo = null;
      }
    });
    await _saveCustom(sp);
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
                        Text(
                            '${s.km.toStringAsFixed(1)} km door${s.custom ? '  •  aapka add kiya hua' : ''}',
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
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _planRoute(s);
                    },
                    icon: const Icon(Icons.alt_route_rounded),
                    label: const Text('Route dikhao'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _go(Uri.parse(
                        'https://www.google.com/maps/dir/?api=1&destination=${s.pos.latitude},${s.pos.longitude}')),
                    icon: const Icon(Icons.navigation_rounded),
                    label: const Text('Google Maps'),
                  ),
                  if (s.phone != null)
                    OutlinedButton.icon(
                      onPressed: () => _go(Uri(
                          scheme: 'tel', path: s.phone!.split(';').first.trim())),
                      icon: const Icon(Icons.call_rounded),
                      label: const Text('Call'),
                    ),
                  if (s.custom)
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _deleteCustom(s);
                      },
                      icon: const Icon(Icons.delete_outline_rounded, color: kRed),
                      label: const Text('Hatao', style: TextStyle(color: kRed)),
                    ),
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

  Widget _routeCard() {
    final to = _routeTo!;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: cardDeco(color: const Color(0xFFEAF2FF), r: 20),
      child: Row(
        children: [
          const Text('🧭', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(to.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800)),
                Text(
                    '${_fmtDist(_routeM ?? 0)}  •  ${_fmtMin(_routeSec ?? 0)}',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF3A6FD8))),
              ],
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _showSteps = !_showSteps),
            child: Text(_showSteps ? 'Pump list' : 'Steps'),
          ),
          IconButton(
            onPressed: _clearRoute,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _stepsList(ScrollController sc) {
    return ListView.separated(
      controller: sc,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
      itemCount: _routeSteps.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => Container(
        padding: const EdgeInsets.all(12),
        decoration: cardDeco(r: 16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: const Color(0xFFFFD9EA),
              child: Text('${i + 1}',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(_routeSteps[i],
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stationList(ScrollController sc) {
    if (_stations.isEmpty) {
      return ListView(
        controller: sc,
        padding: const EdgeInsets.fromLTRB(24, 30, 24, 30),
        children: [
          Text(
            _loading
                ? 'Pump dhoondh raha hu... 🔍'
                : _failed
                    ? 'Internet check karo 🌐 phir refresh dabao'
                    : 'Paas mein CNG pump nahi mila 🥲\nMap pe pump ki jagah long-press karke add kar sakte ho',
            textAlign: TextAlign.center,
            style: const TextStyle(color: kMuted),
          ),
        ],
      );
    }
    return ListView.separated(
      controller: sc,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
      itemCount: _stations.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final s = _stations[i];
        final q = s.queue;
        return GestureDetector(
          onTap: () => _select(s),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: cardDeco(
              color: identical(s, _sel) ? const Color(0xFFFFE9F3) : Colors.white,
              r: 22,
            ),
            child: Row(
              children: [
                const Text('⛽', style: TextStyle(fontSize: 26)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(
                        '${s.km.toStringAsFixed(1)} km door${s.custom ? '  •  mera add kiya' : ''}${s.reportedAt != null ? '  •  ${_ago(s.reportedAt!)}' : ''}',
                        style: const TextStyle(fontSize: 12, color: kMuted),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      s.rate != null ? '₹${s.rate!.toStringAsFixed(1)}/kg' : '₹ --',
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFD9930D)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      q != null ? '🚗 $q gaadi' : '🚗 --',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _queueColor(q)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _pin(Station s) {
    final sel = identical(s, _sel);
    final color = s.custom
        ? const Color(0xFF8E7CFF)
        : s.reportedAt != null
            ? kGreen
            : const Color(0xFFFF8F3C);
    return GestureDetector(
      onTap: () => _select(s),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: sel ? color : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color, width: 1.5),
              boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 4)],
            ),
            child: Text(
              s.rate != null
                  ? '₹${s.rate!.toStringAsFixed(0)}'
                  : '${s.km.toStringAsFixed(1)} km',
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: sel ? Colors.white : kInk),
            ),
          ),
          Icon(Icons.location_on, size: sel ? 36 : 30, color: color),
        ],
      ),
    );
  }

  Widget _roundBtn(IconData icon, VoidCallback? onTap) {
    return Material(
      color: Colors.white,
      elevation: 3,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 46,
          height: 46,
          child: Icon(icon, color: kInk),
        ),
      ),
    );
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
          width: 64,
          height: 58,
          alignment: Alignment.topCenter,
          child: _pin(s),
        ),
    ];

    final busy = _loading || _routing;

    return Scaffold(
      body: Stack(
        children: [
          // ---- full screen map ----
          Positioned.fill(
            child: fm.FlutterMap(
              mapController: _map,
              options: fm.MapOptions(
                initialCenter: _me,
                initialZoom: 13,
                onLongPress: (tp, point) => _addCustom(point),
                onMapReady: () {
                  _mapReady = true;
                  if (_located) _map.move(_me, 13.5);
                },
              ),
              children: [
                fm.TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.cngmeter.cng_meter',
                ),
                if (_routePts.length > 1)
                  fm.PolylineLayer(
                    polylines: [
                      fm.Polyline(
                        points: _routePts,
                        strokeWidth: 5,
                        color: const Color(0xFF4C8DFF),
                        borderStrokeWidth: 2,
                        borderColor: Colors.white,
                      ),
                    ],
                  ),
                fm.MarkerLayer(markers: markers),
                const fm.RichAttributionWidget(
                  alignment: fm.AttributionAlignment.bottomLeft,
                  attributions: [
                    fm.TextSourceAttribution(
                        '© OpenStreetMap contributors • routing: OSRM'),
                  ],
                ),
              ],
            ),
          ),

          // ---- floating top bar ----
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                      decoration: cardDeco(r: 30),
                      child: Row(
                        children: [
                          const CngLogo(size: 36),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('CNG Pump ⛽',
                                    style: TextStyle(
                                        fontSize: 18, fontWeight: FontWeight.w900)),
                                Text('Paas ke CNG pump • route • rate',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 11.5, color: kMuted)),
                              ],
                            ),
                          ),
                          busy
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                      width: 22,
                                      height: 22,
                                      child:
                                          CircularProgressIndicator(strokeWidth: 2.5)),
                                )
                              : IconButton(
                                  onPressed: () => _load(recenter: true),
                                  icon: const Icon(Icons.refresh_rounded),
                                ),
                        ],
                      ),
                    ),
                    if (_fromCache)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF1DC),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text('Offline hu — pichla saved data dikha raha hu',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.orange.shade800)),
                      ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: _roundBtn(Icons.my_location_rounded, () {
                        if (_mapReady) _map.move(_me, 14);
                      }),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ---- draggable bottom sheet ----
          DraggableScrollableSheet(
            initialChildSize: 0.36,
            minChildSize: 0.13,
            maxChildSize: 0.88,
            snap: true,
            snapSizes: const [0.13, 0.36, 0.88],
            builder: (ctx, sc) => Container(
              decoration: const BoxDecoration(
                color: Color(0xFFFFF7FB),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                      color: Color(0x33000000), blurRadius: 16, offset: Offset(0, -4)),
                ],
              ),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD9CFEA),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_routeTo != null)
                    _routeCard()
                  else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _stations.isEmpty
                                  ? 'CNG pump'
                                  : 'Sabse paas ke ${_stations.length} CNG pump',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w900),
                            ),
                          ),
                          const Text('long-press = add',
                              style: TextStyle(fontSize: 11, color: kMuted)),
                        ],
                      ),
                    ),
                  Expanded(
                    child: (_routeTo != null && _showSteps)
                        ? _stepsList(sc)
                        : _stationList(sc),
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
    final c = connected ? kGreen : kMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
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
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 6),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: kMuted)),
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
        decoration: cardDeco(r: 24),
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
      (_) => [r.nextDouble(), r.nextDouble(), 1.5 + r.nextDouble() * 2.5, r.nextDouble() * 6.28],
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < _stars.length; i++) {
      final s = _stars[i];
      final op = 0.08 + 0.32 * (0.5 + 0.5 * math.sin(t * 2 * math.pi + s[3]));
      final base = i.isEven ? const Color(0xFFFF8FC4) : const Color(0xFFA48CFF);
      canvas.drawCircle(
        Offset(s[0] * size.width, s[1] * size.height),
        s[2],
        Paint()..color = base.withOpacity(op),
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
            color: const Color(0xFF9B8CFF).withOpacity(op),
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

    // ground shadow
    canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, body.bottom + 16), width: 170, height: 12),
        Paint()..color = const Color(0x225B4B8A));

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
      Paint()..color = Colors.white.withOpacity(0.7),
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
          colors: [Color(0xFFFFFFFF), Color(0xFFEDE7FF)],
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
        final bp = Paint()..color = Colors.white.withOpacity(0.55);
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
        ..color = const Color(0xFFCDBEFF),
    );
    final shine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 6
      ..color = Colors.white.withOpacity(0.85);
    canvas.drawLine(Offset(body.left + 22, body.top + 62),
        Offset(body.left + 22, body.top + 104), shine);
    canvas.drawCircle(Offset(body.left + 22, body.top + 44), 3.5,
        Paint()..color = Colors.white.withOpacity(0.85));

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
        canvas.drawPath(drop, Paint()..color = const Color(0xFF6CC4FF));
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
      final sp = Paint()..color = const Color(0xFFFFC933);
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
