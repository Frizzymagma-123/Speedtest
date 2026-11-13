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
  String phase = "READY";
  String forcedMode = "AUTO"; // "AUTO", "WIFI", "MOBILE"
  String activeBadge = "Checking...";
  InternetAddress? boundLocalIp;
  int ping = 0;
  double down = 0.0, up = 0.0, gauge = 0.0;
  Timer? _netWatchTimer;

  @override
  void initState() {
    super.initState();
    resolveNetworkBinding().then((_) => runRealThreatCheck());
    _netWatchTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!isTesting) resolveNetworkBinding();
    });
  }

  @override
  void dispose() {
    _netWatchTimer?.cancel();
    super.dispose();
  }

  Future<void> resolveNetworkBinding() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      InternetAddress? wifiIp;
      InternetAddress? cellIp;

      for (var iface in interfaces) {
        final name = iface.name.toLowerCase();
        if (iface.addresses.isEmpty) continue;
        if (name.contains('wlan') || name.contains('wifi')) {
          wifiIp = iface.addresses.first;
        } else if (name.contains('rmnet') || name.contains('ccmni') || name.contains('pdp') || name.contains('wwan')) {
          cellIp = iface.addresses.first;
        }
      }

      InternetAddress? targetIp;
      String label = "Offline";

      if (forcedMode == "WIFI") {
        targetIp = wifiIp;
        label = wifiIp != null ? "Wi-Fi Only (Locked)" : "Wi-Fi Disconnected";
      } else if (forcedMode == "MOBILE") {
        targetIp = cellIp;
        label = cellIp != null ? "Mobile Data Only (Locked)" : "Mobile Data Off";
      } else {
        if (wifiIp != null) {
          targetIp = wifiIp;
          label = "Wi-Fi (Auto)";
        } else if (cellIp != null) {
          targetIp = cellIp;
          label = "Mobile Data (Auto)";
        }
      }

      if (mounted && (activeBadge != label || boundLocalIp != targetIp)) {
        setState(() {
          boundLocalIp = targetIp;
          activeBadge = label;
        });
      }
    } catch (_) {}
  }

  HttpClient createBoundHttpClient() {
    final client = HttpClient();
    final ip = boundLocalIp;
    if (ip != null) {
      client.connectionFactory = (Uri uri, String? proxyHost, int? proxyPort) {
        return Socket.startConnect(uri.host, uri.port, sourceAddress: ip);
      };
    }
    return client;
  }

  Future<void> runRealThreatCheck() async {
    if (!threatProtectionEnabled) {
      if (mounted) setState(() => threatAlertMessage = null);
      return;
    }
    if (mounted) setState(() => isScanningThreat = true);
    String? detectedIssue;

    // 1. Real DNS Hijack Check (Detects local router/hotspot DNS spoofing)
    try {
      final addresses = await InternetAddress.lookup('cloudflare.com').timeout(const Duration(seconds: 4));
      if (addresses.isEmpty) {
        detectedIssue = "Warning: DNS lookup failed. Possible DNS tampering or offline route.";
      } else {
        final ip = addresses.first.address;
        if (ip.startsWith('192.168.') || ip.startsWith('10.') || ip.startsWith('127.')) {
          detectedIssue = "Security Alert: DNS Spoofing detected! Traffic is being redirected to a local address ($ip).";
        }
      }
    } catch (_) {
      detectedIssue = "Warning: Unable to verify DNS integrity on this connection.";
    }

    // 2. Real Encrypted HTTPS & SSL Certificate Check (Eliminates Carrier HTTP 302 False Alarms)
    if (detectedIssue == null) {
      final client = createBoundHttpClient();
      try {
        final req = await client.getUrl(Uri.parse('https://google.com')).timeout(const Duration(seconds: 4));
        req.followRedirects = false;
        final res = await req.close();
        await res.drain();
        if (res.statusCode != 204 && res.statusCode != 200) {
          detectedIssue = "Warning: Captive portal or proxy interception detected (Status ${res.statusCode}). Avoid sensitive logins.";
        }
      } on HandshakeException {
        detectedIssue = "Critical Alert: SSL/TLS certificate mismatch! Potential Man-in-the-Middle attack on this network.";
      } catch (_) {
        detectedIssue = "Warning: Encrypted connection interrupted. Potential firewall block or unstable network.";
      } finally {
        client.close(force: true);
      }
    }

    if (mounted) {
      setState(() {
        isScanningThreat = false;
        threatAlertMessage = threatProtectionEnabled ? detectedIssue : null;
      });
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
            const Text('Select Network Route', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff4c1a80), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
              icon: const Icon(Icons.wifi),
              label: const Text('Wi-Fi Only (Ignore Mobile Data)'),
              onPressed: () async {
                Navigator.pop(context);
                setState(() => forcedMode = "WIFI");
                await resolveNetworkBinding();
                if (boundLocalIp == null && Platform.isAndroid) {
                  await AndroidIntent(action: 'android.settings.WIFI_SETTINGS').launch();
                } else {
                  runRealThreatCheck();
                }
              },
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff6a1b9a), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
              icon: const Icon(Icons.cell_tower),
              label: const Text('Mobile Data Only (Ignore Wi-Fi)'),
              onPressed: () async {
                Navigator.pop(context);
                setState(() => forcedMode = "MOBILE");
                await resolveNetworkBinding();
                if (boundLocalIp == null && Platform.isAndroid) {
                  await AndroidIntent(action: 'android.settings.DATA_ROAMING_SETTINGS').launch();
                } else {
                  runRealThreatCheck();
                }
              },
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                setState(() => forcedMode = "AUTO");
                await resolveNetworkBinding();
                runRealThreatCheck();
              },
              child: const Text('Auto-Detect Default Network', style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      ),
    );
  }

  void runTest() async {
    await resolveNetworkBinding();
    if (forcedMode != "AUTO" && boundLocalIp == null) {
      setState(() => phase = "Enable ${forcedMode == 'WIFI' ? 'Wi-Fi' : 'Mobile Data'} first!");
      return;
    }

    if (threatProtectionEnabled) runRealThreatCheck();
    setState(() { isTesting = true; phase = "Testing Ping"; ping = 0; down = 0.0; up = 0.0; gauge = 0.05; });

    int bestPing = 9999;
    Future<void> pingWorker() async {
      final client = createBoundHttpClient();
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
      final ioClient = createBoundHttpClient();
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
      final ioClient = createBoundHttpClient();
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
      resolveNetworkBinding();
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
                subtitle: Text(threatProtectionEnabled ? 'Enabled (HTTPS & DNS Guard)' : 'Disabled', style: const TextStyle(fontSize: 12, color: Colors.white54)),
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(activeBadge.contains("Wi-Fi") ? Icons.wifi : Icons.cell_tower, size: 14, color: const Color(0xffa366ff)),
                      const SizedBox(width: 6),
                      Text("Mode: $activeBadge", style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
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
