import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

const Color qaraBg = Color(0xFF080D18);
const Color qaraPanel = Color(0xFF111A2B);
const Color qaraCard = Color(0xFF172238);
const Color qaraMint = Color(0xFF54E0C0);
const Color qaraBlue = Color(0xFF78A9FF);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await QaraStore.instance.initialize();
  runApp(const QaraApp());
}

class QaraApp extends StatelessWidget {
  const QaraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'قەرە',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: qaraBg,
        colorScheme: const ColorScheme.dark(
          primary: qaraMint,
          secondary: qaraBlue,
          surface: qaraPanel,
        ),
        textTheme: GoogleFonts.notoSansArabicTextTheme(
          ThemeData.dark().textTheme,
        ),
        useMaterial3: true,
        snackBarTheme: SnackBarThemeData(
          backgroundColor: qaraCard,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: qaraCard,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.white.withOpacity(.06)),
          ),
        ),
      ),
      home: const QaraHomePage(),
    );
  }
}

enum ProviderKind { gemini, openai, compatible }

class QaraProvider {
  final String id;
  String name;
  ProviderKind kind;
  String endpoint;
  String model;
  String apiKey;
  bool enabled;

  QaraProvider({
    required this.id,
    required this.name,
    required this.kind,
    required this.endpoint,
    required this.model,
    required this.apiKey,
    this.enabled = true,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'kind': kind.name, 'endpoint': endpoint,
    'model': model, 'enabled': enabled,
  };

  factory QaraProvider.fromJson(Map<String, dynamic> json, String key) {
    final kindName = json['kind']?.toString() ?? 'gemini';
    return QaraProvider(
      id: json['id']?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: json['name']?.toString() ?? 'Gemini',
      kind: ProviderKind.values.firstWhere(
        (e) => e.name == kindName,
        orElse: () => ProviderKind.compatible,
      ),
      endpoint: json['endpoint']?.toString() ?? '',
      model: json['model']?.toString() ?? '',
      apiKey: key,
      enabled: json['enabled'] != false,
    );
  }

  QaraProvider copy() => QaraProvider(
    id: id, name: name, kind: kind, endpoint: endpoint,
    model: model, apiKey: apiKey, enabled: enabled,
  );
}

class QaraMessage {
  final String role;
  final String text;
  final DateTime createdAt;
  QaraMessage(this.role, this.text, this.createdAt);

  Map<String, dynamic> toJson() => {
    'role': role, 'text': text, 'createdAt': createdAt.toIso8601String(),
  };

  factory QaraMessage.fromJson(Map<String, dynamic> json) => QaraMessage(
    json['role']?.toString() ?? 'assistant',
    json['text']?.toString() ?? '',
    DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
  );
}

class QaraStore {
  QaraStore._();
  static final QaraStore instance = QaraStore._();
  static const FlutterSecureStorage _secure = FlutterSecureStorage();
  late SharedPreferences _prefs;
  final List<QaraProvider> providers = [];
  final List<QaraMessage> messages = [];
  String memory = '';
  String activeProviderId = '';
  bool autoSpeak = true;

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    memory = _prefs.getString('qara_memory') ?? '';
    activeProviderId = _prefs.getString('qara_active_provider') ?? '';
    autoSpeak = _prefs.getBool('qara_auto_speak') ?? true;

    final rawProviders = _prefs.getString('qara_providers');
    if (rawProviders != null) {
      try {
        final List decoded = jsonDecode(rawProviders);
        for (final item in decoded) {
          final map = Map<String, dynamic>.from(item);
          final id = map['id']?.toString() ?? '';
          final secret = await _secure.read(key: 'qara_api_$id') ?? '';
          providers.add(QaraProvider.fromJson(map, secret));
        }
      } catch (_) {
        providers.clear();
      }
    }

    if (providers.isEmpty) {
      providers.add(QaraProvider(
        id: 'gemini-default',
        name: 'Google Gemini',
        kind: ProviderKind.gemini,
        endpoint: 'https://generativelanguage.googleapis.com/v1beta',
        model: 'gemini-2.5-flash',
        apiKey: '',
      ));
      providers.add(QaraProvider(
        id: 'openai-default',
        name: 'OpenAI',
        kind: ProviderKind.openai,
        endpoint: 'https://api.openai.com/v1',
        model: 'gpt-4o-mini',
        apiKey: '',
      ));
    }

