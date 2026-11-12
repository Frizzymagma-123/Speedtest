import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:android_intent_plus/android_intent.dart';

class AccountDashboardScreen extends StatefulWidget {
  const AccountDashboardScreen({super.key});
  @override
  State<AccountDashboardScreen> createState() => _AccountDashboardScreenState();
}

class _AccountDashboardScreenState extends State<AccountDashboardScreen> {
  bool isTesting = false;
  String phase = "READY", netLabel = "Current Network";
  int ping = 0;
  double down = 0.0, up = 0.0, gauge = 0.0;

  void openSettings(String action, String label) async {
    setState(() => netLabel = label);
    if (Platform.isAndroid) {
      await AndroidIntent(action: action).launch();
    }
  }

  void showNetMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xff262626),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Switch Connection to Test', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff4c1a80), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
              icon: const Icon(Icons.wifi),
              label: const Text('Switch Wi-Fi Network'),
              onPressed: () {
                Navigator.pop(context);
                openSettings('android.settings.WIFI_SETTINGS', 'Wi-Fi Test');
              },
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff333333), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
              icon: const Icon(Icons.cell_tower),
              label: const Text('Switch to Mobile Data'),
              onPressed: () {
                Navigator.pop(context);
                openSettings('android.settings.DATA_ROAMING_SETTINGS', 'Mobile Data Test');
              },
            ),
          ],
        ),
      ),
    );
  }
  void runTest() async {
    setState(() { isTesting = true; phase = "Testing Ping"; ping = 0; down = 0.0; up = 0.0; gauge = 0.05; });

    final swPing = Stopwatch()..start();
    try {
      await http.get(Uri.parse('https://cloudflare.com')).timeout(const Duration(seconds: 3));
      if (mounted) setState(() => ping = swPing.elapsedMilliseconds);
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() => phase = "Testing Download Speed");

    final swDown = Stopwatch()..start();
    int bytesDown = 0;
    bool runDown = true;
    final clients = List.generate(4, (_) => http.Client());

    final uiTimerDown = Timer.periodic(const Duration(milliseconds: 150), (_) {
      double sec = swDown.elapsedMilliseconds / 1000.0;
      if (sec > 0.2 && mounted && runDown) {
        setState(() {
          down = (bytesDown * 8) / (sec * 1000000);
          gauge = (down / 250.0).clamp(0.0, 1.0);
        });
      }
    });

    Future<void> downloadWorker(http.Client client) async {
      while (runDown && mounted) {
        try {
          final res = await client.send(http.Request('GET', Uri.parse('https://cloudflare.com00000000')));
          await for (var chunk in res.stream) {
            if (!runDown || !mounted) break;
            bytesDown += chunk.length;
          }
        } catch (_) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
    }

    final downFutures = clients.map((c) => downloadWorker(c)).toList();
    await Future.delayed(const Duration(seconds: 6));
    runDown = false;
    uiTimerDown.cancel();
    for (var c in clients) { c.close(); }
    await Future.wait(downFutures);

    if (!mounted) return;
    setState(() { phase = "Testing Upload Speed"; gauge = 0.0; });
    await Future.delayed(const Duration(milliseconds: 400));

    final swUp = Stopwatch()..start();
    int bytesUp = 0;
    bool runUp = true;
    final Uint8List chunk64k = Uint8List(65536);

    final uiTimerUp = Timer.periodic(const Duration(milliseconds: 150), (_) {
      double sec = swUp.elapsedMilliseconds / 1000.0;
      if (sec > 0.2 && mounted && runUp) {
        setState(() {
          up = (bytesUp * 8) / (sec * 1000000);
          gauge = (up / 150.0).clamp(0.0, 1.0);
        });
      }
    });

    Future<void> uploadWorker() async {
      final ioClient = HttpClient();
      while (runUp && mounted) {
        try {
          final req = await ioClient.postUrl(Uri.parse('https://cloudflare.com'));
          req.headers.set('Origin', 'https://cloudflare.com');
          req.headers.set('Content-Type', 'application/octet-stream');
          req.contentLength = chunk64k.length * 16;
          for (int i = 0; i < 16; i++) {
            if (!runUp || !mounted) break;
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

    final upFutures = List.generate(3, (_) => uploadWorker());
    await Future.delayed(const Duration(seconds: 6));
    runUp = false;
    uiTimerUp.cancel();
    await Future.wait(upFutures);

    if (mounted) {
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
    final user = FirebaseAuth.instance.currentUser;
    String centerText = !isTesting ? "START" : (phase == "Testing Ping" ? "$ping ms" : (phase.contains("Download") ? down.toStringAsFixed(1) : up.toStringAsFixed(1)));

    return Scaffold(
      appBar: AppBar(
        title: Text(user?.displayName != null ? 'Hi, ${user!.displayName}' : 'Member Speedtest', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xff111111),
        centerTitle: true,
        leading: user?.photoURL != null ? Padding(padding: const EdgeInsets.all(10), child: CircleAvatar(backgroundImage: NetworkImage(user!.photoURL!))) : const Icon(Icons.verified_user, color: Colors.amberAccent),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white70),
            onPressed: () async {
              await GoogleSignIn().signOut();
              await FirebaseAuth.instance.signOut();
              if (mounted) {
                Navigator.pushReplacementNamed(context, 'login');
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(20)),
              child: Text("Mode: $netLabel", style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.bold)),
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
            Text(phase, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white54)),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Color(0xff4c1a80), width: 2), padding: const EdgeInsets.symmetric(vertical: 14)),
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
