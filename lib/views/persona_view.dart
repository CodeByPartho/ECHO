import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/haptics.dart';
import '../core/ui.dart';
import '../models/persona.dart';
import '../services/persona_codec.dart';
import '../services/persona_service.dart';

/// Full-screen Persona manager: choose default persona ("No persona" or any
/// saved persona), create/edit personas, and import/export `persona.json`.
class PersonaView extends StatelessWidget {
  const PersonaView({super.key});

  PersonaService get _service => Get.find<PersonaService>();

  Future<void> _importFromFile(BuildContext context) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json', 'txt'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      String? content;
      if (file.bytes != null) {
        content = utf8.decode(file.bytes!, allowMalformed: true);
      } else if (!kIsWeb && file.path != null) {
        content = await File(file.path!).readAsString();
      }
      if (content == null || content.trim().isEmpty) {
        showToast('Import failed', 'The selected file is empty.',
            tone: ToastTone.error);
        return;
      }
      final imported = await _service.importJson(content);
      if (imported.length == 1) {
        await _service.setActive(imported.first.id);
      }
      showToast(
        'Imported',
        imported.length == 1
            ? 'Imported "${imported.first.name}".'
            : 'Imported ${imported.length} personas.',
        tone: ToastTone.success,
      );
    } on PersonaFormatException catch (e) {
      showToast('Invalid persona JSON', e.message, tone: ToastTone.error);
    } catch (e) {
      showToast('Import failed', '$e', tone: ToastTone.error);
    }
  }

  Future<void> _importFromClipboard(BuildContext context) async {
    final textController = TextEditingController();
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    if (clip?.text != null && clip!.text!.trim().isNotEmpty) {
      textController.text = clip.text!.trim();
    }
    if (!context.mounted) return;
    await showAppSheet<void>(
      context,
      title: 'Paste persona JSON',
      subtitle:
          'Paste a persona object or array matching docs/persona_schema.json.',
      builder: (ctx) {
        final t = AppTokens.of(ctx);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: textController,
              minLines: 6,
              maxLines: 12,
              style: t.mono,
              decoration: appInputDecoration(
                ctx,
                hint:
                    '{"schema_version": "1.0", "name": "Pirate", "system_prompt": "..."}',
              ),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Import JSON',
              icon: Icons.file_download_outlined,
              onPressed: () async {
                final raw = textController.text.trim();
                if (raw.isEmpty) return;
                try {
                  final imported = await _service.importJson(raw);
                  if (imported.length == 1) {
                    await _service.setActive(imported.first.id);
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  showToast(
                    'Imported',
                    imported.length == 1
                        ? 'Imported "${imported.first.name}".'
                        : 'Imported ${imported.length} personas.',
                    tone: ToastTone.success,
                  );
                } on PersonaFormatException catch (e) {
                  showToast('Invalid persona JSON', e.message,
                      tone: ToastTone.error);
                } catch (e) {
                  showToast('Import failed', '$e', tone: ToastTone.error);
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _showImportSheet(BuildContext context) {
    showAppSheet<void>(
      context,
      title: 'Import persona',
      subtitle: 'Load a persona.json file or paste raw JSON.',
      builder: (ctx) => AppGroup(dividerIndent: 60, children: [
        AppRow(
          icon: Icons.folder_open_rounded,
          title: 'Choose JSON file',
          subtitle: 'Pick a .json file from your device',
          chevron: true,
          onTap: () {
            Navigator.pop(ctx);
            _importFromFile(context);
          },
        ),
        AppRow(
          icon: Icons.content_paste_rounded,
          title: 'Paste JSON',
          subtitle: 'Import directly from clipboard or text',
          chevron: true,
          onTap: () {
            Navigator.pop(ctx);
            _importFromClipboard(context);
          },
        ),
      ]),
    );
  }

  Future<void> _exportPersona(BuildContext context, Persona persona) async {
    final jsonStr = _service.exportJson(persona, pretty: true);
    await Clipboard.setData(ClipboardData(text: jsonStr));
    if (!kIsWeb) {
      try {
        final dir = await getTemporaryDirectory();
        final slug = persona.name
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
            .replaceAll(RegExp(r'^_+|_+$'), '');
        final fileName = '${slug.isEmpty ? 'persona' : slug}.json';
        final file = File('${dir.path}/$fileName');
        await file.writeAsString(jsonStr, flush: true);
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'application/json')],
          subject: persona.name,
        );
        return;
      } catch (_) {}
    }
    showToast(
      'Copied JSON',
      'Persona JSON copied to clipboard.',
      tone: ToastTone.success,
    );
  }

  void _showPersonaActions(BuildContext context, Persona persona) {
    showAppSheet<void>(
      context,
      title: persona.name,
      subtitle: persona.aliases.isNotEmpty
          ? 'Aliases: ${persona.aliases.join(', ')}'
          : (persona.systemPrompt.trim().isEmpty
              ? 'No system prompt'
              : persona.systemPrompt.trim()),
      builder: (ctx) {
        final isActive = _service.activePersonaId.value == persona.id;
        return AppGroup(dividerIndent: 60, children: [
          AppRow(
            icon: isActive
                ? Icons.person_off_outlined
                : Icons.check_circle_outline_rounded,
            title: isActive ? 'Clear default persona' : 'Set as default',
            onTap: () async {
              Navigator.pop(ctx);
              await _service.setActive(isActive ? null : persona.id);
            },
          ),
          AppRow(
            icon: Icons.edit_outlined,
            title: 'Edit persona',
            chevron: true,
            onTap: () {
              Navigator.pop(ctx);
              Get.to(() => PersonaEditorView(initial: persona));
            },
          ),
          AppRow(
            icon: Icons.copy_outlined,
            title: 'Duplicate',
            onTap: () async {
              Navigator.pop(ctx);
              final copy = await _service.duplicate(persona.id);
              if (copy != null) {
                showToast('Duplicated', 'Created "${copy.name}".',
                    tone: ToastTone.success);
              }
            },
          ),
          AppRow(
            icon: Icons.ios_share_rounded,
            title: 'Export JSON',
            subtitle: 'Share file or copy to clipboard',
            onTap: () {
              Navigator.pop(ctx);
              _exportPersona(context, persona);
            },
          ),
          AppRow(
            icon: Icons.delete_outline_rounded,
            title: 'Delete persona',
            destructive: true,
            onTap: () async {
              Navigator.pop(ctx);
              final ok = await confirmSheet(
                context,
                title: 'Delete "${persona.name}"?',
                message:
                    'Existing chats will keep their messages and fall back to the default system prompt.',
                confirmLabel: 'Delete',
                destructive: true,
              );
              if (ok) {
                await _service.delete(persona.id);
                showToast('Deleted', '"${persona.name}" removed.',
                    tone: ToastTone.info);
              }
            },
          ),
        ]);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Scaffold(
      backgroundColor: t.bg,
      appBar: appScreenBar(
        context,
        title: 'Personas',
        showBack: true,
        actions: [
          AppBarIcon(
            icon: Icons.file_upload_outlined,
            tooltip: 'Import persona JSON',
            onPressed: () => _showImportSheet(context),
          ),
          AppBarIcon(
            icon: Icons.add_rounded,
            tooltip: 'New persona',
            onPressed: () => Get.to(() => const PersonaEditorView()),
          ),
        ],
      ),
      body: Obx(() {
        final list = _service.personas;
        final activeId = _service.activePersonaId.value;
        return ListView(
          padding: kPagePadding,
          children: [
            const SectionHeader(
              'Default for new chats',
              padding: EdgeInsets.fromLTRB(4, 8, 4, 8),
            ),
            AppGroup(dividerIndent: 60, children: [
              AppRow(
                icon: Icons.chat_bubble_outline_rounded,
                title: 'No persona (default)',
                subtitle: 'Uses the global system prompt and model settings',
                selected: activeId.isEmpty,
                onTap: () => _service.setActive(null),
              ),
              for (final p in list)
                AppRow(
                  leading: PersonaAvatar(persona: p, size: 36),
                  title: p.name,
                  subtitle: _personaSummary(p),
                  selected: p.id == activeId,
                  trailing: IconButton(
                    tooltip: 'Persona options',
                    icon: Icon(Icons.more_horiz_rounded,
                        size: 20, color: t.muted),
                    onPressed: () => _showPersonaActions(context, p),
                  ),
                  onTap: () => _service.setActive(p.id),
                ),
            ]),
            const SectionFootnote(
              'A persona customizes the system prompt, optional few-shot examples, and generation parameters for local and cloud models.',
            ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: TonalButton.neutral(
                  context,
                  label: 'Import JSON',
                  onTap: () => _showImportSheet(context),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PrimaryButton(
                  label: 'New Persona',
                  icon: Icons.add_rounded,
                  onPressed: () => Get.to(() => const PersonaEditorView()),
                ),
              ),
            ]),
            if (list.isEmpty) ...[
              const SizedBox(height: 24),
              const EmptyState(
                icon: Icons.theater_comedy_outlined,
                title: 'No custom personas yet',
                message:
                    'Create a persona from scratch or import a persona.json file.',
              ),
            ],
          ],
        );
      }),
    );
  }

  String _personaSummary(Persona p) {
    final parts = <String>[];
    if (p.aliases.isNotEmpty) {
      parts.add(p.aliases.join(', '));
    }
    if (p.fewShotExamples.isNotEmpty) {
      parts.add('${p.fewShotExamples.length} example(s)');
    }
    if (p.temperature != null) {
      parts.add('temp ${p.temperature!.toStringAsFixed(2)}');
    }
    if (parts.isNotEmpty) return parts.join(' · ');
    final prompt = p.systemPrompt.trim();
    return prompt.isEmpty ? 'No system prompt' : prompt;
  }
}

/// Avatar badge for a persona (custom image file if present, else monogram).
class PersonaAvatar extends StatelessWidget {
  final Persona? persona;
  final double size;

  const PersonaAvatar({super.key, required this.persona, this.size = 32});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final p = persona;
    if (p == null) {
      return IconBadge(Icons.person_outline_rounded, size: size);
    }
    final avatarPath = p.avatarPath;
    if (!kIsWeb && avatarPath != null && avatarPath.isNotEmpty) {
      final file = File(avatarPath);
      if (file.existsSync()) {
        return ClipOval(
          child: Image.file(
            file,
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        );
      }
    }
    final trimmed = p.name.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: t.accent.withValues(alpha: t.isDark ? 0.22 : 0.12),
      ),
      child: Text(
        initial,
        style: GoogleFonts.inter(
          fontSize: size * 0.44,
          fontWeight: FontWeight.w700,
          color: t.accent,
        ),
      ),
    );
  }
}

/// Bottom-sheet picker for switching the persona bound to the current chat.
Future<void> showPersonaPickerSheet(
  BuildContext context, {
  required String? selectedPersonaId,
  required ValueChanged<String?> onSelected,
}) {
  final service = Get.find<PersonaService>();
  return showAppSheet<void>(
    context,
    title: 'Choose persona',
    subtitle: 'Applies to this conversation and future new chats.',
    builder: (ctx) => Obx(() {
      final personas = service.personas;
      final current = selectedPersonaId ?? '';
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppGroup(dividerIndent: 60, children: [
            AppRow(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'No persona',
              subtitle: 'Default system prompt',
              selected: current.isEmpty,
              onTap: () {
                Navigator.pop(ctx);
                onSelected(null);
              },
            ),
            for (final p in personas)
              AppRow(
                leading: PersonaAvatar(persona: p, size: 34),
                title: p.name,
                subtitle: p.systemPrompt.trim().isEmpty
                    ? 'No system prompt'
                    : p.systemPrompt.trim(),
                selected: p.id == current,
                onTap: () {
                  Navigator.pop(ctx);
                  onSelected(p.id);
                },
              ),
          ]),
          const SizedBox(height: 14),
          TonalButton.neutral(
            ctx,
            label: 'Manage personas',
            onTap: () {
              Navigator.pop(ctx);
              Get.to(() => const PersonaView());
            },
          ),
        ],
      );
    }),
  );
}

