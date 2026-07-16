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
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/workflow/app_startup_recovery.dart';
import 'package:sitemark/workflow/capture_workflow.dart';
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

final imagePipelineProvider = Provider<ImagePipeline>(
  (ref) => RustImagePipeline(),
);

final captureOutputPathsProvider = Provider<CaptureOutputPaths>(
  (ref) => AppCaptureOutputPaths(),
);

final projectExportPathsProvider = Provider<ProjectExportPaths>(
  (ref) => AppProjectExportPaths(),
);

final shareFileServiceProvider = Provider<ShareFileService>(
  (ref) => SystemShareFileService(),
);

final privateFileStoreProvider = Provider<PrivateFileStore>(
  (ref) => DartIoPrivateFileStore(),
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

final captureWorkflowProvider = Provider<CaptureWorkflow>((ref) {
  return CaptureWorkflow(
    database: ref.watch(databaseProvider),
    platform: ref.watch(platformServicesProvider),
    images: ref.watch(imagePipelineProvider),
    outputPaths: ref.watch(captureOutputPathsProvider),
    fileStore: ref.watch(privateFileStoreProvider),
    scheduler: ref.watch(captureBackgroundSchedulerProvider),
  );
});

final appStartupRecoveryProvider = Provider<AppStartupRecovery>((ref) {
  return AppStartupRecovery(
    recoverCamera: () =>
        ref.read(captureWorkflowProvider).recoverPendingCapture(),
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
  );
});

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const ProjectListScreen(),
        routes: [
          GoRoute(
            path: 'projects/new',
            builder: (context, state) => const ProjectFormScreen(),
          ),
          GoRoute(
            path: 'records',
            builder: (context, state) => const AllCapturesScreen(),
          ),
          GoRoute(
            path: 'settings',
            builder: (context, state) => const GlobalSettingsScreen(),
          ),
          GoRoute(
            path: 'projects/:projectId',
            builder: (context, state) => ProjectDetailScreen(
              projectId: state.pathParameters['projectId']!,
            ),
            routes: [
              GoRoute(
                path: 'settings',
                builder: (context, state) => ProjectWatermarkSettingsScreen(
                  projectId: state.pathParameters['projectId']!,
                ),
              ),
              GoRoute(
                path: 'capture',
                builder: (context, state) => CaptureFormScreen(
                  projectId: state.pathParameters['projectId']!,
                ),
              ),
              GoRoute(
                path: 'captures/:captureId',
                builder: (context, state) => CaptureDetailScreen(
                  projectId: state.pathParameters['projectId']!,
                  captureId: state.pathParameters['captureId']!,
                ),
                routes: [
                  GoRoute(
                    path: 'edit',
                    builder: (context, state) => CaptureEditScreen(
                      projectId: state.pathParameters['projectId']!,
                      captureId: state.pathParameters['captureId']!,
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
    Future<void>.microtask(() async {
      if (!ref.read(startupRecoveryEnabledProvider)) return;
      await ref.read(appStartupRecoveryProvider).run();
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider).value;
    // `initialLocaleProvider` is null in production and only set by widget
    // tests to force a locale; when set it takes precedence over persisted
    // settings so existing tests keep driving the locale explicitly.
    final forcedLocale = ref.watch(initialLocaleProvider);
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
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF176B55),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF37C58B),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      routerConfig: ref.watch(routerProvider),
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
    this.backgroundScheduler,
    this.backgroundWorkClient,
    this.startupRecovery,
  });

  final AppDatabase? database;
  final Locale? initialLocale;
  final PlatformServices? platformServices;
  final ImagePipeline? imagePipeline;
  final CaptureOutputPaths? outputPaths;
  final ProjectExportPaths? projectExportPaths;
  final ShareFileService? shareService;
  final PrivateFileStore? privateFileStore;
  final CaptureBackgroundScheduler? backgroundScheduler;
  final BackgroundWorkClient? backgroundWorkClient;
  final AppStartupRecovery? startupRecovery;

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
        if (backgroundScheduler != null)
          captureBackgroundSchedulerProvider.overrideWithValue(
            backgroundScheduler!,
          ),
        if (backgroundWorkClient != null)
          backgroundWorkClientProvider.overrideWithValue(backgroundWorkClient!),
      ],
      child: const SiteMarkApp(),
    );
  }
}
