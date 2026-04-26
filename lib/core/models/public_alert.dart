import 'dart:convert';

enum AlertSeverity {
  low('LOW', 0xFF4CAF50),
  medium('MEDIUM', 0xFFFFC107),
  high('HIGH', 0xFFF44336);

  final String label;
  final int colorValue;
  const AlertSeverity(this.label, this.colorValue);
}

class PublicAlert {
  final String id;
  final String text;
  final AlertSeverity severity;
  final DateTime createdAt;

  PublicAlert({
    required this.id,
    required this.text,
    required this.severity,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'sev': severity.index,
    'ts': createdAt.millisecondsSinceEpoch,
  };

  factory PublicAlert.fromJson(Map<String, dynamic> json) {
    return PublicAlert(
      id: json['id'] as String,
      text: json['text'] as String,
      severity: AlertSeverity.values[json['sev'] as int],
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['ts'] as int),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PublicAlert &&
      other.text.trim().toLowerCase() == text.trim().toLowerCase() &&
      other.severity == severity;

  @override
  int get hashCode => text.trim().toLowerCase().hashCode ^ severity.hashCode;
}
