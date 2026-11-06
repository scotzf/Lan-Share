enum TransferState { active, done, failed }

class TransferProgress {
  const TransferProgress(
    this.state, {
    this.sent = 0,
    this.total = 0,
    this.name = '',
    this.overallSent = 0,
    this.overallTotal = 0,
  });
  final TransferState state;

  /// Bytes of the current file.
  final int sent;
  final int total;
  final String name;

  /// Bytes of all files together.
  final int overallSent;
  final int overallTotal;

  double get fraction => total == 0 ? 0 : sent / total;

  /// Progress across all files; falls back to the current file when unknown.
  double get overallFraction =>
      overallTotal == 0 ? fraction : (overallSent / overallTotal).clamp(0.0, 1.0);
}
