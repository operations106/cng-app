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
      title: 'CNG Meter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.greenAccent,
        scaffoldBackgroundColor: const Color(0xFF0B1118),
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

class _HomePageState extends State<HomePage> {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _cmdChar;
  StreamSubscription<List<int>>? _dataSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;

  double _percent = 0;
  double _voltage = 0;
  bool _connected = false;
  bool _busy = false;
  String _status = 'Not connected';

  Color _levelColor(double p) {
    if (p < 15) return const Color(0xFFFF5252);
    if (p < 30) return const Color(0xFFFFAB40);
    return const Color(0xFF00E676);
  }

  Future<void> _scanAndConnect() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = 'Searching for CNG_Meter...';
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
            _status = 'Disconnected';
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
        _status = 'Connected';
      });
    } catch (e) {
      await scanSub?.cancel();
      if (mounted) {
        setState(() {
          _connected = false;
          _status = 'Not connected';
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
        _status = 'Disconnected';
      });
    }
  }

  Future<void> _sendCmd(String cmd, String label) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: Text(
          cmd == 'RESET'
              ? 'Calibration default par reset hogi.'
              : 'Abhi ki sensor voltage (${_voltage.toStringAsFixed(2)} V) ko '
                  '${cmd == 'SETEMPTY' ? '0% (empty)' : '100% (full)'} set kiya jayega.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _cmdChar?.write(utf8.encode(cmd));
      _snack('Done');
    } catch (e) {
      _snack('Command failed: $e');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    _connSub?.cancel();
    _device?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _levelColor(_percent);
    final low = _connected && _percent < 15;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.local_gas_station_rounded, size: 28),
                  const SizedBox(width: 10),
                  const Text('CNG Meter',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  _StatusChip(connected: _connected, text: _status),
                ],
              ),
              if (low)
                Container(
                  margin: const EdgeInsets.only(top: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0x33FF5252),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFF5252)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Color(0xFFFF5252)),
                      SizedBox(width: 10),
                      Expanded(child: Text('CNG kam hai! Jaldi fill karwao.')),
                    ],
                  ),
                ),
              Expanded(
                child: Center(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: _connected ? _percent : 0),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) {
                      return SizedBox(
                        width: 280,
                        height: 280,
                        child: CustomPaint(
                          painter: GaugePainter(value, _levelColor(value)),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _connected ? '${value.round()}%' : '--',
                                  style: TextStyle(
                                    fontSize: 64,
                                    fontWeight: FontWeight.w800,
                                    color: _connected ? color : Colors.white38,
                                  ),
                                ),
                                const Text('CNG LEVEL',
                                    style: TextStyle(
                                        letterSpacing: 3, color: Colors.white54, fontSize: 13)),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _InfoCard(
                      icon: Icons.bolt_rounded,
                      label: 'Sensor voltage',
                      value: _connected ? '${_voltage.toStringAsFixed(2)} V' : '--',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _InfoCard(
                      icon: Icons.bluetooth_rounded,
                      label: 'Device',
                      value: _connected ? 'CNG_Meter' : 'Offline',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_connected)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _sendCmd('SETEMPTY', 'Set Empty (0%)'),
                        child: const Text('Set Empty'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _sendCmd('SETFULL', 'Set Full (100%)'),
                        child: const Text('Set Full'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      tooltip: 'Reset calibration',
                      onPressed: () => _sendCmd('RESET', 'Reset calibration'),
                      icon: const Icon(Icons.restart_alt_rounded),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.icon(
                  onPressed: _busy ? null : (_connected ? _disconnect : _scanAndConnect),
                  icon: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(_connected ? Icons.link_off_rounded : Icons.bluetooth_searching_rounded),
                  label: Text(
                    _busy ? 'Please wait...' : (_connected ? 'Disconnect' : 'Connect to CNG Meter'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final bool connected;
  final String text;
  const _StatusChip({required this.connected, required this.text});

  @override
  Widget build(BuildContext context) {
    final c = connected ? const Color(0xFF00E676) : Colors.white54;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 9, color: c),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(fontSize: 12, color: c)),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoCard({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF151F2B),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.white54),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.white54)),
        ],
      ),
    );
  }
}

class GaugePainter extends CustomPainter {
  final double value;
  final Color color;
  GaugePainter(this.value, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.09;
    final rect = Rect.fromLTWH(
        stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    const start = 135 * math.pi / 180;
    const sweep = 270 * math.pi / 180;

    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = Colors.white10;
    canvas.drawArc(rect, start, sweep, false, bg);

    final frac = (value / 100).clamp(0.0, 1.0).toDouble();
    if (frac <= 0) return;

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color.withOpacity(0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawArc(rect, start, sweep * frac, false, glow);

    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(rect, start, sweep * frac, false, fg);
  }

  @override
  bool shouldRepaint(covariant GaugePainter old) =>
      old.value != value || old.color != color;
}
