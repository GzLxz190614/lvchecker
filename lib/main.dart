import 'package:flutter/material.dart';

import 'data/data_loader.dart';
import 'data/progress_store.dart';
import 'pages/gate_pager.dart';
import 'pages/settings_page.dart';
import 'theme.dart';

void main() {
  runApp(const LvCheckerApp());
}

class LvCheckerApp extends StatelessWidget {
  const LvCheckerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '连章进度',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      home: const _Boot(),
    );
  }
}

/// 启动页：加载内置数据 + 读取本地存档，然后进主页面。
class _Boot extends StatefulWidget {
  const _Boot();

  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  late final Future<(AppData, ProgressStore)> _future = _init();

  Future<(AppData, ProgressStore)> _init() async {
    final data = await const DataLoader().load();
    final store = await ProgressStore.load();
    return (data, store);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(AppData, ProgressStore)>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Color(0xFFE57373), size: 40),
                    const SizedBox(height: 14),
                    const Text('数据加载失败',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text(
                      '${snap.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: AppTheme.textDim),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final (data, store) = snap.data!;
        return _Home(data: data, store: store);
      },
    );
  }
}

class _Home extends StatelessWidget {
  const _Home({required this.data, required this.store});

  final AppData data;
  final ProgressStore store;

  @override
  Widget build(BuildContext context) {
    return GatePager(
      gates: data.gateData.gates,
      meta: data.meta,
      store: store,
      dataVersion: data.gateData.dataVersion,
      onOpenSettings: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SettingsPage(
              gates: data.gateData.gates,
              store: store,
              dataVersion: data.gateData.dataVersion,
              gameVersion: data.gateData.gameVersion,
            ),
          ),
        );
      },
    );
  }
}
