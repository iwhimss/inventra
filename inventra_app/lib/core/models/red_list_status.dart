class RedListStatus {
  final bool isOnRedList;
  final bool isOverLimit;
  final bool isOverdue;
  final double balance;

  const RedListStatus({
    required this.isOnRedList,
    required this.isOverLimit,
    required this.isOverdue,
    required this.balance,
  });

  /// Kırmızı listedeyse kısa açıklama
  String get reason {
    if (isOverLimit && isOverdue) return 'Limit aşıldı ve ödeme gecikmesi var';
    if (isOverLimit) return 'Kredi limiti aşıldı';
    if (isOverdue) return 'Ödeme süresi geçti';
    return '';
  }

  static const RedListStatus normal = RedListStatus(
    isOnRedList: false,
    isOverLimit: false,
    isOverdue: false,
    balance: 0,
  );
}
