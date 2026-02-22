import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:screen_protector/screen_protector.dart'; // Android only
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart'; // إضافة فايربيز
import 'package:firebase_auth/firebase_auth.dart' hide User; // إضافة المصادقة الحقيقية (مع إخفاء تعارض الأسماء)

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
// MOCK DATA (للعرض فقط)
// ==========================================

final List<Department> mockDepartments = [
  Department(id: 'dept_cs', name: 'Computer Science'),
  Department(id: 'dept_med', name: 'Medical'),
  Department(id: 'dept_eng', name: 'Engineering'),
  Department(id: 'dept_art', name: 'Arts & Humanities'),
];

final List<Course> mockCourses = [
  Course(
    id: 'course_1',
    departmentId: 'dept_cs',
    title: 'Advanced Flutter Development',
    description: 'Master mobile app development with Flutter and Dart.',
    thumbnailUrl: 'https://picsum.photos/400/225?random=1',
    orderIndex: 1,
  ),
  Course(
    id: 'course_2',
    departmentId: 'dept_cs',
    title: 'React & TypeScript Mastery',
    description: 'Build scalable web applications using modern React.',
    thumbnailUrl: 'https://picsum.photos/400/225?random=2',
    orderIndex: 2,
  ),
  Course(
    id: 'course_3',
    departmentId: 'dept_med',
    title: 'Human Anatomy 101',
    description: 'Introduction to human body structures.',
    thumbnailUrl: 'https://picsum.photos/400/225?random=3',
    orderIndex: 1,
  ),
];

final List<Lecture> mockLectures = [
  Lecture(
    id: 'lec_1',
    courseId: 'course_1',
    title: 'Introduction to Flutter',
    description: 'Setting up environment and first app.',
    orderIndex: 1,
    parts: [
      LecturePart(
        id: 'part_1_1',
        title: 'Setup Guide',
        type: PartType.VIDEO,
        url: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
        source: VideoSource.DIRECT,
      ),
      LecturePart(
        id: 'part_1_2',
        title: 'Course Syllabus',
        type: PartType.PDF,
        url: 'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf',
      ),
    ],
  ),
  Lecture(
    id: 'lec_2',
    courseId: 'course_1',
    title: 'State Management',
    description: 'Understanding Provider and Riverpod.',
    orderIndex: 2,
    parts: [
      LecturePart(
        id: 'part_2_1',
        title: 'Provider Deep Dive',
        type: PartType.VIDEO,
        url: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
        source: VideoSource.DIRECT,
      ),
    ],
  ),
];

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

  // Security: Get Unique Device ID
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

  // تسجيل الدخول الحقيقي بفايربيز
  Future<bool> login(String identifier, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // فايربيز يحتاج إيميل، فنقوم بتحويل رقم الهاتف إلى إيميل أكاديمي
      String email = identifier.contains('@') ? identifier : "$identifier@smacademy.com";

      // الاتصال بسيرفرات فايربيز
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final currentDeviceId = await _getDeviceId();

      // إنشاء بيانات المستخدم الجلسة الحالية
      _user = User(
        id: FirebaseAuth.instance.currentUser!.uid,
        name: "طالب الأكاديمية", // يمكن جلبه لاحقاً من Firestore
        phone: identifier,
        password: password, 
        departmentId: 'dept_cs',
        allowedCourseIds: ['course_1', 'course_2', 'course_3'],
        deviceId: currentDeviceId,
      );

      _isLoading = false;
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'wrong-password' || e.code == 'invalid-credential') {
        _error = "رقم الهاتف أو كلمة المرور غير صحيحة";
      } else {
        _error = "حدث خطأ في الاتصال: ${e.message}";
      }
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

  // إنشاء حساب حقيقي بفايربيز
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
      // تحويل رقم الهاتف إلى إيميل لكي يقبله فايربيز
      String email = "$phone@smacademy.com";

      // إرسال البيانات إلى Firebase
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
        allowedCourseIds: ['course_1'],
        deviceId: currentDeviceId,
      );

      _isLoading = false;
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        _error = "هذا الرقم مسجل مسبقاً";
      } else if (e.code == 'weak-password') {
        _error = "كلمة المرور ضعيفة جداً";
      } else {
        _error = "فشل التسجيل: ${e.message}";
      }
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
    await FirebaseAuth.instance.signOut(); // تسجيل الخروج الحقيقي
    _user = null;
    notifyListeners();
  }

  Future<void> updateProfile(String name, String phone) async {
    _isLoading = true;
    notifyListeners();
    await Future.delayed(const Duration(seconds: 1));
    if (_user != null) {
      _user!.name = name;
      _user!.phone = phone;
    }
    _isLoading = false;
    notifyListeners();
  }
}

