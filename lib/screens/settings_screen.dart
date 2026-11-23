import '../services/notification_service.dart';
import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
// lib/screens/settings_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/expense_provider.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../utils/app_theme.dart';
import '../services/cache_service.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late Future<int> _storageFuture;
  @override
  void initState() {
    super.initState();
    final provider = context.read<ExpenseProvider>();
    _nameController = TextEditingController(text: provider.userName);
    _emailController = TextEditingController(text: provider.userEmail);
    _storageFuture = DatabaseService().getDatabaseSizeBytes();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ExpenseProvider>();
    return Scaffold(
      backgroundColor: AppPalette.of(context).bgDark,
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildIdentityCard(provider),
          const SizedBox(height: 20),
          _buildProfileSection(provider),
          const SizedBox(height: 20),
          _buildSyncSection(provider),
          const SizedBox(height: 20),
          _buildGeneralSection(),
          const SizedBox(height: 20),
          _buildAboutSection(),
          const SizedBox(height: 20),
          _buildSignOutSection(),
          const SizedBox(height: 32),
          _buildSaveButton(),
        ],
      ),
    );
  }

  Widget _buildIdentityCard(ExpenseProvider provider) {
    final initials = provider.userName.trim().isEmpty
        ? 'U'
        : provider.userName.trim().substring(0, 1).toUpperCase();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppPalette.of(context).primaryGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white.withValues(alpha: 0.18),
            child: Text(initials,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(provider.userName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                    provider.userEmail.isEmpty
                        ? 'Local profile'
                        : provider.userEmail,
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileSection(ExpenseProvider provider) {
    return _Section(
      title: 'Profile',
      children: [
        _InfoRow(
            icon: Icons.badge_rounded,
            label: 'User ID',
            value: provider.userId),
        const Divider(color: Color(0xFF2D2D55)),
        TextField(
          controller: _nameController,
          style: TextStyle(color: AppPalette.of(context).textPrimary),
          decoration: InputDecoration(
            labelText: 'User name',
            prefixIcon: Icon(Icons.person_rounded,
                color: AppPalette.of(context).textMuted),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          style: TextStyle(color: AppPalette.of(context).textPrimary),
          decoration: InputDecoration(
            labelText: 'User email',
            prefixIcon: Icon(Icons.email_rounded,
                color: AppPalette.of(context).textMuted),
          ),
        ),
      ],
    );
  }

  Widget _buildSyncSection(ExpenseProvider provider) => _Section(
        title: 'Device sync',
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
                provider.syncNeedsReview
                    ? Icons.sync_problem
                    : Icons.cloud_outlined,
                color: AppPalette.of(context).primary),
            title: Text(
                provider.canSync
                    ? provider.syncStatus
                    : 'Sign in online to sync',
                style: const TextStyle(fontSize: 13)),
            subtitle: provider.lastSyncAt == null
                ? null
                : Text(
                    'Last synced ${DateFormat('d MMM, h:mm a').format(provider.lastSyncAt!.toLocal())}',
                    style: const TextStyle(fontSize: 11)),
          ),
          Wrap(spacing: 8, children: [
            FilledButton.icon(
                onPressed: !provider.canSync || provider.isSyncing
                    ? null
                    : () => provider.syncNow(),
                icon: const Icon(Icons.sync, size: 18),
                label: Text(provider.isSyncing ? 'Syncing…' : 'Sync now')),
            if (provider.syncNeedsReview)
              OutlinedButton(
                  onPressed: () => _reviewSync(provider),
                  child: const Text('Review copies')),
            TextButton(
                onPressed: () => _exportSyncBackup(provider),
                child: const Text('Save backup')),
          ]),
          const SizedBox(height: 6),
          const Text(
              'Use the same account and updated Spendly app on both devices. Expenses, accounts, budgets, jars and bill details sync. Receipt images stay on the original device.',
              style: TextStyle(fontSize: 11)),
        ],
      );

  Future<void> _reviewSync(ExpenseProvider provider) async {
    final owner = provider.userId;
    final useDevice = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Choose the copy to keep'),
              content: const Text(
                  'Both devices changed the same records. Nothing has been overwritten. Sync can use the full copy on this device or the full cloud copy. Save a backup of this device before choosing. Automatic backups are also kept. Use your phone’s copy if it holds your complete records.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel')),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Use cloud copy')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Use this device')),
              ],
            ));
    if (useDevice != null && mounted && owner == provider.userId)
      await provider.syncNow(useDeviceCopy: useDevice);
  }

  Future<void> _exportSyncBackup(ExpenseProvider provider) async {
    final owner = provider.userId;
    try {
      final data = await DatabaseService().exportSyncData(owner);
      final db = await DatabaseService().database;
      final backups = await db.query('device_sync_backups',
          where: 'userId = ?', whereArgs: [owner], orderBy: 'id DESC');
      final root = await getTemporaryDirectory();
      final file = File(
          '${root.path}/spendly-backup-${DateTime.now().millisecondsSinceEpoch}.json');
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert({
        'format': 1,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'records': data,
        'previousCopies': backups
            .map((r) => {
                  'createdAt': r['createdAt'],
                  'records': jsonDecode(r['payload'] as String)
                })
            .toList()
      }));
      if (!mounted || provider.userId != owner) return;
      await Share.shareXFiles([XFile(file.path, mimeType: 'application/json')],
          subject: 'Spendly backup');
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not save the backup. Please try again.')));
    }
  }

  Widget _buildGeneralSection() {
    return _Section(
      title: 'General',
      children: [
        Text('Colour theme', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...[
          (
            'Dark',
            'Dark blue',
            'Deep blue with purple accents',
            Color(0xFF7965DB)
          ),
          (
            'Light',
            'Creamy yellow',
            'Warm cream with brown accents',
            Color(0xFF79502F)
          )
        ].map((option) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                  backgroundColor: option.$4,
                  child: Icon(
                      option.$1 == 'Dark' ? Icons.dark_mode : Icons.light_mode,
                      color: Colors.white)),
              title: Text(option.$2),
              subtitle: Text(option.$3),
              trailing: context.watch<ExpenseProvider>().colorTheme == option.$1
                  ? Icon(Icons.check_circle,
                      color: AppPalette.of(context).primary)
                  : const Icon(Icons.circle_outlined),
              onTap: () => context
                  .read<ExpenseProvider>()
                  .savePreferences(colorTheme: option.$1),
            )),
        FutureBuilder<int>(
          future: _storageFuture,
          builder: (context, snapshot) {
            return _InfoRow(
              icon: Icons.storage_rounded,
              label: 'Saved records',
              value: _formatBytes(snapshot.data ?? 0),
            );
          },
        ),
        TextButton.icon(
            onPressed: _clearCache,
            icon: const Icon(Icons.cleaning_services_outlined),
            label: const Text('Clear temporary cache')),
        const Text('Saved expenses, accounts and receipts are kept.',
            style: TextStyle(fontSize: 12)),
      ],
    );
  }

  Future<void> _clearCache() async {
    try {
      final bytes = await CacheService.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Cleared ${_formatBytes(bytes)} of temporary cache')));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Could not clear temporary cache. Please try again.')));
    }
  }

  Widget _buildAboutSection() {
    return _Section(
      title: 'About',
      children: const [
        _InfoRow(icon: Icons.info_rounded, label: 'Version', value: '1.0.0'),
        Divider(color: Color(0xFF2D2D55)),
        _InfoRow(
            icon: Icons.auto_awesome_rounded,
            label: 'Spending assistance',
            value: 'Groq AI + local learning'),
        Divider(color: Color(0xFF2D2D55)),
        _InfoRow(
            icon: Icons.document_scanner_rounded,
            label: 'OCR',
            value: 'Google ML Kit'),
      ],
    );
  }

  Widget _buildSignOutSection() {
    return _Section(
      title: 'Account',
      children: [
        _DangerRow(
          icon: Icons.logout_rounded,
          label: 'Sign out',
          value: 'Return to setup',
          onTap: _confirmSignOut,
        ),
      ],
    );
  }

  Widget _buildSaveButton() {
    return ElevatedButton(
      onPressed: () async {
        await context.read<ExpenseProvider>().savePreferences(
              userName: _nameController.text.trim().isEmpty
                  ? 'User'
                  : _nameController.text.trim(),
              userEmail: _emailController.text.trim(),
              currencySymbol: 'RM',
            );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile saved'),
            backgroundColor: AppTheme.incomeColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      child: const Text('Save Profile'),
    );
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.of(context).bgCard,
        title: Text('Sign out?',
            style: TextStyle(color: AppPalette.of(context).textPrimary)),
        content: Text(
          'Sign out of Spendly on this device? Your saved records will remain.',
          style: TextStyle(color: AppPalette.of(context).textSecondary),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out',
                style: TextStyle(color: AppTheme.expenseColor)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await SpendlyAuthService().signOut();
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not sign out. Please try again.'),
        ));
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_logged_in', false);
      await prefs.setBool(
          'recurring_paused:${context.read<ExpenseProvider>().userId}', true);
      try {
        await NotificationService.syncRecurringReminders(
            context.read<ExpenseProvider>().userId, [], 'RM');
      } catch (_) {}
      NotificationService.pendingRecurring = null;
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(2)} MB';
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title.toUpperCase(),
            style: TextStyle(
                color: AppPalette.of(context).textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppPalette.of(context).bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppPalette.of(context).border),
          ),
          child: Material(
              color: Colors.transparent, child: Column(children: children)),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _InfoRow(
      {required this.icon,
      required this.label,
      required this.value,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: AppPalette.of(context).textMuted, size: 18),
            const SizedBox(width: 12),
            Expanded(
                child: Text(label,
                    style: TextStyle(
                        color: AppPalette.of(context).textSecondary,
                        fontSize: 14))),
            Flexible(
              child: Text(
                value,
                style: TextStyle(
                    color: AppPalette.of(context).textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded,
                  color: AppPalette.of(context).textMuted, size: 18),
            ],
          ],
        ),
      ),
    );
  }
}

class _DangerRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _DangerRow(
      {required this.icon,
      required this.label,
      required this.value,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.expenseColor, size: 18),
            const SizedBox(width: 12),
            Expanded(
                child: Text(label,
                    style: const TextStyle(
                        color: AppTheme.expenseColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w700))),
            Text(value,
                style: TextStyle(
                    color: AppPalette.of(context).textMuted, fontSize: 13)),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded,
                color: AppPalette.of(context).textMuted, size: 18),
          ],
        ),
      ),
    );
  }
}
