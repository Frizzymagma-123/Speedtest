import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'guest_dashboard.dart';
import 'account_dashboard.dart';

const String bgThreatTaskName = "periodicThreatProtectionScan";

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await Firebase.initializeApp();
      if (FirebaseAuth.instance.currentUser == null) {
        return Future.value(true);
      }

      String? detectedIssue;
      try {
        final addresses = await InternetAddress.lookup('cloudflare.com').timeout(const Duration(seconds: 4));
        if (addresses.isNotEmpty) {
          final ip = addresses.first.address;
          if (ip.startsWith('192.168.') || ip.startsWith('10.') || ip.startsWith('127.')) {
            detectedIssue = "Security Alert: DNS spoofing detected ($ip). Avoid entering passwords.";
          }
        }
      } catch (_) {}

      if (detectedIssue == null) {
        final client = HttpClient();
        try {
          final req = await client.getUrl(Uri.parse('https://cloudflare.com')).timeout(const Duration(seconds: 4));
          req.followRedirects = false;
          final res = await req.close();
          await res.drain();
          if (res.statusCode != 200 && res.statusCode != 204 && res.statusCode != 301 && res.statusCode != 302) {
            detectedIssue = "Warning: Captive portal or proxy interception detected (Status ${res.statusCode}).";
          }
        } on HandshakeException {
          detectedIssue = "Critical Alert: SSL certificate mismatch! Potential Man-in-the-Middle attack.";
        } catch (_) {} finally {
          client.close(force: true);
        }
      }

      if (detectedIssue != null) {
        final notifications = FlutterLocalNotificationsPlugin();
        const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
        await notifications.initialize(const InitializationSettings(android: androidInit));
        const androidDetails = AndroidNotificationDetails(
          'threat_protection_channel',
          'Threat Protection Alerts',
          channelDescription: 'Alerts when a network attack or hijack is detected',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        );
        await notifications.show(
          1002,
          'Security Alert: Network Threat Detected',
          detectedIssue,
          const NotificationDetails(android: androidDetails),
        );
      }
    } catch (_) {}
    return Future.value(true);
  });
}

Future<void> startBackgroundThreatGuard() async {
  final notifications = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await notifications.initialize(const InitializationSettings(android: androidInit));
  await notifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();

  await Workmanager().registerPeriodicTask(
    bgThreatTaskName,
    bgThreatTaskName,
    frequency: const Duration(minutes: 15),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    constraints: Constraints(networkType: NetworkType.connected),
  );
}

Future<void> stopBackgroundThreatGuard() async {
  await Workmanager().cancelByUniqueName(bgThreatTaskName);
}
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  runApp(const MyCustomSpeedtestApp());
}

class MyCustomSpeedtestApp extends StatelessWidget {
  const MyCustomSpeedtestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Speedtest App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xff1a1a1a),
      ),
      initialRoute: 'loading',
      routes: {
        'loading': (context) => const LoadingScreen(),
        'login': (context) => const LoginScreen(),
        'member_home': (context) => const MemberHomeScreen(),
        'guest_dashboard': (context) => const GuestDashboardScreen(),
        'account_dashboard': (context) => const AccountDashboardScreen(),
      },
    );
  }
}

class PurpleLayout extends StatelessWidget {
  final List<Widget> children;
  final double padding;

  const PurpleLayout({
    super.key,
    required this.children,
    this.padding = 40.0,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          color: Color(0xff4c1a80),
        ),
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () async {
      if (!mounted) return;
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await startBackgroundThreatGuard();
        if (mounted) Navigator.pushReplacementNamed(context, 'member_home');
      } else {
        Navigator.pushReplacementNamed(context, 'login');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const PurpleLayout(
      children: [
        Icon(Icons.speed, size: 80, color: Colors.white),
        SizedBox(height: 16),
        Text(
          'Speedtest',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 1,
          ),
        ),
        SizedBox(height: 32),
        Center(
          child: SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 5,
            ),
          ),
        ),
      ],
    );
  }
}
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool isLoading = false;

  Future<void> signInWithGoogle() async {
    setState(() => isLoading = true);
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => isLoading = false);
        return;
      }
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
      await startBackgroundThreatGuard();
      if (mounted) Navigator.pushReplacementNamed(context, 'member_home');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign-In failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PurpleLayout(
      children: [
        const Icon(Icons.speed, size: 80, color: Colors.white),
        const SizedBox(height: 15),
        const Text(
          'Speedtest App',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 8),
        const Text(
          'Tells your Internet Speed With More Features',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.white70),
        ),
        const SizedBox(height: 50),
        if (isLoading)
          const Center(child: CircularProgressIndicator(color: Colors.white))
        else ...[
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
            icon: const Icon(Icons.account_circle, size: 24, color: Colors.redAccent),
            onPressed: signInWithGoogle,
            label: const Text(
              'Sign in with Google Account',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white54, width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
            icon: const Icon(Icons.person_outline, size: 22),
            onPressed: () {
              Navigator.pushReplacementNamed(context, 'guest_dashboard');
            },
            label: const Text(
              'Continue as Guest',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ],
      ],
    );
  }
}

class MemberHomeScreen extends StatelessWidget {
  const MemberHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xff4c1a80),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          user?.displayName != null ? 'Hi, ${user!.displayName}' : 'Member Home',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.white12,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              icon: const Icon(Icons.logout, size: 18, color: Colors.white),
              label: const Text('Log Out', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              onPressed: () async {
                await stopBackgroundThreatGuard();
                await GoogleSignIn().signOut();
                await FirebaseAuth.instance.signOut();
                if (context.mounted) {
                  Navigator.pushReplacementNamed(context, 'login');
                }
              },
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.speed, size: 84, color: Colors.white),
            const SizedBox(height: 16),
            const Text(
              'Speedtest',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 12),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.greenAccent, width: 1),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_user, size: 16, color: Colors.greenAccent),
                    SizedBox(width: 6),
                    Text(
                      'Threat Protection Always Active',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.greenAccent),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 48),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xff4c1a80),
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: const StadiumBorder(),
                elevation: 6,
              ),
              icon: const Icon(Icons.play_arrow_rounded, size: 28),
              label: const Text(
                'Speedtest',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                Navigator.pushReplacementNamed(context, 'account_dashboard');
              },
            ),
          ],
        ),
      ),
    );
  }
}
