class AppStartupRecovery {
  const AppStartupRecovery({
    required this.recoverCamera,
    required this.resolveLocations,
    required this.reconcileQueue,
    required this.cleanupInterruptedImports,
  });

  final Future<void> Function() recoverCamera;
  final Future<void> Function() resolveLocations;
  final Future<void> Function() reconcileQueue;
  final Future<void> Function() cleanupInterruptedImports;

  Future<void> run() async {
    // Remove half-imported projects first so they never surface in the UI
    // or confuse the other recovery steps.
    await cleanupInterruptedImports();
    await recoverCamera();
    await resolveLocations();
    await reconcileQueue();
  }
}
