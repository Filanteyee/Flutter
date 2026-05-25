import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_client.dart';

class CreateRequestSheet extends StatefulWidget {
  final String? prefilledDescription;
  const CreateRequestSheet({super.key, this.prefilledDescription});

  @override
  State<CreateRequestSheet> createState() => _CreateRequestSheetState();
}

class _CreateRequestSheetState extends State<CreateRequestSheet> {
  final _formKey = GlobalKey<FormState>();
  final _desc = TextEditingController();
  final _picker = ImagePicker();
  final ApiClient _api = ApiClient.instance;

  final _categories = const ['Лифт', 'Домофон', 'Дверь/вход', 'Протечка', 'Освещение', 'Электричество', 'Уборка', 'Другое'];

  String _selected = 'Лифт';
  final List<XFile> _photos = [];
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.prefilledDescription != null) {
      _desc.text = widget.prefilledDescription!;
    }
  }

  @override
  void dispose() {
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pickFromGallery() async {
    final images = await _picker.pickMultiImage(imageQuality: 85);
    if (images.isEmpty) return;
    setState(() => _photos.addAll(images));
  }

  Future<void> _takePhoto() async {
    final img = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (img == null) return;
    setState(() => _photos.add(img));
  }

  void _removePhoto(int index) => setState(() => _photos.removeAt(index));

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);

    try {
      final res = await _api.post('/service-requests', data: {
        'category': _selected,
        'description': _desc.text.trim(),
      });

      final requestId = res.data['id'] as String;

      for (final photo in _photos) {
        final formData = FormData.fromMap({
          'photo': await MultipartFile.fromFile(photo.path, filename: photo.name),
        });
        await _api.postForm('/service-requests/$requestId/photos', formData);
      }

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Заявка создана')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка создания заявки: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Создать заявку', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerLeft, child: Text('Категория', style: Theme.of(context).textTheme.labelLarge)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _categories.map((c) => ChoiceChip(
                label: Text(c),
                selected: c == _selected,
                onSelected: _submitting ? null : (_) => setState(() => _selected = c),
              )).toList(),
            ),
            const SizedBox(height: 14),
            Form(
              key: _formKey,
              child: TextFormField(
                controller: _desc,
                enabled: !_submitting,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Описание проблемы',
                  hintText: 'Например: не работает домофон, лифт шумит…',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final text = (v ?? '').trim();
                  if (text.isEmpty) return 'Напиши описание';
                  if (text.length < 8) return 'Слишком коротко';
                  return null;
                },
              ),
            ),
            const SizedBox(height: 14),
            Align(alignment: Alignment.centerLeft, child: Text('Фото (необязательно)', style: Theme.of(context).textTheme.labelLarge)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: OutlinedButton.icon(onPressed: _submitting ? null : _takePhoto, icon: const Icon(Icons.photo_camera), label: const Text('Камера'))),
                const SizedBox(width: 12),
                Expanded(child: OutlinedButton.icon(onPressed: _submitting ? null : _pickFromGallery, icon: const Icon(Icons.photo_library), label: const Text('Галерея'))),
              ],
            ),
            if (_photos.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 92,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _photos.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, i) => Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.file(File(_photos[i].path), width: 92, height: 92, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(width: 92, height: 92, alignment: Alignment.center, child: const Icon(Icons.broken_image)),
                        ),
                      ),
                      Positioned(
                        right: 6, top: 6,
                        child: InkWell(
                          onTap: _submitting ? null : () => _removePhoto(i),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(999)),
                            child: const Icon(Icons.close, size: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: _submitting ? null : () => Navigator.pop(context), child: const Text('Отмена'))),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Создать'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
