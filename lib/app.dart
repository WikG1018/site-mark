import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sitemark/background/capture_background_scheduler.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/data/capture_query_repository.dart';
import 'package:sitemark/domain/project_lifecycle.dart';
import 'package:sitemark/diagnostics/diagnostic_bundle_service.dart';
import 'package:sitemark/diagnostics/diagnostic_event_store.dart';
import 'package:sitemark/diagnostics/diagnostic_recorder.dart';
import 'package:sitemark/features/capture/all_captures_screen.dart';
import 'package:sitemark/features/projects/project_form_screen.dart';
import 'package:sitemark/features/projects/project_list_screen.dart';
import 'package:sitemark/features/settings/global_settings_screen.dart';
import 'package:sitemark/features/settings/sections/about_section_screen.dart';
import 'package:sitemark/features/settings/sections/appearance_section_screen.dart';
import 'package:sitemark/features/settings/sections/backup_restore_section_screen.dart';
import 'package:sitemark/features/settings/sections/diagnostics_section_screen.dart';
import 'package:sitemark/features/settings/sections/language_section_screen.dart';
import 'package:sitemark/features/settings/sections/location_section_screen.dart';
import 'package:sitemark/features/settings/sections/notification_section_screen.dart';
import 'package:sitemark/features/settings/sections/storage_section_screen.dart';
import 'package:sitemark/features/settings/sections/watermark_defaults_section_screen.dart';
import 'package:sitemark/features/settings/sections/project_backup_selection_screen.dart';
import 'package:sitemark/features/capture/capture_form_screen.dart';
import 'package:sitemark/features/capture/capture_detail_screen.dart';
import 'package:sitemark/features/capture/capture_edit_screen.dart';
import 'package:sitemark/features/projects/project_detail_screen.dart';
import 'package:sitemark/features/projects/project_watermark_settings_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/motion.dart';
import 'package:sitemark/navigation/root_navigation_scaffold.dart';
import 'package:sitemark/navigation/route_transitions.dart';
import 'package:sitemark/platform/capture_form_draft_store.dart';
import 'package:sitemark/platform/external_link_service.dart';
import 'package:sitemark/platform/memory_pressure_coordinator.dart';
import 'package:sitemark/platform/memory_pressure_service.dart';
import 'package:sitemark/platform/notification_service.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/workflow/app_startup_recovery.dart';
import 'package:sitemark/workflow/app_storage_service.dart';
import 'package:sitemark/workflow/capture_location_coordinator.dart';
import 'package:sitemark/workflow/capture_media_service.dart';
import 'package:sitemark/workflow/capture_template_service.dart';
import 'package:sitemark/workflow/capture_workflow.dart';
import 'package:sitemark/workflow/location_permission_service.dart';
import 'package:sitemark/workflow/project_bundle_service.dart';
import 'package:sitemark/workflow/project_export_service.dart';
import 'package:sitemark/workflow/project_import_service.dart';
import 'package:sitemark/workflow/project_deletion_service.dart';
import 'package:sitemark/workflow/project_lifecycle_service.dart';
import 'package:sitemark/app_theme.dart';
import 'package:sitemark/shared/theme/accent_swatches.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  // Bridge the ITGSA fair-memory lifecycle to the database's conditional
  // polling. When the app is backgrounded or a MEMORY_TRIM arrives, the
  // MemoryPressureController pauses the 1 Hz polling fallback; on resume
  // (foreground / pressure relieved) it restarts. The drift `watch()` stream
  // itself stays active so writes from the background isolate still refresh
  // the UI immediately.
  final controller = ref.watch(memoryPressureControllerProvider);
  final detach = controller.attachBackground(_DatabasePollingControl(database));
  ref.onDispose(() {
    detach();
    database.close();
  });
  return database;
});

final captureQueryRepositoryProvider = Provider<CaptureQueryRepository>((ref) {
  return CaptureQueryRepository(ref.watch(databaseProvider));
});

