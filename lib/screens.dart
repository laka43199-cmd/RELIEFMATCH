import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'models.dart';
import 'repository.dart';

// ───────── Helpers ─────────
void snack(BuildContext context, String msg) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(msg)));

Future<void> openUri(BuildContext context, Uri uri) async {
  var ok = false;
  try {
    ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok && context.mounted) snack(context, 'เปิดไม่ได้ (อุปกรณ์/อีมูเลเตอร์อาจไม่มีแอปที่รองรับ)');
}

Uri telUri(String n) => Uri(scheme: 'tel', path: n);
Uri mapUri(ReliefPost p) => Uri.https(
    'www.google.com', '/maps/search/', {'api': '1', 'query': '${p.lat},${p.lng}'});

Color shortageColor(ReliefPost p) => p.fulfilled
    ? kSuccess
    : p.progress < 0.3
        ? kAccent
        : p.progress < 0.7
            ? const Color(0xFFF59E0B)
            : kPrimary;

// ───────── Small widgets ─────────
class ProgressBar extends StatelessWidget {
  final double value;
  final Color color;
  final double height;
  const ProgressBar({super.key, required this.value, required this.color, this.height = 10});
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LinearProgressIndicator(
          value: value,
          minHeight: height,
          color: color,
          backgroundColor: Colors.grey.shade300,
        ),
      );
}

class StatusBadge extends StatelessWidget {
  final ReliefPost post;
  const StatusBadge(this.post, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = post.fulfilled ? kSuccess : post.urgency.color;
    final text = post.fulfilled ? 'ได้รับครบแล้ว' : post.urgency.label;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c),
      ),
      child: Text(text, style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }
}

class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({super.key});
  @override
  Widget build(BuildContext context) {
    final repo = RepoScope.of(context);
    final pending = repo.pendingCount;
    Widget banner(Color c, IconData i, String t) => Container(
          width: double.infinity,
          color: c,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(children: [
            Icon(i, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 13))),
          ]),
        );
    if (!repo.online) {
      return banner(kAccent, Icons.cloud_off,
          'ออฟไลน์ – แสดงข้อมูลจากแคชในเครื่อง${pending > 0 ? ' • รอซิงก์ $pending รายการ' : ''}');
    }
    if (repo.syncing) return banner(kPrimary, Icons.sync, 'กำลังซิงก์ข้อมูล…');
    if (pending > 0) return banner(kPrimary, Icons.cloud_upload, 'รอซิงก์ $pending รายการ');
    return const SizedBox.shrink();
  }
}

class CallBar extends StatelessWidget {
  const CallBar({super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: kAccent, minimumSize: const Size(48, 72)),
            onPressed: () => openUri(context, telUri(kHotline)),
            icon: const Icon(Icons.phone, size: 32),
            label: const Text('โทรติดต่อศูนย์ประสานงาน',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      );
}

/// ปุ่ม +/- ขนาดใหญ่สำหรับอัปเดตยอด (Easy Mode: เหลือ ±10)
class QtyButtons extends StatelessWidget {
  final ReliefPost post;
  final ItemNeed item;
  const QtyButtons({super.key, required this.post, required this.item});
  @override
  Widget build(BuildContext context) {
    final repo = RepoScope.of(context);
    final easy = repo.easyMode;
    final steps = easy ? [-10, 10] : [-10, -1, 1, 10];
    final size = Size(64, easy ? 72 : 48);
    final ts = TextStyle(fontSize: easy ? 18 : 16, fontWeight: FontWeight.bold);
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final d in steps)
        d > 0
            ? FilledButton(
                style: FilledButton.styleFrom(minimumSize: size),
                onPressed: () => repo.adjustItem(post, item, d),
                child: Text('+$d', style: ts))
            : OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: size),
                onPressed: () => repo.adjustItem(post, item, d),
                child: Text('$d', style: ts)),
    ]);
  }
}

