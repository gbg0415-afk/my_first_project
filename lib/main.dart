import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:screen_protector/screen_protector.dart'; 
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart'; 
import 'package:firebase_auth/firebase_auth.dart' hide User; 

// ==========================================
// MODELS (Types)
// ==========================================

enum PartType { VIDEO, PDF }

enum VideoSource { YOUTUBE, BUNNY, DIRECT }

class Department {
  final String id;
  final String name;
  Department({required this.id, required this.name});
}

class User {
  final String id;
  String name;
  String phone;
  final String password;
  final String departmentId;
  String? deviceId;
  final List<String> allowedCourseIds;

  User({
    required this.id,
    required this.name,
    required this.phone,
    required this.password,
    required this.departmentId,
    this.deviceId,
    required this.allowedCourseIds,
  });
}

class Course {
  final String id;
  final String departmentId;
  final String title;
  final String description;
  final String thumbnailUrl;
  final int orderIndex;

  Course({
    required this.id,
    required this.departmentId,
    required this.title,
    required this.description,
    required this.thumbnailUrl,
    required this.orderIndex,
  });
}

class LecturePart {
  final String id;
  final String title;
  final PartType type;
  final String url;
  final VideoSource? source;

  LecturePart({
    required this.id,
    required this.title,
    required this.type,
    required this.url,
    this.source,
  });
}

class Lecture {
  final String id;
  final String courseId;
  final String title;
  final String description;
  final int orderIndex;
  final List<LecturePart> parts;

  Lecture({
    required this.id,
    required this.courseId,
    required this.title,
    required this.description,
    required this.orderIndex,
    required this.parts,
  });
}

// ==========================================
// MOCK DATA 
// ==========================================

final List<Department> mockDepartments = [
  Department(id: 'dept_cs', name: 'Computer Science'),
  Department(id: 'dept_med', name: 'Medical'),
];

final List<Course> mockCourses = [];
final List<Lecture> mockLectures = [];

// ==========================================
// SERVICES & PROVIDERS
// ==========================================

class AuthProvider with ChangeNotifier {
  User? _user;
  bool _isLoading = false;
  String? _error;

  User? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<String> _getDeviceId() async {
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      return androidInfo.id;
    } else if (Platform.isIOS) {
      final IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      return iosInfo.identifierForVendor ?? 'unknown_ios_id';
    }
    return 'unknown_platform_id';
  }

  Future<bool> login(String identifier, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      String email = identifier.contains('@') ? identifier : "$identifier@smacademy.com";

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final currentDeviceId = await _getDeviceId();

      _user = User(
        id: FirebaseAuth.instance.currentUser!.uid,
        name: "طالب الأكاديمية", 
        phone: identifier,
        password: password, 
        departmentId: 'dept_cs',
        allowedCourseIds: [],
        deviceId: currentDeviceId,
      );

      _isLoading = false;
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      _error = "خطأ في تسجيل الدخول: ${e.message}";
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = "خطأ غير متوقع: $e";
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> register(
    String name,
    String phone,
    String password,
    String deptId,
  ) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      String email = "$phone@smacademy.com";

      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final currentDeviceId = await _getDeviceId();

      _user = User(
        id: userCredential.user!.uid,
        name: name,
        phone: phone,
        password: password,
        departmentId: deptId,
        allowedCourseIds: [],
        deviceId: currentDeviceId,
      );

      _isLoading = false;
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      _error = "فشل التسجيل: ${e.message}";
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = "خطأ غير متوقع: $e";
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  void logout() async {
    await FirebaseAuth.instance.signOut();
    _user = null;
    notifyListeners();
  }
}

// ==========================================
// MAIN APP & THEME
// ==========================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // هذا السطر يمنع الخطأ الأحمر

  try {
    await Firebase.initializeApp();
    print("--- Firebase Connected Successfully ---");
  } catch (e) {
    print("--- Firebase Error: $e ---");
  }

  try {
    if (Platform.isAndroid) {
      await ScreenProtector.preventScreenshotOn();
    }
  } catch (e) {
    print("Security Flag Error: $e");
  }

  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AuthProvider())],
      child: const SMAcademyApp(),
    ),
  );
}

