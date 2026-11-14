import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:android_intent_plus/android_intent.dart';

class GuestDashboardScreen extends StatefulWidget {
  const GuestDashboardScreen({super.key});
  @override
  State<GuestDashboardScreen> createState() => _GuestDashboardScreenState();
}

class _GuestDashboardScreenState extends State<GuestDashboardScreen> {
  bool isTesting = false;
  bool showGuestLockNotice = false;
  String phase = "READY";
  String selectedMode = "Wi-Fi";
  int ping = 0;
  double down = 0.0, up = 0.0, gauge = 0.0;
  Timer? _netWatchTimer;

  @override
  void initState() {
    super.initState();
    syncActiveNetwork();
    _netWatchTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!isTesting) syncActiveNetwork();
    });
  }

  @override
  void dispose() {
    _netWatchTimer?.cancel();
    super.dispose();
  }

  Future<String> getHardwareNetwork() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      bool hasWifi = false;
      bool hasCellular = false;
      for (var iface in interfaces) {
        final name = iface.name.toLowerCase();
        if (iface.addresses.isEmpty) continue;
        if (name.contains('wlan') || name.contains('wifi')) hasWifi = true;
        if (name.contains('rmnet') || name.contains('ccmni') || name.contains('pdp') || name.contains('wwan')) hasCellular = true;
      }
      if (hasWifi) return "Wi-Fi";
      if (hasCellular) return "Mobile Data";
    } catch (_) {}
    return "Disconnected";
  }

  Future<void> syncActiveNetwork() async {
    final current = await getHardwareNetwork();
    if (mounted && current != "Disconnected" && selectedMode != current) {
      setState(() => selectedMode = current);
    }
  }

  void showNetMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xff262626),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Switch Connection to Test', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xff4c1a80),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.wifi),
              label: const Text('Switch to Wi-Fi'),
              onPressed: () async {
                Navigator.pop(context);
                setState(() => selectedMode = "Wi-Fi");
                if (Platform.isAndroid) {
                  await AndroidIntent(action: 'android.settings.WIFI_SETTINGS').launch();
                }
              },
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xff333333),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.cell_tower),
              label: const Text('Switch to Mobile Data'),
              onPressed: () async {
                Navigator.pop(context);
                setState(() => selectedMode = "Mobile Data");
                if (Platform.isAndroid) {
                  await AndroidIntent(action: 'android.settings.WIFI_SETTINGS').launch();
                }
              },
            ),
            const SizedBox(height: 8),
            const Text(
              'Turn off Wi-Fi to check mobile data speed',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
  void runTest() async {
    final startNet = await getHardwareNetwork();
    if (startNet == "Disconnected") {
      setState(() => phase = "Connection Disconnected");
      return;
    }
    if (selectedMode == "Mobile Data" && startNet == "Wi-Fi") {
      setState(() => phase = "Turn off Wi-Fi first to test Mobile Data");
      return;
    }
    if (selectedMode == "Wi-Fi" && startNet != "Wi-Fi") {
      setState(() => phase = "Connect to Wi-Fi first");
      return;
    }

    bool aborted = false;
    setState(() { isTesting = true; phase = "Testing Ping"; ping = 0; down = 0.0; up = 0.0; gauge = 0.05; });

    final guardTimer = Timer.periodic(const Duration(milliseconds: 250), (t) async {
      final liveNet = await getHardwareNetwork();
      if (liveNet != startNet) {
        aborted = true;
        t.cancel();
        if (mounted) {
          setState(() {
            isTesting = false;
            phase = "Connection Disconnected";
            gauge = 0.0;
          });
        }
      }
    });

    int bestPing = 9999;
    Future<void> pingWorker() async {
      final client = HttpClient();
      try {
        final warmReq = await client.getUrl(Uri.parse('https://cloudflare.com'));
        final warmRes = await warmReq.close();
        await warmRes.drain();

        for (int i = 0; i < 3; i++) {
          if (!mounted || aborted) break;
          final sw = Stopwatch()..start();
          final req = await client.getUrl(Uri.parse('https://cloudflare.com'));
          final res = await req.close();
          await res.drain();
          sw.stop();
          int ms = sw.elapsedMilliseconds;
          if (ms > 0 && ms < bestPing && !aborted) {
            bestPing = ms;
            if (mounted) setState(() => ping = bestPing);
          }
          await Future.delayed(const Duration(milliseconds: 50));
        }
      } catch (_) {}
      client.close(force: true);
    }
    await Future.wait(List.generate(6, (_) => pingWorker()));

    if (aborted || !mounted) { guardTimer.cancel(); return; }
    await Future.delayed(const Duration(milliseconds: 300));
    if (aborted || !mounted) { guardTimer.cancel(); return; }
    setState(() => phase = "Testing Download Speed");

    final swDown = Stopwatch()..start();
    int bytesDown = 0;
    bool runDown = true;

    final uiTimerDown = Timer.periodic(const Duration(milliseconds: 150), (_) {
      double sec = swDown.elapsedMilliseconds / 1000.0;
      if (sec > 0.2 && mounted && runDown && !aborted) {
        setState(() {
          down = (bytesDown * 8) / (sec * 1000000);
          gauge = (down / 250.0).clamp(0.0, 1.0);
        });
      }
    });

    Future<void> downloadWorker() async {
      final ioClient = HttpClient();
      while (runDown && mounted && !aborted) {
        try {
          final req = await ioClient.getUrl(Uri.parse('https://cloudflare.com'));
          req.headers.set('Origin', 'https://cloudflare.com');
          final res = await req.close();
          await for (var chunk in res) {
            if (!runDown || !mounted || aborted) break;
            bytesDown += chunk.length;
          }
        } catch (_) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
      ioClient.close(force: true);
    }

    final downFutures = List.generate(6, (_) => downloadWorker());
    for (int i = 0; i < 60; i++) {
      if (aborted) break;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    runDown = false;
    uiTimerDown.cancel();
    await Future.wait(downFutures);

    if (aborted || !mounted) { guardTimer.cancel(); return; }
    setState(() { phase = "Testing Upload Speed"; gauge = 0.0; });
    await Future.delayed(const Duration(milliseconds: 300));
    if (aborted || !mounted) { guardTimer.cancel(); return; }

    final swUp = Stopwatch()..start();
    int bytesUp = 0;
    bool runUp = true;
    final Uint8List chunk64k = Uint8List(65536);

    final uiTimerUp = Timer.periodic(const Duration(milliseconds: 150), (_) {
      double sec = swUp.elapsedMilliseconds / 1000.0;
      if (sec > 0.2 && mounted && runUp && !aborted) {
        setState(() {
          up = (bytesUp * 8) / (sec * 1000000);
          gauge = (up / 150.0).clamp(0.0, 1.0);
        });
      }
    });

    Future<void> uploadWorker() async {
      final ioClient = HttpClient();
      while (runUp && mounted && !aborted) {
        try {
          final req = await ioClient.postUrl(Uri.parse('https://cloudflare.com/__up'));
          req.headers.set('Origin', 'https://cloudflare.com');
          req.headers.set('Content-Type', 'application/octet-stream');
          req.contentLength = chunk64k.length * 16;
          for (int i = 0; i < 16; i++) {
            if (!runUp || !mounted || aborted) break;
            req.add(chunk64k);
            await req.flush();
            bytesUp += chunk64k.length;
          }
          final res = await req.close();
          await res.drain();
        } catch (_) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
      ioClient.close(force: true);
    }

    final upFutures = List.generate(6, (_) => uploadWorker());
    for (int i = 0; i < 60; i++) {
      if (aborted) break;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    runUp = false;
    uiTimerUp.cancel();
    await Future.wait(upFutures);

    guardTimer.cancel();
    if (!aborted && mounted) {
      setState(() { isTesting = false; phase = "COMPLETED"; gauge = 0.0; });
    }
  }
  Widget statCol(String label, String val, Color col) => Column(children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.white38, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(val, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: col)),
      ]);

  @override
  Widget build(BuildContext context) {
    String centerText = !isTesting ? "START" : (phase == "Testing Ping" ? "$ping ms" : (phase.contains("Download") ? down.toStringAsFixed(1) : up.toStringAsFixed(1)));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Guest Speedtest', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xff111111),
        centerTitle: true,
        leading: const Icon(Icons.person_outline, color: Colors.white54),
        actions: [
          Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
            ),
          ),
        ],
      ),
      endDrawer: Drawer(
        backgroundColor: const Color(0xff1e1e1e),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                color: const Color(0xff4c1a80),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.person_outline, color: Colors.white, size: 36),
                    SizedBox(height: 10),
                    Text('Guest Mode', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    Text('Sign in to unlock security tools', style: TextStyle(fontSize: 12, color: Colors.white70)),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.lock_outline, color: Colors.amberAccent),
                title: const Text('Threat Protection', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Members Only', style: TextStyle(fontSize: 12, color: Colors.white54)),
                trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                onTap: () {
                  Navigator.pop(context);
                  setState(() => showGuestLockNotice = true);
                },
              ),
              const Spacer(),
              const Divider(color: Colors.white12),
              ListTile(
                leading: const Icon(Icons.login, color: Color(0xffa366ff)),
                title: const Text('Sign In / Exit Guest', style: TextStyle(color: Color(0xffa366ff), fontWeight: FontWeight.bold)),
                onTap: () => Navigator.pushReplacementNamed(context, 'login'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            if (showGuestLockNotice)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amberAccent.withOpacity(0.15),
                  border: Border.all(color: Colors.amberAccent, width: 1.5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock_person, color: Colors.amberAccent, size: 26),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'You need a Google Account to use Threat Protection.',
                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18, color: Colors.white54),
                      onPressed: () => setState(() => showGuestLockNotice = false),
                    ),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(20)),
              child: Text("Mode: $selectedMode", style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 24),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              statCol("PING", "$ping ms", Colors.amberAccent),
              statCol("DOWNLOAD", "${down.toStringAsFixed(1)} Mbps", const Color(0xffa366ff)),
              statCol("UPLOAD", "${up.toStringAsFixed(1)} Mbps", const Color(0xffdf80ff)),
            ]),
            const Spacer(),
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(width: 220, height: 220, child: CircularProgressIndicator(value: gauge, strokeWidth: 10, color: const Color(0xff4c1a80), backgroundColor: Colors.white10)),
                GestureDetector(
                  onTap: isTesting ? null : runTest,
                  child: Container(
                    width: 180, height: 180,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xff262626)),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(centerText, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                        if (isTesting && phase != "Testing Ping") const Text("Mbps", style: TextStyle(fontSize: 12, color: Colors.white38)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
            Text(phase, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: phase == "Connection Disconnected" ? Colors.redAccent : Colors.white54)),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xff4c1a80), width: 2),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: const StadiumBorder(),
                ),
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Change Wi-Fi / Mobile Data', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: isTesting ? null : showNetMenu,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
