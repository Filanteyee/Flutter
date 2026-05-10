import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/sensor.dart';
import '../services/auth_service.dart';

class OwnershipVerificationPage extends StatefulWidget {
  const OwnershipVerificationPage({super.key});

  @override
  State<OwnershipVerificationPage> createState() => _OwnershipVerificationPageState();
}

class _OwnershipVerificationPageState extends State<OwnershipVerificationPage> {
  final _authService = AuthService();
  final _formKey = GlobalKey<FormState>();
  final _commentController = TextEditingController();
  final _entranceController = TextEditingController();
  final _floorController = TextEditingController();
  final _apartmentController = TextEditingController();

  String _requestedRole = 'owner';
  List<PlatformFile> _files = [];
  bool _loading = false;

  @override
  void dispose() {
    _commentController.dispose();
    _entranceController.dispose();
    _floorController.dispose();
    _apartmentController.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (result == null || result.files.isEmpty) return;
    final existingKeys = _files.map((f) => '${f.path}|${f.name}').toSet();
    final added = result.files
        .where((f) => !existingKeys.contains('${f.path}|${f.name}'))
        .toList();
    if (added.isEmpty) return;
    setState(() => _files = [..._files, ...added]);
  }

  void _removeFile(PlatformFile file) {
    setState(() => _files.removeWhere((f) => f.path == file.path && f.name == file.name));
  }

  String? _validateInt({
    required String? value,
    required int min,
    required int max,
    required String label,
  }) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Укажите $label';
    final parsed = int.tryParse(v);
    if (parsed == null) return '$label — целое число';
    if (parsed < min || parsed > max) return '$label: от $min до $max';
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Прикрепите хотя бы один документ')),
      );
      return;
    }

    setState(() => _loading = true);

    final error = await _authService.submitVerificationRequest(
      requestedRole: _requestedRole,
      documents: _files,
      comment: _commentController.text,
      entrance: int.parse(_entranceController.text.trim()),
      floor: int.parse(_floorController.text.trim()),
      apartment: int.parse(_apartmentController.text.trim()),
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Документы отправлены на проверку')),
    );
    Navigator.pop(context);
  }

  String _fileSizeText(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Проверка статуса')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Подтверждение владельца или арендатора',
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Прикрепите документ и укажите расположение квартиры. После проверки мы вручную присвоим вам статус owner или tenant.',
              style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant, height: 1.5),
            ),
            const SizedBox(height: 20),
            Card(
              child: Column(
                children: [
                  RadioListTile<String>(
                    value: 'owner',
                    groupValue: _requestedRole,
                    activeColor: colors.primary,
                    onChanged: _loading ? null : (v) { if (v != null) setState(() => _requestedRole = v); },
                    title: const Text('Я владелец'),
                  ),
                  RadioListTile<String>(
                    value: 'tenant',
                    groupValue: _requestedRole,
                    activeColor: colors.primary,
                    onChanged: _loading ? null : (v) { if (v != null) setState(() => _requestedRole = v); },
                    title: const Text('Я арендатор'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text('Расположение квартиры', style: text.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _entranceController,
                    enabled: !_loading,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Подъезд'),
                    validator: (v) => _validateInt(
                      value: v,
                      min: 1,
                      max: kEntrancesCount,
                      label: 'подъезд',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _floorController,
                    enabled: !_loading,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Этаж'),
                    validator: (v) => _validateInt(
                      value: v,
                      min: 1,
                      max: kFloorsPerEntrance,
                      label: 'этаж',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _apartmentController,
              enabled: !_loading,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Номер квартиры'),
              validator: (v) => _validateInt(
                value: v,
                min: 1,
                max: 9999,
                label: 'квартиру',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _commentController,
              maxLines: 4,
              enabled: !_loading,
              style: TextStyle(color: colors.onSurface),
              decoration: const InputDecoration(labelText: 'Комментарий (необязательно)'),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _loading ? null : _pickFiles,
              icon: const Icon(Icons.attach_file),
              label: Text(_files.isEmpty ? 'Прикрепить документ' : 'Добавить ещё документы'),
            ),
            const SizedBox(height: 10),
            if (_files.isNotEmpty)
              Text(
                'Выбрано файлов: ${_files.length}',
                style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
              ),
            const SizedBox(height: 10),
            ..._files.map((file) => Card(
              child: ListTile(
                leading: Icon(Icons.insert_drive_file_outlined, color: colors.primary),
                title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(_fileSizeText(file.size)),
                trailing: IconButton(
                  onPressed: _loading ? null : () => _removeFile(file),
                  icon: Icon(Icons.close, color: colors.onSurfaceVariant),
                ),
              ),
            )),
            const SizedBox(height: 100),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(20),
        child: SizedBox(
          height: 56,
          child: FilledButton(
            onPressed: _loading ? null : _submit,
            child: _loading
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Отправить на проверку'),
          ),
        ),
      ),
    );
  }
}