    if (activeProviderId.isEmpty ||
        !providers.any((p) => p.id == activeProviderId)) {
      activeProviderId = providers.first.id;
    }

    final rawMessages = _prefs.getString('qara_history');
    if (rawMessages != null) {
      try {
        final List decoded = jsonDecode(rawMessages);
        messages.addAll(decoded.map((e) =>
          QaraMessage.fromJson(Map<String, dynamic>.from(e))));
      } catch (_) {
        messages.clear();
      }
    }
    if (messages.isEmpty) {
      messages.add(QaraMessage(
        'assistant',
        'سڵاو! من قەرەم. بە کوردیی سۆرانی لەگەڵت قسە دەکەم. دەتوانیت Gemini یان OpenAI هەڵبژێریت و بە دەنگیش بانگم بکەیت.',
        DateTime.now(),
      ));
    }
  }

  QaraProvider get activeProvider =>
      providers.firstWhere((p) => p.id == activeProviderId,
        orElse: () => providers.first);

  Future<void> saveProviders() async {
    await _prefs.setString('qara_providers',
      jsonEncode(providers.map((p) => p.toJson()).toList()));
    await _prefs.setString('qara_active_provider', activeProviderId);
    for (final p in providers) {
      await _secure.write(key: 'qara_api_${p.id}', value: p.apiKey);
    }
  }

  Future<void> saveHistory() async {
    final recent = messages.length > 120
      ? messages.sublist(messages.length - 120) : messages;
    await _prefs.setString('qara_history',
      jsonEncode(recent.map((m) => m.toJson()).toList()));
  }

  Future<void> saveMemory(String value) async {
    memory = value.trim();
    await _prefs.setString('qara_memory', memory);
  }

  Future<void> saveAutoSpeak() async {
    await _prefs.setBool('qara_auto_speak', autoSpeak);
  }
}

class QaraAiService {
  static const Duration timeout = Duration(seconds: 45);

  Future<String> reply({
    required QaraProvider provider,
    required List<QaraMessage> history,
    required String memory,
  }) async {
    if (provider.apiKey.trim().isEmpty) {
      throw Exception('API Key ـی ${provider.name} دابنێ.');
    }
    if (provider.model.trim().isEmpty) {
      throw Exception('ناوی Model دیاری بکە.');
    }
    if (provider.kind == ProviderKind.gemini) {
      return _gemini(provider, history, memory);
    }
    return _openAi(provider, history, memory);
  }

  String _systemPrompt(String memory) {
    return '''
تۆ قەرەیت، یاریدەدەری زیرەکی دەستکردی بەکارهێنەر.
- بە کوردیی سۆرانیی سروشتی و ڕوون وەڵام بدەرەوە، مەگەر بەکارهێنەر داوای زمانێکی تر بکات.
- وەک هاوڕێیەکی زیرەک و ڕێزدار قسە بکە؛ زانیاری نادروست دروست مەکە.
- ئەگەر دڵنیا نیت، بە ڕاستی بڵێ.
- وەڵامەکان بەپێی پرسیارەکە قەبارەیان بێت.
- دەنگی وەڵامەکان دەخوێندرێتەوە، بۆیە شێوەی قسەکردن سروشتی بێت.
- زانیارییەکانی بیرگەی بەکارهێنەر تەنها بۆ یارمەتیدان بەکاربهێنە و نهێنییان بپارێزە.
بیرگەی بەکارهێنەر:
${memory.isEmpty ? 'هیچ زانیارییەکی تایبەت تۆمار نەکراوە.' : memory}
''';
  }

