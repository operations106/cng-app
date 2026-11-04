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
      home: const Shell(),
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
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('CNG Buddy ⛽',
                              style: TextStyle(
                                  fontSize: 26, fontWeight: FontWeight.w900)),
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
      surfaceTintColor: Colors.transparent,
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
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('CNG Radar 📡',
                            style: TextStyle(
                                fontSize: 24, fontWeight: FontWeight.w900)),
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
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(s.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w800)),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${s.km.toStringAsFixed(1)} km door${s.reportedAt != null ? '  •  ${_ago(s.reportedAt!)}' : ''}',
                                              style: const TextStyle(
                                                  fontSize: 12, color: kMuted),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            s.rate != null
                                                ? '₹${s.rate!.toStringAsFixed(1)}/kg'
                                                : '₹ --',
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
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
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