// ───────── Register ─────────
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _key = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _linked = TextEditingController();
  UserRole _role = UserRole.donor;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _linked.dispose();
    super.dispose();
  }

  String? _req(String? v) => (v == null || v.trim().isEmpty) ? 'กรุณากรอกข้อมูล' : null;
  String? _tel(String? v) => normalizePhone(v ?? '').length < 9 ? 'กรอกเบอร์โทรให้ถูกต้อง' : null;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('ReliefMatch')),
        body: SafeArea(
          child: Form(
            key: _key,
            child: ListView(padding: const EdgeInsets.all(20), children: [
              const Icon(Icons.volunteer_activism, size: 64, color: kPrimary),
              const SizedBox(height: 8),
              Text('ลงทะเบียนใช้งาน',
                  textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 20),
              TextFormField(
                  controller: _name,
                  validator: _req,
                  decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'ชื่อ-นามสกุล')),
              const SizedBox(height: 12),
              TextFormField(
                  controller: _phone,
                  validator: _tel,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'เบอร์โทรศัพท์')),
              const SizedBox(height: 16),
              const Text('ฉันคือ', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                for (final r in UserRole.values)
                  ChoiceChip(
                    label: Text(r.shortLabel),
                    selected: _role == r,
                    onSelected: (_) => setState(() => _role = r),
                  ),
              ]),
              if (_role == UserRole.coAdmin) ...[
                const SizedBox(height: 12),
                TextFormField(
                    controller: _linked,
                    validator: _tel,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'เบอร์โทรของผู้ที่คุณช่วยดูแล',
                        helperText: 'จะจัดการประกาศที่เป็นของเบอร์นี้ได้')),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  if (!_key.currentState!.validate()) return;
                  RepoScope.of(context).register(AppUser(
                    name: _name.text.trim(),
                    phone: _phone.text.trim(),
                    role: _role,
                    linkedOwnerPhone: _role == UserRole.coAdmin ? _linked.text.trim() : '',
                  ));
                },
                child: const Text('เริ่มใช้งาน'),
              ),
              const SizedBox(height: 8),
              Text('เดโมนี้เก็บบัญชีไว้ในเครื่อง (ยังไม่ใช้ OTP)',
                  textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ),
      );
}

// ───────── Home shell ─────────
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final repo = RepoScope.of(context);
    final canManage = repo.user?.role.canManage ?? false;
    final easy = repo.easyMode;

    // Easy Mode ซ่อนแท็บแผนที่เพื่อลดความซับซ้อน
    final tabs = <(Widget, NavigationDestination)>[
      (const FeedScreen(), const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'หน้าหลัก')),
      if (!easy) (const MapScreen(), const NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'แผนที่')),
      if (canManage) (const MyRequestsScreen(), const NavigationDestination(icon: Icon(Icons.edit_note_outlined), selectedIcon: Icon(Icons.edit_note), label: 'ประกาศของฉัน')),
      (const ProfileScreen(), const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'โปรไฟล์')),
    ];
    if (index >= tabs.length) index = 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ReliefMatch'),
        actions: [
          IconButton(
            tooltip: 'โทร $kHotline',
            icon: const Icon(Icons.phone),
            onPressed: () => openUri(context, telUri(kHotline)),
          ),
        ],
      ),
      body: Column(children: [
        const ConnectionBanner(),
        Expanded(child: tabs[index].$1),
      ]),
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        if (easy) const CallBar(), // One-Tap Emergency Call
        NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (i) => setState(() => index = i),
          destinations: [for (final t in tabs) t.$2],
        ),
      ]),
    );
  }
}

// ───────── Feed ─────────
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});
  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  String? province;
  ItemCategory? cat;

  @override
  Widget build(BuildContext context) {
    final repo = RepoScope.of(context);
    final easy = repo.easyMode;
    final posts = repo.posts
        .where((p) =>
            (province == null || p.province == province) &&
            (cat == null || p.items.any((i) => i.category == cat && !i.done)))
        .toList()
      ..sort((a, b) {
        if (a.fulfilled != b.fulfilled) return a.fulfilled ? 1 : -1;
        final u = b.urgency.index.compareTo(a.urgency.index);
        return u != 0 ? u : a.progress.compareTo(b.progress);
      });

    return RefreshIndicator(
      onRefresh: repo.sync,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.tonalIcon(
            onPressed: () => repo.setEasy(!easy),
            icon: Icon(easy ? Icons.text_decrease : Icons.text_increase),
            label: Text(easy ? 'กลับโหมดปกติ' : 'โหมดตัวอักษรใหญ่ (ผู้สูงอายุ)'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: province,
            isExpanded: true,
            decoration: const InputDecoration(
                border: OutlineInputBorder(), labelText: 'จังหวัด', filled: true, fillColor: Colors.white),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('ทุกจังหวัด')),
              for (final p in kProvinces) DropdownMenuItem<String?>(value: p, child: Text(p)),
            ],
            onChanged: (v) => setState(() => province = v),
          ),
          if (!easy) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final c in ItemCategory.values)
                FilterChip(
                  avatar: Icon(c.icon, size: 18),
                  label: Text(c.label),
                  selected: cat == c,
                  onSelected: (s) => setState(() => cat = s ? c : null),
                ),
            ]),
          ],
          const SizedBox(height: 8),
          if (posts.isEmpty)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('ไม่พบจุดรับบริจาคตามเงื่อนไข')))
          else
            for (final p in posts) PostCard(post: p),
        ],
      ),
    );
  }
}

