import 'package:flutter/material.dart';

class PaymentsPage extends StatelessWidget {
  const PaymentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final bills = const [
      ('ОСИ/КСК', '12 500 ₸', 'К оплате до 10 числа'),
      ('Вода', '2 340 ₸', 'К оплате до 15 числа'),
      ('Электроэнергия', '4 980 ₸', 'К оплате до 15 числа'),
      ('Отопление', '9 100 ₸', 'К оплате до 20 числа'),
    ];

    final history = const [
      ('Оплата ОСИ/КСК', '12 500 ₸', '01.03.2026'),
      ('Оплата воды', '2 140 ₸', '20.02.2026'),
      ('Оплата света', '4 730 ₸', '20.02.2026'),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Платежи')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Коммунальные платежи', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.receipt_long_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Итого к оплате (демо)', style: Theme.of(context).textTheme.labelLarge),
                          const SizedBox(height: 6),
                          Text('28 920 ₸', style: Theme.of(context).textTheme.headlineSmall),
                        ],
                      ),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(96, 44),
                      ),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Демо: оплата будет подключена позже')),
                        );
                      },
                      child: const Text('Оплатить'),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),
            Text('Счета', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),

            ...bills.map((b) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: ListTile(
                  title: Text(b.$1),
                  subtitle: Text(b.$3),
                  trailing: Text(b.$2, style: Theme.of(context).textTheme.titleSmall),
                ),
              ),
            )),

            const SizedBox(height: 14),
            Text('История', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),

            ...history.map((h) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: Text(h.$1),
                  subtitle: Text(h.$3),
                  trailing: Text(h.$2),
                ),
              ),
            )),
          ],
        ),
      ),
    );
  }
}