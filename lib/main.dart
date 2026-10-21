import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';

void main() => runApp(const BotIdeApp());

const bg = Color(0xFF0B1020);
const panel = Color(0xFF121A2B);
const panel2 = Color(0xFF192338);
const accent = Color(0xFF62E6B5);
const muted = Color(0xFF9AA8BD);
const border = Color(0xFF253047);

final ValueNotifier<bool> arabicN = ValueNotifier(true);
String tr(String ar, String en) => arabicN.value ? ar : en;

class BotIdeApp extends StatelessWidget {
  const BotIdeApp({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: arabicN,
    builder: (_, ar, __) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Bot IDE',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: const ColorScheme.dark(primary: accent, surface: panel),
        useMaterial3: true,
        fontFamily: 'monospace',
      ),
      builder: (ctx, child) => Directionality(
        textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
        child: MediaQuery.withClampedTextScaling(
          minScaleFactor: 0.85,
          maxScaleFactor: 1.15,
          child: child!,
        ),
      ),
      home: const HomeScreen(),
    ),
  );
}

class BotProject {
  BotProject(this.name, this.path, this.code);
  String name;
  String path;
  String code;
}

Future<Directory> projectDir() async {
  final root = await getApplicationDocumentsDirectory();
  final dir = Directory('${root.path}/bot_ide_projects');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

Future<String?> askText(BuildContext context, String title, String hint, String initial) async {
  final c = TextEditingController(text: initial);
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: panel,
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('إلغاء', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(tr('موافق', 'OK'))),
      ],
    ),
  );
  c.dispose();
  return r;
}

void notify(BuildContext context, String message) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );
}

// ======================= الشاشة الرئيسية =======================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<BotProject> projects = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dir = await projectDir();
    final found = <BotProject>[];
    await for (final e in dir.list()) {
      if (e is File && e.path.toLowerCase().endsWith('.py')) {
        found.add(BotProject(e.uri.pathSegments.last, e.path, await e.readAsString()));
      }
    }
    found.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (!mounted) return;
    setState(() {
      projects..clear()..addAll(found);
      loading = false;
    });
  }

  Future<void> _open(BotProject p) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => BotScreen(project: p)));
    _load();
  }

  Future<void> _newBot() async {
    final name = await askText(context, tr('إنشاء بوت جديد', 'Create a new bot'),
        tr('اسم البوت.py', 'BotName.py'), 'MyBot.py');
    if (name == null || name.isEmpty) return;
    var safe = name.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
    if (!safe.toLowerCase().endsWith('.py')) safe = '$safe.py';
    final dir = await projectDir();
    final file = File('${dir.path}/$safe');
    if (await file.exists()) {
      if (mounted) notify(context, tr('يوجد ملف بهذا الاسم بالفعل', 'A file with that name already exists'));
      return;
    }
    final starter = '# $safe\n'
        '# Keep your bot token private.\n'
        'import telebot\n\n'
        'TOKEN = "PASTE_YOUR_BOT_TOKEN_HERE"\n'
        'bot = telebot.TeleBot(TOKEN)\n\n'
        'bot.infinity_polling()\n';
    await file.writeAsString(starter);
    final p = BotProject(safe, file.path, starter);
    if (!mounted) return;
    await _open(p);
  }

  Future<void> _import() async {
    final result = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['py'], withData: false);
    if (result == null || result.files.single.path == null) return;
    final source = File(result.files.single.path!);
    final dir = await projectDir();
    var filename = result.files.single.name;
    var target = File('${dir.path}/$filename');
    if (await target.exists()) {
      final base = filename.toLowerCase().endsWith('.py')
          ? filename.substring(0, filename.length - 3)
          : filename;
      filename = '${base}_imported.py';
      target = File('${dir.path}/$filename');
    }
    final code = await source.readAsString();
    await target.writeAsString(code);
    if (!mounted) return;
    await _open(BotProject(filename, target.path, code));
  }

  Future<void> _delete(BotProject p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: panel,
        title: Text(tr('حذف البوت', 'Delete bot')),
        content: Text(tr('هل تريد حذف ${p.name} نهائياً؟', 'Delete ${p.name} permanently?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('إلغاء', 'Cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF6B78)),
            child: Text(tr('حذف', 'Delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final f = File(p.path);
    if (await f.exists()) await f.delete();
    _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(children: [
        _topBar(),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : projects.isEmpty
                  ? _empty()
                  : _list(),
        ),
        _bottomBar(),
      ]),
    ),
  );

  Widget _topBar() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: const BoxDecoration(color: panel, border: Border(bottom: BorderSide(color: border))),
    child: Row(children: [
      Container(
        width: 38, height: 38,
        decoration: BoxDecoration(color: accent.withValues(alpha: .13), borderRadius: BorderRadius.circular(11)),
        child: const Icon(Icons.terminal, color: accent),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Bot IDE', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
          Text(tr('بوتاتي', 'MY BOTS'), style: const TextStyle(fontSize: 9, color: muted, letterSpacing: 1)),
        ]),
      ),
      IconButton(
        tooltip: 'العربية / English',
        onPressed: () => arabicN.value = !arabicN.value,
        icon: const Icon(Icons.language),
      ),
      IconButton(
        tooltip: tr('استيراد ملف .py', 'Import .py file'),
        onPressed: _import,
        icon: const Icon(Icons.file_open),
      ),
    ]),
  );

  Widget _empty() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 88, height: 88,
          decoration: BoxDecoration(color: accent.withValues(alpha: .1), borderRadius: BorderRadius.circular(24)),
          child: const Icon(Icons.smart_toy_outlined, color: accent, size: 48),
        ),
        const SizedBox(height: 22),
        Text(tr('مرحباً بك في Bot IDE', 'Welcome to Bot IDE'),
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Text(
          tr('ما عندك بوتات محفوظة حالياً. أنشئ أول بوت وبتلقاه هنا كل مرة تفتح التطبيق.',
              'You have no saved bots yet. Create your first bot and it will appear here.'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted, fontSize: 13, height: 1.6),
        ),
      ]),
    ),
  );

  Widget _list() => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: ListView.separated(
        padding: const EdgeInsets.all(14),
        itemCount: projects.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final p = projects[i];
          final lines = p.code.isEmpty ? 0 : p.code.split('\n').length;
          return Material(
            color: panel,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _open(p),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: border),
                ),
                child: Row(children: [
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(color: accent.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.smart_toy_outlined, color: accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p.name, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 3),
                      Text('$lines ${tr('سطر', 'lines')}', style: const TextStyle(fontSize: 11, color: muted)),
                    ]),
                  ),
                  PopupMenuButton<String>(
                    color: panel2,
                    onSelected: (v) {
                      if (v == 'del') _delete(p);
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'del', child: Text(tr('حذف', 'Delete'))),
                    ],
                  ),
                ]),
              ),
            ),
          );
        },
      ),
    ),
  );

  Widget _bottomBar() => Container(
    padding: const EdgeInsets.all(12),
    decoration: const BoxDecoration(color: panel, border: Border(top: BorderSide(color: border))),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _newBot,
            icon: const Icon(Icons.add),
            label: Text(tr('بوت جديد', 'New bot')),
            style: FilledButton.styleFrom(
              backgroundColor: accent, foregroundColor: bg,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ),
    ),
  );
}