final captureTemplateServiceProvider = Provider<CaptureTemplateService>((ref) {
  return CaptureTemplateService(database: ref.watch(databaseProvider));
});

final projectLifecycleServiceProvider = Provider<ProjectLifecycleService>((
  ref,
) {
  return ProjectLifecycleService(ref.watch(databaseProvider));
});

class _DatabasePollingControl implements BackgroundWorkControl {
  _DatabasePollingControl(this._database);

  final AppDatabase _database;

  @override
  void pauseBackgroundWork() => _database.setPollingPaused(true);

  @override
  void resumeBackgroundWork() => _database.setPollingPaused(false);
}

final initialLocaleProvider = Provider<Locale?>((ref) => null);
final startupRecoveryEnabledProvider = Provider<bool>((ref) => true);

/// Streams the singleton `global` [AppSetting] row so the [SiteMarkApp]
/// MaterialApp can react to persisted theme/locale/watermark-default changes.
final appSettingsProvider = StreamProvider<AppSetting>((ref) {
  return ref.watch(databaseProvider).watchAppSettings();
});

/// Maps a persisted `themeMode` string to [ThemeMode]. Unknown values fall
/// back to [ThemeMode.system] so corrupt or missing data never breaks the UI.
ThemeMode parseThemeMode(String value) => switch (value) {
  'light' => ThemeMode.light,
  'dark' => ThemeMode.dark,
  _ => ThemeMode.system,
};

/// Maps a persisted `localeCode` string to a [Locale]. `null` (and any
/// unrecognized code) yields `null`, meaning "follow the system locale".
Locale? parseLocale(String? value) => switch (value) {
  'zh' => const Locale('zh'),
  'en' => const Locale('en'),
  _ => null,
};

final platformServicesProvider = Provider<PlatformServices>(
  (ref) => PigeonPlatformServices(),
);

/// Non-blocking location-permission coordinator shared by the capture form and
/// the global settings screen. Reads the host permission state and the
/// persisted `locationPermissionPromptDismissed` flag; the capture button path
/// never calls into this service at runtime.
final locationPermissionServiceProvider = Provider<LocationPermissionService>(
  (ref) => LocationPermissionService(
    database: ref.watch(databaseProvider),
    platform: ref.watch(platformServicesProvider),
  ),
);

final imagePipelineProvider = Provider<ImagePipeline>(
  (ref) => RustImagePipeline(),
);

final projectBundlePipelineProvider = Provider<ProjectBundlePipeline>(
  (ref) => RustProjectBundlePipeline(),
);

final captureOutputPathsProvider = Provider<CaptureOutputPaths>(
  (ref) => AppCaptureOutputPaths(),
);

final projectExportPathsProvider = Provider<ProjectExportPaths>(
  (ref) => AppProjectExportPaths(),
);

final originalPhotoPathsProvider = Provider<OriginalPhotoPaths>(
  (ref) => AppOriginalPhotoPaths(),
);

final importStagingPathsProvider = Provider<ImportStagingPaths>(
  (ref) => AppImportStagingPaths(),
);

final importPendingStoreProvider = Provider<ImportPendingStore>(
  (ref) => AppImportPendingStore(),
);

final importFileCommitterProvider = Provider<ImportFileCommitter>(
  (ref) => DartImportFileCommitter(),
);

final selectionExportPathsProvider = Provider<SelectionExportPaths>(
  (ref) => AppSelectionExportPaths(),
);

final projectBundlePathsProvider = Provider<ProjectBundlePaths>(
  (ref) => AppProjectBundlePaths(),
);

final projectBundleFileSystemProvider = Provider<ProjectBundleFileSystem>(
  (ref) => DartProjectBundleFileSystem(),
);

final bundleRestorePendingStoreProvider = Provider<BundleRestorePendingStore>(
  (ref) => AppBundleRestorePendingStore(),
);

