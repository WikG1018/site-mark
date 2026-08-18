import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OhosReviewApp());
}

class OhosReviewApp extends StatelessWidget {
  const OhosReviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SiteMark',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF1B5E20)),
      home: const _ReviewConsentGate(),
    );
  }
}

class _MemoryConsentStore {
  bool accepted = false;
}

class _ReviewConsentGate extends StatefulWidget {
  const _ReviewConsentGate();

  @override
  State<_ReviewConsentGate> createState() => _ReviewConsentGateState();
}

class _ReviewConsentGateState extends State<_ReviewConsentGate> {
  final _store = _MemoryConsentStore();

  @override
  Widget build(BuildContext context) {
    if (_store.accepted) {
      return const _ReviewHome();
    }
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('隐私说明', style: textTheme.headlineSmall),
              const SizedBox(height: 16),
              const Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    'SiteMark 在本机拍摄、生成水印并保存记录。照片、定位结果和工程信息默认只留在这台设备上。'
                    '相册写入需要系统授权；未授权时会改用系统保存面板或应用沙箱。'
                    '同意后才会启动相机、定位和相册相关能力。',
                  ),
                ),
              ),
              FilledButton(
                onPressed: () => setState(() => _store.accepted = true),
                child: const Text('同意并继续'),
              ),
              TextButton(
                onPressed: () => SystemNavigator.pop(),
                child: const Text('退出'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewHome extends StatelessWidget {
  const _ReviewHome();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SiteMark')),
      body: const Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('鸿蒙审查壳已启动'),
            SizedBox(height: 12),
            Text(
              '这是产品 ohos/ 宿主 + 社区 Flutter 3.27.4 可编译入口，用来审查冷启动和隐私门。'
              '不是 Android v1.0.8 全量 Dart 产物。引擎状态 degraded。'
              '模拟器不证明相机、相册 ACL、ohos-arm64 布局对等。',
            ),
          ],
        ),
      ),
    );
  }
}