// ======================= شاشة البوت =======================

class BotScreen extends StatefulWidget {
  const BotScreen({super.key, required this.project});
  final BotProject project;
  @override
  State<BotScreen> createState() => _BotScreenState();
}

class _BotScreenState extends State<BotScreen> with SingleTickerProviderStateMixin {
  late final TabController tabs = TabController(length: 4, vsync: this);
  late final TextEditingController editor = TextEditingController(text: widget.project.code);
  final List<String> logs = [];
  bool running = false;

  BotProject get p => widget.project;

  @override
  void dispose() {
    tabs.dispose();
    editor.dispose();
    super.dispose();
  }

  Future<void> _save({bool silent = false}) async {
    await File(p.path).writeAsString(editor.text);
    p.code = editor.text;
    if (silent || !mounted) return;
    setState(() => logs.insert(0, tr('تم حفظ ${p.name}', 'Saved ${p.name}')));
    notify(context, tr('تم الحفظ', 'Saved'));
  }

  void _run() {
    setState(() {
      running = !running;
      logs.insert(
        0,
        running
            ? tr('وضع تجريبي فقط: تشغيل بايثون غير مفعّل بعد.', 'Preview only: Python execution is not enabled yet.')
            : tr('تم إيقاف الوضع التجريبي.', 'Preview stopped.'),
      );
    });
    tabs.animateTo(2);
  }

  // ---------- الأوامر ----------

  List<String> _commands() => RegExp(r'# --- command: /([a-z0-9_]+) ---')
      .allMatches(editor.text)
      .map((m) => m.group(1)!)
      .toList();

