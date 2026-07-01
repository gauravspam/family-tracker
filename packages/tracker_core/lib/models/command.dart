sealed class ReporterCommand {
  const ReporterCommand();

  factory ReporterCommand.fromJson(Map<String, dynamic> json) {
    final command = json['command'] as String?;
    switch (command) {
      case 'approved':
        return ApprovedCommand(
          ingestToken: json['ingestToken'] as String,
          ingestUrl: json['ingestUrl'] as String,
        );
      case 'live_mode':
        return LiveModeCommand(
          expiresAt: json['expiresAt'] as String,
        );
      case 'idle_mode':
        return const IdleModeCommand();
      case 'removed':
        return const RemovedCommand();
      default:
        throw ArgumentError('Unknown command: $command');
    }
  }
}

final class ApprovedCommand extends ReporterCommand {
  final String ingestToken;
  final String ingestUrl;

  const ApprovedCommand({
    required this.ingestToken,
    required this.ingestUrl,
  });
}

final class LiveModeCommand extends ReporterCommand {
  final String expiresAt;

  const LiveModeCommand({
    required this.expiresAt,
  });
}

final class IdleModeCommand extends ReporterCommand {
  const IdleModeCommand();
}

final class RemovedCommand extends ReporterCommand {
  const RemovedCommand();
}
