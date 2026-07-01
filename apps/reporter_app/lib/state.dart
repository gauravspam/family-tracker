enum ApprovalStatus { pending, approved, removed }
enum TrackingMode { idle, live }

class ReporterState {
  final ApprovalStatus approval;
  final TrackingMode mode;
  final String? ingestToken;
  final String? ingestUrl;
  final DateTime? liveExpiresAt;

  const ReporterState({
    this.approval = ApprovalStatus.pending,
    this.mode = TrackingMode.idle,
    this.ingestToken,
    this.ingestUrl,
    this.liveExpiresAt,
  });

  ReporterState copyWith({
    ApprovalStatus? approval,
    TrackingMode? mode,
    String? ingestToken,
    String? ingestUrl,
    DateTime? liveExpiresAt,
    bool clearExpiry = false,
  }) {
    return ReporterState(
      approval: approval ?? this.approval,
      mode: mode ?? this.mode,
      ingestToken: ingestToken ?? this.ingestToken,
      ingestUrl: ingestUrl ?? this.ingestUrl,
      liveExpiresAt: clearExpiry ? null : (liveExpiresAt ?? this.liveExpiresAt),
    );
  }

  bool get isApproved => approval == ApprovalStatus.approved;
  bool get isLive => mode == TrackingMode.live;
}
