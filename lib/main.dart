import 'package:flutter/material.dart';
import 'models.dart';
import 'repository.dart';
import 'screens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = ReliefRepository(FakeRemote()); // ← เปลี่ยนเป็น FirestoreRemote() ภายหลัง
  await repo.init();
  runApp(RepoScope(repo: repo, child: const ReliefMatchApp()));
}

ThemeData buildTheme(bool easy) {
  final scheme = ColorScheme.fromSeed(seedColor: kPrimary)
      .copyWith(primary: kPrimary, secondary: kAccent);
  final minSize = Size(48, easy ? 64 : 48);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kBg,
    appBarTheme: const AppBarTheme(backgroundColor: kPrimary, foregroundColor: Colors.white),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: easy ? 0 : 1,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: easy ? Colors.black87 : Colors.transparent, width: easy ? 1.5 : 0),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: minSize)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: minSize)),
    textTheme: easy
        ? Typography.material2021().black.apply(bodyColor: Colors.black, displayColor: Colors.black)
        : null,
  );
}

class ReliefMatchApp extends StatelessWidget {
  const ReliefMatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = RepoScope.of(context);
    final easy = repo.easyMode;
    return MaterialApp(
      title: 'ReliefMatch',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(easy),
      // Senior Easy Mode: ขยายตัวอักษร 150%
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(easy ? 1.5 : 1.0)),
        child: child!,
      ),
      home: repo.user == null ? const RegisterScreen() : const HomeShell(),
    );
  }
}