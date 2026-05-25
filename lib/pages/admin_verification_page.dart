import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

import '../models/parking_permit.dart';
import '../services/api_client.dart';
import '../services/parking_service.dart';
import '../utils/error_helper.dart';

class AdminVerificationPage extends StatefulWidget {
  const AdminVerificationPage({super.key});

  @override
  State<AdminVerificationPage> createState() => _AdminVerificationPageState();
}

class _AdminVerificationPageState extends State<AdminVerificationPage> {
  final ApiClient _api = ApiClient.instance;

  bool _loading = true;
  String? _error;
  List<_VerificationRequestItem> _requests = [];

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    try {
      setState(() { _loading = true; _error = null; });
      final res = await _api.get('/verification/requests');
      final items = (res.data as List)
          .map((row) => _VerificationRequestItem.fromMap(Map<String, dynamic>.from(row as Map)))
          .toList();
      if (!mounted) return;
      setState(() { _requests = items; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = 'Ошибка загрузки запросов: $e'; _loading = false; });
    }
  }

  Future<void> _updateStatus(_VerificationRequestItem request, String newStatus) async {
    try {
      await _api.put('/verification/requests/${request.id}/status', data: {'status': newStatus});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(newStatus == 'approved' ? 'Статус пользователя подтверждён' : 'Запрос отклонён'),
      ));
      await _loadRequests();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка обновления статуса: $e')));
    }
  }

  Future<void> _openDocumentsDialog(_VerificationRequestItem request) async {
    await showDialog(
      context: context,
      builder: (dialogCtx) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Прикреплённые документы', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              if (request.documents.isEmpty)
                const Text('Документы не найдены')
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: request.documents.length,
                    itemBuilder: (_, index) {
                      final doc = request.documents[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            const Icon(Icons.insert_drive_file_outlined, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    doc.fileName.isEmpty ? 'Без имени' : doc.fileName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodyMedium,
                                  ),
                                  Text(
                                    _formatFileSize(doc.fileSize),
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () => _openFile(doc, dialogCtx),
                              child: const Text('Открыть'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Закрыть'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// На Android-эмуляторе localhost — это сам эмулятор, а не хост-машина.
  /// Заменяем на 10.0.2.2, чтобы достучаться до сервера.
  String _fixUrl(String url) {
    final host = ApiClient.baseHost;
    return url
        .replaceFirst(RegExp(r'http://localhost:\d+'), host)
        .replaceFirst(RegExp(r'http://127\.0\.0\.1:\d+'), host)
        .replaceFirst(RegExp(r'http://10\.0\.2\.2:\d+'), host);
  }

  /// Собираем список URL-кандидатов, по которым может лежать файл.
  /// Бэкенд может отдать как полный URL, так и относительный путь, плюс
  /// статика на `/uploads/...` живёт ВНЕ `/api/v1`. Перебираем все варианты,
  /// первый успешный (HTTP 200 с непустым телом) — берём.
  List<String> _buildUrlCandidates(_VerificationDocumentItem doc) {
    final urls = <String>{};
    final host = ApiClient.baseHost;
    final api = ApiClient.baseUrl;

    void add(String? raw) {
      if (raw == null || raw.isEmpty) return;
      if (raw.startsWith('http://') || raw.startsWith('https://')) {
        urls.add(_fixUrl(raw));
      } else if (raw.startsWith('/')) {
        urls.add('$host$raw');
      } else {
        urls.add('$host/$raw');
      }
    }

    // 1) То, что вернул сервер в поле url.
    add(doc.url);

    // 2) Статика по file_path (типичная Go-раздача через /uploads/).
    final fp = doc.filePath;
    if (fp.isNotEmpty) {
      final clean = fp.startsWith('/') ? fp.substring(1) : fp;
      // Убираем ведущий 'uploads/', чтобы не получить /uploads/uploads/...
      final cleanNoPrefix = clean.startsWith('uploads/') ? clean.substring('uploads/'.length) : clean;
      urls.add('$host/uploads/$cleanNoPrefix');
      urls.add('$host/$clean');
    }

    // 3) REST-стиль: скачивание по id документа через API.
    if (doc.id.isNotEmpty) {
      urls.add('$api/verification/documents/${doc.id}/download');
      urls.add('$api/verification/documents/${doc.id}');
    }

    return urls.toList();
  }

  bool _looksLikeImage(String name, String contentType) {
    final n = name.toLowerCase();
    if (n.endsWith('.jpg') || n.endsWith('.jpeg') || n.endsWith('.png') ||
        n.endsWith('.gif') || n.endsWith('.webp') || n.endsWith('.bmp')) {
      return true;
    }
    return contentType.toLowerCase().startsWith('image/');
  }

  bool _looksLikePdf(String name, String contentType) {
    if (name.toLowerCase().endsWith('.pdf')) return true;
    return contentType.toLowerCase().contains('pdf');
  }

  /// Имя файла без слешей и зарезервированных символов Windows/Android FS.
  String _sanitizeFileName(String name) =>
      name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

  Future<void> _openFile(_VerificationDocumentItem doc, BuildContext dialogContext) async {
    Navigator.of(dialogContext).pop();

    final fileName = doc.fileName.isNotEmpty ? doc.fileName : 'document';

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Загрузка…'), duration: Duration(seconds: 60)),
    );

    final candidates = _buildUrlCandidates(doc);
    Response<List<int>>? success;
    String lastUrl = '';
    int? lastStatus;
    String? networkError;

    for (final url in candidates) {
      lastUrl = url;
      try {
        final res = await _api.downloadBytes(url);
        lastStatus = res.statusCode;
        final body = res.data;
        if (res.statusCode == 200 && body != null && body.isNotEmpty) {
          success = res;
          break;
        }
      } on DioException catch (e) {
        // Сетевая ошибка — запоминаем и пробуем следующего кандидата.
        networkError = e.message ?? e.toString();
      } catch (e) {
        networkError = e.toString();
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (success == null) {
      final reason = lastStatus != null
          ? 'HTTP $lastStatus'
          : (networkError != null ? 'сеть: $networkError' : 'неизвестно');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Не удалось открыть файл ($reason)\n$lastUrl'),
          duration: const Duration(seconds: 6),
        ),
      );
      return;
    }

    final bytes = Uint8List.fromList(success.data!);
    final contentType = success.headers.value('content-type') ?? '';

    try {
      if (_looksLikeImage(fileName, contentType)) {
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(fileName, maxLines: 1, overflow: TextOverflow.ellipsis)),
            body: InteractiveViewer(
              minScale: 0.5,
              maxScale: 5,
              child: Center(child: Image.memory(bytes)),
            ),
          ),
        ));
      } else if (_looksLikePdf(fileName, contentType)) {
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => _PdfViewerPage(title: fileName, bytes: bytes),
        ));
      } else {
        // doc/docx/xls/xlsx и прочее — сохраняем во временный файл и
        // отдаём системному просмотрщику.
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/${_sanitizeFileName(fileName)}');
        await file.writeAsBytes(bytes, flush: true);
        if (!mounted) return;
        final result = await OpenFile.open(file.path);
        if (result.type != ResultType.done) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Нет приложения для этого формата: ${result.message}')),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка отображения файла: $e')),
      );
    }
  }

  String _formatFileSize(int size) {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Проверка документов'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Верификация'),
              Tab(text: 'Пропуска паркинга'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _VerificationTab(
              loading: _loading,
              error: _error,
              requests: _requests,
              onRefresh: _loadRequests,
              onUpdateStatus: _updateStatus,
              onOpenDocuments: _openDocumentsDialog,
            ),
            const _PermitsTab(),
          ],
        ),
      ),
    );
  }
}

