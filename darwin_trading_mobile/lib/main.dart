
import 'package:flutter/material.dart';

import 'screens/login_screen.dart';
import 'services/api_service.dart';
import 'services/local_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await LocalStore.init();
  await ApiService.init();

  runApp(const DarwinTradingApp());
}

class DarwinTradingApp extends StatelessWidget {
  const DarwinTradingApp({super.key});

  static const Color maroon = Color(0xFF741D35);
  static const Color darkMaroon = Color(0xFF551326);
  static const Color lightMaroon = Color(0xFFF8EEF1);
  static const Color background = Color(0xFFF8F8FA);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Darwin Trading',
      debugShowCheckedModeBanner: false,

      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',

        colorScheme: ColorScheme.fromSeed(
          seedColor: maroon,
          primary: maroon,
          onPrimary: Colors.white,
          secondary: darkMaroon,
          surface: Colors.white,
          error: const Color(0xFFB3261E),
        ),

        scaffoldBackgroundColor: background,

        appBarTheme: const AppBarTheme(
          backgroundColor: maroon,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          iconTheme: IconThemeData(color: Colors.white),
        ),

        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 15,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE4E4E8)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE4E4E8)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: maroon,
              width: 1.5,
            ),
          ),
        ),

        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE9E6E8)),
          ),
        ),

        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: maroon,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 50),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),

        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: lightMaroon,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        ),

        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: maroon,
          foregroundColor: Colors.white,
        ),
      ),

      home: const LoginScreen(),
    );
  }
}
