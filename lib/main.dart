// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

void main() {
  runApp(const MyApp());
}

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  DatabaseHelper._internal();

  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB("speech_texts.db");
    return _db!;
  }

  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, fileName);

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE texts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            content TEXT NOT NULL,
            createdAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
          )
        ''');
      },
    );
  }

  Future<int> insertText(String content) async {
    final db = await database;
    return await db.insert("texts", {"content": content});
  }

  Future<List<Map<String, dynamic>>> fetchTexts() async {
    final db = await database;
    return await db.query("texts", orderBy: "id DESC");
  }

  Future<int> updateText(int id, String newContent) async {
    final db = await database;
    return await db.update(
      "texts",
      {"content": newContent},
      where: "id = ?",
      whereArgs: [id],
    );
  }

  Future<int> deleteText(int id) async {
    final db = await database;
    return await db.delete("texts", where: "id = ?", whereArgs: [id]);
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isDarkTheme = false;

  void _toggleTheme() {
    setState(() {
      _isDarkTheme = !_isDarkTheme;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Speech to Text Demo',
      theme: _isDarkTheme
          ? ThemeData.dark().copyWith(
              colorScheme: const ColorScheme.dark().copyWith(
                primary: Colors.tealAccent,
              ),
            )
          : ThemeData.light().copyWith(
              primaryColor: Colors.blue,
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 20,
                  ),
                ),
              ),
            ),
      home: SpeechHomePage(onToggleTheme: _toggleTheme),
    );
  }
}

class SpeechHomePage extends StatefulWidget {
  final VoidCallback onToggleTheme;
  const SpeechHomePage({super.key, required this.onToggleTheme});

  @override
  State<SpeechHomePage> createState() => _SpeechHomePageState();
}

class _SpeechHomePageState extends State<SpeechHomePage> {
  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _text = '';
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final FlutterTts _flutterTts = FlutterTts();

  List<Map<String, dynamic>> _savedTexts = [];

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _initializeTTS();
    _loadSavedTexts();
  }

  void _initializeTTS() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  Future<void> _speak(String message) async {
    await _flutterTts.stop();
    await _flutterTts.speak(message);
  }

  Future<void> _loadSavedTexts() async {
    final data = await DatabaseHelper.instance.fetchTexts();
    setState(() {
      _savedTexts = data;
    });
  }

  Future<void> _saveText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Nothing to save')));
      return;
    }
    if (_isCommand(trimmed)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This appears to be a command — not saved.'),
        ),
      );
      return;
    }

    await DatabaseHelper.instance.insertText(trimmed);
    _controller.clear();
    await _loadSavedTexts();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Saved successfully')));
  }

  bool _isCommand(String input) {
    final normalized = input.toLowerCase().trim();
    const commands = [
      "open the keyboard",
      "close the keyboard",
      "change the theme",
      "clear the text",
      "exit the app",
    ];
    return commands.contains(normalized);
  }

  void _listen() async {
    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (val) => debugPrint('Status: $val'),
        onError: (val) => debugPrint('Error: $val'),
      );

      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          onResult: (val) async {
            setState(() {
              _text = val.recognizedWords.toLowerCase();
              _controller.text = _text;
              _controller.selection = TextSelection.fromPosition(
                TextPosition(offset: _controller.text.length),
              );
            });

            final normalized = _text.trim();
            if (normalized == "open the keyboard") {
              FocusScope.of(context).requestFocus(_focusNode);
              Future.delayed(const Duration(milliseconds: 100), () {
                SystemChannels.textInput.invokeMethod('TextInput.show');
              });
              await _speak("Keyboard is now open.");
            } else if (normalized == "close the keyboard") {
              FocusScope.of(context).unfocus();
              SystemChannels.textInput.invokeMethod('TextInput.hide');
              await _speak("Keyboard is now closed.");
            } else if (normalized == "change the theme") {
              widget.onToggleTheme();
              await _speak("Theme changed.");
            } else if (normalized == "clear the text") {
              _controller.clear();
              await _speak("Text cleared.");
            } else if (normalized == "exit the app") {
              await _speak("Closing the app.");
              Future.delayed(const Duration(seconds: 1), () {
                SystemNavigator.pop();
              });
            }
          },
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Speech recognition unavailable')),
        );
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  Future<void> _editText(int id, String oldContent) async {
    final controller = TextEditingController(text: oldContent);

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Edit Text"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: "Enter new text"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text("Save"),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      await DatabaseHelper.instance.updateText(id, result);
      await _loadSavedTexts();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Updated successfully')));
    }
  }

  Future<void> _deleteText(int id) async {
    await DatabaseHelper.instance.deleteText(id);
    await _loadSavedTexts();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Deleted successfully')));
  }

  @override
  void dispose() {
    _speech.stop();
    _flutterTts.stop();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Chat Bot"),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: widget.onToggleTheme,
            icon: const Icon(Icons.brightness_6),
            tooltip: "Toggle Theme",
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                hintText: "Say something or type here...",
                hintStyle: TextStyle(color: Theme.of(context).hintColor),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _listen,
              icon: Icon(_isListening ? Icons.mic : Icons.mic_none),
              label: Text(_isListening ? "Listening..." : "Start Listening"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => _saveText(_controller.text),
              icon: const Icon(Icons.save),
              label: const Text("Save Text"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueGrey,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _savedTexts.isEmpty
                  ? const Center(child: Text("No saved texts yet."))
                  : ListView.builder(
                      itemCount: _savedTexts.length,
                      itemBuilder: (context, index) {
                        final item = _savedTexts[index];
                        return Card(
                          child: ListTile(
                            leading: const Icon(Icons.text_snippet),
                            title: Text(item["content"]),
                            subtitle: Text(item["createdAt"].toString()),
                            trailing: Wrap(
                              spacing: 8,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.volume_up,
                                    color: Colors.green,
                                  ),
                                  onPressed: () => _speak(item["content"]),
                                  tooltip: "Listen",
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.edit,
                                    color: Colors.orange,
                                  ),
                                  onPressed: () =>
                                      _editText(item["id"], item["content"]),
                                  tooltip: "Edit",
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                  ),
                                  onPressed: () => _deleteText(item["id"]),
                                  tooltip: "Delete",
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