final shareFileServiceProvider = Provider<ShareFileService>(
  (ref) => SystemShareFileService(),
);

final archiveSaveServiceProvider = Provider<ArchiveSaveService>(
  (ref) => PigeonArchiveSaveService(),
);

final diagnosticBundleServiceProvider = FutureProvider<DiagnosticBundleService>((
  ref,
) async {
  final root = await getApplicationSupportDirectory();
  final store = DiagnosticEventStore(
    directory: Directory(
      '${root.path}${Platform.pathSeparator}diagnostics${Platform.pathSeparator}events',
    ),
  );
  return DiagnosticBundleService(store: store);
});

final diagnosticRecorderProvider = Provider<DiagnosticRecorder>(
  (ref) => DiagnosticRecorder.fromFuture(
    ref
        .watch(diagnosticBundleServiceProvider.future)
        .then((service) => service.store),
  ),
);

final privateFileStoreProvider = Provider<PrivateFileStore>(
  (ref) => DartIoPrivateFileStore(),
);

final projectDeletionPendingStoreProvider =
    Provider<ProjectDeletionPendingStore>(
      (ref) => AppProjectDeletionPendingStore(),
    );

final projectDeletionServiceProvider = Provider<ProjectDeletionService>((ref) {
  return ProjectDeletionService(
    database: ref.watch(databaseProvider),
    capturePaths: ref.watch(captureOutputPathsProvider),
    files: ref.watch(privateFileStoreProvider),
    pendingStore: ref.watch(projectDeletionPendingStoreProvider),
  );
});

final storageUsageServiceProvider = Provider<StorageUsageService>((ref) {
  return AppStorageUsageService(database: ref.watch(databaseProvider));
});

final storageUsageProvider = FutureProvider((ref) {
  return ref.watch(storageUsageServiceProvider).load();
});

final externalLinkServiceProvider = Provider<ExternalLinkService>(
  (ref) => const UrlLauncherExternalLinkService(),
);

final backgroundWorkClientProvider = Provider<BackgroundWorkClient>((ref) {
  return WorkmanagerBackgroundWorkClient();
});

final captureBackgroundSchedulerProvider = Provider<CaptureBackgroundScheduler>(
  (ref) {
    return PersistentCaptureBackgroundScheduler(
      client: ref.watch(backgroundWorkClientProvider),
      database: ref.watch(databaseProvider),
    );
  },
);

final captureLocationCoordinatorProvider = Provider<CaptureLocationCoordinator>(
  (ref) {
    return CaptureLocationCoordinator(
      database: ref.watch(databaseProvider),
      platform: ref.watch(platformServicesProvider),
      scheduler: ref.watch(captureBackgroundSchedulerProvider),
    );
  },
);

final captureWorkflowProvider = Provider<CaptureWorkflow>((ref) {
  return CaptureWorkflow(
    database: ref.watch(databaseProvider),
    platform: ref.watch(platformServicesProvider),
    images: ref.watch(imagePipelineProvider),
    outputPaths: ref.watch(captureOutputPathsProvider),
    fileStore: ref.watch(privateFileStoreProvider),
    scheduler: ref.watch(captureBackgroundSchedulerProvider),
    locationCoordinator: ref.watch(captureLocationCoordinatorProvider),
  );
});

final captureMediaServiceProvider = Provider<CaptureMediaService>((ref) {
  return CaptureMediaService(
    database: ref.watch(databaseProvider),
    platform: ref.watch(platformServicesProvider),
    outputPaths: ref.watch(captureOutputPathsProvider),
    files: ref.watch(privateFileStoreProvider),
  );
});

