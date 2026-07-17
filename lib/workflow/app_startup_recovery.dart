class AppStartupRecovery {
  const AppStartupRecovery({
    required this.recoverCamera,
    required this.resolveLocations,
    required this.reconcileQueue,
  });

  final Future<void> Function() recoverCamera;
  final Future<void> Function() resolveLocations;
  final Future<void> Function() reconcileQueue;

  Future<void> run() async {
    await recoverCamera();
    await resolveLocations();
    await reconcileQueue();
  }
}