  Future<String> _gemini(
    QaraProvider p, List<QaraMessage> history, String memory) async {
    final base = p.endpoint.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse(
      '$base/models/${Uri.encodeComponent(p.model.trim())}:generateContent',
    ).replace(queryParameters: {'key': p.apiKey.trim()});
    final recentHistory = history.length > 24
        ? history.sublist(history.length - 24)
        : history;
    final contents = recentHistory.map((m) => {
      'role': m.role == 'user' ? 'user' : 'model',
      'parts': [{'text': m.text}],
    }).toList();

    final response = await http.post(uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'systemInstruction': {'parts': [{'text': _systemPrompt(memory)}]},
        'contents': contents,
        'generationConfig': {
          'temperature': 0.75,
          'topP': 0.92,
          'maxOutputTokens': 2048,
        },
      }),
    ).timeout(timeout);

    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_apiError(response.statusCode, data));
    }
    final candidates = data['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception('Gemini وەڵامێکی بەتاڵی گەڕاندەوە.');
    }
    final parts = candidates.first['content']?['parts'] as List? ?? [];
    final text = parts.where((x) => x['text'] != null)
      .map((x) => x['text'].toString()).join('\n').trim();
    if (text.isEmpty) throw Exception('وەڵامی Gemini بەتاڵ بوو.');
    return text;
  }

  Future<String> _openAi(
    QaraProvider p, List<QaraMessage> history, String memory) async {
    final base = p.endpoint.trim().replaceAll(RegExp(r'/+$'), '');
    final endpoint = base.endsWith('/chat/completions')
      ? base : '$base/chat/completions';
    final uri = Uri.parse(endpoint);
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': _systemPrompt(memory)},
      ...((history.length > 24
          ? history.sublist(history.length - 24)
          : history).map((m) => {
        'role': m.role == 'user' ? 'user' : 'assistant',
        'content': m.text,
      }),
    ];
    final response = await http.post(uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${p.apiKey.trim()}',
      },
      body: jsonEncode({
        'model': p.model.trim(),
        'messages': messages,
        'temperature': 0.75,
        'max_tokens': 2048,
      }),
    ).timeout(timeout);

    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_apiError(response.statusCode, data));
    }
    final choices = data['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw Exception('OpenAI وەڵامێکی بەتاڵی گەڕاندەوە.');
    }
    final answer = choices.first['message']?['content']?.toString().trim() ?? '';
    if (answer.isEmpty) throw Exception('وەڵامی OpenAI بەتاڵ بوو.');
    return answer;
  }

  Future<List<String>> listModels(QaraProvider p) async {
    if (p.apiKey.trim().isEmpty) throw Exception('سەرەتا API Key دابنێ.');
    final base = p.endpoint.trim().replaceAll(RegExp(r'/+$'), '');
    late Uri uri;
    late Map<String, String> headers;
    if (p.kind == ProviderKind.gemini) {
      uri = Uri.parse('$base/models')
        .replace(queryParameters: {'key': p.apiKey.trim()});
      headers = {};
    } else {
      final root = base.endsWith('/chat/completions')
        ? base.replaceAll('/chat/completions', '') : base;
      uri = Uri.parse('$root/models');
      headers = {'Authorization': 'Bearer ${p.apiKey.trim()}'};
    }
    final response = await http.get(uri, headers: headers).timeout(timeout);
    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_apiError(response.statusCode, data));
    }
    final raw = (data['models'] ?? data['data']) as List? ?? [];
    final names = <String>[];
    for (final item in raw) {
      var name = item['name']?.toString() ?? item['id']?.toString() ?? '';
      if (name.startsWith('models/')) name = name.substring(7);
      if (name.isNotEmpty) names.add(name);
    }
    names.sort();
    return names;
  }

  Map<String, dynamic> _decode(http.Response response) {
    try {
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      if (value is Map<String, dynamic>) return value;
      return {'data': value};
    } catch (_) {
      return {'message': response.body};
    }
  }

  String _apiError(int code, Map<String, dynamic> data) {
    final message = data['error'] is Map
      ? data['error']['message']?.toString()
      : data['message']?.toString();
    if (code == 401 || code == 403) {
      return 'API Key نادروستە یان مۆڵەت نییە. ($code) ${message ?? ''}';
    }
    if (code == 404) return 'Endpoint یان Model نەدۆزرایەوە. ($code) ${message ?? ''}';
    if (code == 429) return 'سنووری بەکارهێنان تەواو بوو. کەمێک چاوەڕێ بکە. ${message ?? ''}';
    return 'هەڵەی API ($code): ${message ?? 'هەڵەی نەناسراو'}';
  }
}

class QaraNative {
  static const MethodChannel _channel = MethodChannel('qara/native');
  static Future<bool> startWakeService() async {
    return await _channel.invokeMethod<bool>('startWakeService') ?? false;
  }
  static Future<bool> stopWakeService() async {
    return await _channel.invokeMethod<bool>('stopWakeService') ?? false;
  }
  static Future<bool> isWakeServiceRunning() async {
    return await _channel.invokeMethod<bool>('isWakeServiceRunning') ?? false;
  }
}

