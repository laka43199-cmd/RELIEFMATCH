import 'dart:math' as math;
import 'package:flutter/material.dart';

// ───────── Design tokens (ตาม CDD หัวข้อ 6) ─────────
const kPrimary = Color(0xFF1E3A8A); // Deep Blue
const kAccent = Color(0xFFEA580C); // Alert Orange
const kSuccess = Color(0xFF10B981); // Emerald Green
const kBg = Color(0xFFF8FAFC); // Soft Slate

const kHotline = '1784'; // ศูนย์ประสานงานกลาง (เปลี่ยนได้)
const kSmsGateway = '0800000000'; // เบอร์ SMS Gateway (ตัวอย่าง)

const kProvinces = [
  'กรุงเทพมหานคร', 'เชียงราย', 'เชียงใหม่', 'น่าน', 'ตาก', 'พิษณุโลก',
  'นครสวรรค์', 'พระนครศรีอยุธยา', 'ขอนแก่น', 'นครราชสีมา', 'อุบลราชธานี',
  'สุราษฎร์ธานี', 'นครศรีธรรมราช', 'สงขลา', 'ปัตตานี',
];

// ───────── Users ─────────
enum UserRole { donor, requester, coAdmin }

extension UserRoleX on UserRole {
  String get label => switch (this) {
        UserRole.donor => 'ผู้บริจาค',
        UserRole.requester => 'ตัวแทนศูนย์พักพิง / ผู้นำชุมชน',
        UserRole.coAdmin => 'ผู้ช่วยดูแลแทน (Co-Admin)',
      };
  String get shortLabel => switch (this) {
        UserRole.donor => 'ผู้บริจาค',
        UserRole.requester => 'ตัวแทนพื้นที่',
        UserRole.coAdmin => 'ผู้ช่วยดูแลแทน',
      };
  bool get canManage => this != UserRole.donor;
}

class AppUser {
  final String name, phone, linkedOwnerPhone;
  final UserRole role;
  const AppUser({
    required this.name,
    required this.phone,
    required this.role,
    this.linkedOwnerPhone = '',
  });

  Map<String, dynamic> toJson() =>
      {'name': name, 'phone': phone, 'role': role.name, 'linked': linkedOwnerPhone};

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        name: j['name'] as String,
        phone: j['phone'] as String,
        role: UserRole.values.byName(j['role'] as String),
        linkedOwnerPhone: (j['linked'] as String?) ?? '',
      );
}

// ───────── Items ─────────
enum ItemCategory { water, food, medical, clothing, shelter, hygiene }

extension ItemCategoryX on ItemCategory {
  String get label => switch (this) {
        ItemCategory.water => 'น้ำดื่ม',
        ItemCategory.food => 'อาหาร',
        ItemCategory.medical => 'ยา/เวชภัณฑ์',
        ItemCategory.clothing => 'เสื้อผ้า/ผ้าห่ม',
        ItemCategory.shelter => 'เต็นท์/ที่พัก',
        ItemCategory.hygiene => 'ของใช้จำเป็น',
      };
  IconData get icon => switch (this) {
        ItemCategory.water => Icons.water_drop,
        ItemCategory.food => Icons.rice_bowl,
        ItemCategory.medical => Icons.medical_services,
        ItemCategory.clothing => Icons.checkroom,
        ItemCategory.shelter => Icons.cabin,
        ItemCategory.hygiene => Icons.clean_hands,
      };

  /// รหัสสำหรับคำสั่ง SMS เช่น RM#SH01#WATER+50
  String get code => switch (this) {
        ItemCategory.water => 'WATER',
        ItemCategory.food => 'FOOD',
        ItemCategory.medical => 'MED',
        ItemCategory.clothing => 'CLOTH',
        ItemCategory.shelter => 'SHELTER',
        ItemCategory.hygiene => 'HYG',
      };
}

enum Urgency { normal, urgent, critical }

