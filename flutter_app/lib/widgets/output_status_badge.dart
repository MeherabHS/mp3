import 'package:flutter/material.dart';
import '../app/theme.dart';
import '../models/audio_quality.dart';

class OutputStatusBadge extends StatelessWidget {
  final OutputStatus outputStatus;
  final VoidCallback? onTap;

  const OutputStatusBadge({
    super.key,
    required this.outputStatus,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Glowing connection dot
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: outputStatus.isConnected
                    ? AppTheme.connectedGreen
                    : AppTheme.textTertiary,
                boxShadow: outputStatus.isConnected
                    ? [
                        BoxShadow(
                          color: AppTheme.connectedGreen.withValues(alpha: 0.5),
                          blurRadius: 6,
                          spreadRadius: 1,
                        )
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  outputStatus.deviceName,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  outputStatus.formattedSummary,
                  style: const TextStyle(
                    color: AppTheme.accentGold,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.textTertiary,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}