// ─── Вкладка "Верификация" ───────────────────────────────────

class _VerificationTab extends StatelessWidget {
  final bool loading;
  final String? error;
  final List<_VerificationRequestItem> requests;
  final Future<void> Function() onRefresh;
  final Future<void> Function(_VerificationRequestItem, String) onUpdateStatus;
  final Future<void> Function(_VerificationRequestItem) onOpenDocuments;

  const _VerificationTab({
    required this.loading,
    required this.error,
    required this.requests,
    required this.onRefresh,
    required this.onUpdateStatus,
    required this.onOpenDocuments,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? _ErrorBlock(message: error!, onRetry: onRefresh)
          : requests.isEmpty
          ? const _EmptyBlock(text: 'Запросов на подтверждение пока нет')
          : RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: requests.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
              final request = requests[index];
              final profile = request.profile;

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(profile.fullName.isEmpty ? 'Без имени' : profile.fullName, style: Theme.of(context).textTheme.titleMedium)),
                          Chip(label: Text(_verStatusLabel(request.status)), avatar: Icon(Icons.circle, size: 10, color: _verStatusColor(request.status))),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (profile.email.isNotEmpty) Text(profile.email),
                      if (profile.phone.isNotEmpty) ...[const SizedBox(height: 4), Text(profile.phone)],
                      if (profile.iin.isNotEmpty) ...[const SizedBox(height: 4), Text('ИИН: ${profile.iin}')],
                      if (profile.fullAddress.isNotEmpty) ...[const SizedBox(height: 4), Text(profile.fullAddress, style: Theme.of(context).textTheme.bodySmall)],
                      const SizedBox(height: 12),
                      Row(children: [const Icon(Icons.badge_outlined, size: 18), const SizedBox(width: 8), Text('Запрошенный статус: ${_verRoleLabel(request.requestedRole)}')]),
                      const SizedBox(height: 8),
                      Row(children: [const Icon(Icons.schedule_outlined, size: 18), const SizedBox(width: 8), Text(_verFormatDate(request.createdAt))]),
                      if (request.comment.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(request.comment),
                        ),
                      ],
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => onOpenDocuments(request),
                          icon: const Icon(Icons.folder_open_outlined),
                          label: Text('Документы (${request.documents.length})'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (request.status == 'pending')
                        Row(
                          children: [
                            Expanded(child: OutlinedButton(onPressed: () => onUpdateStatus(request, 'rejected'), child: const Text('Отклонить'))),
                            const SizedBox(width: 12),
                            Expanded(child: FilledButton(onPressed: () => onUpdateStatus(request, 'approved'), child: const Text('Подтвердить'))),
                          ],
                        )
                      else
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonal(
                            onPressed: null,
                            child: Text(request.status == 'approved' ? 'Уже подтверждено' : 'Уже отклонено'),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
    );
  }
}

