import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_filter.dart';
import 'package:sitemark/features/capture/capture_date_filter_bar.dart';
import 'package:sitemark/features/capture/capture_record_card.dart';
import 'package:sitemark/l10n/app_strings.dart';

/// Global capture-records surface.
///
/// Combines an optional project filter, the shared [CaptureDateFilterBar], and
/// [CaptureRecordCard]s sourced from [AppDatabase.watchCaptureSummaries]. The
/// unfiltered [AppDatabase.watchAllCaptureSummaries] stream drives both the
/// project dropdown options and the cascading date options. Record taps route
/// to the existing project-scoped capture detail using the IDs carried by each
/// [CaptureSummary].
class AllCapturesScreen extends ConsumerStatefulWidget {
  const AllCapturesScreen({super.key});

  @override
  ConsumerState<AllCapturesScreen> createState() => _AllCapturesScreenState();
}

class _AllCapturesScreenState extends ConsumerState<AllCapturesScreen> {
  CaptureFilter _filter = const CaptureFilter();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final database = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(title: Text(strings.allRecords)),
      body: StreamBuilder<List<Project>>(
        stream: database.watchProjects(),
        builder: (context, projectSnapshot) {
          return StreamBuilder<List<CaptureSummary>>(
            stream: database.watchAllCaptureSummaries(),
            builder: (context, allSnapshot) {
              final allSummaries = allSnapshot.data ?? const [];
              final projects = projectSnapshot.data ?? const [];
              return Column(
                children: [
                  _filterBar(
                    context,
                    strings,
                    database,
                    projects,
                    allSummaries,
                  ),
                  Expanded(
                    child: StreamBuilder<List<CaptureSummary>>(
                      stream: database.watchCaptureSummaries(_filter),
                      builder: (context, filteredSnapshot) {
                        if (!filteredSnapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final rows = filteredSnapshot.data!;
                        if (rows.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Text(
                                allSummaries.isEmpty
                                    ? strings.noCaptures
                                    : strings.filteredEmpty,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                            ),
                          );
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                          itemCount: rows.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final summary = rows[index];
                            return CaptureRecordCard(
                              summary: summary,
                              showProjectName: true,
                              onTap: () => context.go(
                                '/projects/${summary.capture.projectId}'
                                '/captures/${summary.capture.id}',
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _filterBar(
    BuildContext context,
    AppStrings strings,
    AppDatabase database,
    List<Project> projects,
    List<CaptureSummary> allSummaries,
  ) {
    final entries = <DropdownMenuEntry<String?>>[
      DropdownMenuEntry<String?>(value: null, label: strings.allProjects),
    ];
    for (final project in projects) {
      entries.add(
        DropdownMenuEntry<String?>(value: project.id, label: project.name),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 240,
              child: DropdownMenu<String?>(
                key: const Key('project-filter'),
                initialSelection: _filter.projectId,
                expandedInsets: EdgeInsets.zero,
                dropdownMenuEntries: entries,
                onSelected: (value) => setState(() {
                  // Reset the entire filter so the project -> year -> month ->
                  // day cascade clears invalid children: changing the project
                  // must drop a previously-selected year/month/day that may not
                  // exist under the new project.
                  _filter = CaptureFilter(projectId: value);
                }),
              ),
            ),
          ),
          const SizedBox(height: 4),
          CaptureDateFilterBar(
            filter: _filter,
            summaries: allSummaries,
            onChanged: (next) => setState(() => _filter = next),
          ),
        ],
      ),
    );
  }
}
