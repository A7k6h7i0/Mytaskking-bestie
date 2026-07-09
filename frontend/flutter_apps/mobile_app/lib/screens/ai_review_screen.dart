import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';

final aiReviewRecordingsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final api = ref.watch(apiProvider);
  return api.aiReviewRecordings();
});

const _intentLabels = {
  'interested in the product': 'Interested',
  'confirmed the deal': 'Deal Confirmed',
  'rejected the offer': 'Rejected',
  'needs follow up': 'Needs Follow Up',
};

String _intentLabel(String raw) =>
    _intentLabels[raw.trim().toLowerCase()] ?? raw;

class AiReviewScreen extends ConsumerStatefulWidget {
  const AiReviewScreen({super.key});

  @override
  ConsumerState<AiReviewScreen> createState() => _AiReviewScreenState();
}

class _AiReviewScreenState extends ConsumerState<AiReviewScreen> {
  String? _selectedId;
  String _phase = 'idle';
  Map<String, dynamic>? _report;
  String? _error;
  Timer? _pollTimer;
  DateTime? _deadline;

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Map<String, dynamic>? get _selected {
    if (_selectedId == null) return null;
    final items = ref.read(aiReviewRecordingsProvider).valueOrNull ?? [];
    for (final item in items) {
      if (item['id']?.toString() == _selectedId) return item;
    }
    return null;
  }

  void _clearPoll() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _pollJob(String jobId) async {
    if (_deadline != null && DateTime.now().isAfter(_deadline!)) {
      setState(() {
        _phase = 'failed';
        _error = 'Analysis timed out after 5 minutes';
      });
      _clearPoll();
      return;
    }
    try {
      final job = await ref.read(apiProvider).getAiReviewJob(jobId);
      final status = job['status']?.toString() ?? '';
      if (status == 'completed' && job['output'] is Map) {
        final output = (job['output'] as Map).cast<String, dynamic>();
        setState(() {
          _report = {
            'text': output['text']?.toString() ?? '',
            'intent': output['intent']?.toString() ?? '',
            'confidence': (output['confidence'] as num?)?.toDouble() ?? 0,
          };
          _phase = 'completed';
          _error = null;
        });
        _clearPoll();
        return;
      }
      if (status == 'failed') {
        setState(() {
          _phase = 'failed';
          _error = job['error']?.toString() ?? 'Analysis failed';
        });
        _clearPoll();
        return;
      }
      setState(() => _phase = 'pending');
      _pollTimer = Timer(const Duration(seconds: 2), () => _pollJob(jobId));
    } catch (e) {
      setState(() {
        _phase = 'failed';
        _error = formatApiError(e);
      });
      _clearPoll();
    }
  }

