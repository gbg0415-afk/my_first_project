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
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

// ==========================================
// MODELS
// ==========================================
class User {
  final String id;
  String name;
  String phone;
  final String departmentId;
  String departmentName;
  String? deviceId;
  String? email;
  String? telegram;
  List<String> allowedCourseIds;

  User({
    required this.id,
    required this.name,
    required this.phone,
    required this.departmentId,
    required this.departmentName,
    this.deviceId,
    this.email,
    this.telegram,
    required this.allowedCourseIds,
  });
}

// ==========================================
// AUTH PROVIDER
// ==========================================
class AuthProvider with ChangeNotifier {
  User? _user;
  bool _isLoading = false;
  bool _isInitializing = true;
  String? _error;

  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isInitializing => _isInitializing;
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
        String deptName = "غير محدد";
        try {
          final deptDoc = await FirebaseFirestore.instance.collection('departments').doc(data['departmentId']).get();
          if (deptDoc.exists) deptName = deptDoc.data()?['name'] ?? "قسم غير معروف";
        } catch (_) {}

        _user = User(
          id: firebaseUser.uid,
          name: data['name'] ?? "طالب",
          phone: data['phone'] ?? "",
          departmentId: data['departmentId'] ?? "",
          departmentName: deptName,
          deviceId: data['deviceId'] ?? "",
          email: data['email'] ?? "",
          telegram: data['telegram'] ?? "",
          allowedCourseIds: List<String>.from(data['allowedCourseIds'] ?? []),
        );
      }
    } else {
      _user = null;
    }
    _isInitializing = false;
    notifyListeners();
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
          await FirebaseAuth.instance.signOut();
          _error = "هذا الحساب مرتبط بجهاز آخر. يرجى مراجعة الإدارة.";
          _isLoading = false; notifyListeners();
          return false;
        } else if (savedDeviceId == "") {
          await FirebaseFirestore.instance.collection('users').doc(cred.user!.uid).update({'deviceId': currentDeviceId});
        }
      }
      await _checkLoginStatus();
      _isLoading = false; return true;
    } catch (e) {
      _error = "بيانات الدخول غير صحيحة";
      _isLoading = false; notifyListeners();
      return false;
    }
  }

  Future<bool> register(String name, String phone, String password, String deptId) async {
    _isLoading = true; _error = null; notifyListeners();
    try {
      String email = "$phone@smacademy.com";
      String currentDeviceId = await _getDeviceId();
      UserCredential cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: password);
      
      await FirebaseFirestore.instance.collection('users').doc(cred.user!.uid).set({
        'uid': cred.user!.uid, 'name': name, 'phone': phone, 'departmentId': deptId,
        'deviceId': currentDeviceId, 'email': "", 'telegram': "", 'allowedCourseIds': [],
        'createdAt': FieldValue.serverTimestamp(),
      });
      await _checkLoginStatus();
      _isLoading = false; return true;
    } catch (e) {
      _error = "فشل التسجيل، قد يكون الرقم مستخدماً";
      _isLoading = false; notifyListeners();
      return false;
    }
  }

  void logout() async {
    await FirebaseAuth.instance.signOut();
    _user = null; notifyListeners();
  }
}