class PostCard extends StatelessWidget {
  final ReliefPost post;
  const PostCard({super.key, required this.post});

  @override
  Widget build(BuildContext context) {
    final easy = RepoScope.of(context).easyMode;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => PostDetailScreen(postId: post.id))),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text(post.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
              if (post.pendingSync) const Icon(Icons.cloud_upload_outlined, size: 18, color: kAccent),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              StatusBadge(post),
              Text('${post.province} • ${ago(post.updatedAt)}', style: Theme.of(context).textTheme.bodySmall),
            ]),
            const SizedBox(height: 10),
            ProgressBar(value: post.progress, color: shortageColor(post), height: easy ? 16 : 10),
            const SizedBox(height: 4),
            Text('ได้รับแล้ว ${(post.progress * 100).round()}%'),
            const SizedBox(height: 8),
            Wrap(spacing: 14, runSpacing: 6, children: [
              for (final i in post.items)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(i.category.icon, size: easy ? 32 : 20, color: i.done ? kSuccess : kPrimary),
                  const SizedBox(width: 4),
                  Text('${i.received}/${i.target}'),
                ]),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ───────── Post detail ─────────
class PostDetailScreen extends StatefulWidget {
  final String postId;
  const PostDetailScreen({super.key, required this.postId});
  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  bool revealed = false;

  Future<void> _reveal() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันการติดต่อ'),
        content: const Text('เบอร์โทรของผู้ประสานงานจะแสดงเพื่อใช้ติดต่อเรื่องการบริจาคเท่านั้น'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ยืนยัน')),
        ],
      ),
    );
    if (ok == true && mounted) setState(() => revealed = true); // PDPA
  }

  @override
  Widget build(BuildContext context) {
    final repo = RepoScope.of(context);
    final post = repo.posts.where((p) => p.id == widget.postId).firstOrNull;
    if (post == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('ไม่พบประกาศ')));
    }
    final canEdit = repo.canEdit(post);
    return Scaffold(
      appBar: AppBar(title: Text(post.name)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          StatusBadge(post),
          Text('${post.province} • อัปเดต ${ago(post.updatedAt)}'),
        ]),
        const SizedBox(height: 4),
        Text('รหัสอัปเดตทาง SMS: ${post.code}', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        ProgressBar(value: post.progress, color: shortageColor(post), height: 14),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const Icon(Icons.phone_in_talk, color: kPrimary),
                const SizedBox(width: 8),
                Text(revealed ? post.phone : maskPhone(post.phone),
                    style: Theme.of(context).textTheme.titleMedium),
              ]),
              const SizedBox(height: 12),
              if (!revealed)
                FilledButton.icon(
                    onPressed: _reveal,
                    icon: const Icon(Icons.visibility),
                    label: const Text('ยืนยันเพื่อดูเบอร์ติดต่อ'))
              else
                FilledButton.icon(
                    onPressed: () => openUri(context, telUri(post.phone)),
                    icon: const Icon(Icons.call),
                    label: const Text('โทรหาศูนย์นี้')),
              if (post.hasCoords) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                    onPressed: () => openUri(context, mapUri(post)),
                    icon: const Icon(Icons.navigation),
                    label: const Text('นำทางด้วยแผนที่')),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Text('รายการสิ่งของ', style: Theme.of(context).textTheme.titleLarge),
        for (final i in post.items) ItemTile(post: post, item: i, canEdit: canEdit),
      ]),
    );
  }
}

class ItemTile extends StatelessWidget {
  final ReliefPost post;
  final ItemNeed item;
  final bool canEdit;
  const ItemTile({super.key, required this.post, required this.item, required this.canEdit});

