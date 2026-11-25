import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

// ───────── Remote (Server) ─────────
// แทนที่ด้วย FirestoreRemote ได้ภายหลัง โดย implements RemoteDataSource ตัวเดียวกัน
abstract class RemoteDataSource {
  Future<List<ReliefPost>> fetchPosts();
  Future<void> upsertPost(ReliefPost post);
}

/// เซิร์ฟเวอร์จำลองในหน่วยความจำ ไว้ทดสอบ sync โดยไม่ต้องตั้งค่า Firebase
class FakeRemote implements RemoteDataSource {
  final Map<String, ReliefPost> _db = {for (final p in seedPosts()) p.id: p};

  ReliefPost _copy(ReliefPost p) => ReliefPost.fromJson(p.toJson());

  @override
  Future<List<ReliefPost>> fetchPosts() async {
    await Future.delayed(const Duration(milliseconds: 600));
    return _db.values.map(_copy).toList();
  }

  @override
  Future<void> upsertPost(ReliefPost post) async {
    await Future.delayed(const Duration(milliseconds: 600));
    _db[post.id] = _copy(post)..pendingSync = false;
  }
}

List<ReliefPost> seedPosts() {
  final t = DateTime(2026, 11, 13);
  ItemNeed i(String id, ItemCategory c, String n, int target, int got) =>
      ItemNeed(id: id, category: c, name: n, target: target, received: got);
  return [
    ReliefPost(
      id: 'p1', code: 'SH01', name: 'ศูนย์พักพิงวัดโพธาราม', province: 'สงขลา',
      lat: 7.0086, lng: 100.4747, phone: '0811111111', ownerPhone: '0811111111',
      urgency: Urgency.critical, updatedAt: t,
      items: [
        i('p1a', ItemCategory.water, 'น้ำดื่มแพ็ก', 100, 35),
        i('p1b', ItemCategory.food, 'ข้าวสาร 5 กก.', 200, 120),
      ],
    ),
    ReliefPost(
      id: 'p2', code: 'SH02', name: 'โรงเรียนบ้านริมน้ำ', province: 'นครศรีธรรมราช',
      lat: 8.4304, lng: 99.9631, phone: '0822222222', ownerPhone: '0822222222',
      urgency: Urgency.urgent, updatedAt: t,
      items: [
        i('p2a', ItemCategory.medical, 'ชุดปฐมพยาบาล', 50, 10),
        i('p2b', ItemCategory.clothing, 'ผ้าห่ม', 80, 80),
      ],
    ),
    ReliefPost(
      id: 'p3', code: 'SH03', name: 'ศาลาประชาคมบ้านดอนแก้ว', province: 'เชียงราย',
      lat: 19.9105, lng: 99.8406, phone: '0833333333', ownerPhone: '0833333333',
      urgency: Urgency.normal, updatedAt: t,
      items: [
        i('p3a', ItemCategory.hygiene, 'สบู่/ผ้าอนามัย', 60, 20),
        i('p3b', ItemCategory.shelter, 'เต็นท์', 10, 2),
      ],
    ),
    ReliefPost(
      id: 'p4', code: 'SH04', name: 'ศูนย์อพยพ อบต.หนองบัว', province: 'อุบลราชธานี',
      lat: 15.2448, lng: 104.8473, phone: '0844444444', ownerPhone: '0844444444',
      urgency: Urgency.urgent, updatedAt: t,
      items: [
        i('p4a', ItemCategory.water, 'น้ำดื่มแพ็ก', 300, 90),
        i('p4b', ItemCategory.food, 'อาหารกระป๋อง', 150, 150),
      ],
    ),
  ];
}

// ───────── Repository (Offline-first) ─────────
class ReliefRepository extends ChangeNotifier {
  ReliefRepository(this.remote);
  final RemoteDataSource remote;

  late SharedPreferences _prefs;
  List<ReliefPost> posts = [];
  AppUser? user;
  bool easyMode = false;
  bool online = true; // จำลองสถานะเน็ต (production ใช้ connectivity_plus)
  bool syncing = false;
  DateTime? lastSync;