class SMAcademyApp extends StatefulWidget {
  const SMAcademyApp({super.key});

  @override
  State<SMAcademyApp> createState() => _SMAcademyAppState();
}

class _SMAcademyAppState extends State<SMAcademyApp> with WidgetsBindingObserver {
  bool _isBlurred = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _isBlurred = state == AppLifecycleState.paused || state == AppLifecycleState.inactive;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SM Academy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF001F3F), 
        scaffoldBackgroundColor: const Color(0xFFF9FAFB),
        textTheme: GoogleFonts.interTextTheme(),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF001F3F),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: Stack(
        children: [
          Consumer<AuthProvider>(
            builder: (context, auth, _) {
              if (auth.user != null) {
                return const MainScreen();
              } else {
                return const LoginScreen();
              }
            },
          ),
          if (_isBlurred)
            Positioned.fill(
              child: Container(
                color: const Color(0xFF001F3F),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.security, color: Colors.white, size: 64),
                      SizedBox(height: 16),
                      Text("Security Mode Active", style: TextStyle(color: Colors.white, fontSize: 20, decoration: TextDecoration.none)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ==========================================
// SCREENS
// ==========================================

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.school, size: 80, color: Color(0xFF001F3F)),
                const SizedBox(height: 16),
                Text("SM Academy", textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontSize: 28, fontWeight: FontWeight.bold, color: const Color(0xFF001F3F))),
                const SizedBox(height: 40),
                if (auth.error != null)
                  Text(auth.error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _identifierController,
                  decoration: const InputDecoration(labelText: "Username or Phone", border: OutlineInputBorder()),
                  validator: (v) => v!.isEmpty ? "Required" : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: "Password", border: OutlineInputBorder()),
                  validator: (v) => v!.isEmpty ? "Required" : null,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: auth.isLoading ? null : () {
                    if (_formKey.currentState!.validate()) {
                      auth.login(_identifierController.text, _passwordController.text);
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF001F3F), padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: auth.isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("LOGIN", style: TextStyle(color: Colors.white)),
                ),
                TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignupScreen())),
                  child: const Text("Don't have an account? Register"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});
  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _selectedDeptId;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    if (mockDepartments.isNotEmpty) _selectedDeptId = mockDepartments[0].id;
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    return Scaffold(
      appBar: AppBar(title: const Text("Registration")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(controller: _nameController, decoration: const InputDecoration(labelText: "Full Name", border: OutlineInputBorder()), validator: (v) => v!.isEmpty ? "Required" : null),
              const SizedBox(height: 16),
              TextFormField(controller: _phoneController, decoration: const InputDecoration(labelText: "Phone Number", border: OutlineInputBorder()), keyboardType: TextInputType.phone, validator: (v) => v!.isEmpty ? "Required" : null),
              const SizedBox(height: 16),
              TextFormField(controller: _passwordController, obscureText: true, decoration: const InputDecoration(labelText: "Password", border: OutlineInputBorder()), validator: (v) => v!.isEmpty ? "Required" : null),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedDeptId,
                decoration: const InputDecoration(labelText: "Department", border: OutlineInputBorder()),
                items: mockDepartments.map((d) => DropdownMenuItem(value: d.id, child: Text(d.name))).toList(),
                onChanged: (val) => setState(() => _selectedDeptId = val),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: auth.isLoading ? null : () async {
                  if (_formKey.currentState!.validate() && _selectedDeptId != null) {
                    final success = await auth.register(_nameController.text, _phoneController.text, _passwordController.text, _selectedDeptId!);
                    if (success && mounted) Navigator.pop(context);
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF001F3F), padding: const EdgeInsets.symmetric(vertical: 16)),
                child: auth.isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("CREATE ACCOUNT", style: TextStyle(color: Colors.white)),
              ),
              if (auth.error != null) Text(auth.error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("SM Academy"),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: () => Provider.of<AuthProvider>(context, listen: false).logout()),
        ],
      ),
      body: const Center(child: Text("تم تسجيل الدخول بنجاح! هنا ستظهر الكورسات لاحقاً.")),
    );
  }
}