// ==========================================
// MAIN APP & THEME
// ==========================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
    print("--- Firebase Connected Successfully ---");
  } catch (e) {
    print("--- Firebase Error: $e ---");
  }

  // Security: Prevent Screen Recording (Android)
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

class _SMAcademyAppState extends State<SMAcademyApp>
    with WidgetsBindingObserver {
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

  // Security: Window Blur on Background
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _isBlurred =
          state == AppLifecycleState.paused ||
          state == AppLifecycleState.inactive;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SM Academy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF001F3F), // Navy Blue
        scaffoldBackgroundColor: const Color(0xFFF9FAFB),
        textTheme: GoogleFonts.interTextTheme(),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF001F3F),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        colorScheme: ColorScheme.fromSwatch().copyWith(
          primary: const Color(0xFF001F3F),
          secondary: const Color(0xFFC5B358), // Academic Gold
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
          // Privacy Curtain
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
                      Text(
                        "Security Mode Active",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          decoration: TextDecoration.none,
                        ),
                      ),
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

// --- LOGIN SCREEN ---
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
                Text(
                  "SM Academy",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.merriweather(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF001F3F),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Secure Student Portal",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 40),
                if (auth.error != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            auth.error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ),
                TextFormField(
                  controller: _identifierController,
                  decoration: const InputDecoration(
                    labelText: "Username or Phone",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: (v) => v!.isEmpty ? "Required" : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: "Password",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                  validator: (v) => v!.isEmpty ? "Required" : null,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: auth.isLoading
                      ? null
                      : () {
                          if (_formKey.currentState!.validate()) {
                            auth.login(
                              _identifierController.text,
                              _passwordController.text,
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF001F3F),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: auth.isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          "LOGIN",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SignupScreen()),
                    );
                  },
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

// --- SIGNUP SCREEN ---
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
    if (mockDepartments.isNotEmpty) {
      _selectedDeptId = mockDepartments[0].id;
    }
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
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: "Full Name",
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v!.isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: "Phone Number",
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
                validator: (v) => v!.isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: "Password",
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v!.isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedDeptId,
                decoration: const InputDecoration(
                  labelText: "Department",
                  border: OutlineInputBorder(),
                ),
                items: mockDepartments
                    .map(
                      (d) => DropdownMenuItem(value: d.id, child: Text(d.name)),
                    )
                    .toList(),
                onChanged: (val) => setState(() => _selectedDeptId = val),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: auth.isLoading
                    ? null
                    : () async {
                        if (_formKey.currentState!.validate() &&
                            _selectedDeptId != null) {
                          final success = await auth.register(
                            _nameController.text,
                            _phoneController.text,
                            _passwordController.text,
                            _selectedDeptId!,
                          );
                          if (success && mounted) {
                            Navigator.pop(
                              context,
                            ); // Go back to wrapper which will show MainScreen
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF001F3F),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: auth.isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        "CREATE ACCOUNT",
                        style: TextStyle(color: Colors.white),
                      ),
              ),
              if (auth.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    auth.error!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- MAIN SCREEN (Courses) ---
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthProvider>(context).user!;

    // Filter courses assigned to user and sort
    final myCourses =
        mockCourses.where((c) => user.allowedCourseIds.contains(c.id)).toList()
          ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

    return Scaffold(
      appBar: AppBar(
        title: const Text("SM Academy"),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () => _showProfileDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () =>
                Provider.of<AuthProvider>(context, listen: false).logout(),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Responsive Grid
          final isWide = constraints.maxWidth > 600;
          final crossAxisCount = isWide ? 2 : 1;

          if (myCourses.isEmpty) {
            return const Center(
              child: Text("No courses assigned. Contact Admin."),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: isWide
                  ? 1.5
                  : 1.1, // Adjust based on card content
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: myCourses.length,
            itemBuilder: (context, index) {
              return CourseCard(
                course: myCourses[index],
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          CourseDetailScreen(course: myCourses[index]),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  void _showProfileDialog(BuildContext context) {
    // A simple placeholder for profile
    final user = Provider.of<AuthProvider>(context, listen: false).user!;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Profile"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Name: ${user.name}"),
            const SizedBox(height: 8),
            Text("Phone: ${user.phone}"),
            const SizedBox(height: 8),
            Text("Dept: ${user.departmentId}"),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }
}

// --- COURSE CARD WIDGET ---
class CourseCard extends StatelessWidget {
  final Course course;
  final VoidCallback onTap;

  const CourseCard({super.key, required this.course, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    course.thumbnailUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, s) => Container(
                      color: Colors.grey,
                      child: const Icon(Icons.broken_image),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withOpacity(0.7),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                  const Positioned(
                    bottom: 8,
                    left: 8,
                    child: Chip(
                      label: Text(
                        "Course",
                        style: TextStyle(color: Colors.white, fontSize: 10),
                      ),
                      backgroundColor: Color(0xFF001F3F),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      course.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: const [
                        Icon(
                          Icons.book_outlined,
                          size: 16,
                          color: Color(0xFF001F3F),
                        ),
                        SizedBox(width: 4),
                        Text(
                          "View Lectures",
                          style: TextStyle(
                            color: Color(0xFF001F3F),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- COURSE DETAIL SCREEN ---
class CourseDetailScreen extends StatelessWidget {
  final Course course;

  const CourseDetailScreen({super.key, required this.course});

  @override
  Widget build(BuildContext context) {
    final lectures = mockLectures.where((l) => l.courseId == course.id).toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

    return Scaffold(
      appBar: AppBar(title: Text(course.title)),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            color: const Color(0xFF001F3F),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  course.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  course.description,
                  style: TextStyle(color: Colors.white.withOpacity(0.9)),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: lectures.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final lecture = lectures[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue.shade50,
                    child: Text(
                      "${index + 1}",
                      style: const TextStyle(
                        color: Color(0xFF001F3F),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    lecture.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(lecture.description),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LectureDetailScreen(lecture: lecture),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// --- LECTURE DETAIL & PLAYER ---
class LectureDetailScreen extends StatelessWidget {
  final Lecture lecture;

  const LectureDetailScreen({super.key, required this.lecture});

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthProvider>(context, listen: false).user!;

    return Scaffold(
      appBar: AppBar(title: Text(lecture.title)),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: lecture.parts.length,
        itemBuilder: (context, index) {
          final part = lecture.parts[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (part.type == PartType.VIDEO)
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      children: [
                        VideoPlayerWidget(
                          url: part.url,
                          source: part.source ?? VideoSource.DIRECT,
                        ),
                        // DYNAMIC WATERMARK OVERLAY
                        WatermarkOverlay(text: "${user.name}\n${user.phone}"),
                        // Security Badge (UI Only)
                        const Positioned(
                          top: 8,
                          right: 8,
                          child: Chip(
                            label: Text(
                              "Protected",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                            ),
                            backgroundColor: Colors.black45,
                            avatar: Icon(
                              Icons.lock,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    height: 200,
                    alignment: Alignment.center,
                    color: Colors.grey.shade100,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.picture_as_pdf,
                          size: 48,
                          color: Colors.red,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => _launchURL(part.url),
                          child: const Text("Open PDF"),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        part.type == PartType.VIDEO
                            ? Icons.play_circle
                            : Icons.description,
                        color: const Color(0xFF001F3F),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        part.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _launchURL(String urlString) async {
    final uri = Uri.parse(urlString);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}

// --- VIDEO PLAYER WRAPPER ---
class VideoPlayerWidget extends StatefulWidget {
  final String url;
  final VideoSource source;

  const VideoPlayerWidget({super.key, required this.url, required this.source});

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
      );

      await _videoPlayerController.initialize();

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController,
        autoPlay: false,
        looping: false,
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Text(
              errorMessage,
              style: const TextStyle(color: Colors.white),
            ),
          );
        },
      );
      setState(() {});
    } catch (e) {
      setState(() {
        _isError = true;
      });
      print("Video Error: $e");
    }
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isError) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Text(
            "Video Load Error",
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }
    if (_chewieController != null &&
        _videoPlayerController.value.isInitialized) {
      return Chewie(controller: _chewieController!);
    } else {
      return Container(
        color: Colors.black,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
  }
}

// --- WATERMARK OVERLAY ---
class WatermarkOverlay extends StatelessWidget {
  final String text;

  const WatermarkOverlay({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            // Random floating watermark style
            Positioned(
              top: 50,
              left: 50,
              child: Opacity(
                opacity: 0.3,
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 50,
              right: 50,
              child: Opacity(
                opacity: 0.3,
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
