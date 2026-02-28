import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:screen_protector/screen_protector.dart'; 
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart'; 
import 'package:firebase_auth/firebase_auth.dart' hide User; 
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
// مكتبات المحرك الجديد
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

// ==========================================
// MODELS
// ==========================================
class User {
  final String id; String name; String phone; final String departmentId; String departmentName;
  String? deviceId; String? email; String? telegram; List<String> allowedCourseIds;
  User({required this.id, required this.name, required this.phone, required this.departmentId, required this.departmentName, this.deviceId, this.email, this.telegram, required this.allowedCourseIds});
}

// ==========================================
// AUTH PROVIDER
// ==========================================
class AuthProvider with ChangeNotifier {
  User? _user; bool _isLoading = false; bool _isInitializing = true; String? _error;
  User? get user => _user; bool get isLoading => _isLoading; bool get isInitializing => _isInitializing; String? get error => _error;

  AuthProvider() { _checkLoginStatus(); }
  Future<void> refreshUserData() async { await _checkLoginStatus(); }

  Future<void> _checkLoginStatus() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser != null) {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(firebaseUser.uid).get();
      if (userDoc.exists) {
        final data = userDoc.data()!;
        String deptName = "غير محدد";
        try {
          final deptDoc = await FirebaseFirestore.instance.collection('departments').doc(data['departmentId']).get();
          if (deptDoc.exists) deptName = deptDoc.data()?['name'] ?? "قسم غير معروف";
        } catch (_) {}

        _user = User(
          id: firebaseUser.uid, name: data['name'] ?? "طالب", phone: data['phone'] ?? "", departmentId: data['departmentId'] ?? "",
          departmentName: deptName, deviceId: data['deviceId'] ?? "", email: data['email'] ?? "", telegram: data['telegram'] ?? "",
          allowedCourseIds: List<String>.from(data['allowedCourseIds'] ?? []),
        );
      }
    } else { _user = null; }
    _isInitializing = false; notifyListeners();
  }

  Future<String> _getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) return (await deviceInfo.androidInfo).id;
    if (Platform.isIOS) return (await deviceInfo.iosInfo).identifierForVendor ?? 'unknown_ios';
    return 'unknown_device';
  }

  Future<bool> login(String identifier, String password) async {
    _isLoading = true; _error = null; notifyListeners();
    try {
      String email = identifier.contains('@') ? identifier : "$identifier@smacademy.com";
      UserCredential cred = await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(cred.user!.uid).get();
      if (userDoc.exists) {
        String savedDeviceId = userDoc.data()?['deviceId'] ?? "";
        String currentDeviceId = await _getDeviceId();
        if (savedDeviceId != "" && savedDeviceId != currentDeviceId) {
          await FirebaseAuth.instance.signOut(); _error = "هذا الحساب مرتبط بجهاز آخر. يرجى مراجعة الإدارة.";
          _isLoading = false; notifyListeners(); return false;
        } else if (savedDeviceId == "") {
          await FirebaseFirestore.instance.collection('users').doc(cred.user!.uid).update({'deviceId': currentDeviceId});
        }
      }
      await _checkLoginStatus(); _isLoading = false; return true;
    } catch (e) {
      _error = "بيانات الدخول غير صحيحة"; _isLoading = false; notifyListeners(); return false;
    }
  }

  Future<bool> register(String name, String phone, String password, String deptId) async {
    _isLoading = true; _error = null; notifyListeners();
    try {
      String email = "$phone@smacademy.com"; String currentDeviceId = await _getDeviceId();
      UserCredential cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: password);
      await FirebaseFirestore.instance.collection('users').doc(cred.user!.uid).set({
        'uid': cred.user!.uid, 'name': name, 'phone': phone, 'departmentId': deptId,
        'deviceId': currentDeviceId, 'email': "", 'telegram': "", 'allowedCourseIds': [], 'createdAt': FieldValue.serverTimestamp(),
      });
      await _checkLoginStatus(); _isLoading = false; return true;
    } catch (e) {
      _error = "فشل التسجيل، قد يكون الرقم مستخدماً"; _isLoading = false; notifyListeners(); return false;
    }
  }
  void logout() async { await FirebaseAuth.instance.signOut(); _user = null; notifyListeners(); }
}

