enum TransferState { active, done, failed }

class TransferProgress {
  const TransferProgress(this.state, {this.sent = 0, this.total = 0, this.name = ''});
  final TransferState state;
  final int sent;
  final int total;
  final String name;
  double get fraction => total == 0 ? 0 : sent / total;
}
