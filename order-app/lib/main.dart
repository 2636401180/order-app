import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const OrderApp());

/* ═══════ 配色 ═══════ */
const kG1 = Color(0xFF4F46E5);
const kG2 = Color(0xFF6366F1);
const kG3 = Color(0xFF818CF8);
const kAccent = Color(0xFF5B5FE8);
const kAccentSoft = Color(0xFFECEDFF);
const kAccentDeep = Color(0xFF4338CA);
const kBg = Color(0xFFF4F5FB);
const kInk = Color(0xFF171A23);
const kGrey = Color(0xFF8B91A6);
const kLine = Color(0xFFE5E7F0);

const kProgressList = ['制作中', '初稿', '修改中', '定稿', '交付', '结款'];

/* ═══════ 数据模型 ═══════ */
class Order {
  String id;
  String source;
  String project;
  String type;
  double amount;
  String progress;
  String note;
  bool delivered;
  String paidDate;

  Order({
    required this.id,
    required this.source,
    required this.project,
    required this.type,
    required this.amount,
    required this.progress,
    required this.note,
    required this.delivered,
    required this.paidDate,
  });

  Map<String, dynamic> toJson() => {
        'id': id, 'source': source, 'project': project, 'type': type,
        'amount': amount, 'progress': progress, 'note': note,
        'delivered': delivered, 'paidDate': paidDate,
      };

  factory Order.fromJson(Map<String, dynamic> j) => Order(
        id: j['id']?.toString() ?? '',
        source: j['source']?.toString() ?? '',
        project: j['project']?.toString() ?? '',
        type: j['type']?.toString() ?? '',
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        progress: j['progress']?.toString() ?? '',
        note: j['note']?.toString() ?? '',
        delivered: j['delivered'] == true,
        paidDate: j['paidDate']?.toString() ?? '',
      );
}

/* ═══════ 工具函数 ═══════ */
String fmtMoney(double v) {
  final neg = v < 0;
  final s = v.abs().toStringAsFixed(2);
  final dot = s.indexOf('.');
  final intPart = s.substring(0, dot);
  final decPart = s.substring(dot + 1);
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
    buf.write(intPart[i]);
  }
  var out = buf.toString();
  if (decPart != '00') out += '.' + decPart.replaceAll(RegExp(r'0+$'), '');
  return (neg ? '-' : '') + out;
}

String plainNum(double n) =>
    n == n.truncateToDouble() ? n.toInt().toString() : n.toString();

String ymStr(int offset) {
  final d = DateTime.now();
  final m = DateTime(d.year, d.month + offset, 1);
  return '${m.year}-${m.month.toString().padLeft(2, '0')}';
}

String todayStr() {
  final d = DateTime.now();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/* ═══════ App ═══════ */
class OrderApp extends StatelessWidget {
  const OrderApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '订单记录',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: kBg,
        colorScheme: ColorScheme.fromSeed(seedColor: kAccent),
      ),
      home: const HomePage(),
    );
  }
}