// ==========================================
// MAIN APP
// ==========================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  if (Platform.isAndroid) {
    try { await ScreenProtector.preventScreenshotOn(); } catch (_) {}
  }
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
        scaffoldBackgroundColor: const Color(0xFFF4F7FE),
        textTheme: GoogleFonts.cairoTextTheme(),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF001F3F), 
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
      ),
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      home: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          if (auth.isInitializing) return const Scaffold(backgroundColor: Color(0xFF001F3F), body: Center(child: CircularProgressIndicator(color: Colors.white)));
          return auth.user != null ? const MainScreen() : const LoginScreen();
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
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.school, size: 80, color: Color(0xFF001F3F)),
                const SizedBox(height: 16),
                const Text("SM Academy", textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF001F3F))),
                const SizedBox(height: 30),
                if (auth.error != null) Text(auth.error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                TextFormField(controller: _idCtrl, decoration: const InputDecoration(labelText: "رقم الهاتف", border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(15)))), validator: (v) => v!.isEmpty ? "مطلوب" : null),
                const SizedBox(height: 16),
                TextFormField(controller: _passCtrl, obscureText: true, decoration: const InputDecoration(labelText: "كلمة المرور", border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(15)))), validator: (v) => v!.isEmpty ? "مطلوب" : null),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: auth.isLoading ? null : () { if (_formKey.currentState!.validate()) auth.login(_idCtrl.text, _passCtrl.text); },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF001F3F), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                  child: auth.isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("تسجيل الدخول", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignupScreen())), child: const Text("إنشاء حساب جديد", style: TextStyle(color: Color(0xFF001F3F), fontWeight: FontWeight.bold))),
              ],
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
      appBar: AppBar(title: const Text("إنشاء حساب")),
      body: FutureBuilder<QuerySnapshot>(
        future: FirebaseFirestore.instance.collection('departments').get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("لا توجد أقسام متاحة حالياً."));
          var departments = snapshot.data!.docs;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(controller: _nameCtrl, decoration: const InputDecoration(labelText: "الاسم الكامل", border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(15)))), validator: (v) => v!.isEmpty ? "مطلوب" : null),
                  const SizedBox(height: 16),
                  TextFormField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: "رقم الهاتف", border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(15)))), keyboardType: TextInputType.phone, validator: (v) => v!.isEmpty ? "مطلوب" : null),
                  const SizedBox(height: 16),
                  TextFormField(controller: _passCtrl, obscureText: true, decoration: const InputDecoration(labelText: "كلمة المرور", border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(15)))), validator: (v) => v!.isEmpty ? "مطلوب" : null),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _selectedDeptId, hint: const Text("اختر القسم"),
                    decoration: const InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(15)))),
                    items: departments.map((doc) => DropdownMenuItem(value: doc.id, child: Text((doc.data() as Map)['name'] ?? ''))).toList(),
                    onChanged: (val) => setState(() => _selectedDeptId = val), validator: (v) => v == null ? "مطلوب" : null,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: auth.isLoading ? null : () async {
                      if (_formKey.currentState!.validate() && _selectedDeptId != null) {
                        bool success = await auth.register(_nameCtrl.text, _phoneCtrl.text, _passCtrl.text, _selectedDeptId!);
                        if (success && mounted) Navigator.pop(context);
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF001F3F), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                    child: auth.isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("إنشاء حساب", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
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

// ==========================================
// MAIN SCREEN (Dashboard)
// ==========================================
class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthProvider>(context).user!;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 180.0,
            floating: false,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFF001F3F), Color(0xFF003366)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(top: 80, right: 20, left: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("مرحباً بك، ${user.name}", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(color: Colors.orangeAccent, borderRadius: BorderRadius.circular(20)),
                        child: Text(user.departmentName, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              IconButton(icon: const Icon(Icons.refresh), onPressed: () => Provider.of<AuthProvider>(context, listen: false).refreshUserData()),
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
                child: const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: CircleAvatar(radius: 18, backgroundColor: Colors.white24, child: Icon(Icons.person, color: Colors.white))),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: const Text("كورساتي", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF001F3F))),
            ),
          ),
          FutureBuilder<QuerySnapshot>(
            future: FirebaseFirestore.instance.collection('courses').where('departmentId', isEqualTo: user.departmentId).get(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const SliverToBoxAdapter(child: Center(child: Text("لا توجد كورسات متاحة.")));

              var allowedCourses = snapshot.data!.docs.where((c) => user.allowedCourseIds.contains(c.id)).toList();
              if (allowedCourses.isEmpty) {
                return const SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(20), 
                      child: Text("لم يتم تفعيل أي كورس لك بعد. تواصل مع الإدارة.", style: TextStyle(fontSize: 16, color: Colors.grey))
                    )
                  )
                );
              }

              return SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 15, mainAxisSpacing: 15, childAspectRatio: 0.85),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      var courseData = allowedCourses[index].data() as Map<String, dynamic>;
                      String imageUrl = courseData['imageUrl'] ?? courseData['coverImage'] ?? '';
                      return GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CourseLecturesScreen(courseId: allowedCourses[index].id, courseTitle: courseData['title'] ?? 'كورس'))),
                        child: Container(
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10, spreadRadius: 2)]),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                flex: 3,
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                                  child: imageUrl.isNotEmpty 
                                    ? CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.cover, errorWidget: (c, u, e) => const Icon(Icons.image_not_supported, size: 50, color: Colors.grey))
                                    : Container(color: Colors.grey[200], child: const Icon(Icons.menu_book, size: 50, color: Colors.grey)),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(courseData['title'] ?? 'بدون عنوان', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF001F3F))),
                                      const SizedBox(height: 5),
                                      const Text("دخول للكورس >", style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    childCount: allowedCourses.length,
                  ),
                ),
              );
            }
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 40))
        ],
      ),
    );
  }
}