class _VerificationRequestItem {
  final String id;
  final String userId;
  final String requestedRole;
  final String comment;
  final String status;
  final DateTime createdAt;
  final _ProfileInfo profile;
  final List<_VerificationDocumentItem> documents;

  const _VerificationRequestItem({
    required this.id,
    required this.userId,
    required this.requestedRole,
    required this.comment,
    required this.status,
    required this.createdAt,
    required this.profile,
    required this.documents,
  });

  factory _VerificationRequestItem.fromMap(Map<String, dynamic> map) {
    final profileMap = Map<String, dynamic>.from((map['profile'] as Map?) ?? {});
    final docsRaw = map['documents'];
    final docs = <_VerificationDocumentItem>[];
    if (docsRaw is List) {
      for (final item in docsRaw) {
        docs.add(_VerificationDocumentItem.fromMap(Map<String, dynamic>.from(item as Map)));
      }
    }
    return _VerificationRequestItem(
      id: (map['id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      requestedRole: (map['requested_role'] ?? '').toString(),
      comment: (map['comment'] ?? '').toString(),
      status: (map['status'] ?? 'pending').toString(),
      createdAt: DateTime.tryParse((map['created_at'] ?? '').toString()) ?? DateTime.now(),
      profile: _ProfileInfo.fromMap(profileMap),
      documents: docs,
    );
  }
}

class _ProfileInfo {
  final String fullName;
  final String email;
  final String phone;
  final String iin;
  final String fullAddress;

  const _ProfileInfo({required this.fullName, required this.email, required this.phone, required this.iin, required this.fullAddress});

  factory _ProfileInfo.fromMap(Map<String, dynamic> map) => _ProfileInfo(
    fullName: (map['full_name'] ?? '').toString(),
    email: (map['email'] ?? '').toString(),
    phone: (map['phone'] ?? '').toString(),
    iin: (map['iin'] ?? '').toString(),
    fullAddress: (map['full_address'] ?? '').toString(),
  );
}

class _VerificationDocumentItem {
  final String id;
  final String filePath;
  final String fileName;
  final int fileSize;
  final String url;

  const _VerificationDocumentItem({required this.id, required this.filePath, required this.fileName, required this.fileSize, required this.url});

  factory _VerificationDocumentItem.fromMap(Map<String, dynamic> map) => _VerificationDocumentItem(
    id: (map['id'] ?? '').toString(),
    filePath: (map['file_path'] ?? '').toString(),
    fileName: (map['file_name'] ?? '').toString(),
    fileSize: map['file_size'] is int ? map['file_size'] as int : int.tryParse((map['file_size'] ?? '0').toString()) ?? 0,
    url: (map['url'] ?? '').toString(),
  );
}

class _EmptyBlock extends StatelessWidget {
  final String text;
  const _EmptyBlock({required this.text});
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(text, textAlign: TextAlign.center)));
}

