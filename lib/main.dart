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

class User {
  final String id;
  String name;
  String phone;
  final String password;
  final String departmentId;
  String? deviceId;
  String? email;
  String? telegram;

  User({
    required this.id,
    required this.name,
    required this.phone,
    required this.password,
    required this.departmentId,
    this.deviceId,
    this.email,
    this.telegram,
  });
}

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

  Future<void> refreshUserData() async {
    await _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser != null) {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(firebaseUser.uid).get();
      
      if (userDoc.exists) {
        final data = userDoc.data()!;
        
        // جلب اسم القسم الحقيقي من مجموعة departments
        String deptName = "غير محدد";
        try {
          final deptDoc = await FirebaseFirestore.instance
              .collection('departments')
              .doc(data['departmentId'])
              .get();
          if (deptDoc.exists) {
            deptName = deptDoc.data()?['name'] ?? "قسم غير معروف";
          }
        } catch (e) {
          print("Error fetching dept name: $e");
        }

        _user = User(
          id: firebaseUser.uid,
          name: data['name'] ?? "طالب الأكاديمية",
          phone: data['phone'] ?? "",
          password: "", 
          departmentId: deptName, // هنا سيظهر الاسم (تخدير/تمريض) بدلاً من الرمز
          deviceId: data['deviceId'] ?? "",
          email: data['email'] ?? "",
          telegram: data['telegram'] ?? "",
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
      _error = "خطأ في تسجيل الدخول: تأكد من البيانات";
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

      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: password);
      
      await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).set({
        'uid': userCredential.user!.uid,
        'name': name,
        'phone': phone,
        'departmentId': deptId, // نحفظ الرمز هنا لربط العلاقات
        'deviceId': currentDeviceId,
        'email': "",
        'telegram': "",
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _checkLoginStatus();
      _isLoading = false;
      return true;
    } on FirebaseAuthException catch (e) {
      _error = "فشل التسجيل، قد يكون الرقم مستخدماً";
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
                TextFormField(controller: _identifierController, decoration: const InputDecoration(labelText: "رقم الهاتف", border: OutlineInputBorder()), validator: (v) => v!.isEmpty ? "مطلوب" : null),
                const SizedBox(height: 16),
                TextFormField(controller: _passwordController, obscureText: true, decoration: const InputDecoration(labelText: "كلمة المرور", border: OutlineInputBorder()), validator: (v) => v!.isEmpty ? "مطلوب" : null),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: auth.isLoading ? null : () {
                    if (_formKey.currentState!.validate()) auth.login(_identifierController.text, _passwordController.text);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF001F3F), padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: auth.isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("تسجيل الدخول", style: TextStyle(color: Colors.white)),
                ),
                TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignupScreen())),
                  child: const Text("لا تملك حساباً؟ أنشئ حساباً جديداً"),
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
      body: FutureBuilder<QuerySnapshot>(
        future: FirebaseFirestore.instance.collection('departments').get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("لا توجد أقسام متاحة حالياً."));
          }

          var departments = snapshot.data!.docs;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(controller: _nameController, decoration: const InputDecoration(labelText: "الاسم الكامل", border: OutlineInputBorder()), validator: (v) => v!.isEmpty ? "مطلوب" : null),
                  const SizedBox(height: 16),
                  TextFormField(controller: _phoneController, decoration: const InputDecoration(labelText: "رقم الهاتف", border: OutlineInputBorder()), keyboardType: TextInputType.phone, validator: (v) => v!.isEmpty ? "مطلوب" : null),
                  const SizedBox(height: 16),
                  TextFormField(controller: _passwordController, obscureText: true, decoration: const InputDecoration(labelText: "كلمة المرور", border: OutlineInputBorder()), validator: (v) => v!.isEmpty ? "مطلوب" : null),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _selectedDeptId,
                    hint: const Text("اختر القسم"),
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: departments.map((doc) {
                      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
                      return DropdownMenuItem(value: doc.id, child: Text(data['name'] ?? 'قسم غير معروف'));
                    }).toList(),
                    onChanged: (val) => setState(() => _selectedDeptId = val),
                    validator: (v) => v == null ? "يجب اختيار القسم" : null,
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
                  if (auth.error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(auth.error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center)),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text("SM Academy"),
        centerTitle: false,
        actions: [
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
      body: const Center(child: Text("سيتم جلب الكورسات من لوحة الويب قريباً", style: TextStyle(fontSize: 18))),
    );
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  
  Future<void> _updateData(String field, String newValue) async {
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.id).update({
        field: newValue,
      });
      Provider.of<AuthProvider>(context, listen: false).refreshUserData();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم التحديث بنجاح")));
    }
  }

  void _showEditDialog(String title, String field, String currentValue) {
    TextEditingController controller = TextEditingController(text: currentValue);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("تعديل $title"),
        content: TextField(controller: controller, decoration: InputDecoration(hintText: "أدخل $title الجديد")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                _updateData(field, controller.text);
                Navigator.pop(context);
              }
            },
            child: const Text("حفظ"),
          ),
        ],
      ),
    );
  }

  void _updatePassword() {
    TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("تغيير كلمة المرور"),
        content: TextField(controller: controller, obscureText: true, decoration: const InputDecoration(hintText: "أدخل كلمة المرور الجديدة")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.length >= 6) {
                try {
                  await FirebaseAuth.instance.currentUser?.updatePassword(controller.text);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم تغيير كلمة المرور بنجاح")));
                  Navigator.pop(context);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("حدث خطأ، يرجى تسجيل الدخول مجدداً والمحاولة")));
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("كلمة المرور يجب أن تكون 6 أحرف على الأقل")));
              }
            },
            child: const Text("حفظ"),
          ),
        ],
      ),
    );
  }

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
          
          _buildInfoItem("الاسم الكامل", user?.name ?? "", true, () => _showEditDialog("الاسم", "name", user?.name ?? "")),
          _buildInfoItem("رقم الهاتف", user?.phone ?? "", true, () => _showEditDialog("رقم الهاتف", "phone", user?.phone ?? "")),
          _buildInfoItem("البريد الإلكتروني", (user?.email == null || user!.email!.isEmpty) ? "أضف بريد إلكتروني" : user.email!, true, () => _showEditDialog("البريد", "email", user?.email ?? "")),
          _buildInfoItem("معرف تليجرام", (user?.telegram == null || user!.telegram!.isEmpty) ? "أضف @username" : user.telegram!, true, () => _showEditDialog("تليجرام", "telegram", user?.telegram ?? "")),
          
          const Divider(),
          _buildInfoItem("القسم الأكاديمي", user?.departmentId ?? "", false, null),
          const SizedBox(height: 20),
          
          ListTile(
            leading: const Icon(Icons.lock_outline, color: Colors.orange),
            title: const Text("تغيير كلمة المرور"),
            trailing: const Icon(Icons.edit, size: 18),
            onTap: _updatePassword,
          ),

          const SizedBox(height: 30),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Provider.of<AuthProvider>(context, listen: false).logout();
            },
            child: const Text("تسجيل الخروج", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value, bool isEditable, VoidCallback? onTap) {
    return ListTile(
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
      subtitle: Text(value, style: const TextStyle(fontSize: 16, color: Colors.black)),
      trailing: isEditable ? const Icon(Icons.edit, size: 18, color: Color(0xFF001F3F)) : null,
      onTap: isEditable ? onTap : null,
    );
  }
}
