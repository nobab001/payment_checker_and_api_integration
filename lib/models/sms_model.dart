/// Wrapper for parsed SMS rows from the server (e.g. /api/sms).
class SmsModel {
  final int id;
  final int userId;
  final int deviceId;
  final String address;
  final String body;
  final String timestamp;
  final String simSlot;
  final int readStatus;

  const SmsModel({
    required this.id,
    required this.userId,
    required this.deviceId,
    required this.address,
    required this.body,
    required this.timestamp,
    required this.simSlot,
    this.readStatus = 0,
  });

  factory SmsModel.fromJson(Map<String, dynamic> m) {
    return SmsModel(
      id: (m['id'] is int) ? m['id'] : int.tryParse('${m['id']}') ?? 0,
      userId: (m['user_id'] ?? m['userId'] is int)
          ? m['user_id']
          : int.tryParse('${m['userId']}') ?? 0,
      deviceId: (m['device_id'] ?? m['deviceId'] is int)
          ? m['device_id']
          : int.tryParse('${m['deviceId']}') ?? 0,
      address: (m['address'] ?? m['sender'] ?? m['from'] ?? '').toString(),
      body: (m['body'] ?? m['message'] ?? m['msg'] ?? '').toString(),
      timestamp: (m['timestamp'] ?? m['date'] ?? m['time'] ?? '').toString(),
      simSlot: (m['sim_slot'] ?? m['simSlot'] ?? m['slot'] ?? '0').toString(),
      readStatus: (m['read_status'] ?? m['readStatus'] ?? m['read'] ?? 0) is int
          ? m['read_status'] ?? m['readStatus'] ?? m['read']
          : 0,
    );
  }
}