  Future<void> _addCommand() async {
    final nameC = TextEditingController();
    final replyC = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: panel,
        title: Text(tr('أمر جديد', 'New command')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: nameC,
              autofocus: true,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(prefixText: '/', hintText: tr('اسم الأمر (مثل start)', 'Command name (e.g. start)')),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: replyC,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(hintText: tr('نص الرد', 'Reply text')),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('إضافة', 'Add'))),
        ],
      ),
    );
    final name = nameC.text.trim().toLowerCase().replaceAll('/', '').replaceAll(RegExp(r'[^a-z0-9_]'), '_');
    final reply = replyC.text.trim();
    nameC.dispose();
    replyC.dispose();
    if (ok != true || name.isEmpty) return;
    if (_commands().contains(name)) {
      if (mounted) notify(context, tr('الأمر موجود بالفعل', 'Command already exists'));
      return;
    }
    final snippet = '# --- command: /$name ---\n'
        "@bot.message_handler(commands=['$name'])\n"
        'def cmd_$name(message):\n'
        '    bot.reply_to(message, ${jsonEncode(reply.isEmpty ? '...' : reply)})\n';
    var code = editor.text;
    const marker = 'bot.infinity_polling()';
    final idx = code.indexOf(marker);
    if (idx >= 0) {
      code = '${code.substring(0, idx)}$snippet\n${code.substring(idx)}';
    } else {
      code = '$code\n$snippet';
    }
    setState(() => editor.text = code);
    await _save(silent: true);
    if (mounted) notify(context, tr('تمت إضافة /$name', 'Added /$name'));
  }

  Future<void> _deleteCommand(String name) async {
    final re = RegExp('# --- command: /$name ---\\n[\\s\\S]*?(?=\\n# --- command:|\\nbot\\.infinity_polling\\(\\)|\$)');
    setState(() => editor.text = editor.text.replaceFirst(re, '').replaceAll(RegExp(r'\n{3,}'), '\n\n'));
    await _save(silent: true);
  }

  // ---------- الواجهة ----------

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      await _save(silent: true);
      if (mounted) Navigator.pop(context);
    },
    child: Scaffold(
      body: SafeArea(
        child: Column(children: [
          _topBar(),
          Container(
            color: panel,
            child: TabBar(
              controller: tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: accent,
              labelColor: Colors.white,
              unselectedLabelColor: muted,
              labelStyle: const TextStyle(fontSize: 12),
              dividerColor: border,
              tabs: [
                Tab(icon: const Icon(Icons.code, size: 16), text: tr('المحرر', 'Editor'), iconMargin: const EdgeInsets.only(bottom: 2)),
                Tab(icon: const Icon(Icons.bolt, size: 16), text: tr('الأوامر', 'Commands'), iconMargin: const EdgeInsets.only(bottom: 2)),
                Tab(icon: const Icon(Icons.terminal, size: 16), text: tr('الطرفية', 'Terminal'), iconMargin: const EdgeInsets.only(bottom: 2)),
                Tab(icon: const Icon(Icons.info_outline, size: 16), text: tr('معلومات', 'Info'), iconMargin: const EdgeInsets.only(bottom: 2)),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: tabs,
              physics: const NeverScrollableScrollPhysics(),
              children: [_editorPane(), _commandsPane(), _terminalPane(), _infoPane()],
            ),
          ),
        ]),
      ),
    ),
  );

  Widget _topBar() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
    decoration: const BoxDecoration(color: panel),
    child: LayoutBuilder(builder: (context, c) {
      final narrow = c.maxWidth < 380;
      return Row(children: [
        IconButton(
          tooltip: tr('رجوع', 'Back'),
          onPressed: () async {
            await _save(silent: true);
            if (mounted) Navigator.pop(context);
          },
          icon: const Icon(Icons.arrow_back),
        ),
        Expanded(
          child: Text(p.name, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        IconButton(tooltip: tr('حفظ', 'Save'), onPressed: _save, icon: const Icon(Icons.save_outlined)),
        if (narrow)
          IconButton.filled(
            onPressed: _run,
            style: IconButton.styleFrom(
              backgroundColor: running ? const Color(0xFFFF6B78) : accent, foregroundColor: bg),
            icon: Icon(running ? Icons.stop : Icons.play_arrow),
          )
        else
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 6),
            child: FilledButton.icon(
              onPressed: _run,
              style: FilledButton.styleFrom(
                backgroundColor: running ? const Color(0xFFFF6B78) : accent, foregroundColor: bg),
              icon: Icon(running ? Icons.stop : Icons.play_arrow, size: 18),
              label: Text(running ? tr('إيقاف', 'Stop') : tr('تشغيل', 'Run')),
            ),
          ),
      ]);
    }),
  );

  Widget _editorPane() => TextField(
    controller: editor,
    expands: true,
    maxLines: null,
    minLines: null,
    textAlignVertical: TextAlignVertical.top,
    textDirection: TextDirection.ltr,
    keyboardType: TextInputType.multiline,
    autocorrect: false,
    enableSuggestions: false,
    style: const TextStyle(fontSize: 13, height: 1.55, color: Color(0xFFDCE7F7)),
    decoration: InputDecoration(
      contentPadding: const EdgeInsets.all(14),
      border: InputBorder.none,
      hintText: tr('# اكتب كود Python هنا...', '# Write Python code here...'),
      hintStyle: const TextStyle(color: Color(0xFF65738A)),
    ),
  );

  Widget _commandsPane() => ListenableBuilder(
    listenable: editor,
    builder: (context, _) {
      final cmds = _commands();
      return Column(children: [
        Expanded(
          child: cmds.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(tr('لا توجد أوامر بعد. اضغط "أمر جديد" لإضافة أول أمر.', 'No commands yet. Tap "New command".'),
                        textAlign: TextAlign.center, style: const TextStyle(color: muted, fontSize: 13)),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: cmds.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
                    child: Row(children: [
                      const Icon(Icons.bolt, size: 18, color: accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('/${cmds[i]}', textDirection: TextDirection.ltr,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      ),
                      IconButton(
                        tooltip: tr('حذف', 'Delete'),
                        onPressed: () => _deleteCommand(cmds[i]),
                        icon: const Icon(Icons.delete_outline, size: 20, color: Color(0xFFFF6B78)),
                      ),
                    ]),
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _addCommand,
              icon: const Icon(Icons.add),
              label: Text(tr('أمر جديد', 'New command')),
              style: FilledButton.styleFrom(
                backgroundColor: accent, foregroundColor: bg, padding: const EdgeInsets.symmetric(vertical: 13)),
            ),
          ),
        ),
      ]);
    },
  );

  Widget _terminalPane() => Container(
    color: const Color(0xFF070B14),
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('الطرفية • المخرجات', 'TERMINAL • OUTPUT'),
          style: const TextStyle(color: accent, fontSize: 11, letterSpacing: 1)),
      const SizedBox(height: 12),
      Expanded(
        child: logs.isEmpty
            ? Text(tr('لا توجد مخرجات حتى الآن.', 'No output yet.'), style: const TextStyle(color: muted, fontSize: 12))
            : ListView.builder(
                itemCount: logs.length,
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('› ${logs[i]}', style: const TextStyle(fontSize: 11, height: 1.4, color: Color(0xFFB7C7D9))),
                ),
              ),
      ),
      Text(tr('تنبيه: تشغيل Python الحقيقي غير مفعّل في هذه النسخة.', 'Note: real Python execution is not enabled in this build.'),
          style: const TextStyle(color: muted, fontSize: 10)),
    ]),
  );

  Widget _infoPane() => ListView(padding: const EdgeInsets.all(16), children: [
    const Align(alignment: AlignmentDirectional.centerStart, child: Icon(Icons.smart_toy_outlined, size: 42, color: accent)),
    const SizedBox(height: 12),
    Text(p.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    const SizedBox(height: 12),
    _infoRow(tr('نوع الملف', 'File type'), '.py'),
    _infoRow(tr('الحفظ على الجهاز', 'Saved locally'), tr('نعم', 'Yes')),
    _infoRow(tr('محرك Python', 'Python runtime'), tr('غير مضاف', 'Not connected')),
    _infoRow(tr('حالة تيليجرام', 'Telegram status'), tr('لم يتم التحقق', 'Not checked')),
    const SizedBox(height: 14),
    Text(
      tr('هذه النسخة تحفظ وتحرر ملفات البوتات، لكن يلزم إضافة محرك Python لأندرويد حتى يعمل زر التشغيل فعلياً.',
          'This build saves and edits bot files, but an Android Python runtime is required for the Run button to execute code.'),
      style: const TextStyle(color: muted, fontSize: 12, height: 1.5),
    ),
    const SizedBox(height: 12),
    Text(
      tr('الأمان: لا تشارك رمز البوت. إذا انكشف، أنشئ رمزاً جديداً من BotFather.',
          'Security: never share your bot token. If exposed, regenerate it using BotFather.'),
      style: const TextStyle(color: Color(0xFFFFC857), fontSize: 12, height: 1.5),
    ),
  ]);

  Widget _infoRow(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(vertical: 11),
    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: border))),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(color: muted, fontSize: 12))),
      Text(value, style: const TextStyle(fontSize: 12)),
    ]),
  );
}