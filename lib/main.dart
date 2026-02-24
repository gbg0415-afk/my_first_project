import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';

void main() async {
  // 1. التأكد من جاهزية المحرك
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    // 2. تشغيل فايربيز (بدون هذا السطر ينهار التطبيق فوراً)
    await Firebase.initializeApp();
    print("Firebase Initialized Successfully");
  } catch (e) {
    print("Firebase Init Error: $e");
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SM Academy',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: const Text("SM Academy")),
        body: const Center(
          child: Text(
            "تم التشغيل بنجاح!\nنحن الآن متصلون بـ Firebase",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20),
          ),
        ),
      ),
    );
  }
}