// ==========================================
// MAIN APP
// ==========================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized(); // تهيئة المحرك الجديد
  await Firebase.initializeApp();
  if (Platform.isAndroid) { try { await ScreenProtector.preventScreenshotOn(); } catch (_) {} }
  runApp(MultiProvider(providers: [ChangeNotifierProvider(create: (_) => AuthProvider())], child: const SMAcademyApp()));
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
        scaffoldBackgroundColor: const Color(0xFFF8F9FE),
        textTheme: GoogleFonts.cairoTextTheme(),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF001F3F), foregroundColor: Colors.white, elevation: 0, centerTitle: true),
        colorScheme: ColorScheme.fromSwatch().copyWith(secondary: Colors.orangeAccent),
      ),
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      home: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          if (auth.isInitializing) return const Scaffold(backgroundColor: Color(0xFF001F3F), body: Center(child: CircularProgressIndicator(color: Colors.white)));
          return auth.user != null ? const MainLayout() : const LoginScreen();
        },
      ),
    );
  }
}

// ==========================================
// AUTH SCREENS
// ==========================================
class LoginScreen extends StatefulWidget { const LoginScreen({super.key}); @override State<LoginScreen> createState() => _LoginScreenState(); }
class _LoginScreenState extends State<LoginScreen> {
  final _idCtrl = TextEditingController(); final _passCtrl = TextEditingController(); final _formKey = GlobalKey<FormState>();
  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF001F3F), Color(0xFF003366)], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              elevation: 10, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(padding: const EdgeInsets.all(16), decoration: const BoxDecoration(color: Color(0xFFF4F7FE), shape: BoxShape.circle), child: const Icon(Icons.school, size: 60, color: Color(0xFF001F3F))),
                      const SizedBox(height: 16),
                      const Text("SM Academy", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF001F3F))),
                      const SizedBox(height: 30),
                      if (auth.error != null) Padding(padding: const EdgeInsets.only(bottom: 15), child: Text(auth.error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center)),
                      TextFormField(controller: _idCtrl, decoration: InputDecoration(labelText: "رقم الهاتف", prefixIcon: const Icon(Icons.phone), border: OutlineInputBorder(borderRadius: BorderRadius.circular(15))), validator: (v) => v!.isEmpty ? "مطلوب" : null),
                      const SizedBox(height: 16),
                      TextFormField(controller: _passCtrl, obscureText: true, decoration: InputDecoration(labelText: "كلمة المرور", prefixIcon: const Icon(Icons.lock), border: OutlineInputBorder(borderRadius: BorderRadius.circular(15))), validator: (v) => v!.isEmpty ? "مطلوب" : null),
                      const SizedBox(height: 24),
                      SizedBox(width: double.infinity, height: 50, child: ElevatedButton(onPressed: auth.isLoading ? null : () { if (_formKey.currentState!.validate()) auth.login(_idCtrl.text, _passCtrl.text); }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF001F3F), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), child: auth.isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("تسجيل الدخول", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)))),
                      const SizedBox(height: 10),
                      TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignupScreen())), child: const Text("ليس لديك حساب؟ إنشاء حساب", style: TextStyle(color: Color(0xFF001F3F), fontWeight: FontWeight.bold))),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SignupScreen extends StatefulWidget { const SignupScreen({super.key}); @override State<SignupScreen> createState() => _SignupScreenState(); }
class _SignupScreenState extends State<SignupScreen> {
  final _nameCtrl = TextEditingController(); final _phoneCtrl = TextEditingController(); final _passCtrl = TextEditingController();
  String? _selectedDeptId; final _formKey = GlobalKey<FormState>();
  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    return Scaffold(
      appBar: AppBar(title: const Text("إنشاء حساب جديد")),
      body: FutureBuilder<QuerySnapshot>(
        future: FirebaseFirestore.instance.collection('departments').get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          var departments = snapshot.data?.docs ?? [];
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(controller: _nameCtrl, decoration: InputDecoration(labelText: "الاسم الكامل", border: OutlineInputBorder(borderRadius: BorderRadius.circular(15))), validator: (v) => v!.isEmpty ? "مطلوب" : null), const SizedBox(height: 16),
                  TextFormField(controller: _phoneCtrl, decoration: InputDecoration(labelText: "رقم الهاتف", border: OutlineInputBorder(borderRadius: BorderRadius.circular(15))), keyboardType: TextInputType.phone, validator: (v) => v!.isEmpty ? "مطلوب" : null), const SizedBox(height: 16),
                  TextFormField(controller: _passCtrl, obscureText: true, decoration: InputDecoration(labelText: "كلمة المرور", border: OutlineInputBorder(borderRadius: BorderRadius.circular(15))), validator: (v) => v!.isEmpty ? "مطلوب" : null), const SizedBox(height: 16),
                  DropdownButtonFormField<String>(value: _selectedDeptId, hint: const Text("اختر القسم"), decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(15))), items: departments.map((doc) => DropdownMenuItem(value: doc.id, child: Text((doc.data() as Map)['name'] ?? ''))).toList(), onChanged: (val) => setState(() => _selectedDeptId = val), validator: (v) => v == null ? "مطلوب" : null),
                  const SizedBox(height: 24),
                  SizedBox(width: double.infinity, height: 50, child: ElevatedButton(onPressed: auth.isLoading ? null : () async { if (_formKey.currentState!.validate() && _selectedDeptId != null) { bool success = await auth.register(_nameCtrl.text, _phoneCtrl.text, _passCtrl.text, _selectedDeptId!); if (success && mounted) Navigator.pop(context); } }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF001F3F), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), child: auth.isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("إنشاء الحساب", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)))),
                ],
              ),
            ),
          );
        }
      ),
    );
  }
}

