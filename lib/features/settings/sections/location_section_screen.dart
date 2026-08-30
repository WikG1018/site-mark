import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/features/settings/settings_section_scaffold.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/shared/ui/adaptive_progress.dart';
import 'package:sitemark/workflow/location_permission_service.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';

class LocationSectionScreen extends ConsumerStatefulWidget {
  const LocationSectionScreen({super.key});

  @override
  ConsumerState<LocationSectionScreen> createState() =>
      _LocationSectionScreenState();
}

class _LocationSectionScreenState extends ConsumerState<LocationSectionScreen>
    with WidgetsBindingObserver {
  /// 缓存定位权限的视图状态。初始化时加载，并在 App 恢复前台时刷新，
  /// 以反映用户在系统对话框或系统设置中修改的权限。
  /// `null` 表示首次加载尚未完成。
  LocationPermissionViewState? _permissionState;

  @override
  void initState() {
    super.initState();
    _loadPermission();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 用户从系统权限对话框或系统设置返回后刷新 tile，以反映新权限状态。
    if (state == AppLifecycleState.resumed) {
      _loadPermission();
    }
  }

  Future<void> _loadPermission() async {
    try {
      final state = await ref.read(locationPermissionServiceProvider).load();
      if (!mounted) return;
      setState(() => _permissionState = state);
    } catch (_) {
      // 平台通道不可用（例如没有平台 override 的单测环境）。
      // 默认渲染为 disabled 且不显示 explanation 的状态，避免无限转圈。
      if (!mounted) return;
      setState(() {
        _permissionState = const LocationPermissionViewState(
          permission: LocationPermissionState.denied,
          showExplanation: false,
        );
      });
    }
  }

  Future<void> _onLocationTapped() async {
    final service = ref.read(locationPermissionServiceProvider);
    final current = _permissionState;
    if (current == null || current.locationEnabled) return;
    if (current.openSettings) {
      // 跳转系统设置；resumed 生命周期回调会在用户返回时刷新 tile。
      await service.openSettings();
      return;
    }
    final state = await service.request();
    if (!mounted) return;
    setState(() => _permissionState = state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return SettingsSectionScaffold(
      title: strings.locationLabel,
      body: _LocationPermissionTile(
        state: _permissionState,
        onTap: _onLocationTapped,
      ),
    );
  }
}

/// 展示当前定位权限状态的 ListTile。权限未授予时点击会发起请求
/// （或当平台报告 `permanentlyDenied` 时打开系统设置）。
class _LocationPermissionTile extends StatelessWidget {
  const _LocationPermissionTile({required this.state, required this.onTap});

  final LocationPermissionViewState? state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final current = state;
    final enabled = current?.locationEnabled ?? false;
    return ListTile(
      key: const Key('location-permission-setting'),
      leading: const Icon(Icons.location_on_outlined),
      title: Text(strings.locationLabel),
      trailing: current == null
          ? AdaptiveProgressIndicator(size: 16)
          : Text(enabled ? strings.enabled : strings.disabled),
      subtitle: current != null && !enabled
          ? Text(
              current.openSettings
                  ? strings.locationPermanentlyDeniedHint
                  : strings.locationDisabledHint,
            )
          : null,
      onTap: current == null || enabled ? null : onTap,
    );
  }
}