/// Create / edit screen for a single [Persona].
class PersonaEditorView extends StatefulWidget {
  final Persona? initial;

  const PersonaEditorView({super.key, this.initial});

  @override
  State<PersonaEditorView> createState() => _PersonaEditorViewState();
}

class _PersonaEditorViewState extends State<PersonaEditorView> {
  final _service = Get.find<PersonaService>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _aliasesCtrl;
  late final TextEditingController _systemPromptCtrl;
  late final TextEditingController _greetingCtrl;
  late final TextEditingController _temperatureCtrl;
  late final TextEditingController _topPCtrl;
  late final TextEditingController _maxTokensCtrl;
  late final TextEditingController _stopCtrl;
  final List<({TextEditingController user, TextEditingController assistant})>
      _examples = [];

  String? _avatarPath;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _aliasesCtrl = TextEditingController(text: p?.aliases.join(', ') ?? '');
    _systemPromptCtrl = TextEditingController(text: p?.systemPrompt ?? '');
    _greetingCtrl = TextEditingController(text: p?.greeting ?? '');
    _temperatureCtrl = TextEditingController(
        text: p?.temperature != null ? p!.temperature.toString() : '');
    _topPCtrl =
        TextEditingController(text: p?.topP != null ? p!.topP.toString() : '');
    _maxTokensCtrl = TextEditingController(
        text: p?.maxTokens != null ? p!.maxTokens.toString() : '');
    _stopCtrl = TextEditingController(text: p?.stopSequences.join('\n') ?? '');
    _avatarPath = p?.avatarPath;