  Future<void> _pledge(BuildContext context) async {
    final repo = RepoScope.of(context);
    final q = await showDialog<int>(
        context: context,
        builder: (_) => PledgeDialog(max: item.stillNeeded > 0 ? item.stillNeeded : 1));
    if (q != null) {
      await repo.pledge(post, item, q);
      if (context.mounted) snack(context, 'บันทึกการแจ้งบริจาค $q ชิ้น ขอบคุณครับ');
    }
  }

  @override
  Widget build(BuildContext context) {
    final easy = RepoScope.of(context).easyMode;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(item.category.icon, size: easy ? 40 : 28, color: item.done ? kSuccess : kPrimary),
            const SizedBox(width: 10),
            Expanded(child: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold))),
            Text('${item.received}/${item.target}', style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 8),
          ProgressBar(value: item.progress, color: item.done ? kSuccess : kAccent, height: easy ? 16 : 10),
          const SizedBox(height: 6),
          Text(item.done
              ? 'ได้รับครบแล้ว ✓'
              : 'ยังขาดอีก ${item.target - item.received} • มีผู้แจ้งบริจาคแล้ว ${item.pledged}'),
          const SizedBox(height: 10),
          if (canEdit)
            QtyButtons(post: post, item: item)
          else if (!item.done)
            OutlinedButton.icon(
                onPressed: () => _pledge(context),
                icon: const Icon(Icons.volunteer_activism),
                label: const Text('แจ้งความจำนงบริจาค')),
        ]),
      ),
    );
  }
}

class PledgeDialog extends StatefulWidget {
  final int max;
  const PledgeDialog({super.key, required this.max});
  @override
  State<PledgeDialog> createState() => _PledgeDialogState();
}

class _PledgeDialogState extends State<PledgeDialog> {
  int qty = 1;
  int get step => widget.max >= 100 ? 10 : 1;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('จำนวนที่จะบริจาค'),
        content: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton.filledTonal(
              onPressed: qty > 1 ? () => setState(() => qty = (qty - step).clamp(1, widget.max).toInt()) : null,
              icon: const Icon(Icons.remove)),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('$qty', style: Theme.of(context).textTheme.headlineMedium)),
          IconButton.filledTonal(
              onPressed: qty < widget.max ? () => setState(() => qty = (qty + step).clamp(1, widget.max).toInt()) : null,
              icon: const Icon(Icons.add)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
          FilledButton(onPressed: () => Navigator.pop(context, qty), child: const Text('ยืนยัน')),
        ],
      );
}

// ───────── Map (เวอร์ชันเบา; Google Maps SDK เต็มรูปแบบใน v1.1) ─────────
class MapScreen extends StatelessWidget {
  const MapScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final repo = RepoScope.of(context);
    final groups = <String, List<ReliefPost>>{};
    for (final p in repo.posts) {
      groups.putIfAbsent(p.province, () => []).add(p);
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Card(
          child: Padding(
              padding: EdgeInsets.all(12),
              child: Text('มุมมองพื้นที่: สีบอกระดับความขาดแคลน (ส้ม = ขาดมาก, เขียว = ครบ)\n'
                  'แผนที่ปักหมุดเต็มรูปแบบ (Google Maps SDK) จะเพิ่มใน v1.1'))),
      for (final e in groups.entries) ...[
        Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(e.key, style: Theme.of(context).textTheme.titleMedium)),
        for (final p in e.value)
          Card(
            child: ListTile(
              leading: CircleAvatar(
                  backgroundColor: shortageColor(p),
                  child: Text('${(p.progress * 100).round()}%',
                      style: const TextStyle(color: Colors.white, fontSize: 11))),
              title: Text(p.name),
              subtitle: Text(p.fulfilled ? 'ได้รับครบแล้ว' : 'ยังขาด ${p.itemsMissing} รายการ'),
              trailing: p.hasCoords
                  ? IconButton(
                      icon: const Icon(Icons.navigation, color: kPrimary),
                      onPressed: () => openUri(context, mapUri(p)))
                  : null,
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => PostDetailScreen(postId: p.id))),
            ),
          ),
      ],
    ]);
  }
}