final appStartupRecoveryProvider = Provider<AppStartupRecovery>((ref) {
  return AppStartupRecovery(
    recoverCamera: () =>
        ref.read(captureWorkflowProvider).recoverPendingCapture(),
    resolveLocations: () => ref
        .read(captureLocationCoordinatorProvider)
        .reconcilePendingLocations(),
    reconcileQueue: () =>
        ref.read(captureBackgroundSchedulerProvider).reconcilePending(),
    cleanupInterruptedExports: () =>
        ref.read(projectBackupServiceProvider).cleanupInterruptedExports(),
    cleanupInterruptedImports: () =>
        ref.read(projectImportServiceProvider).cleanupInterruptedImports(),
    cleanupInterruptedBundleRestores: () => ref
        .read(projectBundleServiceProvider)
        .cleanupInterruptedBundleRestores(),
    cleanupInterruptedProjectDeletions: () =>
        ref.read(projectDeletionServiceProvider).cleanupInterruptedDeletions(),
  );
});

/// Coordinator provider. Wires the service to the controller. Created lazily
/// when first read; the root widget reads it in `initState` to start
/// forwarding events.
final memoryPressureCoordinatorProvider = Provider<MemoryPressureCoordinator>((
  ref,
) {
  final coordinator = MemoryPressureCoordinator(
    service: ref.watch(memoryPressureServiceProvider),
    controller: ref.watch(memoryPressureControllerProvider),
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

final projectExportServiceProvider = Provider<ProjectExportService>((ref) {
  return ProjectExportService(
    database: ref.watch(databaseProvider),
    images: ref.watch(imagePipelineProvider),
    capturePaths: ref.watch(captureOutputPathsProvider),
    exportPaths: ref.watch(projectExportPathsProvider),
    selectionExportPaths: ref.watch(selectionExportPathsProvider),
  );
});

final projectImportServiceProvider = Provider<ProjectImportService>((ref) {
  return ProjectImportService(
    database: ref.watch(databaseProvider),
    images: ref.watch(imagePipelineProvider),
    capturePaths: ref.watch(captureOutputPathsProvider),
    originalPaths: ref.watch(originalPhotoPathsProvider),
    fileStore: ref.watch(privateFileStoreProvider),
    stagingPaths: ref.watch(importStagingPathsProvider),
    pendingStore: ref.watch(importPendingStoreProvider),
    committer: ref.watch(importFileCommitterProvider),
  );
});

final projectBackupServiceProvider = Provider<ProjectBackupService>((ref) {
  return ProjectBackupService(
    projectExporter: ref.watch(projectExportServiceProvider),
    database: ref.watch(databaseProvider),
    bundles: ref.watch(projectBundlePipelineProvider),
    paths: ref.watch(projectBundlePathsProvider),
    files: ref.watch(projectBundleFileSystemProvider),
    diagnostics: ref.watch(diagnosticRecorderProvider),
  );
});

final projectBundleRollbackProvider = Provider<ProjectBundleRollback>((ref) {
  return ProjectDeletionBundleRollback(
    database: ref.watch(databaseProvider),
    deletions: ref.watch(projectDeletionServiceProvider),
  );
});

final projectBundleServiceProvider = Provider<ProjectBundleService>((ref) {
  return ProjectBundleService(
    database: ref.watch(databaseProvider),
    bundles: ref.watch(projectBundlePipelineProvider),
    importer: ref.watch(projectImportServiceProvider),
    paths: ref.watch(projectBundlePathsProvider),
    files: ref.watch(projectBundleFileSystemProvider),
    pendingStore: ref.watch(bundleRestorePendingStoreProvider),
    rollback: ref.watch(projectBundleRollbackProvider),
  );
});

/// Shared Axis (horizontal) page for hierarchical navigation (list → detail
/// → form/edit), per M3 motion guidance.
CustomTransitionPage<void> _sharedAxisPage(
  GoRouterState state,
  Widget child, {
  bool freezeSecondary = false,
}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: AppMotion.medium2,
    reverseTransitionDuration: AppMotion.medium2,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return buildSharedAxisRouteTransition(
        context: context,
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        freezeSecondary: freezeSecondary,
        child: child,
      );
    },
    child: child,
  );
}

/// Project detail uses a short clipped slide over a stable project list.
CustomTransitionPage<void> _projectDetailPage(
  GoRouterState state,
  Widget child,
) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: AppMotion.medium2,
    reverseTransitionDuration: AppMotion.medium2,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return buildProjectDetailRouteTransition(
        context: context,
        animation: animation,
        child: child,
      );
    },
    child: child,
  );
}