// ==========================================
// MAIN LAYOUT
// ==========================================
class MainLayout extends StatefulWidget { const MainLayout({super.key}); @override State<MainLayout> createState() => _MainLayoutState(); }
class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 0;
  final List<Widget> _pages = [const HomeScreen(), const ProfileScreen()];
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, spreadRadius: 2)]),
        child: BottomNavigationBar(
          currentIndex: _currentIndex, onTap: (index) => setState(() => _currentIndex = index), backgroundColor: Colors.white, selectedItemColor: const Color(0xFF001F3F), unselectedItemColor: Colors.grey, showUnselectedLabels: true, type: BottomNavigationBarType.fixed,
          items: const [BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: "الرئيسية"), BottomNavigationBarItem(icon: Icon(Icons.person), label: "حسابي")],
        ),
      ),
    );
  }
}

// ==========================================
// HOME SCREEN
// ==========================================
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthProvider>(context).user!;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => Provider.of<AuthProvider>(context, listen: false).refreshUserData(),
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 160.0, floating: false, pinned: true,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF001F3F), Color(0xFF004080)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30))),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 70, right: 20, left: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("مرحباً بك،", style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 16)),
                            Text(user.name, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: Colors.orangeAccent.withOpacity(0.9), borderRadius: BorderRadius.circular(20)), child: Text(user.departmentName, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12))),
                          ],
                        ),
                        const CircleAvatar(radius: 25, backgroundColor: Colors.white24, child: Icon(Icons.school, color: Colors.white, size: 28)),
                      ],
                    ),
                  ),
                ),
              ),
              shape: const ContinuousRectangleBorder(borderRadius: BorderRadius.only(bottomLeft: Radius.circular(60), bottomRight: Radius.circular(60))),
            ),
            const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.fromLTRB(20, 25, 20, 10), child: Text("الكورسات المتاحة لك", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF001F3F))))),
            FutureBuilder<QuerySnapshot>(
              future: FirebaseFirestore.instance.collection('courses').where('departmentId', isEqualTo: user.departmentId).get(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const SliverToBoxAdapter(child: Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())));
                var allowedCourses = snapshot.data?.docs.where((c) => user.allowedCourseIds.contains(c.id)).toList() ?? [];
                if (allowedCourses.isEmpty) return SliverToBoxAdapter(child: Center(child: Column(children: [const SizedBox(height: 50), Icon(Icons.lock_outline, size: 80, color: Colors.grey.withOpacity(0.5)), const SizedBox(height: 15), const Text("لم يتم تفعيل أي كورس لك بعد\nتواصل مع الإدارة للتفعيل", textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey))])));
                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 15, mainAxisSpacing: 15, childAspectRatio: 0.8),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        var cData = allowedCourses[index].data() as Map<String, dynamic>;
                        String imgUrl = cData['imageUrl'] ?? cData['coverImage'] ?? '';
                        String cId = allowedCourses[index].id;
                        return GestureDetector(
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CourseLecturesScreen(courseId: cId, courseTitle: cData['title'] ?? 'كورس', imageUrl: imgUrl))),
                          child: Container(
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.15), blurRadius: 15, offset: const Offset(0, 5))]),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(flex: 5, child: Hero(tag: 'course_img_$cId', child: ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(20)), child: imgUrl.isNotEmpty ? CachedNetworkImage(imageUrl: imgUrl, fit: BoxFit.cover, placeholder: (c, u) => Container(color: Colors.grey[200], child: const Center(child: CircularProgressIndicator(strokeWidth: 2)))) : Container(color: Colors.grey[200], child: const Icon(Icons.medical_information, size: 50, color: Colors.grey))))),
                                Expanded(flex: 3, child: Padding(padding: const EdgeInsets.all(12.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text(cData['title'] ?? 'بدون عنوان', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF001F3F))), const Spacer(), Row(children: const [Icon(Icons.play_circle_fill, size: 14, color: Colors.orange), SizedBox(width: 4), Text("دخول للكورس", style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold))])]))),
                              ],
                            ),
                          ),
                        );
                      }, childCount: allowedCourses.length,
                    ),
                  ),
                );
              }
            ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 40))
          ],
        ),
      ),
    );
  }
}

