import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/features/settings/settings_section_scaffold.dart';

class DiagnosticsSectionScreen extends ConsumerWidget {
  const DiagnosticsSectionScreen({
    super.key,
    this.onGenerateAndShare,
    this.onClear,
  });

  final Future<void> Function(BuildContext context)? onGenerateAndShare;
  final Future<void> Function(BuildContext context)? onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsSectionScaffold(
      title: '诊断与反馈',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('隐私保护', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('诊断记录只保存在本机，不会自动上传。'),
                  SizedBox(height: 6),
                  Text(
                    '诊断包不包含照片、项目名称、工程内容、拍摄人、位置坐标或原图路径；'
                    '只有你主动点击分享后，文件才会交给系统分享面板。',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text('诊断记录最多保留 7 天，空间上限为 2 MB。'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onGenerateAndShare == null
                ? () => _generateAndShare(context, ref)
                : () => onGenerateAndShare!(context),
            icon: const Icon(Icons.ios_share_outlined),
            label: const Text('生成并分享诊断包'),
          ),
          TextButton(
            onPressed: onClear == null
                ? () => _clear(context, ref)
                : () => onClear!(context),
            child: const Text('清除本机诊断记录'),
          ),
        ],
      ),
    );
  }

  Future<void> _generateAndShare(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('分享诊断包？'),
        content: const Text(
          '包含：应用版本、系统环境、存储统计、操作结果与耗时。\n\n'
          '不包含：照片、项目名称、工程内容、拍摄人、位置坐标、文件路径和原始异常。\n\n'
          '确认后才会打开系统分享面板。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认生成'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final service = await ref.read(diagnosticBundleServiceProvider.future);
      final path = await service.generate();
      await ref.read(shareFileServiceProvider).shareFile(path);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('诊断包生成失败，请稍后重试')));
    }
  }

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清除诊断记录？'),
        content: const Text('只清除本机诊断事件，不会删除照片、项目或备份。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final service = await ref.read(diagnosticBundleServiceProvider.future);
    await service.store.clear();
  }
}
