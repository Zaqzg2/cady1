import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'providers/data_provider.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DataProvider(),
      child: Consumer<DataProvider>(
        builder: (context, provider, child) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'كادي للمنظفات',
            locale: const Locale('ar', 'YE'),
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('ar', 'YE')],
            theme: ThemeData(
              brightness: Brightness.light,
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0EA5E9), brightness: Brightness.light),
              cardTheme: CardTheme(elevation: 4, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
              appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
            ),
            darkTheme: ThemeData(
              brightness: Brightness.dark,
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0EA5E9), brightness: Brightness.dark),
              cardTheme: CardTheme(elevation: 4, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
              appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
            ),
            themeMode: provider.settings.darkMode ? ThemeMode.dark : ThemeMode.light,
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