class QaraHomePage extends StatefulWidget {
  const QaraHomePage({super.key});
  @override
  State<QaraHomePage> createState() => _QaraHomePageState();
}

class _QaraHomePageState extends State<QaraHomePage> {
  final QaraStore store = QaraStore.instance;
  final QaraAiService ai = QaraAiService();
  final TextEditingController input = TextEditingController();
  final ScrollController scroll = ScrollController();
  final FlutterTts tts = FlutterTts();
  final stt.SpeechToText speech = stt.SpeechToText();
  bool thinking = false;
  bool listening = false;
  bool wakeEnabled = false;
  bool speaking = false;

  @override
  void initState() {
    super.initState();
    _setupVoice();
    _checkWakeService();
  }

  Future<void> _setupVoice() async {
    await tts.setSpeechRate(0.88);
    await tts.setPitch(1.0);
    await tts.setVolume(1.0);
    tts.setStartHandler(() { if (mounted) setState(() => speaking = true); });
    tts.setCompletionHandler(() { if (mounted) setState(() => speaking = false); });
    tts.setErrorHandler((_) { if (mounted) setState(() => speaking = false); });
    final languages = await tts.getLanguages;
    if (languages is List) {
      if (languages.contains('ckb-IQ')) {
        await tts.setLanguage('ckb-IQ');
      } else if (languages.contains('ar-IQ')) {
        await tts.setLanguage('ar-IQ');
      }
    }
  }

  Future<void> _checkWakeService() async {
    try {
      final value = await QaraNative.isWakeServiceRunning();
      if (mounted) setState(() => wakeEnabled = value);
    } catch (_) {}
  }

  Future<void> _speak(String text) async {
    if (!store.autoSpeak || text.trim().isEmpty) return;
    await tts.stop();
    await tts.speak(text);
  }

  Future<void> _stopSpeak() async {
    await tts.stop();
    if (mounted) setState(() => speaking = false);
  }

