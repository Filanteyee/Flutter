import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../models/vehicle.dart';
import '../services/vehicle_service.dart';
import '../utils/error_helper.dart';

class VehiclesPage extends StatefulWidget {
  const VehiclesPage({super.key});

  @override
  State<VehiclesPage> createState() => _VehiclesPageState();
}

class _VehiclesPageState extends State<VehiclesPage> {
  final _service = VehicleService.instance;

  bool _loading = true;
  List<Vehicle> _vehicles = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      setState(() { _loading = true; _error = null; });
      final list = await _service.getMyVehicles();
      if (!mounted) return;
      setState(() { _vehicles = list; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _delete(Vehicle v) async {
    try {
      await _service.deleteVehicle(v.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      _snack('Ошибка удаления: $e');
    }
  }

  Future<void> _showAddDialog() async {
    final plateCtrl = TextEditingController();
    final brandCtrl = TextEditingController();
    final colorCtrl = TextEditingController();
    bool saving = false;
    String? err;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Добавить автомобиль'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              TextField(
                controller: plateCtrl,
                textCapitalization: TextCapitalization.characters,
                onChanged: (v) => plateCtrl.value = plateCtrl.value.copyWith(
                  text: v.toUpperCase(),
                  selection: TextSelection.collapsed(offset: v.length),
                ),
                decoration: const InputDecoration(
                  labelText: 'Номер авто',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: brandCtrl,
                decoration: const InputDecoration(
                  labelText: 'Марка',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: colorCtrl,
                decoration: const InputDecoration(
                  labelText: 'Цвет',
                  border: OutlineInputBorder(),
                ),
              ),
              if (err != null) ...[
                const SizedBox(height: 10),
                Text(err!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final plate = plateCtrl.text.trim().toUpperCase();
                      if (plate.isEmpty) {
                        setDialogState(() => err = 'Введите номер');
                        return;
                      }
                      setDialogState(() { saving = true; err = null; });
                      try {
                        await _service.addVehicle(
                          plateNumber: plate,
                          brand: brandCtrl.text.trim(),
                          color: colorCtrl.text.trim(),
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        await _load();
                      } on DioException catch (e) {
                        final msg = e.response?.data?['error']?.toString() ?? '';
                        setDialogState(() {
                          err = msg.contains('already') ? 'Этот номер уже зарегистрирован' : 'Ошибка: $msg';
                          saving = false;
                        });
                      } catch (e) {
                        setDialogState(() { err = 'Ошибка: $e'; saving = false; });
                      }
                    },
              child: saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Добавить'),
            ),
          ],
        ),
      ),
    );
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Мои автомобили')),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _load, child: const Text('Повторить')),
                      ],
                    ),
                  ),
                )
              : _vehicles.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.directions_car_outlined, size: 64, color: Colors.grey),
                            SizedBox(height: 12),
                            Text(
                              'Нет зарегистрированных автомобилей',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                        itemCount: _vehicles.length,
                        itemBuilder: (_, i) => _VehicleCard(
                          vehicle: _vehicles[i],
                          onDelete: () => _delete(_vehicles[i]),
                        ),
                      ),
                    ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  final Vehicle vehicle;
  final VoidCallback onDelete;

  const _VehicleCard({required this.vehicle, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final info = [vehicle.brand, vehicle.color]
        .where((s) => s.isNotEmpty)
        .join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            const Icon(Icons.directions_car_outlined, size: 36),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vehicle.plateNumber,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                  ),
                  if (info.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(info, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: vehicle.isActive ? Colors.green.withOpacity(0.15) : Colors.red.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                vehicle.isActive ? 'Активен' : 'Неактивен',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: vehicle.isActive ? Colors.green : Colors.red,
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