    if (p != null) {
      for (final ex in p.fewShotExamples) {
        _examples.add((
          user: TextEditingController(text: ex.user),
          assistant: TextEditingController(text: ex.assistant),
        ));
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _aliasesCtrl.dispose();
    _systemPromptCtrl.dispose();
    _greetingCtrl.dispose();
    _temperatureCtrl.dispose();
    _topPCtrl.dispose();
    _maxTokensCtrl.dispose();
    _stopCtrl.dispose();
    for (final ex in _examples) {
      ex.user.dispose();
      ex.assistant.dispose();
    }
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    if (kIsWeb) return;
    try {
      final file =
          await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 512);
      if (file != null) {
        setState(() => _avatarPath = file.path);
      }
    } catch (_) {}
  }

  void _addExample() {
    Haptics.selectionClick();
    setState(() {
      _examples.add((
        user: TextEditingController(),
        assistant: TextEditingController(),
      ));
    });
  }

  void _removeExample(int index) {
    Haptics.selectionClick();
    setState(() {
      final removed = _examples.removeAt(index);
      removed.user.dispose();
      removed.assistant.dispose();
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      showToast('Name required', 'Give this persona a name.',
          tone: ToastTone.warning);
      return;
    }

    setState(() => _saving = true);
    try {
      final aliases = _aliasesCtrl.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);

      final examples = _examples
          .map((e) => FewShotExample(
                user: e.user.text.trim(),
                assistant: e.assistant.text.trim(),
              ))
          .where((e) => !e.isEmpty)
          .toList(growable: false);

      final stops = _stopCtrl.text
          .split('\n')
          .map((l) => l.replaceAll(r'\n', '\n').replaceAll(r'\t', '\t'))
          .where((l) => l.trim().isNotEmpty)
          .toList(growable: false);

      final temp = double.tryParse(_temperatureCtrl.text.trim());
      final topP = double.tryParse(_topPCtrl.text.trim());
      final maxTokens = int.tryParse(_maxTokensCtrl.text.trim());
      final greeting = _greetingCtrl.text.trim();

      final draft = Persona(
        id: widget.initial?.id ?? '',
        name: name,
        aliases: aliases,
        avatarPath: _avatarPath,
        systemPrompt: _systemPromptCtrl.text,
        greeting: greeting.isEmpty ? null : greeting,
        fewShotExamples: examples,
        temperature: temp?.clamp(0.0, 2.0).toDouble(),
        topP: topP?.clamp(0.0, 1.0).toDouble(),
        maxTokens: maxTokens?.clamp(1, 32768),
        stopSequences: stops,
        isActive: widget.initial?.isActive ?? false,
        metadata: widget.initial?.metadata ?? const {},
      );

      var saved = await _service.save(draft);
      if (_avatarPath != null &&
          _avatarPath != widget.initial?.avatarPath &&
          !kIsWeb) {
        final persisted = await _service.persistAvatar(saved.id, _avatarPath!);
        if (persisted != null) {
          saved = await _service.save(saved.copyWith(avatarPath: persisted));
        }
      }

      if (mounted) Navigator.pop(context, saved);
      showToast('Saved', 'Persona "${saved.name}" saved.',
          tone: ToastTone.success);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final isEdit = widget.initial != null;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: appScreenBar(
        context,
        title: isEdit ? 'Edit Persona' : 'New Persona',
        showBack: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: PillButton(
                label: 'Save',
                primary: true,
                onPressed: _saving ? null : _save,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: kPagePadding,
        children: [
          if (!kIsWeb) ...[
            Center(
              child: GestureDetector(
                onTap: _pickAvatar,
                child: Column(children: [
                  PersonaAvatar(
                    persona: Persona(
                      id: widget.initial?.id ?? 'preview',
                      name: _nameCtrl.text.isEmpty ? 'P' : _nameCtrl.text,
                      avatarPath: _avatarPath,
                    ),
                    size: 64,
                  ),
                  const SizedBox(height: 6),
                  Text('Tap to set avatar', style: t.small),
                ]),
              ),
            ),
            const SizedBox(height: 16),
          ],
          AppField(
            label: 'Name',
            child: TextField(
              controller: _nameCtrl,
              style: t.body,
              onChanged: (_) => setState(() {}),
              decoration:
                  appInputDecoration(context, hint: 'e.g. Senior Rust Mentor'),
            ),
          ),
          const SizedBox(height: 16),
          AppField(
            label: 'Aliases (optional)',
            helper: 'Comma-separated alternative names.',
            child: TextField(
              controller: _aliasesCtrl,
              style: t.body,
              decoration:
                  appInputDecoration(context, hint: 'rust, borrow-checker'),
            ),
          ),
          const SizedBox(height: 16),
          AppField(
            label: 'System prompt',
            helper:
                'Injected as the system instruction for both local and cloud inference.',
            child: TextField(
              controller: _systemPromptCtrl,
              minLines: 4,
              maxLines: 10,
              style: t.body,
              decoration: appInputDecoration(
                context,
                hint: 'You are a concise, pragmatic assistant...',
              ),
            ),
          ),
          const SizedBox(height: 16),
          AppField(
            label: 'Greeting (optional)',
            child: TextField(
              controller: _greetingCtrl,
              minLines: 1,
              maxLines: 3,
              style: t.body,
              decoration: appInputDecoration(
                context,
                hint: 'Optional opening line or description',
              ),
            ),
          ),
          SectionHeader(
            'Few-shot examples',
            trailing: PillButton(
              label: 'Add pair',
              icon: Icons.add_rounded,
              onPressed: _addExample,
            ),
          ),
          if (_examples.isEmpty)
            const SectionFootnote(
              'Add sample User / Assistant turns to demonstrate the persona\'s tone and format.',
            )
          else
            for (var i = 0; i < _examples.length; i++) ...[
              AppCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text('Example ${i + 1}', style: t.label),
                      ),
                      GestureDetector(
                        onTap: () => _removeExample(i),
                        child: Icon(Icons.close_rounded,
                            size: 18, color: t.muted),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _examples[i].user,
                      minLines: 1,
                      maxLines: 4,
                      style: t.body,
                      decoration:
                          appInputDecoration(context, label: 'User says'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _examples[i].assistant,
                      minLines: 1,
                      maxLines: 4,
                      style: t.body,
                      decoration: appInputDecoration(context,
                          label: 'Assistant replies'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
          const SectionHeader('Generation settings (optional)'),
          AppGroup(
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(children: [
                  Row(children: [
                    Expanded(
                      child: AppField(
                        label: 'Temperature (0–2)',
                        child: TextField(
                          controller: _temperatureCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          style: t.body,
                          decoration:
                              appInputDecoration(context, hint: 'Default'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppField(
                        label: 'Top P (0–1)',
                        child: TextField(
                          controller: _topPCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          style: t.body,
                          decoration:
                              appInputDecoration(context, hint: 'Default'),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  AppField(
                    label: 'Max tokens',
                    child: TextField(
                      controller: _maxTokensCtrl,
                      keyboardType: TextInputType.number,
                      style: t.body,
                      decoration: appInputDecoration(context, hint: 'Default'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppField(
                    label: 'Stop sequences (one per line)',
                    child: TextField(
                      controller: _stopCtrl,
                      minLines: 2,
                      maxLines: 4,
                      style: t.mono,
                      decoration:
                          appInputDecoration(context, hint: '###\n\\nUser:'),
                    ),
                  ),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            label: isEdit ? 'Save Changes' : 'Create Persona',
            busy: _saving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}
