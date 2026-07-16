class AppStartupRecovery {
  const AppStartupRecovery({
    required this.recoverCamera,
    required this.reconcileQueue,
  });

  final Future<void> Function() recoverCamera;
  final Future<void> Function() reconcileQueue;

  Future<void> run() async {
    await recoverCamera();
    await reconcileQueue();
  }
}
