/// Support inbox / Issues access helpers (mirrors web `supportAccess.ts`).
const assigneeUpdateStatuses = ['IN_PROGRESS', 'RESOLVED', 'CLOSED'];

List<Map<String, dynamic>> assigneeStatusOptions(
  List<Map<String, dynamic>> all,
) {
  return all
      .where((s) => assigneeUpdateStatuses.contains(s['value']?.toString()))
      .toList();
}

String defaultAssigneeStatus(String current) {
  return assigneeUpdateStatuses.contains(current) ? current : 'IN_PROGRESS';
}

bool assigneeCanUpdateIssueStatus({
  required bool isSuperAdmin,
  required String ticketStatus,
  required List<String> assigneeIds,
  required String? userId,
}) {
  if (isSuperAdmin) return true;
  if (ticketStatus == 'CLOSED') return false;
  if (userId == null) return false;
  return assigneeIds.contains(userId);
}
