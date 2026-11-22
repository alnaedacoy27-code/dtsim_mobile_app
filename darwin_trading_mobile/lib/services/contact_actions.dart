import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Reaching a supplier's contact person with the phone's own apps:
/// the dialer, the SMS app, the email app and Maps. Nothing is sent by this app itself.
class ContactActions {
  /// Opens the dialer with the number filled in (the person still taps Call).
  static Future<void> call(BuildContext context, String number) =>
      _open(context, Uri(scheme: 'tel', path: number), 'No phone app was found on this device.');

  /// Opens the SMS app with the number and an optional message filled in.
  static Future<void> text(BuildContext context, String number, {String? message}) {
    // built by hand: Uri(queryParameters:) would turn spaces into "+" in many SMS apps
    final body = (message == null || message.isEmpty) ? '' : '?body=${Uri.encodeComponent(message)}';
    return _open(context, Uri.parse('sms:$number$body'), 'No messaging app was found on this device.');
  }

  /// Opens the email app with the address and an optional subject filled in.
  static Future<void> email(BuildContext context, String address, {String? subject}) {
    final q = (subject == null || subject.isEmpty) ? '' : '?subject=${Uri.encodeComponent(subject)}';
    return _open(context, Uri.parse('mailto:$address$q'), 'No email app was found on this device.');
  }

  /// Opens the address in Google Maps (the app when installed, otherwise the browser).
  static Future<void> map(BuildContext context, String address) => _open(
        context,
        Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}'),
        'No maps app or browser was found on this device.',
      );

  static Future<void> copy(BuildContext context, String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$what copied.')));
    }
  }

  static Future<void> _open(BuildContext context, Uri uri, String failure) async {
    bool ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure)));
    }
  }
}
