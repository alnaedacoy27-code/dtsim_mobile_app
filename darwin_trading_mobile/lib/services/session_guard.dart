import 'package:flutter/material.dart';
import '../screens/login_screen.dart';
import 'local_store.dart';

/// Clears the saved session and sends the user back to the login screen.
Future<void> handleSessionExpired(BuildContext context) async {
  await LocalStore.clearSession();
  if (!context.mounted) return;

  Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginScreen()),
    (_) => false,
  );
}
