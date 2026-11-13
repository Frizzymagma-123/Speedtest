import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
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
  bool threatProtectionEnabled = true;
  bool isScanningThreat = false;
  String? threatAlertMessage;
  String phase = "READY", netLabel = "Current Network";
  int ping = 0;
  double down = 0.0, up = 0.0, gauge = 0.0;

  @override
  void initState() {
    super.initState();
    runRealThreatCheck();
  }

  Future<void> runRealThreatCheck() async {
    if (!threatProtectionEnabled) {
      if (mounted) setState(() => threatAlertMessage = null);
      return;
    }
    if (mounted) setState(() => isScanningThreat = true);
    String? detectedIssue;

    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse('http://gstatic.com')).timeout(const Duration(seconds: 4));
      req.followRedirects = false;
      final res = await req.close();
      await res.drain();
      if (res.statusCode != 204) {
        detectedIssue = "Warning: Network interception or captive portal detected (HTTP ${res.statusCode}). Avoid entering passwords.";
      }
    } catch (_) {
      detectedIssue = "Warning: Unable to verify clean internet route. Possible DNS block or unstable network.";
    } finally {
      client.close(force: true);
    }

    if (detectedIssue == null) {
      try {
        final socket = await SecureSocket.connect('cloudflare.com', 443, timeout: const Duration(seconds: 4));
        final cert = socket.peerCertificate;
        if (cert == null || (!cert.issuer.contains('Cloudflare') && !cert.issuer.contains('DigiCert') && !cert.issuer.contains('Google'))) {
          detectedIssue = "Security Alert: Untrusted SSL certificate issuer detected (${cert?.issuer ?? 'Unknown'}). Traffic may be monitored.";
        }
        await socket.close();
      } on HandshakeException {
        detectedIssue = "Critical Alert: SSL/TLS handshake failed! Potential Man-in-the-Middle attack on this Wi-Fi.";
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        isScanningThreat = false;
        threatAlertMessage = threatProtectionEnabled ? detectedIssue : null;
      });
    }
  }

  void openSettings(String action, String label) async {
    setState(() => netLabel = label);
    if (Platform.isAndroid) {
      await AndroidIntent(action: action).launch();
    }
    await Future.delayed(const Duration(seconds: 2));
    runRealThreatCheck();
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
    if (threatProtectionEnabled) runRealThreatCheck();
    setState(() { isTesting = true; phase = "Testing Ping"; ping = 0; down = 0.0; up = 0.0; gauge = 0.05; });

    int bestPing = 9999;
    Future<void> pingWorker() async {
      final client = HttpClient();
      try {
        final warmReq = await client.getUrl(Uri.parse('https://cloudflare.com'));
        final warmRes = await warmReq.close();
        await warmRes.drain();

        for (int i = 0; i < 3; i++) {
          if (!mounted) break;
          final sw = Stopwatch()..start();
          final req = await client.getUrl(Uri.parse('https://cloudflare.com'));
          final res = await req.close();
          await res.drain();
          sw.stop();
          int ms = sw.elapsedMilliseconds;
          if (ms > 0 && ms < bestPing) {
            bestPing = ms;
            if (mounted) setState(() => ping = bestPing);
          }
          await Future.delayed(const Duration(milliseconds: 50));
        }
      } catch (_) {}
      client.close(force: true);
    }
    await Future.wait(List.generate(6, (_) => pingWorker()));

    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() => phase = "Testing Download Speed");

    final swDown = Stopwatch()..start();
    int bytesDown = 0;
    bool runDown = true;

    final uiTimerDown = Timer.periodic(const Duration(milliseconds: 150), (_) {
      double sec = swDown.elapsedMilliseconds / 1000.0;
      if (sec > 0.2 && mounted && runDown) {
        setState(() {
          down = (bytesDown * 8) / (sec * 1000000);
          gauge = (down / 250.0).clamp(0.0, 1.0);
        });
      }
    });

    Future<void> downloadWorker() async {
      final ioClient = HttpClient();
      while (runDown && mounted) {
        try {
          final req = await ioClient.getUrl(Uri.parse('https://cloudflare.com'));
          req.headers.set('Origin', 'https://cloudflare.com');
          final res = await req.close();
          await for (var chunk in res) {
            if (!runDown || !mounted) break;
            bytesDown += chunk.length;
          }
        } catch (_) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
      ioClient.close(force: true);
    }

    final downFutures = List.generate(6, (_) => downloadWorker());
    await Future.delayed(const Duration(seconds: 6));
    runDown = false;
    uiTimerDown.cancel();
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
          final req = await ioClient.postUrl(Uri.parse('https://cloudflare.com/__up'));
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

    final upFutures = List.generate(6, (_) => uploadWorker());
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.shield, color: Colors.white, size: 36),
                    const SizedBox(height: 10),
                    Text(user?.displayName ?? 'Member Account', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    Text(user?.email ?? 'Verified Member', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                  ],
                ),
              ),
              SwitchListTile(
                activeColor: const Color(0xffa366ff),
                secondary: Icon(threatProtectionEnabled ? Icons.gpp_good : Icons.gpp_maybe, color: threatProtectionEnabled ? Colors.greenAccent : Colors.white54),
                title: const Text('Threat Protection', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(threatProtectionEnabled ? 'Enabled (Live SSL & DNS check)' : 'Disabled', style: const TextStyle(fontSize: 12, color: Colors.white54)),
                value: threatProtectionEnabled,
                onChanged: (val) {
                  setState(() => threatProtectionEnabled = val);
                  if (val) {
                    runRealThreatCheck();
                  } else {
                    setState(() => threatAlertMessage = null);
                  }
                },
              ),
              if (threatProtectionEnabled)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextButton.icon(
                    icon: const Icon(Icons.refresh, size: 18, color: Color(0xffa366ff)),
                    label: const Text('Re-scan Current Network', style: TextStyle(color: Color(0xffa366ff))),
                    onPressed: isScanningThreat ? null : runRealThreatCheck,
                  ),
                ),
              const Spacer(),
              const Divider(color: Colors.white12),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.redAccent),
                title: const Text('Log Out', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                onTap: () async {
                  Navigator.pop(context);
                  await GoogleSignIn().signOut();
                  await FirebaseAuth.instance.signOut();
                  if (mounted) Navigator.pushReplacementNamed(context, 'login');
                },
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
            if (threatProtectionEnabled && threatAlertMessage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.15),
                  border: Border.all(color: Colors.redAccent, width: 1.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
                    const SizedBox(width: 12),
                    Expanded(child: Text(threatAlertMessage!, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600))),
                  ],
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(20)),
                  child: Text("Mode: $netLabel", style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.bold)),
                ),
                if (threatProtectionEnabled) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: (threatAlertMessage == null ? Colors.green : Colors.red).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Icon(isScanningThreat ? Icons.sync : (threatAlertMessage == null ? Icons.verified_user : Icons.gpp_bad), size: 14, color: threatAlertMessage == null ? Colors.greenAccent : Colors.redAccent),
                        const SizedBox(width: 4),
                        Text(isScanningThreat ? "Scanning..." : (threatAlertMessage == null ? "Protected" : "Risk"), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: threatAlertMessage == null ? Colors.greenAccent : Colors.redAccent)),
                      ],
                    ),
                  ),
                ],
              ],
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
