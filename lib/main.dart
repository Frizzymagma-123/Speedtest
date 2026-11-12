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
      theme: ThemeData.dark()
          .copyWith(scaffoldBackgroundColor: const Color(0xff1a1a1a)),
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

Widget purpleScreen(List<Widget> children) => Scaffold(
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(40),
        color: const Color(0xff4c1a80),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});
  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 5), () {
      if (!mounted) return;
      Navigator.pushReplacementNamed(
          context,
          FirebaseAuth.instance.currentUser != null
              ? 'account_dashboard'
              : 'login');
    });
  }

  @override
  Widget build(BuildContext context) => purpleScreen(const [
        Text('Speedtest App',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
        SizedBox(height: 30),
        Center(child: CircularProgressIndicator(color: Colors.white)),
      ]);
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool isSigningIn = false;

  Future<void> signInWithGoogle() async {
    setState(() => isSigningIn = true);
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return;
      final auth = await googleUser.authentication;
      await FirebaseAuth.instance.signInWithCredential(
        GoogleAuthProvider.credential(
            accessToken: auth.accessToken, idToken: auth.idToken),
      );
      if (mounted) {
        Navigator.pushReplacementNamed(context, 'account_dashboard');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Sign-In failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => isSigningIn = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => purpleScreen([
        const Icon(Icons.speed, size: 80, color: Colors.white),
        const SizedBox(height: 15),
        const Text('Speedtest App',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
        const SizedBox(height: 60),
        if (isSigningIn)
          const Center(child: CircularProgressIndicator(color: Colors.white))
        else ...[
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                padding: const EdgeInsets.symmetric(vertical: 14)),
            icon: const Icon(Icons.account_circle, color: Colors.redAccent),
            onPressed: signInWithGoogle,
            label: const Text('Sign in with Google Account',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 14)),
            icon: const Icon(Icons.person_outline, color: Colors.white),
            onPressed: () =>
                Navigator.pushReplacementNamed(context, 'guest_dashboard'),
            label: const Text('Continue as Guest',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ]);
}