  Future<void> _toggleWake() async {
    if (wakeEnabled) {
      await QaraNative.stopWakeService();
      if (mounted) setState(() => wakeEnabled = false);
      _toast('گوێگرتنی پاشبنەما وەستا.');
      return;
    }
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      _toast('مۆڵەتی مایکرۆفۆن پێویستە.');
      return;
    }
    final notification = await Permission.notification.request();
    if (!notification.isGranted) {
      _toast('بۆ نیشاندانی ئاگادارکردنەوە مۆڵەت پێویستە.');
      return;
    }
    try {
      final started = await QaraNative.startWakeService();
      if (mounted) setState(() => wakeEnabled = started);
      _toast(started
        ? 'قەرە لە پاشبنەما گوێ دەگرێت. وشەی بانگکردن: قەرە.'
        : 'نەتوانرا خزمەتگوزاری دەنگ چالاک بکرێت.');
    } on PlatformException catch (e) {
      _toast('هەڵە: ${e.message ?? e.code}');
    }
  }

  Future<void> _toggleMic() async {
    if (listening) {
      await speech.stop();
      if (mounted) setState(() => listening = false);
      return;
    }
    await _stopSpeak();
    final permission = await Permission.microphone.request();
    if (!permission.isGranted) {
      _toast('مۆڵەتی مایکرۆفۆن پێویستە.');
      return;
    }
    final available = await speech.initialize(
      onError: (error) {
        if (mounted) setState(() => listening = false);
        _toast('هەڵەی ناسینەوەی دەنگ: ${error.errorMsg}');
      },
    );
    if (!available) {
      _toast('سیستەمی ناسینەوەی دەنگ لەم مۆبایلەدا بەردەست نییە.');
      return;
    }
    setState(() => listening = true);
    await speech.listen(
      localeId: 'ar_IQ',
      listenFor: const Duration(seconds: 45),
      pauseFor: const Duration(seconds: 3),
      onResult: (result) {
        if (result.finalResult && result.recognizedWords.trim().isNotEmpty) {
          final words = result.recognizedWords.trim();
          if (mounted) setState(() => listening = false);
          _send(words);
        }
      },
    );
  }

  Future<void> _send([String? value]) async {
    final text = (value ?? input.text).trim();
    if (text.isEmpty || thinking) return;
    await _stopSpeak();
    input.clear();
    setState(() {
      store.messages.add(QaraMessage('user', text, DateTime.now()));
      thinking = true;
    });
    await store.saveHistory();
    _toBottom();
    try {
      final answer = await ai.reply(
        provider: store.activeProvider,
        history: store.messages,
        memory: store.memory,
      );
      if (!mounted) return;
      setState(() {
        thinking = false;
        store.messages.add(QaraMessage('assistant', answer, DateTime.now()));
      });
      await store.saveHistory();
      _toBottom();
      await _speak(answer);
    } catch (e) {
      if (!mounted) return;
      final error = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        thinking = false;
        store.messages.add(QaraMessage('assistant', 'ببورە، کێشەیەک ڕوویدا: $error', DateTime.now()));
      });
      await store.saveHistory();
      _toBottom();
    }
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) {
        scroll.animateTo(scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
      }
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showMemory() {
    final controller = TextEditingController(text: store.memory);
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: qaraPanel,
      title: const Text('بیرگەی قەرە'),
      content: SizedBox(width: 420, child: TextField(
        controller: controller, minLines: 4, maxLines: 9,
        decoration: const InputDecoration(
          hintText: 'زانیارییە گرنگەکان بنووسە کە دەتەوێت قەرە لەبیر بگرێت...',
        ),
      )),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('داخستن')),
        FilledButton(onPressed: () async {
          await store.saveMemory(controller.text);
          if (ctx.mounted) Navigator.pop(ctx);
          if (mounted) setState(() {});
        }, child: const Text('پاشەکەوت')),
      ],
    ));
  }

  void _showProviderSettings() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => QaraSettingsPage(onChanged: () {
        if (mounted) setState(() {});
      }),
    ));
  }

  Future<void> _clearChat() async {
    final yes = await showDialog<bool>(context: context, builder: (ctx) =>
      AlertDialog(
        backgroundColor: qaraPanel,
        title: const Text('سڕینەوەی گفتوگۆ؟'),
        content: const Text('هەموو مێژووی گفتوگۆ لەم مۆبایلە دەسڕدرێتەوە.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('نەخێر')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('بسڕەوە')),
        ],
      ));
    if (yes == true) {
      store.messages.clear();
      store.messages.add(QaraMessage('assistant', 'سڵاو، من قەرەم. چۆن یارمەتیت بدەم؟', DateTime.now()));
      await store.saveHistory();
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    tts.stop();
    speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = store.activeProvider;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: qaraBg,
        titleSpacing: 16,
        title: Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [qaraMint, qaraBlue]),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.graphic_eq_rounded, color: qaraBg, size: 25),
          ),
          const SizedBox(width: 11),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('قەرە', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
            Text('${active.name} • ${active.model}',
              style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(.55))),
          ]),
        ]),
        actions: [
          IconButton(tooltip: 'بیرگە', onPressed: _showMemory, icon: const Icon(Icons.psychology_alt_outlined)),
          IconButton(
            tooltip: wakeEnabled ? 'وەستاندنی گوێگرتنی پاشبنەما' : 'چالاککردنی گوێگرتنی پاشبنەما',
            onPressed: _toggleWake,
            icon: Icon(wakeEnabled ? Icons.hearing : Icons.hearing_disabled,
              color: wakeEnabled ? qaraMint : null),
          ),
          PopupMenuButton<String>(
            color: qaraPanel,
            onSelected: (v) {
              if (v == 'settings') _showProviderSettings();
              if (v == 'clear') _clearChat();
              if (v == 'voice') {
                setState(() => store.autoSpeak = !store.autoSpeak);
                store.saveAutoSpeak();
                if (!store.autoSpeak) _stopSpeak();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'settings', child: Text('API و Model')),
              PopupMenuItem(value: 'voice', child: Text(store.autoSpeak ? 'دەنگ: چالاک' : 'دەنگ: ناچالاک')),
              const PopupMenuItem(value: 'clear', child: Text('پاککردنەوەی گفتوگۆ')),
            ],
          ),
        ],
      ),
      body: Column(children: [
        if (wakeEnabled)
          Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              color: qaraMint.withOpacity(.09),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: qaraMint.withOpacity(.25)),
            ),
            child: const Row(children: [
              Icon(Icons.hearing, color: qaraMint, size: 18),
              SizedBox(width: 8),
              Expanded(child: Text('قەرە لە پاشبنەما چالاکە • وشەی بانگکردن: قەرە',
                style: TextStyle(fontSize: 12))),
              Icon(Icons.circle, color: qaraMint, size: 8),
            ]),
          ),
        Expanded(
          child: ListView.builder(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
            itemCount: store.messages.length + (thinking ? 1 : 0),
            itemBuilder: (context, index) {
              if (thinking && index == store.messages.length) {
                return const _ThinkingBubble();
              }
              final message = store.messages[index];
              return _MessageBubble(
                message: message,
                onSpeak: () => _speak(message.text),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: BoxDecoration(
              color: qaraPanel,
              border: Border(top: BorderSide(color: Colors.white.withOpacity(.06))),
            ),
            child: Row(children: [
              _RoundAction(
                icon: listening ? Icons.stop_rounded : Icons.mic_rounded,
                color: listening ? Colors.redAccent : qaraMint,
                onTap: _toggleMic,
              ),
              const SizedBox(width: 9),
              Expanded(child: TextField(
                controller: input,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'بە قەرە بڵێ یان بنووسە...',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 17, vertical: 13),
                  suffixIcon: speaking ? IconButton(
                    onPressed: _stopSpeak, icon: const Icon(Icons.volume_off)) : null,
                ),
              )),
              const SizedBox(width: 9),
              _RoundAction(icon: Icons.arrow_upward_rounded,
                color: qaraBlue, onTap: thinking ? null : _send),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _RoundAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  const _RoundAction({required this.icon, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
    color: color.withOpacity(.13),
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: SizedBox(width: 48, height: 48,
        child: Icon(icon, color: color, size: 23)),
    ),
  );
}

class _MessageBubble extends StatelessWidget {
  final QaraMessage message;
  final VoidCallback onSpeak;
  const _MessageBubble({required this.message, required this.onSpeak});
  @override
  Widget build(BuildContext context) {
    final user = message.role == 'user';
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .88),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.fromLTRB(14, 11, 12, 9),
        decoration: BoxDecoration(
          color: user ? const Color(0xFF234B70) : qaraCard,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(user ? 18 : 5),
            bottomRight: Radius.circular(user ? 5 : 18),
          ),
          border: Border.all(color: Colors.white.withOpacity(.045)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!user)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(children: [
                const Icon(Icons.auto_awesome, color: qaraMint, size: 14),
                const SizedBox(width: 5),
                const Text('قەرە', style: TextStyle(color: qaraMint, fontSize: 11, fontWeight: FontWeight.bold)),
                const Spacer(),
                InkWell(onTap: onSpeak, child: const Icon(Icons.volume_up_outlined, size: 17, color: Colors.white54)),
              ]),
            ),
          if (user)
            Text(message.text, style: const TextStyle(fontSize: 15, height: 1.55))
          else
            MarkdownBody(
              data: message.text,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(fontSize: 15, height: 1.6, color: Colors.white),
                code: const TextStyle(color: qaraMint, backgroundColor: qaraBg),
                h1: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                h2: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.bottomLeft,
            child: Text(
              '${message.createdAt.hour.toString().padLeft(2, '0')}:${message.createdAt.minute.toString().padLeft(2, '0')}',
              style: TextStyle(fontSize: 9, color: Colors.white.withOpacity(.35)),
            ),
          ),
        ]),
      ),
    );
  }
}

