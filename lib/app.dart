import 'package:animations/animations.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/background/capture_background_scheduler.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/features/capture/all_captures_screen.dart';
import 'package:sitemark/features/projects/project_form_screen.dart';
import 'package:sitemark/features/projects/project_list_screen.dart';
import 'package:sitemark/features/settings/global_settings_screen.dart';
import 'package:sitemark/features/capture/capture_form_screen.dart';
import 'package:sitemark/features/capture/capture_detail_screen.dart';
import 'package:sitemark/features/capture/capture_edit_screen.dart';
import 'package:sitemark/features/projects/project_detail_screen.dart';
import 'package:sitemark/features/projects/project_watermark_settings_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/motion.dart';
import 'package:sitemark/platform/external_link_service.dart';
import 'package:sitemark/platform/notification_service.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/workflow/app_startup_recovery.dart';
import 'package:sitemark/workflow/app_storage_service.dart';
import 'package:sitemark/workflow/capture_location_coordinator.dart';
import 'package:sitemark/workflow/capture_media_service.dart';
import 'package:sitemark/workflow/capture_workflow.dart';
import 'package:sitemark/workflow/location_permission_service.dart';
import 'package:sitemark/workflow/project_export_service.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(() {
    database.close();
  });
  return database;
});

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

final captureOutputPathsProvider = Provider<CaptureOutputPaths>(
  (ref) => AppCaptureOutputPaths(),
);

final projectExportPathsProvider = Provider<ProjectExportPaths>(
  (ref) => AppProjectExportPaths(),
);

final selectionExportPathsProvider = Provider<SelectionExportPaths>(
  (ref) => AppSelectionExportPaths(),
);

final shareFileServiceProvider = Provider<ShareFileService>(
  (ref) => SystemShareFileService(),
);

final privateFileStoreProvider = Provider<PrivateFileStore>(
  (ref) => DartIoPrivateFileStore(),
);

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
  );
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

/// Shared Axis (horizontal) page for hierarchical navigation (list → detail
/// → form/edit), per M3 motion guidance.
CustomTransitionPage<void> _sharedAxisPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: AppMotion.medium2,
    reverseTransitionDuration: AppMotion.medium2,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return SharedAxisTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        transitionType: SharedAxisTransitionType.horizontal,
        child: child,
      );
    },
    child: child,
  );
}

/// Fade Through page for top-level destination switches (projects ↔ all
/// records ↔ settings), per M3 motion guidance.
CustomTransitionPage<void> _fadeThroughPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: AppMotion.medium2,
    reverseTransitionDuration: AppMotion.medium2,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeThroughTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        child: child,
      );
    },
    child: child,
  );
}

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (context, state) =>
            _fadeThroughPage(state, const ProjectListScreen()),
        routes: [
          GoRoute(
            path: 'projects/new',
            pageBuilder: (context, state) =>
                _sharedAxisPage(state, const ProjectFormScreen()),
          ),
          GoRoute(
            path: 'records',
            pageBuilder: (context, state) =>
                _fadeThroughPage(state, const AllCapturesScreen()),
          ),
          GoRoute(
            path: 'settings',
            pageBuilder: (context, state) =>
                _fadeThroughPage(state, const GlobalSettingsScreen()),
          ),
          GoRoute(
            path: 'projects/:projectId',
            pageBuilder: (context, state) => _sharedAxisPage(
              state,
              ProjectDetailScreen(
                projectId: state.pathParameters['projectId']!,
              ),
            ),
            routes: [
              GoRoute(
                path: 'settings',
                pageBuilder: (context, state) => _sharedAxisPage(
                  state,
                  ProjectWatermarkSettingsScreen(
                    projectId: state.pathParameters['projectId']!,
                  ),
                ),
              ),
              GoRoute(
                path: 'capture',
                pageBuilder: (context, state) => _sharedAxisPage(
                  state,
                  CaptureFormScreen(
                    projectId: state.pathParameters['projectId']!,
                  ),
                ),
              ),
              GoRoute(
                path: 'captures/:captureId',
                pageBuilder: (context, state) => _sharedAxisPage(
                  state,
                  CaptureDetailScreen(
                    projectId: state.pathParameters['projectId']!,
                    captureId: state.pathParameters['captureId']!,
                  ),
                ),
                routes: [
                  GoRoute(
                    path: 'edit',
                    pageBuilder: (context, state) => _sharedAxisPage(
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
  );
  ref.onDispose(router.dispose);
  return router;
});

class SiteMarkApp extends ConsumerStatefulWidget {
  const SiteMarkApp({super.key});

  @override
  ConsumerState<SiteMarkApp> createState() => _SiteMarkAppState();
}

class _SiteMarkAppState extends ConsumerState<SiteMarkApp> {
  @override
  void initState() {
    super.initState();
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
    Future<void>.microtask(() async {
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
    });
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
        final lightScheme = useDynamicColor
            ? lightDynamic
            : ColorScheme.fromSeed(
                seedColor: const Color(0xFF176B55),
                brightness: Brightness.light,
              );
        final darkScheme = useDynamicColor
            ? darkDynamic
            : ColorScheme.fromSeed(
                seedColor: const Color(0xFF37C58B),
                brightness: Brightness.dark,
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
          theme: ThemeData(
            colorScheme: lightScheme,
            useMaterial3: true,
            inputDecorationTheme: const InputDecorationTheme(
              border: OutlineInputBorder(),
            ),
          ),
          darkTheme: ThemeData(colorScheme: darkScheme, useMaterial3: true),
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
      ],
      child: const SiteMarkApp(),
    );
  }
}