// ==========================================
// COURSE LECTURES LIST SCREEN
// ==========================================
class CourseLecturesScreen extends StatelessWidget {
  final String courseId; final String courseTitle;
  const CourseLecturesScreen({super.key, required this.courseId, required this.courseTitle});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(courseTitle)),
      body: FutureBuilder<QuerySnapshot>(
        future: FirebaseFirestore.instance.collection('lectures').where('courseId', isEqualTo: courseId).get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("لا توجد محاضرات حالياً."));

          var lectures = snapshot.data!.docs;
          lectures.sort((a, b) => ((a.data() as Map)['position'] ?? 9999).compareTo(((b.data() as Map)['position'] ?? 9999)));

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: lectures.length,
            itemBuilder: (context, index) {
              var lectureData = lectures[index].data() as Map<String, dynamic>;
              
              return Card(
                margin: const EdgeInsets.only(bottom: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                elevation: 3,
                child: ListTile(
                  contentPadding: const EdgeInsets.all(15),
                  leading: Container(width: 50, height: 50, decoration: BoxDecoration(color: const Color(0xFF001F3F).withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.folder, color: Color(0xFF001F3F), size: 30)),
                  title: Text(lectureData['title'] ?? 'محاضرة', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(lectureData['description'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => LectureDetailsScreen(lectureData: lectureData)
                    ));
                  },
                ),
              );
            }
          );
        }
      )
    );
  }
}

// ==========================================
// LECTURE DETAILS SCREEN (Preparation Screen)
// ==========================================
class LectureDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> lectureData;

  const LectureDetailsScreen({super.key, required this.lectureData});

  @override
  Widget build(BuildContext context) {
    List parts = lectureData['parts'] ?? [];

    return Scaffold(
      appBar: AppBar(title: Text(lectureData['title'] ?? 'تفاصيل المحاضرة')),
      body: Column(
        children: [
          Container(
            height: 200,
            width: double.infinity,
            color: const Color(0xFF001F3F),
            child: const Center(
              child: Icon(Icons.library_books, size: 80, color: Colors.white24),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(lectureData['title'] ?? '', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF001F3F))),
                const SizedBox(height: 10),
                Text(lectureData['description'] ?? 'لا يوجد وصف حالياً لهذه المحاضرة.', style: const TextStyle(color: Colors.grey, fontSize: 14)),
                const SizedBox(height: 30),
                
                if (lectureData['pdfUrl'] != null && lectureData['pdfUrl'].toString().isNotEmpty)
                  ElevatedButton.icon(
                    onPressed: () {
                       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("سيتم فتح الملف قريباً")));
                    }, 
                    icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
                    label: const Text("تحميل ملزمة المحاضرة (PDF)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700], padding: const EdgeInsets.all(15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                  ),
                
                const SizedBox(height: 30),
                const Text("أجزاء الفيديو المتاحة:", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF001F3F))),
                const SizedBox(height: 10),
                
                if (parts.isEmpty)
                  const Center(child: Padding(padding: EdgeInsets.all(20.0), child: Text("لا توجد فيديوهات مضافة لهذه المحاضرة.")))
                else
                  ...parts.map((part) => Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 1,
                    child: ListTile(
                      leading: const CircleAvatar(backgroundColor: Color(0xFF001F3F), child: Icon(Icons.play_arrow, color: Colors.white)),
                      title: Text(part['title'] ?? 'جزء غير معنون', style: const TextStyle(fontWeight: FontWeight.bold)),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => VideoPlayerScreen(
                            videoUrl: part['url'] ?? '', 
                            title: part['title'] ?? 'عرض الفيديو'
                          )
                        ));
                      },
                    ),
                  )).toList(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// VIDEO PLAYER SCREEN (YouTube, Bunny, G-Drive)
// ==========================================
class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl; final String title;
  const VideoPlayerScreen({super.key, required this.videoUrl, required this.title});
  @override State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  YoutubePlayerController? _ytController;
  VideoPlayerController? _vpController;
  ChewieController? _chewieController;
  bool isYoutube = false;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    isYoutube = widget.videoUrl.contains("youtube.com") || widget.videoUrl.contains("youtu.be");
    
    if (isYoutube) {
      _initYoutube();
    } else {
      _initStandardPlayer();
    }
  }

  void _initYoutube() {
    String? videoId = YoutubePlayer.convertUrlToId(widget.videoUrl);
    if (videoId != null) {
      _ytController = YoutubePlayerController(
        initialVideoId: videoId,
        flags: const YoutubePlayerFlags(
          autoPlay: false, // تعطيل التشغيل التلقائي لتخطي حظر التابلت
          mute: false, 
          forceHD: false,  // تعطيل الـ HD التلقائي لتسريع الاستجابة
        ),
      );
    }
    setState(() => isLoading = false);
  }

  Future<void> _initStandardPlayer() async {
    String finalUrl = widget.videoUrl;
    if (finalUrl.contains("drive.google.com")) {
      RegExp regExp = RegExp(r'id=([a-zA-Z0-9_-]+)|d\/([a-zA-Z0-9_-]+)');
      Match? match = regExp.firstMatch(finalUrl);
      String? id = match?.group(1) ?? match?.group(2);
      if (id != null) {
        finalUrl = "https://docs.google.com/uc?export=download&id=$id";
      }
    }

    _vpController = VideoPlayerController.networkUrl(Uri.parse(finalUrl));
    
    try {
      await _vpController!.initialize();
      _chewieController = ChewieController(
        videoPlayerController: _vpController!,
        autoPlay: true,
        fullScreenByDefault: true, 
        allowFullScreen: true,
        aspectRatio: _vpController!.value.aspectRatio,
        materialProgressColors: ChewieProgressColors(playedColor: Colors.orange, handleColor: Colors.orange, backgroundColor: Colors.grey, bufferedColor: Colors.white54),
      );
    } catch (e) {
      print("Error initializing standard player: $e");
    }
    
    if (mounted) setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, 
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: isLoading 
                ? const CircularProgressIndicator(color: Colors.orange)
                : isYoutube && _ytController != null
                  ? YoutubePlayerBuilder(
                      player: YoutubePlayer(
                        controller: _ytController!,
                        showVideoProgressIndicator: true,
                      ),
                      builder: (context, player) {
                        return player;
                      },
                    )
                  : _chewieController != null
                    ? Chewie(controller: _chewieController!)
                    : const Text("عذراً، لا يمكن تشغيل هذا الفيديو.", style: TextStyle(color: Colors.white)),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 24),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ytController?.dispose();
    _vpController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }
}

