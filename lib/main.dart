import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:screen_protector/screen_protector.dart'; 
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart'; 
import 'package:firebase_auth/firebase_auth.dart' hide User; 
import 'package:cloud_firestore/cloud_firestore.dart';

// ==========================================
// MODELS (Types)
// ==========================================

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

  User({
    required this.id,
    required this.name,
    required this.phone,
    required this.password,
    required this.departmentId,
    this.deviceId,
  });
}

// الأقسام المؤقتة (سنربطها لاحقاً بلوحة الأدمن)
final List<Department> mockDepartments = [
  Department(id: 'dept_cs', name: 'Computer Science'),
  Department(id: 'dept_med', name: 'Medical'),
];

// ==========================================
// AUTH PROVIDER
// ==========================================

class AuthProvider with ChangeNotifier {
  User? _user;
  bool _isLoading = false;
  String? _error;

  User? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;

  AuthProvider() {
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser != null) {
      // جلب بيانات المستخدم من Firestore للتأكد من الاسم والقسم
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(firebaseUser.uid).get();
      
      if (userDoc.exists) {
        final data = userDoc.data()!;
        _user = User(
          id: firebaseUser.uid,
          name: data['name'] ?? "طالب الأكاديمية",
          phone: data['phone'] ?? "",
          password: "", 
          departmentId: data['departmentId'] ?? "",
          deviceId: data['deviceId'] ?? "",
        );
      }
      notifyListeners();
    }
  }

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
      UserCredential userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
      
      // فحص رقم الجهاز عند تسجيل الدخول (قفل الحساب)
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).get();
      if (userDoc.exists) {
        String savedDeviceId = userDoc.data()?['deviceId'] ?? "";
        String currentDeviceId = await _getDeviceId();

        if (savedDeviceId != "" && savedDeviceId != currentDeviceId) {
          await FirebaseAuth.instance.signOut();
          _error = "هذا الحساب مرتبط بجهاز آخر. يرجى التواصل مع الإدارة.";
          _isLoading = false;
          notifyListeners();
          return false;
        }
      }

      await _checkLoginStatus();
      _isLoading = false;
      return true;
    } on FirebaseAuthException catch (e) {
      _error = "خطأ في تسجيل الدخول: ${e.message}";
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> register(String name, String phone, String password, String deptId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      String email = "$phone@smacademy.com";
      String currentDeviceId = await _getDeviceId();

      // 1. إنشاء الحساب في Authentication
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: password);
      
      // 2. حفظ البيانات في Firestore (هنا الإضافة الجديدة)
      await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).set({
        'uid': userCredential.user!.uid,
        'name': name,
        'phone': phone,
        'departmentId': deptId,
        'deviceId': currentDeviceId, // ربط الحساب بهذا الجهاز فوراً
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _checkLoginStatus();
      _isLoading = false;
      return true;
    } on FirebaseAuthException catch (e) {
      _error = "فشل التسجيل: ${e.message}";
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
// MAIN APP & SCREENS
// ==========================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    print("Firebase Error: $e");
  }

  try {
    if (Platform.isAndroid) {
      await ScreenProtector.preventScreenshotOn();
    }
  } catch (e) {}

  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AuthProvider())],
      child: const SMAcademyApp(),
    ),
  );
}

class SMAcademyApp extends StatelessWidget {
  const SMAcademyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SM Academy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF001F3F), 
        scaffoldBackgroundColor: const Color(0xFFF9FAFB),
        textTheme: GoogleFonts.interTextTheme(),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF001F3F), foregroundColor: Colors.white),
      ),
      home: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          return auth.user != null ? const MainScreen() : const LoginScreen();
        },
      ),
    );
  }
}

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
                if (auth.error != null) Text(auth.error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                TextFormField(controller: _identifierController, decoration: const InputDecoration(labelText: "Username or Phone", border: OutlineInputBorder()), validator: (v) => v!.isEmpty ? "Required" : null),
                const SizedBox(height: 16),
                TextFormField(controller: _passwordController, obscureText: true, decoration: const InputDecoration(labelText: "Password", border: OutlineInputBorder()), validator: (v) => v!.isEmpty ? "Required" : null),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: auth.isLoading ? null : () {
                    if (_formKey.currentState!.validate()) auth.login(_identifierController.text, _passwordController.text);
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
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    return Scaffold(
      appBar: AppBar(title: const Text("إنشاء حساب")),
      // FutureBuilder لجلب الأقسام من Firestore
      body: FutureBuilder<QuerySnapshot>(
        future: FirebaseFirestore.instance.collection('departments').get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("لا توجد أقسام متاحة حالياً. قم بإضافتها من لوحة الويب."));
          }

          var departments = snapshot.data!.docs;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(controller: _nameController, decoration: const InputDecoration(labelText: "الاسم الكامل", border: OutlineInputBorder())),
                  const SizedBox(height: 16),
                  TextFormField(controller: _phoneController, decoration: const InputDecoration(labelText: "رقم الهاتف", border: OutlineInputBorder()), keyboardType: TextInputType.phone),
                  const SizedBox(height: 16),
                  TextFormField(controller: _passwordController, obscureText: true, decoration: const InputDecoration(labelText: "كلمة المرور", border: OutlineInputBorder())),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _selectedDeptId,
                    hint: const Text("اختر القسم"),
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    // تحويل البيانات القادمة من السيرفر إلى قائمة منسدلة
                    items: departments.map((doc) {
                      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
                      return DropdownMenuItem(value: doc.id, child: Text(data['name'] ?? 'قسم غير معروف'));
                    }).toList(),
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
                    child: auth.isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("إنشاء حساب", style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
          );
        }
      ),
    );
  }
}

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthProvider>(context).user;

    return Scaffold(
      appBar: AppBar(
        title: const Text("SM Academy"),
        centerTitle: false,
        actions: [
          // أيقونة الملف الشخصي
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: Colors.white24,
                child: Icon(Icons.person, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
      body: const Center(child: Text("مرحباً بك في كورساتك")),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthProvider>(context).user;
    
    return Scaffold(
      appBar: AppBar(title: const Text("ملفي الشخصي")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Center(child: CircleAvatar(radius: 50, child: Icon(Icons.person, size: 50))),
          const SizedBox(height: 20),
          _buildInfoItem("الاسم", user?.name ?? ""),
          _buildInfoItem("رقم الهاتف", user?.phone ?? ""),
          _buildInfoItem("القسم", user?.departmentId ?? ""),
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: () { /* هنا كود التعديل مستقبلاً */ },
            child: const Text("تعديل البيانات"),
          ),
          TextButton(
            onPressed: () => Provider.of<AuthProvider>(context, listen: false).logout(),
            child: const Text("تسجيل الخروج", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return ListTile(
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      subtitle: Text(value, style: const TextStyle(fontSize: 16)),
      trailing: const Icon(Icons.edit, size: 16),
    );
  }
}