/* ═══════ 主页 ═══════ */
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Order> _orders = [];
  List<String> _channels = ['彼得潘', '风起了'];
  String _filter = '全部';
  int _tab = 0;
  bool _ready = false;

  String? _bgOrdersPath;
  String? _bgIncomePath;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString('orders_v1');
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        _orders = list.map((e) => Order.fromJson(Map<String, dynamic>.from(e))).toList();
      } catch (_) {}
    }
    final rawCh = sp.getString('channels_v1');
    if (rawCh != null) {
      try { _channels = List<String>.from(jsonDecode(rawCh)); } catch (_) {}
    }
    if (_channels.isEmpty) _channels = ['彼得潘', '风起了'];

    _bgOrdersPath = sp.getString('bg_orders');
    _bgIncomePath = sp.getString('bg_income');

    if (mounted) setState(() => _ready = true);
  }

  Future<void> _persist() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('orders_v1', jsonEncode(_orders.map((e) => e.toJson()).toList()));
    await sp.setString('channels_v1', jsonEncode(_channels));
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xEB171A23),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(milliseconds: 1500),
    ));
  }

  /* ─── 统计 ─── */
  double get _pendingAmount =>
      _orders.where((o) => !o.delivered).fold(0.0, (a, b) => a + b.amount);
  int get _doingCount => _orders.where((o) => !o.delivered).length;
  int get _doneCount => _orders.where((o) => o.delivered).length;

  /* ─── 收入 ─── */
  double _yearIncome() {
    final y = DateTime.now().year.toString();
    return _orders
        .where((o) => o.progress == '结款' && o.paidDate.startsWith(y))
        .fold(0.0, (a, b) => a + b.amount);
  }

  double _monthIncome() {
    final ym = ymStr(0);
    return _orders
        .where((o) => o.progress == '结款' && o.paidDate.startsWith(ym))
        .fold(0.0, (a, b) => a + b.amount);
  }

  int _paidCount() => _orders.where((o) => o.progress == '结款' && o.paidDate.isNotEmpty).length;

  Map<String, List<Order>> _incomeGroups() {
    final map = <String, List<Order>>{};
    for (final o in _orders) {
      if (o.progress == '结款' && o.paidDate.isNotEmpty) {
        final ym = o.paidDate.substring(0, 7);
        map.putIfAbsent(ym, () => []).add(o);
      }
    }
    return map;
  }

  /* ═══════ 界面 ═══════ */
  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        backgroundColor: kBg,
        body: Center(child: CircularProgressIndicator(color: kAccent)),
      );
    }
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _tab,
          children: [_buildOrdersPage(), _buildIncomePage()],
        ),
      ),
      floatingActionButton: _tab == 0
          ? FloatingActionButton(
              onPressed: () => _openEditor(null),
              backgroundColor: kAccent,
              child: const Icon(Icons.add, size: 30),
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
        selectedItemColor: kAccent,
        unselectedItemColor: kGrey,
        backgroundColor: Colors.white,
        elevation: 8,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: '订单'),
          BottomNavigationBarItem(icon: Icon(Icons.attach_money), label: '收入'),
        ],
      ),
    );
  }

  /* ─── 订单页 ─── */
  Widget _buildOrdersPage() {
    final visible = _orders
        .where((o) => _filter == '全部' || o.source == _filter)
        .toList()
      ..sort((a, b) {
        if (a.delivered != b.delivered) return a.delivered ? 1 : -1;
        return b.id.compareTo(a.id);
      });

    return Column(
      children: [
        _headerCard(
          title: '待收金额',
          amount: _pendingAmount,
          stat1Label: '进行中',
          stat1Value: '$_doingCount 单',
          stat2Label: '已交付',
          stat2Value: '$_doneCount 单',
          bgPath: _bgOrdersPath,
          onPick: () => _pickBg('bg_orders', true),
          onReset: () => _resetBg('bg_orders', true),
        ),
        _buildTabs(),
        Expanded(
          child: visible.isEmpty
              ? const Center(
                  child: Text('这个渠道下还没有订单\n点右下角 + 添加第一单',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: kGrey, fontSize: 14, height: 1.8)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 100),
                  itemCount: visible.length,
                  itemBuilder: (_, i) => _orderCard(visible[i]),
                ),
        ),
      ],
    );
  }

  /* ─── 收入页 ─── */
  Widget _buildIncomePage() {
    final groups = _incomeGroups();
    final keys = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      children: [
        _headerCard(
          title: '今年总收入',
          amount: _yearIncome(),
          stat1Label: '本月收入',
          stat1Value: '¥${fmtMoney(_monthIncome())}',
          stat2Label: '已结款',
          stat2Value: '${_paidCount()} 单',
          bgPath: _bgIncomePath,
          onPick: () => _pickBg('bg_income', false),
          onReset: () => _resetBg('bg_income', false),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(22, 4, 22, 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('月度明细',
                style: TextStyle(fontSize: 13, color: kGrey, fontWeight: FontWeight.w500)),
          ),
        ),
        Expanded(
          child: keys.isEmpty
              ? const Center(
                  child: Text('还没有结款记录\n把订单进度改成「结款」后这里会显示',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: kGrey, fontSize: 13.5, height: 1.8)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 100),
                  itemCount: keys.length,
                  itemBuilder: (_, i) {
                    final ym = keys[i];
                    final list = groups[ym]!
                      ..sort((a, b) => b.paidDate.compareTo(a.paidDate));
                    final total = list.fold(0.0, (a, b) => a + b.amount);
                    final y = ym.substring(0, 4);
                    final m = int.parse(ym.substring(5, 7));
                    return _monthCard(y, m, list, total);
                  },
                ),
        ),
      ],
    );
  }

  /* ─── 顶部卡片 ─── */
  Widget _headerCard({
    required String title,
    required double amount,
    required String stat1Label,
    required String stat1Value,
    required String stat2Label,
    required String stat2Value,
    required String? bgPath,
    required VoidCallback onPick,
    required VoidCallback onReset,
  }) {
    final hasImg = bgPath != null && File(bgPath).existsSync();
    return GestureDetector(
      onTap: onPick,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        height: 176,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: hasImg
              ? null
              : const LinearGradient(
                  colors: [kG1, kG2, kG3],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          boxShadow: const [
            BoxShadow(color: Color(0x4D4F46E5), blurRadius: 24, offset: Offset(0, 12)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasImg)
              Image.file(File(bgPath!), fit: BoxFit.cover)
            else
              const SizedBox.expand(),
            if (hasImg)
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0x9914103C), Color(0x6640236E), Color(0x4D463C8C)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title,
                      style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                  const SizedBox(height: 4),
                  Text('¥${fmtMoney(amount)}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1)),
                  const SizedBox(height: 12),
                  Container(height: 1, color: Colors.white24),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(stat1Value,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w600)),
                          Text(stat1Label,
                              style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
                        ],
                      ),
                      Container(
                          width: 1,
                          height: 26,
                          color: Colors.white24,
                          margin: const EdgeInsets.symmetric(horizontal: 18)),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(stat2Value,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w600)),
                          Text(stat2Label,
                              style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (!hasImg)
              const Positioned(
                right: 14,
                bottom: 12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0x3D000000),
                    borderRadius: BorderRadius.all(Radius.circular(99)),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    child: Text('点击换背景图',
                        style: TextStyle(color: Colors.white70, fontSize: 10.5)),
                  ),
                ),
              ),
            if (hasImg)
              Positioned(
                right: 12,
                top: 12,
                child: GestureDetector(
                  onTap: onReset,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(
                        color: Color(0x42000000), shape: BoxShape.circle),
                    child: const Icon(Icons.refresh, color: Colors.white, size: 17),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /* ─── 渠道标签 ─── */
  Widget _buildTabs() {
    final items = ['全部', ..._channels];
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        children: [
          for (final n in items) ...[
            _tabChip(n),
            const SizedBox(width: 8),
          ],
          GestureDetector(
            onTap: () => _openChannelDialog(null),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: kLine, style: BorderStyle.solid),
              ),
              child: const Icon(Icons.add, size: 18, color: kGrey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabChip(String name) {
    final active = _filter == name;
    final isAll = name == '全部';
    return GestureDetector(
      onTap: () => setState(() => _filter = name),
      onLongPress: isAll
          ? null
          : () => _openChannelMenu(name),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? kInk : Colors.white,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: active ? kInk : kLine),
        ),
        child: Text(name,
            style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: active ? Colors.white : kGrey)),
      ),
    );
  }

  /* ─── 订单卡片 ─── */
  Widget _orderCard(Order o) {
    final tagClass = _progClass(o.progress);
    return GestureDetector(
      onTap: () => _openEditor(o),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(color: Color(0x0D171A23), blurRadius: 14, offset: Offset(0, 3)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: o.delivered ? const Color(0xFF10B981) : kAccent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(o.project.isEmpty ? '未命名项目' : o.project,
                                style: const TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w600,
                                    color: kInk,
                                    height: 1.35)),
                          ),
                          const SizedBox(width: 10),
                          Text('¥${fmtMoney(o.amount)}',
                              style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: kInk,
                                  letterSpacing: -0.3)),
                        ],
                      ),
                      if (o.note.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Text(o.note,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12.5, color: kGrey, height: 1.45)),
                      ],
                      const SizedBox(height: 11),
                      Row(
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                if (o.type.isNotEmpty) _smallTag(o.type, kGrey, const Color(0xFFF0F1F7)),
                                if (o.progress.isNotEmpty)
                                  _smallTag(o.progress, tagClass.$1, tagClass.$2),
                              ],
                            ),
                          ),
                          if (o.delivered)
                            const Icon(Icons.check_circle,
                                size: 16, color: Color(0xFF10B981)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _smallTag(String text, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }

  (Color, Color) _progClass(String p) {
    switch (p) {
      case '制作中':
      case '初稿':
        return (kAccentDeep, kAccentSoft);
      case '修改中':
        return (const Color(0xFFE08A00), const Color(0xFFFFF4E5));
      case '定稿':
        return (kAccent, kAccentSoft);
      case '交付':
        return (const Color(0xFF0E9F6E), const Color(0xFFE8F8F1));
      case '结款':
        return (const Color(0xFF047857), const Color(0xFFD9F2E6));
      default:
        return (kAccentDeep, kAccentSoft);
    }
  }

  /* ─── 月度卡片 ─── */
  Widget _monthCard(String y, int m, List<Order> list, double total) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: Color(0x0D171A23), blurRadius: 14, offset: Offset(0, 3)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        childrenPadding: EdgeInsets.zero,
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text('$y年$m月',
            style: const TextStyle(
                fontSize: 15.5, fontWeight: FontWeight.w600, color: kInk)),
        subtitle: Text('${list.length} 单已结款',
            style: const TextStyle(fontSize: 12, color: kGrey)),
        trailing: Text('¥${fmtMoney(total)}',
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w700, color: kAccentDeep)),
        children: [
          for (final o in list)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFF0F1F7), style: BorderStyle.solid)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(o.project,
                            style: const TextStyle(
                                fontSize: 13.5, color: kInk, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 2),
                        Text('${o.source} · ${int.parse(o.paidDate.substring(8, 10))}日结款',
                            style: const TextStyle(fontSize: 11.5, color: kGrey)),
                      ],
                    ),
                  ),
                  Text('¥${fmtMoney(o.amount)}',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600, color: kInk)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /* ═══════ 背景图 ═══════ */
  Future<void> _pickBg(String key, bool isOrders) async {
    try {
      final x = await ImagePicker().pickImage(
          source: ImageSource.gallery, maxWidth: 1200, imageQuality: 88);
      if (x == null) return;
      final dir = await getApplicationDocumentsDirectory();
      final dest = '${dir.path}/${key}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(x.path).copy(dest);
      final sp = await SharedPreferences.getInstance();
      await sp.setString(key, dest);
      setState(() {
        if (isOrders) _bgOrdersPath = dest;
        else _bgIncomePath = dest;
      });
      _snack('已更换背景图');
    } catch (e) {
      _snack('选图失败');
    }
  }

  Future<void> _resetBg(String key, bool isOrders) async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(key);
    setState(() {
      if (isOrders) _bgOrdersPath = null;
      else _bgIncomePath = null;
    });
  }

  /* ═══════ 渠道管理 ═══════ */
  Future<void> _openChannelDialog(String? oldName) async {
    final isRename = oldName != null;
    final ctrl = TextEditingController(text: isRename ? oldName : '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(isRename ? '重命名渠道' : '新增渠道',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 12,
          decoration: const InputDecoration(hintText: '例如：朋友圈 / 老客户'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消', style: TextStyle(color: kGrey))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text(isRename ? '确定' : '添加',
                  style: const TextStyle(color: kAccent, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    if (isRename) {
      if (name == oldName) return;
      if (_channels.contains(name)) { _snack('该渠道已存在'); return; }
      final idx = _channels.indexOf(oldName);
      if (idx > -1) _channels[idx] = name;
      for (final o in _orders) { if (o.source == oldName) o.source = name; }
      if (_filter == oldName) _filter = name;
      _snack('已重命名');
    } else {
      if (_channels.contains(name)) { _snack('该渠道已存在'); return; }
      _channels.add(name);
      _filter = name;
      _snack('已添加');
    }
    setState(() {});
    await _persist();
  }

  Future<void> _openChannelMenu(String name) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text('渠道「$name」',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            ListTile(
              leading: const Icon(Icons.edit, color: kAccent),
              title: const Text('重命名'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              tileColor: kAccentSoft,
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
              title: const Text('删除该渠道', style: TextStyle(color: Color(0xFFEF4444))),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              tileColor: const Color(0xFFFEF2F2),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );

    if (action == 'rename') {
      await _openChannelDialog(name);
    } else if (action == 'delete') {
      final used = _orders.where((o) => o.source == name).length;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('删除渠道？',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          content: Text(used > 0
              ? '该渠道下有 $used 条订单，删除渠道不会删订单，订单会归入「未分类」。'
              : '确定删除这个渠道？',
              style: const TextStyle(fontSize: 14, color: kGrey)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消', style: TextStyle(color: kGrey))),
            TextButton(onPressed: () => Navigator.pop(ctx, true),
                child: const Text('删除',
                    style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600))),
          ],
        ),
      );
      if (ok == true) {
        _channels.remove(name);
        for (final o in _orders) { if (o.source == name) o.source = '未分类'; }
        if (_orders.any((o) => o.source == '未分类') && !_channels.contains('未分类')) {
          _channels.add('未分类');
        }
        if (_filter == name) _filter = '全部';
        setState(() {});
        await _persist();
        _snack('已删除渠道');
      }
    }
  }

  /* ═══════ 订单编辑面板 ═══════ */
  Future<void> _openEditor(Order? order) async {
    final isNew = order == null;
    String source = order?.source ?? (_filter != '全部' ? _filter : _channels[0]);
    String progress = order?.progress ?? kProgressList[0];
    bool delivered = order?.delivered ?? false;

    final projectCtrl = TextEditingController(text: order?.project ?? '');
    final typeCtrl = TextEditingController(text: order?.type ?? '');
    final amountCtrl = TextEditingController(
        text: (order == null || order.amount == 0) ? '' : plainNum(order.amount));
    final noteCtrl = TextEditingController(text: order?.note ?? '');
    String paidDate = order?.paidDate ?? '';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx2, setSheet) {
            if (progress == '结款' && paidDate.isEmpty) paidDate = todayStr();
            return Container(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx2).size.height * 0.92),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(ctx2).viewInsets.bottom),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 38, height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE3E6EF),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(isNew ? '新建订单' : '编辑订单',
                          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: kInk)),
                      const SizedBox(height: 20),
                      _label('渠道'),
                      Wrap(
                        spacing: 8, runSpacing: 8,
                        children: [
                          ..._channels.map((c) => _chip(c, source == c, () => setSheet(() => source = c))),
                          GestureDetector(
                            onTap: () async {
                              Navigator.pop(sheetCtx);
                              await _openChannelDialog(null);
                              if (mounted) _openEditor(order);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                              decoration: BoxDecoration(
                                border: Border.all(color: kLine, style: BorderStyle.solid),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text('+ 新渠道',
                                  style: TextStyle(fontSize: 14, color: kGrey)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _label('项目名称'),
                      _input(projectCtrl, '例如：π-PEC体系及新产品介绍'),
                      const SizedBox(height: 18),
                      _label('类型'),
                      _input(typeCtrl, '例如：画册 / 海报 / 修图'),
                      const SizedBox(height: 18),
                      _label('金额（元）'),
                      _input(amountCtrl, '0', keyboard: const TextInputType.numberWithOptions(decimal: true)),
                      const SizedBox(height: 18),
                      _label('进度'),
                      Wrap(
                        spacing: 8, runSpacing: 8,
                        children: kProgressList.map((p) =>
                            _chip(p, progress == p, () {
                              setSheet(() {
                                progress = p;
                                if (p == '结款' && paidDate.isEmpty) paidDate = todayStr();
                              });
                            })).toList(),
                      ),
                      if (progress == '结款') ...[
                        const SizedBox(height: 18),
                        _label('结款日期'),
                        GestureDetector(
                          onTap: () async {
                            final parts = paidDate.split('-').map(int.parse).toList();
                            final picked = await showDatePicker(
                              context: ctx2,
                              initialDate: DateTime(parts[0], parts[1], parts[2]),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setSheet(() {
                                paidDate = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                              });
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8F9FC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: kLine),
                            ),
                            child: Row(
                              children: [
                                Text(paidDate, style: const TextStyle(fontSize: 15.5, color: kInk)),
                                const Spacer(),
                                const Icon(Icons.calendar_today, size: 18, color: kGrey),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      _label('备注'),
                      _input(noteCtrl, '尺寸、页数等'),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F9FC),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Icon(delivered ? Icons.check_circle : Icons.check_circle_outline,
                                size: 20, color: delivered ? const Color(0xFF10B981) : kGrey),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text('标记为已交付',
                                  style: TextStyle(fontSize: 15, color: kInk)),
                            ),
                            Switch(
                              value: delivered,
                              activeColor: Colors.white,
                              activeTrackColor: const Color(0xFF10B981),
                              onChanged: (v) => setSheet(() => delivered = v),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 26),
                      Row(
                        children: [
                          if (!isNew) ...[
                            Expanded(
                              child: TextButton(
                                onPressed: () async {
                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (dctx) => AlertDialog(
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(20)),
                                      title: const Text('删除这条订单？',
                                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                                      content: Text(order!.project,
                                          style: const TextStyle(color: kGrey, fontSize: 14)),
                                      actions: [
                                        TextButton(
                                            onPressed: () => Navigator.pop(dctx, false),
                                            child: const Text('取消', style: TextStyle(color: kGrey))),
                                        TextButton(
                                            onPressed: () => Navigator.pop(dctx, true),
                                            child: const Text('删除',
                                                style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600))),
                                      ],
                                    ),
                                  );
                                  if (ok == true) {
                                    _orders.removeWhere((x) => x.id == order!.id);
                                    await _persist();
                                    if (mounted) setState(() {});
                                    if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                                    _snack('已删除');
                                  }
                                },
                                style: TextButton.styleFrom(
                                  backgroundColor: const Color(0xFFFEF2F2),
                                  foregroundColor: const Color(0xFFEF4444),
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14)),
                                ),
                                child: const Text('删除',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            flex: 2,
                            child: GestureDetector(
                              onTap: () async {
                                final name = projectCtrl.text.trim();
                                if (name.isEmpty) { _snack('请填写项目名称'); return; }
                                final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
                                final pd = progress == '结款' ? (paidDate.isEmpty ? todayStr() : paidDate) : '';

                                if (isNew) {
                                  _orders.add(Order(
                                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                                    source: source,
                                    project: name,
                                    type: typeCtrl.text.trim(),
                                    amount: amount,
                                    progress: progress,
                                    note: noteCtrl.text.trim(),
                                    delivered: delivered,
                                    paidDate: pd,
                                  ));
                                  _snack('已添加');
                                } else {
                                  order!
                                    ..source = source
                                    ..project = name
                                    ..type = typeCtrl.text.trim()
                                    ..amount = amount
                                    ..progress = progress
                                    ..note = noteCtrl.text.trim()
                                    ..delivered = delivered
                                    ..paidDate = pd;
                                  _snack('已保存');
                                }
                                await _persist();
                                if (mounted) setState(() {});
                                if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                              },
                              child: Container(
                                height: 52,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                      colors: [kG1, kG2],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Center(
                                  child: Text('保存',
                                      style: TextStyle(
                                          fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    projectCtrl.dispose();
    typeCtrl.dispose();
    amountCtrl.dispose();
    noteCtrl.dispose();
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: const TextStyle(fontSize: 13, color: kGrey, fontWeight: FontWeight.w500)),
      );

  Widget _chip(String text, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: active ? kAccentSoft : const Color(0xFFF2F3F8),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? kAccent : Colors.transparent, width: 1.5),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 14,
                color: active ? kAccent : const Color(0xFF5A6076),
                fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
      ),
    );
  }

  Widget _input(TextEditingController ctrl, String hint, {TextInputType? keyboard}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboard,
      style: const TextStyle(fontSize: 15.5, color: kInk),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFB4B9C8), fontSize: 15),
        filled: true,
        fillColor: const Color(0xFFF8F9FC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kLine)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kLine)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kAccent, width: 1.5)),
      ),
    );
  }
}