// ==========================================
// COURSE LECTURES SCREEN
// ==========================================
class CourseLecturesScreen extends StatelessWidget {
  final String courseId; final String courseTitle; final String imageUrl;
  const CourseLecturesScreen({super.key, required this.courseId, required this.courseTitle, required this.imageUrl});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 220.0, pinned: true,
            flexibleSpace: FlexibleSpaceBar(title: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(8)), child: Text(courseTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))), background: Hero(tag: 'course_img_$courseId', child: imageUrl.isNotEmpty ? CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.cover) : Container(color: const Color(0xFF001F3F), child: const Icon(Icons.school, size: 80, color: Colors.white24)))),
          ),
          FutureBuilder<QuerySnapshot>(
            future: FirebaseFirestore.instance.collection('lectures').where('courseId', isEqualTo: courseId).get(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const SliverToBoxAdapter(child: Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())));
              var lectures = snapshot.data?.docs ?? [];
              lectures.sort((a, b) => ((a.data() as Map)['position'] ?? 9999).compareTo(((b.data() as Map)['position'] ?? 9999)));
              if (lectures.isEmpty) return const SliverToBoxAdapter(child: Center(child: Padding(padding: EdgeInsets.all(40), child: Text("لا توجد محاضرات حالياً في هذا الكورس."))));
              return SliverPadding(
                padding: const EdgeInsets.all(20),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      var lData = lectures[index].data() as Map<String, dynamic>;
                      return Card(margin: const EdgeInsets.only(bottom: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), elevation: 2, child: ListTile(contentPadding: const EdgeInsets.all(15), leading: Container(width: 50, height: 50, decoration: BoxDecoration(color: const Color(0xFF001F3F).withOpacity(0.05), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.menu_book_rounded, color: Color(0xFF001F3F), size: 28)), title: Text(lData['title'] ?? 'محاضرة', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)), subtitle: Text(lData['description'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)), trailing: Container(padding: const EdgeInsets.all(8), decoration: const BoxDecoration(color: Color(0xFFF4F7FE), shape: BoxShape.circle), child: const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFF001F3F))), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LectureDetailsScreen(lectureData: lData)))));
                    }, childCount: lectures.length,
                  ),
                ),
              );
            }
          ),
        ],
      ),
    );
  }
}

