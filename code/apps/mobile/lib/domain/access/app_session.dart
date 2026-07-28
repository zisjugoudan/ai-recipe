enum AppSessionKind { guest, authenticated }

class AppSession {
  const AppSession._({
    required this.kind,
    this.userId,
    this.displayName,
    this.signedInAt,
  });

  const AppSession.guest() : this._(kind: AppSessionKind.guest);

  factory AppSession.authenticated({
    required String userId,
    String? displayName,
    required DateTime signedInAt,
  }) {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) {
      throw const FormatException('Authenticated session userId is required.');
    }
    final normalizedDisplayName = displayName?.trim();
    return AppSession._(
      kind: AppSessionKind.authenticated,
      userId: normalizedUserId,
      displayName:
          normalizedDisplayName == null || normalizedDisplayName.isEmpty
          ? null
          : normalizedDisplayName,
      signedInAt: signedInAt,
    );
  }

  final AppSessionKind kind;
  final String? userId;
  final String? displayName;
  final DateTime? signedInAt;

  bool get isAuthenticated => kind == AppSessionKind.authenticated;

  Map<String, Object?> toJson() {
    return switch (kind) {
      AppSessionKind.guest => const <String, Object?>{
        'schemaVersion': 1,
        'kind': 'guest',
      },
      AppSessionKind.authenticated => <String, Object?>{
        'schemaVersion': 1,
        'kind': 'authenticated',
        'userId': userId,
        'displayName': displayName,
        'signedInAt': signedInAt?.toIso8601String(),
      },
    };
  }

  @override
  bool operator ==(Object other) {
    return other is AppSession &&
        other.kind == kind &&
        other.userId == userId &&
        other.displayName == displayName &&
        other.signedInAt == signedInAt;
  }

  @override
  int get hashCode => Object.hash(kind, userId, displayName, signedInAt);
}
