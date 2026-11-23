import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/live_data.dart';
import '../../core/theme.dart';
import '../../providers/session_provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _slow = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const FitLinkLogo(size: 40),
          const SizedBox(height: 28),
          const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(color: AppColors.lime, strokeWidth: 2.5)),
          if (session.profileError != null || _slow) ...[
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                session.profileError != null
                    ? friendlyError(session.profileError)
                    : 'Still loading your profile…',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
            if (session.isSignedIn)
              TextButton(
                onPressed: () => session.signOut(),
                child: const Text('Sign out', style: TextStyle(color: AppColors.lime)),
              ),
          ],
        ]),
      ),
    );
  }
}

class FitLinkLogo extends StatelessWidget {
  const FitLinkLogo({super.key, this.size = 32, this.dark = true});
  final double size;
  final bool dark;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: EdgeInsets.all(size * 0.22),
          decoration: BoxDecoration(color: AppColors.lime, borderRadius: BorderRadius.circular(size * 0.3)),
          child: Icon(Icons.fitness_center_rounded, color: AppColors.ink, size: size * 0.8),
        ),
        SizedBox(width: size * 0.35),
        Text(
          'FitLink',
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w800,
            color: dark ? Colors.white : AppColors.ink,
            letterSpacing: -0.5,
          ),
        ),
      ]);
}
