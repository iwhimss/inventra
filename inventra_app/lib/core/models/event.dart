class SyncEvent {
  final String id;
  final String entityType;
  final String entityId;
  final String action;
  final String payload;
  final bool isSynced;
  final String? deviceId;
  final DateTime createdAt;

  SyncEvent({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.payload,
    this.isSynced = false,
    this.deviceId,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'entity_type': entityType,
      'entity_id': entityId,
      'action': action,
      'payload': payload,
      'is_synced': isSynced ? 1 : 0,
      'device_id': deviceId,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory SyncEvent.fromMap(Map<String, dynamic> map) {
    return SyncEvent(
      id: map['id'],
      entityType: map['entity_type'],
      entityId: map['entity_id'],
      action: map['action'],
      payload: map['payload'],
      isSynced: map['is_synced'] == 1,
      deviceId: map['device_id'],
      createdAt: DateTime.parse(map['created_at']),
    );
  }
}