// ==========================================
// PROFILE SCREEN
// ==========================================
class ProfileScreen extends StatefulWidget { const ProfileScreen({super.key}); @override State<ProfileScreen> createState() => _ProfileScreenState(); }
class _ProfileScreenState extends State<ProfileScreen> {
  Future<void> _update(String field, String val) async {
    final u = Provider.of<AuthProvider>(context, listen: false).user;
    if (u != null) {
      await FirebaseFirestore.instance.collection('users').doc(u.id).update({field: val});
      Provider.of<AuthProvider>(context, listen: false).refreshUserData();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم التحديث")));
    }
  }
  void _showEdit(String title, String field, String current) {
    TextEditingController c = TextEditingController(text: current);
    showDialog(context: context, builder: (_) => AlertDialog(
      title: Text("تعديل $title"), content: TextField(controller: c),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
        ElevatedButton(onPressed: () { if (c.text.isNotEmpty) { _update(field, c.text); Navigator.pop(context); } }, child: const Text("حفظ")),
      ],
    ));
  }
  @override
  Widget build(BuildContext context) {
    final u = Provider.of<AuthProvider>(context).user;
    return Scaffold(
      appBar: AppBar(title: const Text("الملف الشخصي")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Center(child: CircleAvatar(radius: 50, backgroundColor: Color(0xFF001F3F), child: Icon(Icons.person, size: 50, color: Colors.white))),
          const SizedBox(height: 20),
          _item("الاسم", u?.name ?? "", true, () => _showEdit("الاسم", "name", u?.name ?? "")),
          _item("الهاتف", u?.phone ?? "", true, () => _showEdit("الهاتف", "phone", u?.phone ?? "")),
          _item("الإيميل", (u?.email?.isEmpty??true)?"أضف ايميل":u!.email!, true, () => _showEdit("الإيميل", "email", u?.email ?? "")),
          _item("تليجرام", (u?.telegram?.isEmpty??true)?"أضف @username":u!.telegram!, true, () => _showEdit("تليجرام", "telegram", u?.telegram ?? "")),
          const Divider(),
          _item("القسم", u?.departmentName ?? "", false, null),
          const SizedBox(height: 30),
          TextButton(onPressed: () { Navigator.pop(context); Provider.of<AuthProvider>(context, listen: false).logout(); }, child: const Text("تسجيل الخروج", style: TextStyle(color: Colors.red, fontSize: 16, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }
  Widget _item(String l, String v, bool ed, VoidCallback? onT) {
    return ListTile(title: Text(l, style: const TextStyle(fontSize: 12, color: Colors.grey)), subtitle: Text(v, style: const TextStyle(fontSize: 16)), trailing: ed ? const Icon(Icons.edit, size: 16) : null, onTap: onT);
  }
}
