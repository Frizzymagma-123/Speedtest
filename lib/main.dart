import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'guest_dashboard.dart';
import 'account_dashboard.dart';

bool firebaseReady = false;
bool threatProtectionEnabled = true;

Future<void> _performBackgroundThreatScan(FlutterLocalNotificationsPlugin notifications) async {
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
    const alertDetails = AndroidNotificationDetails(
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
      const NotificationDetails(android: alertDetails),
    );
  }
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final notifications = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await notifications.initialize(const InitializationSettings(android: androidInit));

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  await _performBackgroundThreatScan(notifications);

  Timer.periodic(const Duration(minutes: 5), (timer) async {
    await _performBackgroundThreatScan(notifications);
  });
}

Future<void> initBackgroundService() async {
  final service = FlutterBackgroundService();
  final notifications = FlutterLocalNotificationsPlugin();

  const channel = AndroidNotificationChannel(
    'threat_guard_foreground',
    'Threat Protection Background Guard',
    description: 'Keeps 5-minute network Threat Protection active',
    importance: Importance.min,
    playSound: false,
    enableVibration: false,
    showBadge: false,
  );

  await notifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'threat_guard_foreground',
      initialNotificationTitle: 'Speedtest Threat Protection',
      initialNotificationContent: 'Monitoring network every 5 minutes',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(autoStart: false),
  );
}

Future<void> startBackgroundThreatGuard() async {
  if (!threatProtectionEnabled) return;
  final notifications = FlutterLocalNotificationsPlugin();
  await notifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();

  final service = FlutterBackgroundService();
  if (!(await service.isRunning())) {
    await service.startService();
  }
}