  Future<void> _analyse() async {
    final id = _selectedId;
    if (id == null || id.isEmpty) {
      bestieToast(context, 'Select a recording first',
          kind: BestieToastKind.warning);
      return;
    }
    _clearPoll();
    setState(() {
      _phase = 'uploading';
      _report = null;
      _error = null;
    });
    _deadline = DateTime.now().add(const Duration(minutes: 5));
    try {
      final submitted = await ref.read(apiProvider).submitAiReviewAnalyse(id);
      final jobId = submitted['jobID']?.toString();
      if (jobId == null || jobId.isEmpty) throw 'No job ID returned';
      setState(() => _phase = 'pending');
      _pollTimer = Timer(const Duration(seconds: 2), () => _pollJob(jobId));
    } catch (e) {
      setState(() {
        _phase = 'failed';
        _error = formatApiError(e);
      });
      if (mounted) {
        bestieToast(context, 'Analysis failed',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    }
  }

  String _recordingLabel(Map<String, dynamic> r) {
    final lead = (r['lead'] as Map?)?.cast<String, dynamic>();
    final agent = (r['agent'] as Map?)?.cast<String, dynamic>();
    final leadName = lead?['name']?.toString() ?? 'Unknown lead';
    final leadPhone = lead?['phone']?.toString() ?? r['toNumber']?.toString();
    final from = r['fromNumber']?.toString() ?? '—';
    final agentName = agent?['name']?.toString() ?? 'Telecaller';
    final created = DateTime.tryParse(r['createdAt']?.toString() ?? '')?.toLocal();
    final when = created == null
        ? ''
        : '${_month(created.month)} ${created.day}, ${_two(created.hour)}:${_two(created.minute)}';
    return '$leadName · $leadPhone · from $from · by $agentName · $when';
  }

  String _month(int m) => const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ][m - 1];

  String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final colors = BestieColors.of(context);
    final role = ref.watch(authStoreProvider).user?.role ?? '';
    final isAdmin = role == 'ADMIN' || role == 'SUPER_ADMIN';
    final recordings = ref.watch(aiReviewRecordingsProvider);
    final busy = _phase == 'uploading' || _phase == 'pending';
    final selected = _selected;

    if (!isAdmin) {
      return const Scaffold(
        body: BestieEmptyState(
          icon: Icons.lock_outline,
          title: 'Admin access only',
          description: 'AI Review is available to admins and super admins.',
        ),
      );
    }

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        title: const Text('AI Review'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(aiReviewRecordingsProvider),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: recordings.when(
        loading: () => const Center(child: BestieSpinner()),
        error: (e, _) => BestieEmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load recordings',
          description: formatApiError(e),
        ),
        data: (items) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Text(
                'Analyse telecaller recordings with Voice AI.',
                style: TextStyle(color: colors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Text(
                'CHOOSE TELECALLER RECORDING',
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedId,
                isExpanded: true,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(BestieTokens.rMd),
                  ),
                  hintText: '— Select a recording —',
                ),
                items: [
                  for (final r in items)
                    DropdownMenuItem(
                      value: r['id']?.toString(),
                      child: Text(
                        _recordingLabel(r),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                ],
                onChanged: busy
                    ? null
                    : (v) => setState(() {
                          _selectedId = v;
                          _phase = 'idle';
                          _report = null;
                          _error = null;
                          _clearPoll();
                        }),
              ),
              if (selected != null) ...[
                const SizedBox(height: 16),
                _DetailsCard(recording: selected),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: (_selectedId == null || busy) ? null : _analyse,
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.auto_awesome_rounded),
                label: Text(busy
                    ? (_phase == 'uploading'
                        ? 'Uploading & starting…'
                        : 'Processing analysis…')
                    : 'Analyse'),
              ),
              if (busy) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [colors.surface, colors.brandSoft],
                    ),
                    borderRadius: BorderRadius.circular(BestieTokens.rLg),
                    border: Border.all(color: colors.brand.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.graphic_eq_rounded,
                          size: 32, color: colors.brandStrong),
                      const SizedBox(height: 10),
                      const Text(
                        'Voice AI Analysis in progress',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _phase == 'uploading'
                            ? 'Uploading recording to the AI server…'
                            : 'Transcribing and detecting intent — may take 30–60 seconds.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.textMuted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
              if (_phase == 'failed' && _error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors.dangerSoft,
                    borderRadius: BorderRadius.circular(BestieTokens.rMd),
                  ),
                  child: Text(_error!,
                      style: TextStyle(color: colors.danger, fontSize: 13)),
                ),
              ],
              if (_phase == 'completed' && _report != null) ...[
                const SizedBox(height: 24),
                _ReportCard(report: _report!),
              ],
              if (items.isEmpty) ...[
                const SizedBox(height: 24),
                const BestieEmptyState(
                  icon: Icons.mic_none_outlined,
                  title: 'No recordings yet',
                  description:
                      'Telecaller recordings with audio will appear here.',
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  final Map<String, dynamic> recording;

  const _DetailsCard({required this.recording});

  @override
  Widget build(BuildContext context) {
    final colors = BestieColors.of(context);
    final lead = (recording['lead'] as Map?)?.cast<String, dynamic>();
    final agent = (recording['agent'] as Map?)?.cast<String, dynamic>();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.brandSoft.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(BestieTokens.rMd),
        border: Border.all(color: colors.brand.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _detail('Lead', lead?['name']?.toString() ?? '—'),
          _detail('Lead phone', lead?['phone']?.toString() ?? recording['toNumber']?.toString() ?? '—'),
          if ((lead?['company']?.toString() ?? '').isNotEmpty)
            _detail('Company', lead!['company']!.toString()),
          _detail('Called from', recording['fromNumber']?.toString() ?? '—'),
          _detail('Called to', recording['toNumber']?.toString() ?? '—'),
          _detail('Telecaller', agent?['name']?.toString() ?? '—'),
          if ((recording['recordingUrl']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Recording URL',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: BestieColors.of(context).textMuted,
                )),
            const SizedBox(height: 4),
            Text(
              recording['recordingUrl']!.toString(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: BestieColors.of(context).textSoft,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _detail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final Map<String, dynamic> report;
  const _ReportCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final colors = BestieColors.of(context);
    final confidence = (report['confidence'] as num?)?.toDouble() ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [colors.surface, colors.brandSoft],
            ),
            borderRadius: BorderRadius.circular(BestieTokens.rLg),
            border: Border.all(color: colors.brand.withValues(alpha: 0.2)),
          ),
          child: const Text(
            'VOICE AI ANALYSIS REPORT',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: Color(0xFF0066FF),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ANALYSIS DETAILS',
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  )),
              const SizedBox(height: 16),
              _bulletRow(
                title: 'Detected Intent',
                body: Text(
                  _intentLabel(report['intent']?.toString() ?? ''),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0066FF),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _bulletRow(
                title: 'Transcript Response',
                body: Text(
                  report['text']?.toString() ?? '',
                  style: const TextStyle(fontSize: 14, height: 1.55),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            children: [
              Text('OVERALL ANALYSIS CONFIDENCE',
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  )),
              const SizedBox(height: 12),
              _ConfidenceGauge(value: confidence),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bulletRow({required String title, required Widget body}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF0066FF), width: 2.5),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
                  )),
              const SizedBox(height: 4),
              body,
            ],
          ),
        ),
      ],
    );
  }
}

class _ConfidenceGauge extends StatelessWidget {
  final double value;
  const _ConfidenceGauge({required this.value});

  @override
  Widget build(BuildContext context) {
    final pct = value.clamp(0.0, 100.0);
    return SizedBox(
      height: 130,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          CustomPaint(
            size: const Size(240, 120),
            painter: _GaugePainter(pct: pct),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Score',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
              Text(
                '${pct.toStringAsFixed(1)}%',
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0066FF),
                ),
              ),
            ],
          ),
          const Positioned(
            bottom: 0,
            left: 18,
            right: 18,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('0%', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                Text('100%', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double pct;
  _GaugePainter({required this.pct});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 14.0;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height * 2 - stroke);
    const start = math.pi;
    const sweep = math.pi;
    final track = Paint()
      ..color = const Color(0xFFE6F0FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..color = const Color(0xFF0066FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, start, sweep, false, track);
    canvas.drawArc(rect, start, sweep * (pct / 100), false, fill);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.pct != pct;
}
