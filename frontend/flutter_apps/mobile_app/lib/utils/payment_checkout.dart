import 'package:flutter/material.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:url_launcher/url_launcher.dart';

const paymentCheckoutBaseUrl = String.fromEnvironment(
  'PAYMENT_URL',
  defaultValue: 'https://payment.mytaskking.com',
);

Uri paymentCheckoutUri({
  required String tenantId,
  required String planId,
}) {
  return Uri.parse(
    '$paymentCheckoutBaseUrl/checkout?tenantId=$tenantId&plan=$planId',
  );
}

Future<bool> launchPaymentCheckout(
  BuildContext context, {
  required String tenantId,
  required String planId,
}) async {
  final uri = paymentCheckoutUri(tenantId: tenantId, planId: planId);
  final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!launched && context.mounted) {
    bestieToast(
      context,
      'Could not open payment page',
      body: 'Open $uri in your browser.',
      kind: BestieToastKind.error,
    );
  }
  return launched;
}
