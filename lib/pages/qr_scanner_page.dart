import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/barrier_service.dart';

class QRScannerPage extends StatefulWidget {
  const QRScannerPage({super.key});

  @override
  State<QRScannerPage> createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QRScannerPage> {
  bool _processing = false;

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || code.isEmpty) return;

    setState(() => _processing = true);

    try {
      final result = await BarrierService.instance.scanQR(code);
      if (!mounted) return;

      final action = result['action']?.toString() ?? '';
      final guestName = result['guest_name']?.toString() ?? '';
      final guestPhone = result['guest_phone']?.toString() ?? '';

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: Text(action == 'OPEN' ? '✅ Доступ разрешён' : '❌ Доступ запрещён'),
          content: action == 'OPEN'
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Гость: $guestName'),
                    if (guestPhone.isNotEmpty) Text('Телефон: $guestPhone'),
                  ],
                )
              : const Text('Пропуск недействителен'),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(context); // close dialog
                Navigator.pop(context); // close scanner
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      final errCode = e.response?.data?['error']?.toString() ?? '';
      final msg = switch (errCode) {
        'QR_NOT_FOUND' => 'QR-код не найден',
        'QR_ALREADY_USED' => 'Этот пропуск уже был использован',
        'QR_EXPIRED' => 'Срок действия пропуска истёк',
        _ => 'Ошибка: $errCode',
      };
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('❌ Доступ запрещён'),
          content: Text(msg),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(context); // close dialog
                Navigator.pop(context); // close scanner
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _processing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка сканирования: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Сканировать QR пропуск')),
      body: Stack(
        children: [
          MobileScanner(onDetect: _onDetect),
          // Прицел в центре экрана
          Center(
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.green, width: 3),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Text(
              'Наведите камеру на QR-код гостевого пропуска',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 14, shadows: [
                Shadow(blurRadius: 6, color: Colors.black)
              ]),
            ),
          ),
          if (_processing)
            const ColoredBox(
              color: Colors.black38,
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
