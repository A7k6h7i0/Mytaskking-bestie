import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import 'field_helpers.dart';

/// Full-screen field sub-page with system back + app bar back support.
class FieldSubScaffold extends StatelessWidget {
  const FieldSubScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.fallbackRoute = '/field',
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final String fallbackRoute;

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    return PopScope(
      canPop: context.canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) fieldGoBack(context, fallbackRoute: fallbackRoute);
      },
      child: Scaffold(
        backgroundColor: c.surface,
        appBar: AppBar(
          backgroundColor: c.surface,
          foregroundColor: c.text,
          leading: BackButton(
            onPressed: () => fieldGoBack(context, fallbackRoute: fallbackRoute),
          ),
          title: Text(title),
          actions: actions,
        ),
        body: body,
        floatingActionButton: floatingActionButton,
      ),
    );
  }
}