Future<void> stopBackgroundThreatGuard() async {
  final service = FlutterBackgroundService();
  if (await service.isRunning()) {
    service.invoke('stopService');
  }
}
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
    firebaseReady = true;
  } catch (_) {
    firebaseReady = false;
  }
  try {
    await initBackgroundService();
  } catch (_) {}
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
        'email_auth': (context) => const EmailAuthScreen(),
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
      User? user;
      if (firebaseReady) {
        try {
          user = FirebaseAuth.instance.currentUser;
        } catch (_) {}
      }
      if (user != null) {
        threatProtectionEnabled = true;
        try {
          await startBackgroundThreatGuard();
        } catch (_) {}
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
    if (!firebaseReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Google Sign-In unavailable here. Try Sign in with Email or Guest Mode.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

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
      threatProtectionEnabled = true;
      try {
        await startBackgroundThreatGuard();
      } catch (_) {}
      if (mounted) Navigator.pushReplacementNamed(context, 'member_home');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Google Sign-In unavailable on this device. Try Sign in with Email.'),
            backgroundColor: Colors.redAccent,
          ),
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
        const SizedBox(height: 44),
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
          const SizedBox(height: 14),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xff2d0f4d),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
            icon: const Icon(Icons.email, size: 24, color: Color(0xff4fc3f7)),
            onPressed: () {
              Navigator.pushNamed(context, 'email_auth');
            },
            label: const Text(
              'Sign in with Email',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          const SizedBox(height: 14),
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
class EmailAuthScreen extends StatefulWidget {
  const EmailAuthScreen({super.key});

  @override
  State<EmailAuthScreen> createState() => _EmailAuthScreenState();
}

class _EmailAuthScreenState extends State<EmailAuthScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool isCreateMode = false;
  bool waitingForVerification = false;
  bool isBusy = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showMsg(String text, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
      ),
    );
  }

  Future<void> _handleEmailSubmit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.length < 6) {
      _showMsg('Enter a valid email and a password (at least 6 characters).');
      return;
    }

    setState(() => isBusy = true);
    try {
      if (isCreateMode) {
        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        await cred.user?.sendEmailVerification();
        setState(() {
          waitingForVerification = true;
          isBusy = false;
        });
        _showMsg('Verification link sent to $email! Check your inbox.', isError: false);
      } else {
        final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        if (cred.user != null && !cred.user!.emailVerified) {
          await cred.user!.sendEmailVerification();
          setState(() {
            waitingForVerification = true;
            isBusy = false;
          });
          _showMsg('Please verify your email first. We sent a new link to $email.');
          return;
        }
        threatProtectionEnabled = true;
        try {
          await startBackgroundThreatGuard();
        } catch (_) {}
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(context, 'member_home', (route) => false);
        }
      }
    } on FirebaseAuthException catch (e) {
      _showMsg(e.message ?? 'Authentication failed.');
    } catch (e) {
      _showMsg('Error: $e');
    } finally {
      if (mounted) setState(() => isBusy = false);
    }
  }

  Future<void> _checkEmailVerified() async {
    setState(() => isBusy = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      await user?.reload();
      final refreshed = FirebaseAuth.instance.currentUser;
      if (refreshed != null && refreshed.emailVerified) {
        threatProtectionEnabled = true;
        try {
          await startBackgroundThreatGuard();
        } catch (_) {}
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(context, 'member_home', (route) => false);
        }
      } else {
        _showMsg('Not verified yet. Open the email link we sent you, then tap below again.');
      }
    } catch (e) {
      _showMsg('Could not check verification: $e');
    } finally {
      if (mounted) setState(() => isBusy = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff4c1a80),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          waitingForVerification
              ? 'Verify Your Email'
              : (isCreateMode ? 'Create Account' : 'Sign in with Email'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                waitingForVerification ? Icons.mark_email_unread_outlined : Icons.email_rounded,
                size: 72,
                color: Colors.white,
              ),
              const SizedBox(height: 20),
              if (waitingForVerification) ...[
                Text(
                  'We sent a verification email to:\n${_emailController.text.trim()}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Open the link in your email inbox (check Spam if needed), then tap the button below.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.white70),
                ),
                const SizedBox(height: 32),
                if (isBusy)
                  const Center(child: CircularProgressIndicator(color: Colors.white))
                else ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xff4c1a80),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: const StadiumBorder(),
                    ),
                    icon: const Icon(Icons.verified_user),
                    label: const Text('I Have Verified My Email', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    onPressed: _checkEmailVerified,
                  ),
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: () async {
                      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
                      _showMsg('Verification link resent!', isError: false);
                    },
                    child: const Text('Resend Verification Email', style: TextStyle(color: Colors.white70)),
                  ),
                ],
              ] else ...[
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Email Address',
                    labelStyle: const TextStyle(color: Colors.white70),
                    prefixIcon: const Icon(Icons.email_outlined, color: Colors.white70),
                    filled: true,
                    fillColor: Colors.white12,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Password (min 6 chars)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    prefixIcon: const Icon(Icons.lock_outline, color: Colors.white70),
                    filled: true,
                    fillColor: Colors.white12,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 28),
                if (isBusy)
                  const Center(child: CircularProgressIndicator(color: Colors.white))
                else ...[
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xff4c1a80),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: const StadiumBorder(),
                    ),
                    onPressed: _handleEmailSubmit,
                    child: Text(
                      isCreateMode ? 'Create Account & Send Verification' : 'Sign In',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () {
                      setState(() => isCreateMode = !isCreateMode);
                    },
                    child: Text(
                      isCreateMode
                          ? 'Already have an account? Sign In'
                          : 'Create an Account',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
class MemberHomeScreen extends StatefulWidget {
  const MemberHomeScreen({super.key});

  @override
  State<MemberHomeScreen> createState() => _MemberHomeScreenState();
}

class _MemberHomeScreenState extends State<MemberHomeScreen> {
  @override
  Widget build(BuildContext context) {
    User? user;
    if (firebaseReady) {
      try {
        user = FirebaseAuth.instance.currentUser;
      } catch (_) {}
    }

    final displayLabel = user?.displayName ?? user?.email ?? 'Member Home';

    return Scaffold(
      backgroundColor: const Color(0xff4c1a80),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'Hi, $displayLabel',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
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
                try {
                  await stopBackgroundThreatGuard();
                  await GoogleSignIn().signOut();
                  await FirebaseAuth.instance.signOut();
                } catch (_) {}
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
              child: GestureDetector(
                onTap: () async {
                  setState(() => threatProtectionEnabled = !threatProtectionEnabled);
                  if (threatProtectionEnabled) {
                    await startBackgroundThreatGuard();
                  } else {
                    await stopBackgroundThreatGuard();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: (threatProtectionEnabled ? Colors.greenAccent : Colors.white24).withOpacity(0.18),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: threatProtectionEnabled ? Colors.greenAccent : Colors.white54, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        threatProtectionEnabled ? Icons.verified_user : Icons.shield_outlined,
                        size: 16,
                        color: threatProtectionEnabled ? Colors.greenAccent : Colors.white70,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        threatProtectionEnabled ? 'Threat Protection: ON' : 'Threat Protection: OFF',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: threatProtectionEnabled ? Colors.greenAccent : Colors.white70,
                        ),
                      ),
                    ],
                  ),
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
              icon: const Icon(Icons.speed, size: 28),
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
