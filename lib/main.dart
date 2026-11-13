import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'guest_dashboard.dart';
import 'account_dashboard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const SpeedtestApp());
}

class SpeedtestApp extends StatelessWidget {
  const SpeedtestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Speedtest',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xff1a1a1a),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xff4c1a80),
          secondary: Color(0xffa366ff),
        ),
      ),
      initialRoute: 'loading',
      routes: {
        'loading': (_) => const LoadingScreen(),
        'login': (_) => const LoginScreen(),
        'guest_dashboard': (_) => const GuestDashboardScreen(),
        'account_dashboard': (_) => const AccountDashboardScreen(),
      },
    );
  }
}

Widget purpleScreen(List<Widget> children) {
  return Scaffold(
    body: Container(
      width: double.infinity,
      height: double.infinity,
      color: const Color(0xff4c1a80),
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
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
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      final user = FirebaseAuth.instance.currentUser;
      Navigator.pushReplacementNamed(context, user != null ? 'account_dashboard' : 'login');
    });
  }

  @override
  Widget build(BuildContext context) {
    return purpleScreen([
      const Icon(Icons.speed, size: 80, color: Colors.white),
      const SizedBox(height: 20),
      const Text('Speedtest', textAlign: TextAlign.center, style: TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: Colors.white)),
      const SizedBox(height: 10),
      const Text('Loading...', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: Colors.white70)),
    ]);
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
      if (mounted) Navigator.pushReplacementNamed(context, 'account_dashboard');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sign-In failed: $e'), backgroundColor: Colors.redAccent));
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return purpleScreen([
      const Icon(Icons.network_check, size: 75, color: Colors.white),
      const SizedBox(height: 16),
      const Text('Speedtest', textAlign: TextAlign.center, style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.white)),
      const SizedBox(height: 8),
      const Text('Check your Wi-Fi and mobile network speed', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.white70)),
      const SizedBox(height: 48),
      if (isLoading)
        const Center(child: CircularProgressIndicator(color: Colors.white))
      else ...[
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black87,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: const Icon(Icons.login, color: Color(0xff4c1a80)),
          label: const Text('Sign in with Google', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          onPressed: signInWithGoogle,
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white54, width: 1.5),
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: const Icon(Icons.person_outline),
          label: const Text('Continue as Guest', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          onPressed: () => Navigator.pushReplacementNamed(context, 'guest_dashboard'),
        ),
      ],
    ]);
  }
}