// ───────── My requests ─────────
class MyRequestsScreen extends StatelessWidget {
  const MyRequestsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final repo = RepoScope.of(context);
    final mine = repo.posts.where(repo.canEdit).toList();
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kAccent,
        foregroundColor: Colors.white,
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreatePostScreen())),
        icon: const Icon(Icons.add),
        label: const Text('สร้างประกาศ'),
      ),
      body: mine.isEmpty
          ? const Center(
              child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('ยังไม่มีประกาศของคุณ\nกด "สร้างประกาศ" เพื่อเริ่มต้น', textAlign: TextAlign.center)))
          : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
              for (final p in mine) ...[
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('${p.name}  (${p.code})', style: Theme.of(context).textTheme.titleMedium)),
                for (final i in p.items) ItemTile(post: p, item: i, canEdit: true),
              ],
            ]),
    );
  }
}

class _ItemDraft {
  ItemCategory category = ItemCategory.water;
  final name = TextEditingController();
  final target = TextEditingController();
  void dispose() {
    name.dispose();
    target.dispose();
  }
}

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});
  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _key = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  String _province = kProvinces.first;
  Urgency _urgency = Urgency.urgent;
  final _drafts = [_ItemDraft()];

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _lat.dispose();
    _lng.dispose();
    for (final d in _drafts) {
      d.dispose();
    }
    super.dispose();
  }

  String? _req(String? v) => (v == null || v.trim().isEmpty) ? 'กรุณากรอกข้อมูล' : null;
  String? _num(String? v) => (int.tryParse(v ?? '') ?? 0) <= 0 ? 'ใส่จำนวน > 0' : null;
  String? _coord(String? v) =>
      (v == null || v.trim().isEmpty || double.tryParse(v) != null) ? null : 'ตัวเลขไม่ถูกต้อง';

  Future<void> _submit() async {
    if (!_key.currentState!.validate()) return;
    final repo = RepoScope.of(context);
    final u = repo.user!;
    final owner = u.role == UserRole.coAdmin ? u.linkedOwnerPhone : u.phone;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final post = ReliefPost(
      id: id,
      code: repo.nextCode(),
      name: _name.text.trim(),
      province: _province,
      phone: _phone.text.trim(),
      ownerPhone: owner,
      urgency: _urgency,
      lat: double.tryParse(_lat.text),
      lng: double.tryParse(_lng.text),
      updatedAt: DateTime.now(),
      items: [
        for (var i = 0; i < _drafts.length; i++)
          ItemNeed(
            id: '$id-$i',
            category: _drafts[i].category,
            name: _drafts[i].name.text.trim().isEmpty ? _drafts[i].category.label : _drafts[i].name.text.trim(),
            target: int.parse(_drafts[i].target.text),
          ),
      ],
    );
    await repo.createPost(post);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const border = OutlineInputBorder();
    return Scaffold(
      appBar: AppBar(title: const Text('สร้างประกาศรับบริจาค')),
      body: Form(
        key: _key,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(controller: _name, validator: _req, decoration: const InputDecoration(border: border, labelText: 'ชื่อสถานที่')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _province,
            decoration: const InputDecoration(border: border, labelText: 'จังหวัด'),
            items: [for (final p in kProvinces) DropdownMenuItem(value: p, child: Text(p))],
            onChanged: (v) => setState(() => _province = v!),
          ),
          const SizedBox(height: 12),
          TextFormField(
              controller: _phone,
              validator: _req,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(border: border, labelText: 'เบอร์ติดต่อประสานงาน')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: TextFormField(
                    controller: _lat,
                    validator: _coord,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: const InputDecoration(border: border, labelText: 'ละติจูด (ถ้ามี)'))),
            const SizedBox(width: 8),
            Expanded(
                child: TextFormField(
                    controller: _lng,
                    validator: _coord,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: const InputDecoration(border: border, labelText: 'ลองจิจูด (ถ้ามี)'))),
          ]),
          const SizedBox(height: 12),
          DropdownButtonFormField<Urgency>(
            initialValue: _urgency,
            decoration: const InputDecoration(border: border, labelText: 'ระดับความเร่งด่วน'),
            items: [for (final u in Urgency.values) DropdownMenuItem(value: u, child: Text(u.label))],
            onChanged: (v) => setState(() => _urgency = v!),
          ),
          const SizedBox(height: 20),
          Text('รายการสิ่งของที่ต้องการ', style: Theme.of(context).textTheme.titleMedium),
          for (var i = 0; i < _drafts.length; i++)
            Card(
              key: ValueKey(_drafts[i]),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  DropdownButtonFormField<ItemCategory>(
                    initialValue: _drafts[i].category,
                    decoration: const InputDecoration(border: border, labelText: 'หมวดหมู่'),
                    items: [for (final c in ItemCategory.values) DropdownMenuItem(value: c, child: Text(c.label))],
                    onChanged: (v) => setState(() => _drafts[i].category = v!),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                      controller: _drafts[i].name,
                      decoration: const InputDecoration(border: border, labelText: 'ชื่อรายการ (เช่น น้ำดื่มแพ็ก)')),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                        child: TextFormField(
                            controller: _drafts[i].target,
                            validator: _num,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(border: border, labelText: 'จำนวนที่ต้องการ'))),
                    if (_drafts.length > 1)
                      IconButton(
                          onPressed: () => setState(() => _drafts.removeAt(i).dispose()),
                          icon: const Icon(Icons.delete_outline)),
                  ]),
                ]),
              ),
            ),
          OutlinedButton.icon(
              onPressed: () => setState(() => _drafts.add(_ItemDraft())),
              icon: const Icon(Icons.add),
              label: const Text('เพิ่มรายการสิ่งของ')),
          const SizedBox(height: 16),
          FilledButton(onPressed: _submit, child: const Text('เผยแพร่ประกาศ')),
        ]),
      ),
    );
  }
}

