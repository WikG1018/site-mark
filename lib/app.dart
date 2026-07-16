import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/features/projects/project_form_screen.dart';
import 'package:sitemark/features/projects/project_list_screen.dart';
import 'package:sitemark/features/capture/capture_form_screen.dart';
import 'package:sitemark/features/capture/capture_detail_screen.dart';
import 'package:sitemark/features/capture/capture_edit_screen.dart';
import 'package:sitemark/features/projects/project_detail_screen.dart';
import 'package:sitemark/features/projects/project_watermark_settings_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/platform/platform_services.dart';
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

final captureWorkflowProvider = Provider<CaptureWorkflow>((ref) {
  return CaptureWorkflow(
    database: ref.watch(databaseProvider),
    platform: ref.watch(platformServicesProvider),
    images: ref.watch(imagePipelineProvider),
    outputPaths: ref.watch(captureOutputPathsProvider),
    fileStore: ref.watch(privateFileStoreProvider),
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
      if (ref.read(startupRecoveryEnabledProvider)) {
        await ref.read(captureWorkflowProvider).recoverPendingCapture();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'SiteMark 工程印记',
      locale: ref.watch(initialLocaleProvider),
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
  });

  final AppDatabase? database;
  final Locale? initialLocale;
  final PlatformServices? platformServices;
  final ImagePipeline? imagePipeline;
  final CaptureOutputPaths? outputPaths;
  final ProjectExportPaths? projectExportPaths;
  final ShareFileService? shareService;
  final PrivateFileStore? privateFileStore;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        if (database != null) databaseProvider.overrideWithValue(database!),
        if (database != null)
          startupRecoveryEnabledProvider.overrideWithValue(false),
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
      ],
      child: const SiteMarkApp(),
    );
  }
}
