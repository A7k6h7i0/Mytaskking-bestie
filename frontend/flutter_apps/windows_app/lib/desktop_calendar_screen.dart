import 'package:flutter/material.dart';
import 'package:mytaskking_core/mytaskking_core.dart';

/// Windows calendar — delegates to the shared Bestie calendar view.
class DesktopCalendarScreen extends StatelessWidget {
  const DesktopCalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const BestieCalendarView();
  }
}
