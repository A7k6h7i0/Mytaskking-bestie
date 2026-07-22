String formatSubscriptionDate(dynamic value) {
  if (value == null) return '';
  final raw = value.toString();
  if (raw.isEmpty) return '';
  return raw.replaceFirst('T', ' ').split('.').first;
}

String subscriptionStatusLabel(Map<String, dynamic>? sub) {
  if (sub == null) return 'No subscription';
  final status = (sub['status'] ?? 'NONE').toString();
  switch (status) {
    case 'TRIAL_ACTIVE':
      final ends = formatSubscriptionDate(sub['trialEndsAt']);
      return ends.isEmpty
          ? '7-day free trial'
          : '7-day free trial (ends $ends)';
    case 'TRIAL_REQUESTED':
      return 'Trial pending approval';
    case 'PAID':
      final plan = sub['planLabel']?.toString() ??
          (sub['planMonths'] != null
              ? '${sub['planMonths']} month plan'
              : 'Paid plan');
      final until = formatSubscriptionDate(sub['paidUntil']);
      return until.isEmpty ? plan : '$plan (until $until)';
    case 'PAYMENT_PENDING':
      return 'Payment pending';
    case 'EXPIRED':
      return 'Subscription expired';
    case 'NONE':
      return 'Not subscribed';
    default:
      return status.replaceAll('_', ' ');
  }
}