class _ThinkingBubble extends StatefulWidget {
  const _ThinkingBubble();
  @override
  State<_ThinkingBubble> createState() => _ThinkingBubbleState();
}
class _ThinkingBubbleState extends State<_ThinkingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 950))..repeat();
  @override
  void dispose() { controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 7),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(color: qaraCard, borderRadius: BorderRadius.circular(18)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.auto_awesome, color: qaraMint, size: 16),
        const SizedBox(width: 9),
        const Text('قەرە بیر دەکاتەوە...'),
        const SizedBox(width: 8),
        SizedBox(width: 17, height: 17, child: CircularProgressIndicator(
          strokeWidth: 2, valueColor: const AlwaysStoppedAnimation(qaraMint),
          value: controller.value,
        )),
      ]),
    ),
  );
}

class QaraSettingsPage extends StatefulWidget {
  final VoidCallback onChanged;
  const QaraSettingsPage({super.key, required this.onChanged});
  @override
  State<QaraSettingsPage> createState() => _QaraSettingsPageState();
}

class _QaraSettingsPageState extends State<QaraSettingsPage> {
  final store = QaraStore.instance;
  final service = QaraAiService();
  bool loadingModels = false;

  Future<void> _editProvider([QaraProvider? existing]) async {
    final provider = existing?.copy() ?? QaraProvider(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: 'AI Provider',
      kind: ProviderKind.gemini,
      endpoint: 'https://generativelanguage.googleapis.com/v1beta',
      model: 'gemini-2.5-flash',
      apiKey: '',
    );
    final name = TextEditingController(text: provider.name);
    final endpoint = TextEditingController(text: provider.endpoint);
    final model = TextEditingController(text: provider.model);
    final key = TextEditingController(text: provider.apiKey);
    final result = await showDialog<bool>(context: context, builder: (ctx) =>
      StatefulBuilder(builder: (ctx, setDialog) => AlertDialog(
        backgroundColor: qaraPanel,
        title: Text(existing == null ? 'زیادکردنی Provider' : 'دەستکاریکردنی Provider'),
        content: SizedBox(width: 450, child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<ProviderKind>(
              value: provider.kind,
              decoration: const InputDecoration(labelText: 'جۆری API'),
              items: const [
                DropdownMenuItem(value: ProviderKind.gemini, child: Text('Google Gemini')),
                DropdownMenuItem(value: ProviderKind.openai, child: Text('OpenAI')),
                DropdownMenuItem(value: ProviderKind.compatible, child: Text('OpenAI-compatible')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setDialog(() {
                  provider.kind = value;
                  if (value == ProviderKind.gemini) {
                    endpoint.text = 'https://generativelanguage.googleapis.com/v1beta';
                    if (model.text.isEmpty) model.text = 'gemini-2.5-flash';
                  } else if (value == ProviderKind.openai) {
                    endpoint.text = 'https://api.openai.com/v1';
                    if (model.text.isEmpty) model.text = 'gpt-4o-mini';
                  }
                });
              },
            ),
            const SizedBox(height: 12),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'ناوی Provider')),
            const SizedBox(height: 12),
            TextField(controller: endpoint, decoration: const InputDecoration(
              labelText: 'API Endpoint',
              hintText: 'https://api.openai.com/v1',
            )),
            const SizedBox(height: 12),
            TextField(controller: model, decoration: const InputDecoration(labelText: 'Model ID')),
            const SizedBox(height: 12),
            TextField(controller: key, obscureText: true, decoration: const InputDecoration(
              labelText: 'API Key', helperText: 'بە شێوەی پارێزراو لە مۆبایل هەڵدەگیرێت.',
            )),
          ],
        ))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('پاشگەزبوونەوە')),
          FilledButton(onPressed: () {
            provider.name = name.text.trim();
            provider.endpoint = endpoint.text.trim();
            provider.model = model.text.trim();
            provider.apiKey = key.text.trim();
            if (provider.name.isEmpty || provider.endpoint.isEmpty || provider.model.isEmpty) return;
            Navigator.pop(ctx, true);
          }, child: const Text('پاشەکەوت')),
        ],
      )));
    if (result == true) {
      if (existing == null) {
        store.providers.add(provider);
      } else {
        final index = store.providers.indexWhere((p) => p.id == provider.id);
        if (index >= 0) store.providers[index] = provider;
      }
      await store.saveProviders();
      if (mounted) setState(() {});
      widget.onChanged();
    }
    name.dispose(); endpoint.dispose(); model.dispose(); key.dispose();
  }

  Future<void> _fetchModels(QaraProvider p) async {
    setState(() => loadingModels = true);
    try {
      final models = await service.listModels(p);
      if (!mounted) return;
      if (models.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('هیچ Model ـێک لە API وەرنەگیرا. ناوی Model بە دەستی بنووسە.')));
      } else {
        final selected = await showModalBottomSheet<String>(
          context: context, backgroundColor: qaraPanel,
          builder: (ctx) => SafeArea(child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('Model هەڵبژێرە')),
              ...models.map((m) => ListTile(
                title: Text(m),
                onTap: () => Navigator.pop(ctx, m),
              )),
            ],
          )),
        );
        if (selected != null) {
          p.model = selected;
          await store.saveProviders();
          setState(() {});
          widget.onChanged();
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => loadingModels = false);
    }
  }

  Future<void> _delete(QaraProvider p) async {
    if (store.providers.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('دەبێت لانیکەم یەک Provider بمێنێتەوە.')));
      return;
    }
    store.providers.removeWhere((x) => x.id == p.id);
    if (store.activeProviderId == p.id) store.activeProviderId = store.providers.first.id;
    await store.saveProviders();
    setState(() {});
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ڕێکخستنەکانی قەرە')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _editProvider(),
      backgroundColor: qaraMint,
      foregroundColor: qaraBg,
      icon: const Icon(Icons.add),
      label: const Text('زیادکردنی API'),
    ),
    body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), children: [
      const Text('AI PROVIDERS', style: TextStyle(
        color: qaraMint, letterSpacing: 1.6, fontWeight: FontWeight.bold, fontSize: 11)),
      const SizedBox(height: 8),
      ...store.providers.map((p) => Card(
        color: qaraPanel,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(children: [
            Row(children: [
              CircleAvatar(
                backgroundColor: p.kind == ProviderKind.gemini
                  ? const Color(0xFF314B83) : const Color(0xFF145B4A),
                child: Icon(p.kind == ProviderKind.gemini
                  ? Icons.auto_awesome : Icons.hub_outlined, color: Colors.white),
              ),
              const SizedBox(width: 11),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('${p.kind.name} • ${p.model}',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 11)),
                Text(p.apiKey.isEmpty ? 'API Key دانەنراوە' : 'API Key پارێزراوە',
                  style: TextStyle(fontSize: 10, color: p.apiKey.isEmpty ? Colors.orange : qaraMint)),
              ])),
              if (store.activeProviderId == p.id)
                const Icon(Icons.check_circle, color: qaraMint),
            ]),
            const Divider(height: 22, color: Colors.white12),
            Row(children: [
              TextButton.icon(
                onPressed: () async {
                  store.activeProviderId = p.id;
                  await store.saveProviders();
                  setState(() {});
                  widget.onChanged();
                },
                icon: const Icon(Icons.check, size: 17),
                label: const Text('بەکاربهێنە'),
              ),
              const Spacer(),
              IconButton(tooltip: 'وەرگرتنی Model ـەکان',
                onPressed: loadingModels ? null : () => _fetchModels(p),
                icon: const Icon(Icons.refresh)),
              IconButton(tooltip: 'دەستکاری',
                onPressed: () => _editProvider(p), icon: const Icon(Icons.edit_outlined)),
              IconButton(tooltip: 'سڕینەوە',
                onPressed: () => _delete(p), icon: const Icon(Icons.delete_outline, color: Colors.redAccent)),
            ]),
          ]),
        ),
      )),
      const SizedBox(height: 20),
      const Text('تێبینیی پاراستن', style: TextStyle(color: qaraMint, fontWeight: FontWeight.bold)),
      const SizedBox(height: 7),
      const Text(
        'API Key ـەکان بە flutter_secure_storage لە مۆبایل هەڵدەگیرێن. بەڵام هەر کاتێک داواکاری بۆ Gemini یان OpenAI دەنێردرێت، ناوەڕۆکی پەیامەکان بۆ ئەو خزمەتگوزارییە دەنێردرێت. API Key لە APK ـێکی کڕاودا بە تەواوی لە دەرچوون پارێزراو نییە؛ بۆ بەرهەمهێنانی گشتی Backend ـی تایبەت باشترە.',
        style: TextStyle(color: Colors.white60, height: 1.5, fontSize: 12),
      ),
      const SizedBox(height: 14),
      const Text(
        'هەموو Endpoint ـەکان دەبێت بە شێوەی API ـی گونجاو لەگەڵ جۆری Provider کار بکەن. Gemini بە generateContent و OpenAI بە chat/completions بەکاردەهێنرێت.',
        style: TextStyle(color: Colors.white38, height: 1.5, fontSize: 11),
      ),
    ]),
  );
}