class _ErrorBlock extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ErrorBlock({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 42),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      ),
    );
  }
}

class _PdfViewerPage extends StatefulWidget {
  final String title;
  final List<int> bytes;

  const _PdfViewerPage({required this.title, required this.bytes});

  @override
  State<_PdfViewerPage> createState() => _PdfViewerPageState();
}

class _PdfViewerPageState extends State<_PdfViewerPage> {
  bool _ready = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: Stack(
        children: [
          PDFView(
            pdfData: Uint8List.fromList(widget.bytes),
            enableSwipe: true,
            swipeHorizontal: false,
            autoSpacing: true,
            onRender: (_) => setState(() => _ready = true),
            onError: (e) => setState(() => _error = e.toString()),
            onPageError: (_, e) => setState(() => _error = e.toString()),
          ),
          if (!_ready && _error == null)
            const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.broken_image_outlined, size: 48),
                    const SizedBox(height: 12),
                    Text('Не удалось отобразить PDF: $_error', textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Top-level helpers ───────────────────────────────────────

String _verStatusLabel(String s) => switch (s) {
  'pending' => 'На проверке', 'approved' => 'Подтверждено', 'rejected' => 'Отклонено', _ => s
};
Color _verStatusColor(String s) => switch (s) {
  'approved' => Colors.green, 'rejected' => Colors.red, _ => Colors.orange
};
String _verRoleLabel(String r) => switch (r) {
  'owner' => 'Владелец', 'tenant' => 'Арендатор', _ => r
};
String _verFormatDate(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(dt.day)}.${two(dt.month)}.${dt.year}  ${two(dt.hour)}:${two(dt.minute)}';
}

// ─── Вкладка "Пропуска паркинга" ────────────────────────────

class _PermitsTab extends StatefulWidget {
  const _PermitsTab();
  @override
  State<_PermitsTab> createState() => _PermitsTabState();
}

class _PermitsTabState extends State<_PermitsTab> {
  bool _loading = true;
  List<ParkingPermit> _permits = [];
  String? _error;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      setState(() { _loading = true; _error = null; });
      final permits = await ParkingService.instance
          .getAdminPermits(status: _filter == 'all' ? null : _filter);
      if (!mounted) return;
      setState(() { _permits = permits; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _openPermitDoc(ParkingPermit permit) async {
    final rawUrl = permit.documentUrl;
    if (rawUrl == null) return;
    final host = ApiClient.baseHost;
    final url = rawUrl
        .replaceFirst(RegExp(r'http://localhost:\d+'), host)
        .replaceFirst(RegExp(r'http://127\.0\.0\.1:\d+'), host)
        .replaceFirst(RegExp(r'http://10\.0\.2\.2:\d+'), host);
    final fileName = url.split('/').last.isNotEmpty ? url.split('/').last : 'document';

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Загрузка…'), duration: Duration(seconds: 60)),
    );

    try {
      final res = await ApiClient.instance.downloadBytes(url);
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (res.statusCode != 200 || res.data == null || res.data!.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось загрузить файл (HTTP ${res.statusCode})')),
        );
        return;
      }

      final bytes = Uint8List.fromList(res.data!);
      final contentType = res.headers.value('content-type') ?? '';
      final n = fileName.toLowerCase();
      final isImage = n.endsWith('.jpg') || n.endsWith('.jpeg') || n.endsWith('.png') ||
          n.endsWith('.webp') || n.endsWith('.gif') || contentType.startsWith('image/');
      final isPdf = n.endsWith('.pdf') || contentType.contains('pdf');

      if (isImage) {
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(fileName, maxLines: 1, overflow: TextOverflow.ellipsis)),
            body: InteractiveViewer(
              minScale: 0.5, maxScale: 5,
              child: Center(child: Image.memory(bytes)),
            ),
          ),
        ));
      } else if (isPdf) {
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => _PdfViewerPage(title: fileName, bytes: bytes),
        ));
      } else {
        final dir = await getTemporaryDirectory();
        final clean = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        final file = File('${dir.path}/$clean');
        await file.writeAsBytes(bytes, flush: true);
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        final result = await OpenFile.open(file.path);
        if (result.type != ResultType.done) {
          messenger.showSnackBar(
            SnackBar(content: Text('Нет приложения для этого формата: ${result.message}')),
          );
        }
      }
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка сети: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  Future<void> _review(ParkingPermit permit, String status) async {
    String? comment;
    if (status == 'rejected') {
      final ctrl = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Причина отклонения'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (permit.documentUrl != null) ...[
                      OutlinedButton.icon(
                        onPressed: () => _openPermitDoc(permit),
                        icon: const Icon(Icons.insert_drive_file_outlined, size: 16),
                        label: const Text('Просмотреть документ'),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: ctrl,
                      onChanged: (_) => setDialogState(() {}),
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'Укажите причину',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
              FilledButton(
                onPressed: ctrl.text.trim().isEmpty
                    ? null
                    : () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Отклонить'),
              ),
            ],
          ),
        ),
      );
      if (confirmed != true) return;
      comment = ctrl.text.trim();
    }
    try {
      await ParkingService.instance.adminReviewPermit(permit.id, status, adminComment: comment);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'all', label: Text('Все')),
              ButtonSegment(value: 'pending', label: Text('Ожидают')),
              ButtonSegment(value: 'approved', label: Text('Одобрены')),
              ButtonSegment(value: 'rejected', label: Text('Отклонены')),
            ],
            selected: {_filter},
            onSelectionChanged: (val) {
              setState(() => _filter = val.first);
              _load();
            },
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!))
                  : _permits.isEmpty
                      ? const Center(child: Text('Нет заявок'))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _permits.length,
                            itemBuilder: (_, i) {
                              final p = _permits[i];
                              return _PermitCard(
                                permit: p,
                                onApprove: p.isPending ? () => _review(p, 'approved') : null,
                                onReject:  p.isPending ? () => _review(p, 'rejected') : null,
                                onOpenDocument: p.documentUrl != null ? () => _openPermitDoc(p) : null,
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}

class _PermitCard extends StatelessWidget {
  final ParkingPermit permit;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final VoidCallback? onOpenDocument;

  const _PermitCard({required this.permit, this.onApprove, this.onReject, this.onOpenDocument});

  @override
  Widget build(BuildContext context) {
    final p = permit;
    final color = p.isApproved ? Colors.green : p.isRejected ? Colors.red : Colors.orange;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(p.fullNameOrEmpty.isNotEmpty ? p.fullNameOrEmpty : 'Житель',
                    style: const TextStyle(fontWeight: FontWeight.bold))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(p.statusLabel,
                      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.directions_car_outlined, size: 16, color: Colors.black54),
                const SizedBox(width: 4),
                Text(p.plateNumber, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (p.spotNumber != null) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.local_parking, size: 16, color: Colors.black54),
                  const SizedBox(width: 4),
                  Text(p.spotNumber!),
                ],
              ],
            ),
            if (p.documentUrl != null) ...[
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: onOpenDocument,
                icon: const Icon(Icons.insert_drive_file_outlined, size: 16),
                label: const Text('Открыть документ'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
              ),
            ],
            if (p.adminComment != null && p.adminComment!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Комментарий: ${p.adminComment}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ],
            if (onApprove != null || onReject != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  if (onApprove != null)
                    Expanded(child: FilledButton(
                      onPressed: onApprove,
                      style: FilledButton.styleFrom(backgroundColor: Colors.green),
                      child: const Text('Одобрить'),
                    )),
                  if (onApprove != null && onReject != null) const SizedBox(width: 8),
                  if (onReject != null)
                    Expanded(child: OutlinedButton(
                      onPressed: onReject,
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('Отклонить'),
                    )),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