  int get pendingCount => posts.where((p) => p.pendingSync).length;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs.getString('posts');
    if (raw != null) {
      posts = (jsonDecode(raw) as List)
          .map((e) => ReliefPost.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    final u = _prefs.getString('user');
    if (u != null) user = AppUser.fromJson(jsonDecode(u) as Map<String, dynamic>);
    easyMode = _prefs.getBool('easy') ?? false;
    notifyListeners();
    unawaited(sync());
  }

  Future<void> _save() =>
      _prefs.setString('posts', jsonEncode(posts.map((p) => p.toJson()).toList()));

  /// Auto-Sync: push รายการที่รอซิงก์ → ดึงข้อมูลล่าสุด → รวมแบบ "ใหม่กว่าชนะ"
  Future<void> sync() async {
    if (!online || syncing) return;
    syncing = true;
    notifyListeners();
    try {
      for (final p in posts.where((p) => p.pendingSync).toList()) {
        await remote.upsertPost(p);
        p.pendingSync = false;
      }
      final remotePosts = await remote.fetchPosts();
      final local = {for (final p in posts) p.id: p};
      for (final r in remotePosts) {
        final l = local[r.id];
        if (l == null || (!l.pendingSync && r.updatedAt.isAfter(l.updatedAt))) {
          local[r.id] = r;
        }
      }
      posts = local.values.toList();
      lastSync = DateTime.now();
      await _save();
    } catch (e) {
      debugPrint('sync failed: $e');
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> _commit(ReliefPost p) async {
    p.updatedAt = DateTime.now();
    p.pendingSync = true;
    await _save();
    notifyListeners();
    if (online) unawaited(sync());
  }

  // ── Auth (จำลองในเครื่อง; production ใช้ Firebase Auth) ──
  Future<void> register(AppUser u) async {
    user = u;
    await _prefs.setString('user', jsonEncode(u.toJson()));
    notifyListeners();
  }

  Future<void> logout() async {
    user = null;
    await _prefs.remove('user');
    notifyListeners();
  }

  /// เจ้าของประกาศ หรือ Co-Admin ที่ผูกกับเบอร์เจ้าของ แก้ไขได้
  bool canEdit(ReliefPost p) {
    final u = user;
    if (u == null || !u.role.canManage) return false;
    final mine = normalizePhone(u.role == UserRole.coAdmin ? u.linkedOwnerPhone : u.phone);
    return mine == normalizePhone(p.ownerPhone);
  }

  Future<void> setEasy(bool v) async {
    easyMode = v;
    await _prefs.setBool('easy', v);
    notifyListeners();
  }

  void setOnline(bool v) {
    online = v;
    notifyListeners();
    if (v) unawaited(sync());
  }

  // ── Mutations ──
  String nextCode() {
    var n = posts.length + 1;
    while (posts.any((p) => p.code == 'SH${n.toString().padLeft(2, '0')}')) {
      n++;
    }
    return 'SH${n.toString().padLeft(2, '0')}';
  }

  Future<void> createPost(ReliefPost p) {
    posts.insert(0, p);
    return _commit(p);
  }

  Future<void> adjustItem(ReliefPost p, ItemNeed item, int delta) {
    item.received = (item.received + delta).clamp(0, item.target).toInt();
    return _commit(p);
  }

  Future<void> pledge(ReliefPost p, ItemNeed item, int qty) {
    item.pledged += qty;
    return _commit(p);
  }

  /// จำลอง SMS Gateway: RM#<รหัสศูนย์>#<รหัสสิ่งของ>[+|-|=]<จำนวน>
  String applySms(String raw) {
    final m = RegExp(r'^RM#([A-Z0-9]+)#([A-Z]+)([+\-=])(\d+)$')
        .firstMatch(raw.trim().toUpperCase());
    if (m == null) return 'รูปแบบไม่ถูกต้อง ตัวอย่าง: RM#SH01#WATER+50';
    final code = m.group(1)!, cat = m.group(2)!, op = m.group(3)!;
    final n = int.parse(m.group(4)!);
    final post = posts.where((p) => p.code == code).firstOrNull;
    if (post == null) return 'ไม่พบรหัสศูนย์ $code';
    if (!canEdit(post)) return 'บัญชีนี้ไม่มีสิทธิ์อัปเดตศูนย์ $code';
    final item = post.items.where((i) => i.category.code == cat).firstOrNull;
    if (item == null) return 'ศูนย์ $code ไม่มีรายการ $cat';
    final v = switch (op) {
      '+' => item.received + n,
      '-' => item.received - n,
      _ => n,
    };
    item.received = v.clamp(0, item.target).toInt();
    unawaited(_commit(post));
    return 'อัปเดตแล้ว: ${item.name} ${item.received}/${item.target}';
  }
}

// ───────── InheritedNotifier สำหรับเข้าถึง repository ทั่วแอป ─────────
class RepoScope extends InheritedNotifier<ReliefRepository> {
  const RepoScope({super.key, required ReliefRepository repo, required super.child})
      : super(notifier: repo);

  static ReliefRepository of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RepoScope>()!.notifier!;
}