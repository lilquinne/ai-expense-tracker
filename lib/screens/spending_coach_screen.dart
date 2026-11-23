import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/expense_provider.dart';
import '../services/spending_coach_service.dart';
import '../utils/app_theme.dart';
import '../widgets/savings_plan_dialog.dart';
import 'login_screen.dart';

class SpendingCoachScreen extends StatefulWidget {
  const SpendingCoachScreen(
      {super.key, this.service, this.prepare, this.sessionCheck});
  final SpendingCoachService? service;
  final Future<void> Function(String)? prepare;
  final bool Function(String)? sessionCheck;
  @override
  State<SpendingCoachScreen> createState() => _SpendingCoachScreenState();
}

class _ChatMessage {
  const _ChatMessage(this.text, {this.reply});
  final String text;
  final CoachReply? reply;
  bool get isUser => reply == null;
}

class _SpendingCoachScreenState extends State<SpendingCoachScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_ChatMessage>[];
  late final SpendingCoachService _service;
  StreamSubscription<AuthState>? _auth;
  String? _owner, _error;
  bool _busy = false;

  int _generation = 0;
  Map<String, dynamic>? _activePlan;
  CoachReply? _latest;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? SpendingCoachService();
    if (widget.sessionCheck == null) {
      try {
        _auth = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
          if (mounted && state.session?.user.id != _owner) setState(_clear);
        });
      } catch (_) {
        /* Sign-in prompt remains available if cloud is unconfigured. */
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final owner = context.watch<ExpenseProvider>().userId;
    if (_owner != owner) {
      _clear();
      _owner = owner;
    }
  }

  bool get _signedIn =>
      _owner != null &&
      (widget.sessionCheck ?? SpendingCoachService.ownsSession)(_owner!);

  void _clear() {
    _generation++;
    _messages.clear();
    _input.clear();
    _latest = null;
    _activePlan = null;
    _error = null;
    _busy = false;
  }

  @override
  void dispose() {
    _auth?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients)
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut);
      });

  Future<void> _send(String question) async {
    if (_busy || !_signedIn || question.trim().isEmpty) return;
    final provider = context.read<ExpenseProvider>();
    final owner = _owner!, generation = _generation;
    final now = DateTime.now();
    final selected = provider.selectedMonth;
    final month =
        selected.isAfter(DateTime(now.year, now.month + 1, 0)) ? now : selected;
    final history = _messages
        .map((m) => {
              'role': m.isUser ? 'user' : 'assistant',
              'content':
                  m.text.length > 4000 ? m.text.substring(0, 4000) : m.text
            })
        .toList();
    final message = _ChatMessage(question.trim());
    setState(() {
      _busy = true;
      _error = null;
      _messages.add(message);
      _input.clear();
    });
    _scrollDown();
    bool active() =>
        mounted && generation == _generation && owner == _owner && _signedIn;
    try {
      CoachReply? result;
      result = await _service.askLocal(
          owner: owner,
          message: question,
          month: selected,
          currency: provider.currencySymbol);
      if (!active()) return;
      if (result == null) {
        if (widget.prepare != null) {
          await widget.prepare!(owner);
        } else {
          await SpendingCoachService.prepare(owner, month: month);
        }
        if (!active()) return;
        result = await _service.ask(
            message: question,
            month: month,
            currency: provider.currencySymbol,
            history: history,
            plan: _activePlan);
      }
      if (!active()) return;
      final response = result;
      setState(() {
        _messages.add(_ChatMessage(response.answer, reply: response));
        _latest = response;
      });
      _scrollDown();
    } catch (error) {
      if (!active()) return;
      setState(() {
        _messages.remove(message);
        _input.text = question;
        _error = error is CoachException
            ? error.message
            : 'Could not reach Coach. Please try again.';
      });
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _plan() async {
    final provider = context.read<ExpenseProvider>();
    final generation = _generation;
    final plan = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => SavingsPlanDialog(
            currency: provider.currencySymbol,
            hint: _latest?.goalHint,
            baseline: _latest?.evidence['baseline'] is Map
                ? Map<String, dynamic>.from(_latest!.evidence['baseline'])
                : null));
    if (plan == null || !mounted || generation != _generation || !_signedIn)
      return;
    _activePlan = plan;
    await _send(
        'Check my savings plan and suggest realistic next steps, protecting my essential bills and safety buffer.');
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ExpenseProvider>();
    return Scaffold(
      backgroundColor: AppPalette.of(context).bgDark,
      appBar: AppBar(title: const Text('Spending coach AI'), actions: [
        IconButton(
            tooltip: 'New chat',
            onPressed: () => setState(_clear),
            icon: const Icon(Icons.add_comment_outlined)),
      ]),
      body: !_signedIn
          ? Center(
              child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.lock_outline_rounded,
                        size: 42, color: AppTheme.primaryLight),
                    const SizedBox(height: 16),
                    const Text('Sign in to chat about your spending',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 20)),
                    const SizedBox(height: 12),
                    const Text(
                        'Coach uses the records belonging to your online account.',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    FilledButton(
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const LoginScreen())),
                        child: const Text('Sign in')),
                  ])))
          : SafeArea(
              child: Column(children: [
              Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Row(children: [
                    Expanded(
                        child: Text(
                            '${DateFormat('MMM yyyy').format(provider.selectedMonth)} + previous months',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppPalette.of(context).textSecondary))),
                    TextButton.icon(
                        onPressed: _busy ? null : _plan,
                        icon: const Icon(Icons.savings_outlined, size: 18),
                        label: const Text('Savings plan')),
                  ])),
              Expanded(
                  child: _messages.isEmpty && !_busy
                      ? _welcome()
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: _messages.length + (_busy ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == _messages.length)
                              return const Padding(
                                  padding: EdgeInsets.all(20),
                                  child: Row(children: [
                                    SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2)),
                                    SizedBox(width: 12),
                                    Text('Looking at your records…'),
                                  ]));
                            return _bubble(_messages[index]);
                          })),
              if (_error != null)
                Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Text(_error!,
                        style: const TextStyle(
                            color: AppTheme.warningColor, fontSize: 12))),
              Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                            child: TextField(
                                controller: _input,
                                enabled: !_busy,
                                minLines: 1,
                                maxLines: 4,
                                maxLength: 1600,
                                decoration: const InputDecoration(
                                    hintText: 'Ask about your spending…',
                                    counterText: ''),
                                textInputAction: TextInputAction.send,
                                onSubmitted: _send)),
                        const SizedBox(width: 8),
                        IconButton.filled(
                            tooltip: 'Send question',
                            onPressed: _busy ? null : () => _send(_input.text),
                            icon: const Icon(Icons.arrow_upward_rounded)),
                      ])),
            ])),
    );
  }

  Widget _welcome() => SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.auto_awesome_rounded,
            size: 40, color: AppTheme.primaryLight),
        const SizedBox(height: 22),
        Text('Make room for your goals',
            style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: AppPalette.of(context).textPrimary)),
        const SizedBox(height: 12),
        const Text(
            'Explore where your money goes, compare months, or work out a savings plan.',
            style: TextStyle(height: 1.5)),
        const SizedBox(height: 24),
        for (final question in [
          'How much budget is remaining?',
          'How are my jars progressing?',
          'Where does most of my money go?',
          'How has my spending changed?',
          'I want to save RM500 in two months. How can I do it?'
        ])
          Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OutlinedButton(
                  onPressed: () => _send(question),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                      alignment: Alignment.centerLeft),
                  child: Row(children: [
                    Expanded(child: Text(question)),
                    const SizedBox(width: 8),
                    const Icon(Icons.north_east_rounded, size: 16)
                  ]))),
        const SizedBox(height: 12),
        Text(
            'Budget, comparison, pace and jar calculations stay on this device. Other questions and spending summaries are sent to Groq. Receipt images and account details are not sent. Chat clears when you leave. Current prices and offers are not connected yet.',
            style: TextStyle(
                fontSize: 11,
                color: AppPalette.of(context).textSecondary,
                height: 1.5)),
      ]));

  Widget _bubble(_ChatMessage message) => Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
          margin: const EdgeInsets.only(bottom: 16, top: 4),
          padding: const EdgeInsets.all(16),
          constraints: const BoxConstraints(maxWidth: 600),
          decoration: BoxDecoration(
              color: message.isUser
                  ? AppTheme.primary.withValues(alpha: .22)
                  : AppPalette.of(context).bgCard,
              borderRadius: BorderRadius.circular(18)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(message.isUser ? 'You' : 'Coach',
                style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.primaryLight,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SelectableText.rich(
                TextSpan(children: _answerSpans(message.text, message.isUser)),
                style: TextStyle(
                    color: AppPalette.of(context).textPrimary,
                    height: 1.55,
                    fontSize: 14)),
            if (message.reply != null) ...[
              if (message.reply!.fallback)
                Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                        'Calculated from your records. AI commentary is temporarily unavailable.',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppPalette.of(context).textSecondary))),
              Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: Material(
                      color: Colors.transparent,
                      child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: const Text('Numbers used',
                              style: TextStyle(fontSize: 12)),
                          children: [
                            for (final entry in (message
                                    .reply!.evidence['metrics'] as Map)
                                .entries
                                .where((e) =>
                                    [
                                      'income_0',
                                      'expenses_0',
                                      'net_0',
                                      'average_expenses',
                                      'average_salary',
                                      'goal_monthly',
                                      'goal_surplus',
                                      'goal_gap',
                                      'goal_flexible',
                                      'jar_saved',
                                      'comparison_previous',
                                      'comparison_current',
                                      'projected_expenses'
                                    ].contains(e.key) ||
                                    (message.reply!.evidence['source'] ==
                                            'local' &&
                                        e.key
                                            .toString()
                                            .startsWith('budget_'))))
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(children: [
                                    Expanded(
                                        child: Text(_metricLabel(entry.key),
                                            style:
                                                const TextStyle(fontSize: 11))),
                                    Text('${entry.value}',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600)),
                                  ])),
                            Padding(
                                padding: EdgeInsets.only(bottom: 10),
                                child: Text(
                                    message.reply!.evidence['source'] == 'local'
                                        ? 'Calculated on this device from saved records. Missing entries can change the picture.'
                                        : 'Based on synced records. Current-month totals are month-to-date. Missing records can change the picture.',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: AppPalette.of(context)
                                            .textSecondary))),
                          ]))),
              if (message.reply!.suggestPlan)
                TextButton.icon(
                    onPressed: _busy ? null : _plan,
                    icon: const Icon(Icons.savings_outlined),
                    label: const Text('Build a savings plan')),
            ],
          ])));

  List<TextSpan> _answerSpans(String text, bool isUser) {
    if (isUser) return [TextSpan(text: text)];
    final spans = <TextSpan>[];
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final label =
          RegExp(r'^(?:\d+\.\s+.*?|Overall expenses)\s*:').firstMatch(line);
      if (label != null) {
        spans.add(TextSpan(
            text: line.substring(0, label.end).replaceAll('**', ''),
            style: const TextStyle(fontWeight: FontWeight.w700)));
        spans.add(
            TextSpan(text: line.substring(label.end).replaceAll('**', '')));
      } else {
        var start = 0;
        for (final match in RegExp(r'\*\*(.+?)\*\*').allMatches(line)) {
          spans.add(TextSpan(text: line.substring(start, match.start)));
          spans.add(TextSpan(
              text: match.group(1),
              style: const TextStyle(fontWeight: FontWeight.w700)));
          start = match.end;
        }
        spans.add(TextSpan(text: line.substring(start).replaceAll('**', '')));
      }
      if (i < lines.length - 1) spans.add(const TextSpan(text: '\n'));
    }
    return spans;
  }

  String _metricLabel(dynamic key) =>
      const {
        'income_0': 'Recorded income',
        'expenses_0': 'Recorded expenses',
        'net_0': 'Net cash flow',
        'average_expenses': 'Past monthly expenses',
        'average_salary': 'Past monthly salary',
        'goal_monthly': 'Monthly saving needed',
        'goal_surplus': 'Expected surplus',
        'goal_gap': 'Extra monthly gap',
        'goal_flexible': 'Flexible spending',
        'jar_saved': 'Recorded jar reservations',
        'comparison_previous': 'Previous matched period',
        'comparison_current': 'Current matched period',
        'projected_expenses': 'Estimated month-end spending'
      }[key] ??
      '$key';
}
