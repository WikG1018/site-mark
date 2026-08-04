## Commit list

5ed3047 feat: add nested settings routes

## Diff stat

 lib/app.dart | 58 ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
 1 file changed, 58 insertions(+)

## Full diff

diff --git a/lib/app.dart b/lib/app.dart
index 9907591..8520d09 100644
--- a/lib/app.dart
+++ b/lib/app.dart
@@ -3,20 +3,27 @@ import 'package:dynamic_color/dynamic_color.dart';
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
+import 'package:sitemark/features/settings/sections/about_section_screen.dart';
+import 'package:sitemark/features/settings/sections/appearance_section_screen.dart';
+import 'package:sitemark/features/settings/sections/language_section_screen.dart';
+import 'package:sitemark/features/settings/sections/location_section_screen.dart';
+import 'package:sitemark/features/settings/sections/notification_section_screen.dart';
+import 'package:sitemark/features/settings/sections/storage_section_screen.dart';
+import 'package:sitemark/features/settings/sections/watermark_defaults_section_screen.dart';
 import 'package:sitemark/features/capture/capture_form_screen.dart';
 import 'package:sitemark/features/capture/capture_detail_screen.dart';
 import 'package:sitemark/features/capture/capture_edit_screen.dart';
 import 'package:sitemark/features/projects/project_detail_screen.dart';
 import 'package:sitemark/features/projects/project_watermark_settings_screen.dart';
 import 'package:sitemark/l10n/app_strings.dart';
 import 'package:sitemark/motion.dart';
 import 'package:sitemark/platform/capture_form_draft_store.dart';
 import 'package:sitemark/platform/external_link_service.dart';
 import 'package:sitemark/platform/memory_pressure_coordinator.dart';
@@ -267,20 +274,71 @@ final routerProvider = Provider<GoRouter>((ref) {
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
+            routes: [
+              GoRoute(
+                path: 'watermark',
+                pageBuilder: (context, state) => _sharedAxisPage(
+                  state,
+                  const WatermarkDefaultsSectionScreen(),
+                ),
+              ),
+              GoRoute(
+                path: 'appearance',
+                pageBuilder: (context, state) => _sharedAxisPage(
+                  state,
+                  const AppearanceSectionScreen(),
+                ),
+              ),
+              GoRoute(
+                path: 'language',
+                pageBuilder: (context, state) => _sharedAxisPage(
+                  state,
+                  const LanguageSectionScreen(),
+                ),
+              ),
+              GoRoute(
+                path: 'storage',
+                pageBuilder: (context, state) => _sharedAxisPage(
+                  state,
+                  const StorageSectionScreen(),
+                ),
+              ),
+              GoRoute(
+                path: 'location',
+                pageBuilder: (context, state) => _sharedAxisPage(
+                  state,
+                  const LocationSectionScreen(),
+                ),
+              ),
+              GoRoute(
+                path: 'notification',
+                pageBuilder: (context, state) => _sharedAxisPage(
+                  state,
+                  const NotificationSectionScreen(),
+                ),
+              ),
+              GoRoute(
+                path: 'about',
+                pageBuilder: (context, state) => _sharedAxisPage(
+                  state,
+                  const AboutSectionScreen(),
+                ),
+              ),
+            ],
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