// ───────── Profile ─────────
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _sms = TextEditingController(text: 'RM#SH01#WATER+50');

  @override
  void dispose() {
    _sms.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = RepoScope.of(context);
    final u = repo.user!;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        child: ListTile(
          leading: const CircleAvatar(backgroundColor: kPrimary, child: Icon(Icons.person, color: Colors.white)),
          title: Text(u.name),
          subtitle: Text('${u.role.label}\n${u.phone}'),
          isThreeLine: true,
        ),
      ),
      Card(
        child: Column(children: [
          SwitchListTile(
            secondary: const Icon(Icons.text_increase),
            title: const Text('โหมดผู้สูงอายุ (ตัวอักษรใหญ่)'),
            value: repo.easyMode,
            onChanged: repo.setEasy,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.wifi),
            title: const Text('ออนไลน์ (สวิตช์จำลองสำหรับทดสอบ)'),
            subtitle: Text(repo.lastSync == null ? 'ยังไม่เคยซิงก์' : 'ซิงก์ล่าสุด ${ago(repo.lastSync!)}'),
            value: repo.online,
            onChanged: repo.setOnline,
          ),
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('ซิงก์ตอนนี้'),
            subtitle: Text('รอซิงก์ ${repo.pendingCount} รายการ'),
            onTap: repo.online ? repo.sync : null,
          ),
        ]),
      ),
      if (u.role.canManage)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('อัปเดตยอดผ่าน SMS (จำลอง)', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text('รูปแบบ: RM#รหัสศูนย์#รหัสสิ่งของ+จำนวน\nรหัสสิ่งของ: WATER, FOOD, MED, CLOTH, SHELTER, HYG'),
              const SizedBox(height: 8),
              TextField(controller: _sms, decoration: const InputDecoration(border: OutlineInputBorder())),
              const SizedBox(height: 8),
              FilledButton(
                  onPressed: () => snack(context, repo.applySms(_sms.text)),
                  child: const Text('จำลองรับ SMS เข้าระบบ')),
              const SizedBox(height: 8),
              OutlinedButton(
                  onPressed: () => openUri(
                      context, Uri(scheme: 'sms', path: kSmsGateway, queryParameters: {'body': _sms.text})),
                  child: const Text('เปิดแอป SMS เพื่อส่งไปยังเกตเวย์')),
            ]),
          ),
        ),
      if (u.role == UserRole.requester)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('ให้ลูกหลาน/อสม. ช่วยดูแลแทน: ให้เขาลงทะเบียนเป็น "ผู้ช่วยดูแลแทน" '
                'แล้วกรอกเบอร์ของคุณ (${u.phone}) ในช่อง "เบอร์ของผู้ที่คุณช่วยดูแล"'),
          ),
        ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.phone, color: kAccent),
          title: const Text('โทรศูนย์ประสานงานกลาง'),
          subtitle: const Text(kHotline),
          onTap: () => openUri(context, telUri(kHotline)),
        ),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(onPressed: repo.logout, icon: const Icon(Icons.logout), label: const Text('ออกจากระบบ')),
    ]);
  }
}