/// Photo detail and its editor use a position-only transition so the Hero
/// overlay is not also handed between two independently fading image trees.
CustomTransitionPage<void> _captureDetailPage(
  GoRouterState state,
  Widget child,
) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: AppMotion.medium2,
    reverseTransitionDuration: AppMotion.medium2,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.disableAnimationsOf(context)) {
        return child;
      }
      return buildCaptureDetailRouteTransition(
        animation: animation,
        child: child,
      );
    },
    child: child,
  );
}

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    routes: [
      StatefulShellRoute(
        builder: (context, state, navigationShell) =>
            RootNavigationScaffold(navigationShell: navigationShell),
        navigatorContainerBuilder: (context, navigationShell, children) =>
            RootBranchContainer(
              currentIndex: navigationShell.currentIndex,
              children: children,
            ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => ProjectListScreen(
                  initialStatus: state.extra is ProjectLifecycleStatus
                      ? state.extra! as ProjectLifecycleStatus
                      : null,
                ),
                routes: [
                  GoRoute(
                    parentNavigatorKey: rootNavigatorKey,
                    path: 'projects/new',
                    pageBuilder: (context, state) =>
                        _sharedAxisPage(state, const ProjectFormScreen()),
                  ),
                  GoRoute(
                    parentNavigatorKey: rootNavigatorKey,
                    path: 'projects/:projectId',
                    pageBuilder: (context, state) => _projectDetailPage(
                      state,
                      ProjectDetailScreen(
                        projectId: state.pathParameters['projectId']!,
                        initialProject: state.extra is Project
                            ? state.extra! as Project
                            : null,
                      ),
                    ),
                    routes: [
                      GoRoute(
                        parentNavigatorKey: rootNavigatorKey,
                        path: 'settings',
                        pageBuilder: (context, state) => _sharedAxisPage(
                          state,
                          ProjectWatermarkSettingsScreen(
                            projectId: state.pathParameters['projectId']!,
                          ),
                        ),
                      ),
                      GoRoute(
                        parentNavigatorKey: rootNavigatorKey,
                        path: 'capture',
                        pageBuilder: (context, state) => _sharedAxisPage(
                          state,
                          CaptureFormScreen(
                            projectId: state.pathParameters['projectId']!,
                          ),
                        ),
                      ),
                      GoRoute(
                        parentNavigatorKey: rootNavigatorKey,
                        path: 'captures/:captureId',
                        pageBuilder: (context, state) {
                          final arguments =
                              state.extra is CaptureDetailArguments
                              ? state.extra! as CaptureDetailArguments
                              : null;
                          return _captureDetailPage(
                            state,
                            CaptureDetailScreen(
                              projectId: state.pathParameters['projectId']!,
                              captureId: state.pathParameters['captureId']!,
                              initialCapture:
                                  arguments?.capture ??
                                  (state.extra is CaptureRecord
                                      ? state.extra! as CaptureRecord
                                      : null),
                              initialImagePath: arguments?.initialImagePath,
                              navigationContext: arguments?.navigationContext,
                            ),
                          );
                        },
                        routes: [
                          GoRoute(
                            parentNavigatorKey: rootNavigatorKey,
                            path: 'edit',
                            pageBuilder: (context, state) => _captureDetailPage(
                              state,
                              CaptureEditScreen(
                                projectId: state.pathParameters['projectId']!,
                                captureId: state.pathParameters['captureId']!,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/records',
                builder: (context, state) => const AllCapturesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const GlobalSettingsScreen(),
                routes: [
                  GoRoute(
                    parentNavigatorKey: rootNavigatorKey,
                    path: 'watermark',
                    pageBuilder: (context, state) => _sharedAxisPage(
                      state,
                      const WatermarkDefaultsSectionScreen(),
                    ),
                  ),
                  GoRoute(
                    parentNavigatorKey: rootNavigatorKey,
                    path: 'appearance',
                    pageBuilder: (context, state) =>
                        _sharedAxisPage(state, const AppearanceSectionScreen()),
                  ),
                  GoRoute(
                    parentNavigatorKey: rootNavigatorKey,
                    path: 'backup-restore',
                    pageBuilder: (context, state) => _sharedAxisPage(
                      state,
                      const BackupRestoreSectionScreen(),
                    ),
                    routes: [
                      GoRoute(
                        parentNavigatorKey: rootNavigatorKey,
                        path: 'backup',
                        pageBuilder: (context, state) {
                          final arguments =
                              state.extra is ProjectBackupSelectionArguments
                              ? state.extra! as ProjectBackupSelectionArguments
                              : const ProjectBackupSelectionArguments();
                          return _sharedAxisPage(
                            state,
                            ProjectBackupSelectionScreen(
                              initialProjectIds: arguments.initialProjectIds,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  GoRoute(
                    parentNavigatorKey: rootNavigatorKey,
                    path: 'language',
                    pageBuilder: (context, state) =>
                        _sharedAxisPage(state, const LanguageSectionScreen()),
                  ),
                  GoRoute(
                    parentNavigatorKey: rootNavigatorKey,
                    path: 'storage',
                    pageBuilder: (context, state) =>
                        _sharedAxisPage(state, const StorageSectionScreen()),
                  ),
                  GoRoute(
                    parentNavigatorKey: rootNavigatorKey,
                    path: 'location',
                    pageBuilder: (context, state) =>
                        _sharedAxisPage(state, const LocationSectionScreen()),
                  ),
                  GoRoute(
                    parentNavigatorKey: rootNavigatorKey,
                    path: 'notification',
                    pageBuilder: (context, state) => _sharedAxisPage(
                      state,
                      const NotificationSectionScreen(),
                    ),
                  ),
                  GoRoute(
                    parentNavigatorKey: rootNavigatorKey,
                    path: 'diagnostics',
                    pageBuilder: (context, state) => _sharedAxisPage(
                      state,
                      const DiagnosticsSectionScreen(),
                    ),
                  ),
                  GoRoute(
                    parentNavigatorKey: rootNavigatorKey,
                    path: 'about',
                    pageBuilder: (context, state) =>
                        _sharedAxisPage(state, const AboutSectionScreen()),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class SiteMarkApp extends ConsumerStatefulWidget {
  const SiteMarkApp({super.key});

  @override
  ConsumerState<SiteMarkApp> createState() => _SiteMarkAppState();
}

class _SiteMarkAppState extends ConsumerState<SiteMarkApp>
    with WidgetsBindingObserver {
  MemoryPressureCoordinator? _pressureCoordinator;

  /// Tracks whether background work was paused via the lifecycle path.
  /// `resumed` unconditionally resumes; this flag only suppresses a
  /// redundant resume when the app was never backgrounded (e.g. a transient
  /// `inactive` from a permission dialog).
  bool _backgroundPaused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Keep the notification service's send gate in sync with the persisted
    // `completionNotificationsEnabled` switch. The provider throws
    // UnimplementedError when no production service is injected (e.g. in
    // widget tests), in which case the gate update is skipped silently.
    ref.listenManual(appSettingsProvider, (previous, next) {
      final settings = next.value;
      if (settings == null) return;
      try {
        ref
            .read(completionNotificationServiceProvider)
            .setEnabled(settings.completionNotificationsEnabled);
      } on UnimplementedError {
        // No production implementation injected; notifications stay inert.
      }
    });
    // WorkManager must register its headless dispatcher before the first
    // capture is handed to the location coordinator. v0.5.1 moved this work
    // entirely to the first enqueue, which is too late on some Android
    // devices: registering that first task can fail and marks its capture as
    // failed. Deferring to the post-frame callback keeps the fast first paint
    // while establishing the queue before the user can reach the capture form.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await ref.read(captureBackgroundSchedulerProvider).initialize();
      } catch (_) {
        // The scheduler clears its failed initialization future. A later
        // capture enqueue retries it instead of letting startup fail.
      }
      if (ref.read(startupRecoveryEnabledProvider)) {
        await ref.read(appStartupRecoveryProvider).run();
      }
      // Wire completion notifications: taps (including the cold-start
      // launch payload) deep-link into the capture detail page.
      try {
        await ref.read(completionNotificationServiceProvider).initialize((
          path,
        ) {
          ref.read(routerProvider).push(path);
        });
      } on UnimplementedError {
        // No production implementation injected (e.g. widget tests);
        // notifications stay inert.
      }
      // Initialize the ITGSA fair-memory bridge. The native
      // `MemoryPressureReceiver` forwards `itgsa.intent.action.MEMORY_TRIM`
      // and `MEMORY_KILL` broadcasts through the
      // `sitemark/memory_pressure` MethodChannel; the coordinator dispatches
      // them to the controller (image cache flush, background-work pause,
      // kill hooks) and then ACKs the OEM Binder.
      // The provider defaults to [NoopMemoryPressureService] so tests that
      // don't override it still run without errors.
      _pressureCoordinator = ref.read(memoryPressureCoordinatorProvider);
      await ref.read(memoryPressureServiceProvider).initialize();
      _pressureCoordinator!.start();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final controller = ref.read(memoryPressureControllerProvider);
    switch (state) {
      case AppLifecycleState.resumed:
        if (_backgroundPaused) {
          _backgroundPaused = false;
          // Resume the conditional-polling streams and other paused work.
          controller.resumeBackgroundWork();
        }
      case AppLifecycleState.inactive:
        // Transient state (e.g. a permission dialog or system overlay
        // briefly covering the app). Do NOT release resources or pause
        // polling — the user is still interacting with the app and will
        // return momentarily. Grouping this with paused/hidden caused the
        // image cache and fullscreen viewer to be cleared on every
        // permission prompt (I1 fix).
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // The app is no longer in the foreground. Pause non-essential
        // background work (drift polling) and release caches so the
        // process stays quiet while backgrounded. This is required by the
        // ITGSA "fair running memory" mechanism: backgrounded apps must
        // not keep polling.
        if (!_backgroundPaused) {
          _backgroundPaused = true;
          controller.pauseBackgroundWork();
          controller.releaseResources();
        }
      case AppLifecycleState.detached:
        // The activity is being destroyed. Nothing to resume; the process
        // will be killed shortly.
        break;
    }
  }

  @override
  void didHaveMemoryPressure() {
    // Flutter's own memory-pressure callback (e.g. from
    // `ActivityManager` / `onTrimMemory`). Release caches but do NOT pause
    // polling — this fires while the app is in the foreground and the user
    // is still looking at it, so the 1 Hz database refresh must continue.
    // Routing through `dispatch(system)` would stall the polling streams
    // with no lifecycle `resumed` to restart them (C1 fix).
    ref.read(memoryPressureControllerProvider).releaseResources();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider).value;
    // `initialLocaleProvider` is null in production and only set by widget
    // tests to force a locale; when set it takes precedence over persisted
    // settings so existing tests keep driving the locale explicitly.
    final forcedLocale = ref.watch(initialLocaleProvider);
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        // Dynamic color applies only when the persisted opt-in is on AND the
        // platform supplied both palettes; any gap falls back to the brand
        // seed colors so the app never loses its identity.
        final useDynamicColor =
            (settings?.useDynamicColor ?? false) &&
            lightDynamic != null &&
            darkDynamic != null;
        final seedColor = Color(
          settings?.appSeedColorArgb ?? kDefaultSeedColorArgb,
        );
        return MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: 'SiteMark 工程印记',
          themeMode: settings != null
              ? parseThemeMode(settings.themeMode)
              : ThemeMode.system,
          locale: forcedLocale ?? parseLocale(settings?.localeCode),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: buildLightTheme(
            seedColor: seedColor,
            dynamicColor: useDynamicColor ? lightDynamic : null,
          ),
          darkTheme: buildDarkTheme(
            seedColor: seedColor,
            dynamicColor: useDynamicColor ? darkDynamic : null,
          ),
          routerConfig: ref.watch(routerProvider),
        );
      },
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    this.database,
    this.initialLocale,
    this.platformServices,
    this.imagePipeline,
    this.outputPaths,
    this.projectExportPaths,
    this.shareService,
    this.privateFileStore,
    this.externalLinkService,
    this.backgroundScheduler,
    this.backgroundWorkClient,
    this.startupRecovery,
    this.completionNotificationService,
    this.memoryPressureService,
    this.captureFormDraftStore,
    this.memoryPressureController,
  });

  final AppDatabase? database;
  final Locale? initialLocale;
  final PlatformServices? platformServices;
  final ImagePipeline? imagePipeline;
  final CaptureOutputPaths? outputPaths;
  final ProjectExportPaths? projectExportPaths;
  final ShareFileService? shareService;
  final PrivateFileStore? privateFileStore;
  final ExternalLinkService? externalLinkService;
  final CaptureBackgroundScheduler? backgroundScheduler;
  final BackgroundWorkClient? backgroundWorkClient;
  final AppStartupRecovery? startupRecovery;
  final CompletionNotificationService? completionNotificationService;
  final MemoryPressureService? memoryPressureService;
  final CaptureFormDraftStore? captureFormDraftStore;
  final MemoryPressureController? memoryPressureController;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        if (database != null) databaseProvider.overrideWithValue(database!),
        if (database != null && startupRecovery == null)
          startupRecoveryEnabledProvider.overrideWithValue(false),
        if (startupRecovery != null)
          appStartupRecoveryProvider.overrideWithValue(startupRecovery!),
        if (initialLocale != null)
          initialLocaleProvider.overrideWithValue(initialLocale),
        if (platformServices != null)
          platformServicesProvider.overrideWithValue(platformServices!),
        if (imagePipeline != null)
          imagePipelineProvider.overrideWithValue(imagePipeline!),
        if (outputPaths != null)
          captureOutputPathsProvider.overrideWithValue(outputPaths!),
        if (projectExportPaths != null)
          projectExportPathsProvider.overrideWithValue(projectExportPaths!),
        if (shareService != null)
          shareFileServiceProvider.overrideWithValue(shareService!),
        if (privateFileStore != null)
          privateFileStoreProvider.overrideWithValue(privateFileStore!),
        if (externalLinkService != null)
          externalLinkServiceProvider.overrideWithValue(externalLinkService!),
        if (backgroundScheduler != null)
          captureBackgroundSchedulerProvider.overrideWithValue(
            backgroundScheduler!,
          ),
        if (backgroundWorkClient != null)
          backgroundWorkClientProvider.overrideWithValue(backgroundWorkClient!),
        if (completionNotificationService != null)
          completionNotificationServiceProvider.overrideWithValue(
            completionNotificationService!,
          ),
        if (memoryPressureService != null)
          memoryPressureServiceProvider.overrideWithValue(
            memoryPressureService!,
          ),
        if (captureFormDraftStore != null)
          captureFormDraftStoreProvider.overrideWithValue(
            captureFormDraftStore!,
          ),
        if (memoryPressureController != null)
          memoryPressureControllerProvider.overrideWithValue(
            memoryPressureController!,
          ),
      ],
      child: const SiteMarkApp(),
    );
  }
}