// ==========================================
// LECTURE DETAILS SCREEN
// ==========================================
class LectureDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> lectureData;
  const LectureDetailsScreen({super.key, required this.lectureData});
  @override
  Widget build(BuildContext context) {
    List parts = lectureData['parts'] ?? [];
    return Scaffold(
      appBar: AppBar(title: Text(lectureData['title'] ?? 'المحاضرة'), elevation: 0),
      body: Column(
        children: [
          Container(padding: const EdgeInsets.all(20), width: double.infinity, decoration: const BoxDecoration(color: Color(0xFF001F3F), borderRadius: BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(lectureData['title'] ?? '', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)), const SizedBox(height: 10), Text(lectureData['description'] ?? 'لا يوجد وصف متاح.', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14))])),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (lectureData['pdfUrl'] != null && lectureData['pdfUrl'].toString().isNotEmpty)
                  Container(margin: const EdgeInsets.only(bottom: 25), child: ElevatedButton.icon(onPressed: () async { final Uri uri = Uri.parse(lectureData['pdfUrl']); if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication); }, icon: const Icon(Icons.picture_as_pdf, color: Colors.white), label: const Text("تحميل ملزمة المحاضرة (PDF)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)), style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.all(16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), elevation: 5))),
                Row(children: const [Icon(Icons.video_library, color: Color(0xFF001F3F)), SizedBox(width: 8), Text("أجزاء الفيديو:", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF001F3F)))]), const SizedBox(height: 15),
                if (parts.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(20.0), child: Text("لا توجد فيديوهات مضافة.", style: TextStyle(color: Colors.grey))))
                else ...parts.map((part) {
                  String url = part['url'] ?? ''; bool isYoutube = url.contains('youtube.com') || url.contains('youtu.be');
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 1,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: CircleAvatar(radius: 22, backgroundColor: isYoutube ? Colors.red.withOpacity(0.1) : const Color(0xFF001F3F).withOpacity(0.1), child: Icon(isYoutube ? Icons.ondemand_video : Icons.play_arrow, color: isYoutube ? Colors.red : const Color(0xFF001F3F))),
                      title: Text(part['title'] ?? 'جزء الفيديو', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Text(isYoutube ? "يفتح في تطبيق يوتيوب" : "مشاهدة داخل التطبيق", style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                      trailing: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.play_circle_outline, size: 20, color: Colors.orange)),
                      onTap: () async { if (isYoutube) { final Uri uri = Uri.parse(url); if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication); } else { Navigator.push(context, MaterialPageRoute(builder: (_) => VideoPlayerScreen(videoUrl: url, title: part['title'] ?? ''))); } },
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// VIDEO PLAYER SCREEN (Media Kit - Software Decoding Force)
// ==========================================
class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl; final String title;
  const VideoPlayerScreen({super.key, required this.videoUrl, required this.title});
  @override State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final player = Player();
  late final controller = VideoController(player);

  @override
  void initState() {
    super.initState();
    // إجبار التشفير البرمجي لدعم أجهزة هواوي والتابلت
    if (player.platform is NativePlayer) {
      (player.platform as NativePlayer).setProperty('vd-lavc-dr', 'no');
      (player.platform as NativePlayer).setProperty('hwdec', 'no');
    }
    player.open(Media(widget.videoUrl));
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    final watermarkText = "${user?.name ?? ''}\n${user?.phone ?? ''}";

    return Scaffold(
      backgroundColor: Colors.black, 
      body: SafeArea(
        child: Stack(
          children: [
            Center(child: Video(controller: controller, controls: AdaptiveVideoControls)),
            IgnorePointer(
              child: Center(
                child: Transform.rotate(
                  angle: -0.5,
                  child: Text(watermarkText, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withOpacity(0.12), fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 2)),
                ),
              ),
            ),
            Positioned(top: 15, right: 15, child: Container(decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)), child: IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 24), onPressed: () => Navigator.pop(context)))),
            Positioned(top: 25, left: 15, child: Text(widget.title, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold))),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// PROFILE SCREEN
// ==========================================
class ProfileScreen extends StatelessWidget { 
  const ProfileScreen({super.key}); 
  @override Widget build(BuildContext context) {
    final u = Provider.of<AuthProvider>(context).user;
    return Scaffold(
      appBar: AppBar(title: const Text("حسابي"), elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 20),
            Center(child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.orange, width: 2)), child: const CircleAvatar(radius: 50, backgroundColor: Color(0xFF001F3F), child: Icon(Icons.person, size: 50, color: Colors.white)))),
            const SizedBox(height: 15),
            Text(u?.name ?? "", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF001F3F))),
            Container(margin: const EdgeInsets.only(top: 5), padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5), decoration: BoxDecoration(color: const Color(0xFF001F3F).withOpacity(0.1), borderRadius: BorderRadius.circular(20)), child: Text(u?.departmentName ?? "", style: const TextStyle(color: Color(0xFF001F3F), fontWeight: FontWeight.bold))),
            const SizedBox(height: 30),
            Card(elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), child: Column(children: [_tile(Icons.phone, "رقم الهاتف", u?.phone ?? ""), const Divider(height: 0), _tile(Icons.email, "البريد الإلكتروني", (u?.email?.isEmpty??true)?"غير محدد":u!.email!), const Divider(height: 0), _tile(Icons.telegram, "معرف تليجرام", (u?.telegram?.isEmpty??true)?"غير محدد":u!.telegram!)])),
            const SizedBox(height: 30),
            ElevatedButton.icon(onPressed: () => Provider.of<AuthProvider>(context, listen: false).logout(), icon: const Icon(Icons.logout, color: Colors.white), label: const Text("تسجيل الخروج", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)), style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)))),
          ],
        ),
      ),
    );
  }
  Widget _tile(IconData icon, String title, String val) => ListTile(leading: Icon(icon, color: const Color(0xFF001F3F)), title: Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)), subtitle: Text(val, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)));
}