extension UrgencyX on Urgency {
  String get label => switch (this) {
        Urgency.normal => 'ทั่วไป',
        Urgency.urgent => 'ขาดแคลนด่วน',
        Urgency.critical => 'ขาดแคลนด่วนมาก',
      };
  Color get color => switch (this) {
        Urgency.normal => kPrimary,
        Urgency.urgent => const Color(0xFFB45309),
        Urgency.critical => kAccent,
      };
}

class ItemNeed {
  final String id;
  final ItemCategory category;
  String name;
  int target, received, pledged;

  ItemNeed({
    required this.id,
    required this.category,
    required this.name,
    required this.target,
    this.received = 0,
    this.pledged = 0,
  });

  bool get done => received >= target;
  int get stillNeeded => math.max(0, target - received - pledged);
  double get progress =>
      target == 0 ? 1.0 : (received / target).clamp(0.0, 1.0).toDouble();

  Map<String, dynamic> toJson() => {
        'id': id, 'category': category.name, 'name': name,
        'target': target, 'received': received, 'pledged': pledged,
      };

  factory ItemNeed.fromJson(Map<String, dynamic> j) => ItemNeed(
        id: j['id'] as String,
        category: ItemCategory.values.byName(j['category'] as String),
        name: j['name'] as String,
        target: j['target'] as int,
        received: j['received'] as int,
        pledged: (j['pledged'] as int?) ?? 0,
      );
}

class ReliefPost {
  final String id, code, ownerPhone;
  String name, province, phone;
  double? lat, lng;
  Urgency urgency;
  List<ItemNeed> items;
  DateTime updatedAt;
  bool pendingSync; // true = แก้ไขในเครื่องแล้ว ยังไม่ขึ้นเซิร์ฟเวอร์

  ReliefPost({
    required this.id,
    required this.code,
    required this.name,
    required this.province,
    required this.phone,
    required this.ownerPhone,
    required this.urgency,
    required this.items,
    required this.updatedAt,
    this.lat,
    this.lng,
    this.pendingSync = false,
  });

  int get totalTarget => items.fold(0, (s, i) => s + i.target);
  int get totalReceived =>
      items.fold(0, (s, i) => s + math.min(i.received, i.target));
  double get progress =>
      totalTarget == 0 ? 1.0 : (totalReceived / totalTarget).toDouble();
  bool get fulfilled => items.isNotEmpty && items.every((i) => i.done);
  int get itemsMissing => items.where((i) => !i.done).length;
  bool get hasCoords => lat != null && lng != null;

  Map<String, dynamic> toJson() => {
        'id': id, 'code': code, 'name': name, 'province': province,
        'phone': phone, 'ownerPhone': ownerPhone, 'urgency': urgency.name,
        'lat': lat, 'lng': lng,
        'updatedAt': updatedAt.toIso8601String(),
        'pendingSync': pendingSync,
        'items': items.map((i) => i.toJson()).toList(),
      };

  factory ReliefPost.fromJson(Map<String, dynamic> j) => ReliefPost(
        id: j['id'] as String,
        code: j['code'] as String,
        name: j['name'] as String,
        province: j['province'] as String,
        phone: j['phone'] as String,
        ownerPhone: j['ownerPhone'] as String,
        urgency: Urgency.values.byName(j['urgency'] as String),
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        updatedAt: DateTime.parse(j['updatedAt'] as String),
        pendingSync: (j['pendingSync'] as bool?) ?? false,
        items: (j['items'] as List)
            .map((e) => ItemNeed.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// ───────── Helpers ─────────
String normalizePhone(String p) => p.replaceAll(RegExp(r'\D'), '');

/// PDPA: ซ่อนเบอร์จนกว่าผู้ใช้จะกดยืนยันการติดต่อ
String maskPhone(String p) {
  final d = normalizePhone(p);
  if (d.length < 6) return 'xxx-xxx';
  return '${d.substring(0, 3)}-xxx-xx${d.substring(d.length - 2)}';
}

String ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'เมื่อสักครู่';
  if (d.inMinutes < 60) return '${d.inMinutes} นาทีที่แล้ว';
  if (d.inHours < 24) return '${d.inHours} ชม.ที่แล้ว';
  return '${d.inDays} วันที่แล้ว';
}