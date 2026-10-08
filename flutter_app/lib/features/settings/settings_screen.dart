import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme.dart';
import '../../providers/settings_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _nameController = TextEditingController(text: settings.userName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          // ── Profile ─────────────────────────────────────────────────────
          _sectionHeader('Profile'),
          const SizedBox(height: 12),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Display Name', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nameController,
                        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
                        decoration: const InputDecoration(
                          hintText: 'Your name',
                          hintStyle: TextStyle(color: AppTheme.textTertiary),
                          border: InputBorder.none,
                        ),
                        onSubmitted: notifier.setUserName,
                      ),
                    ),
                    TextButton(
                      onPressed: () => notifier.setUserName(_nameController.text.trim()),
                      child: const Text('Save', style: TextStyle(color: AppTheme.accentPurple, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Performance Mode ─────────────────────────────────────────────
          _sectionHeader('Performance Mode'),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'Controls animation complexity and lyric rendering detail.',
              style: TextStyle(color: AppTheme.textTertiary, fontSize: 12),
            ),
          ),
          _card(
            child: Column(
              children: PerformanceMode.values.map((mode) {
                final isSelected = settings.performanceMode == mode;
                return InkWell(
                  onTap: () => notifier.setPerformanceMode(mode),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    child: Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? AppTheme.accentPurple : AppTheme.border,
                              width: isSelected ? 6 : 2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _modeLabel(mode),
                              style: TextStyle(
                                color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            Text(
                              _modeDescription(mode),
                              style: const TextStyle(color: AppTheme.textTertiary, fontSize: 11),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 24),

          // ── Storage ──────────────────────────────────────────────────────
          _sectionHeader('Storage'),
          const SizedBox(height: 12),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Preferred Music Path', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                const SizedBox(height: 8),
                Text(
                  settings.storagePath.isEmpty ? '/storage/emulated/0/Music (default)' : settings.storagePath,
                  style: TextStyle(
                    color: settings.storagePath.isEmpty ? AppTheme.textTertiary : AppTheme.textPrimary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => notifier.setStoragePath('/storage/emulated/0/Music'),
                      icon: const Icon(Icons.phone_android_rounded, size: 14),
                      label: const Text('Internal', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textSecondary,
                        side: const BorderSide(color: AppTheme.border),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        // Pick SD card root — user can type it in
                        final result = await showDialog<String>(
                          context: context,
                          builder: (ctx) {
                            final c = TextEditingController(text: settings.storagePath);
                            return AlertDialog(
                              backgroundColor: AppTheme.surfaceElevated,
                              title: const Text('SD Card Path', style: TextStyle(color: AppTheme.textPrimary)),
                              content: TextField(
                                controller: c,
                                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                                decoration: const InputDecoration(
                                  hintText: '/storage/XXXX-XXXX/Music',
                                  hintStyle: TextStyle(color: AppTheme.textTertiary),
                                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
                                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.accentPurple)),
                                ),
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                                TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Set')),
                              ],
                            );
                          },
                        );
                        if (result != null && result.isNotEmpty) {
                          notifier.setStoragePath(result);
                        }
                      },
                      icon: const Icon(Icons.sd_card_rounded, size: 14),
                      label: const Text('SD Card', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textSecondary,
                        side: const BorderSide(color: AppTheme.border),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Lyrics Sources ───────────────────────────────────────────────
          _sectionHeader('Lyrics'),
          const SizedBox(height: 12),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.lyrics_rounded, size: 16, color: AppTheme.accentPurple),
                    const SizedBox(width: 8),
                    const Text('Musixmatch Token', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    if (settings.musixmatchToken.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.connectedGreen.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('Active', style: TextStyle(color: AppTheme.connectedGreen, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Enables synced lyrics from Musixmatch — the world\'s largest catalogue. Get token from the desktop app\'s network requests (see TODO.md).',
                  style: TextStyle(color: AppTheme.textTertiary, fontSize: 12, height: 1.4),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        settings.musixmatchToken.isEmpty
                            ? 'No token set'
                            : '••••••••${settings.musixmatchToken.length > 8 ? settings.musixmatchToken.substring(settings.musixmatchToken.length - 4) : ''}',
                        style: TextStyle(
                          color: settings.musixmatchToken.isEmpty
                              ? AppTheme.textTertiary
                              : AppTheme.textSecondary,
                          fontSize: 13,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final c = TextEditingController(text: settings.musixmatchToken);
                        final result = await showDialog<String>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: const Color(0xFF1E1E2E),
                            title: const Text('Musixmatch Token', style: TextStyle(color: AppTheme.textPrimary)),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '1. Install Musixmatch desktop app\n2. Sign in, open DevTools (F12)\n3. Network tab → filter "apic-desktop"\n4. Copy the usertoken= value',
                                  style: TextStyle(color: AppTheme.textTertiary, fontSize: 12, height: 1.5),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: c,
                                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontFamily: 'monospace'),
                                  maxLines: 3,
                                  decoration: const InputDecoration(
                                    hintText: 'Paste token here...',
                                    hintStyle: TextStyle(color: AppTheme.textTertiary),
                                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
                                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.accentPurple)),
                                  ),
                                ),
                              ],
                            ),
                            actions: [
                              if (settings.musixmatchToken.isNotEmpty)
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, ''),
                                  child: const Text('Remove', style: TextStyle(color: Colors.redAccent)),
                                ),
                              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                              TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save')),
                            ],
                          ),
                        );
                        if (result != null) {
                          notifier.setMusixmatchToken(result);
                        }
                      },
                      style: TextButton.styleFrom(foregroundColor: AppTheme.accentPurple),
                      child: Text(settings.musixmatchToken.isEmpty ? 'Set Token' : 'Change'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) => Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: AppTheme.textTertiary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      );

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
        ),
        child: child,
      );

  String _modeLabel(PerformanceMode mode) => switch (mode) {
        PerformanceMode.light => 'Light',
        PerformanceMode.balanced => 'Balanced',
        PerformanceMode.visual => 'Visual',
      };

  String _modeDescription(PerformanceMode mode) => switch (mode) {
        PerformanceMode.light => 'Minimal animations — best battery life',
        PerformanceMode.balanced => 'Standard animations — recommended',
        PerformanceMode.visual => 'Full animations + word-sync lyrics',
      };
}
