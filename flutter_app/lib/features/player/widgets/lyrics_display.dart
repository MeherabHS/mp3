import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../../../models/lyrics.dart';

class LyricsDisplay extends StatefulWidget {
  final SyncedLyrics lyrics;
  final LyricsSyncState syncState;
  final Function(int positionMs) onSeek;

  const LyricsDisplay({
    super.key,
    required this.lyrics,
    required this.syncState,
    required this.onSeek,
  });

  @override
  State<LyricsDisplay> createState() => _LyricsDisplayState();
}

class _LyricsDisplayState extends State<LyricsDisplay> {
  final ScrollController _scrollController = ScrollController();
  final double _itemHeight = 54.0;

  @override
  void didUpdateWidget(covariant LyricsDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.syncState.activeLineIndex != oldWidget.syncState.activeLineIndex) {
      _scrollToActiveLine();
    }
  }

  void _scrollToActiveLine() {
    if (!widget.lyrics.isSynchronized || widget.lyrics.lines.isEmpty) return;
    final activeIndex = widget.syncState.activeLineIndex ?? 0;
    if (_scrollController.hasClients) {
      final targetOffset = (activeIndex * _itemHeight) - 80.0;
      _scrollController.animateTo(
        targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.lyrics.isSynchronized || widget.lyrics.lines.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.music_note_rounded,
              color: AppTheme.textTertiary.withValues(alpha: 0.4),
              size: 40,
            ),
            const SizedBox(height: 12),
            const Text(
              'No synchronized lyrics available',
              style: TextStyle(
                color: AppTheme.textTertiary,
                fontSize: 14,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      );
    }

    final activeIndex = widget.syncState.activeLineIndex;

    return ShaderMask(
      shaderCallback: (rect) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.transparent,
          ],
          stops: [0.0, 0.15, 0.85, 1.0],
        ).createShader(rect);
      },
      blendMode: BlendMode.dstIn,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
        itemCount: widget.lyrics.lines.length,
        itemBuilder: (context, index) {
          final line = widget.lyrics.lines[index];
          final isActive = index == activeIndex;
          final isPast = activeIndex != null && index < activeIndex;

          final lineColor = isActive
              ? AppTheme.textPrimary
              : (isPast
                  ? AppTheme.textTertiary.withValues(alpha: 0.6)
                  : AppTheme.textSecondary.withValues(alpha: 0.4));
          final lineFontSize = isActive ? 20.0 : 16.0;
          final lineFontWeight = isActive ? FontWeight.w800 : FontWeight.w500;

          // Word-level rendering for the active line when word timestamps exist
          final useWordSync = isActive &&
              widget.lyrics.isWordSynced &&
              line.words.isNotEmpty;

          Widget lineContent;
          if (useWordSync) {
            final activeWordIdx = widget.syncState.activeWordIndex;
            lineContent = Wrap(
              alignment: WrapAlignment.center,
              runSpacing: 2,
              children: line.words.asMap().entries.map((e) {
                final wordIdx = e.key;
                final word = e.value;
                final isHighlighted = activeWordIdx != null && wordIdx == activeWordIdx;
                return AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 100),
                  style: TextStyle(
                    color: isHighlighted ? AppTheme.neonPurple : lineColor,
                    fontSize: lineFontSize,
                    fontWeight: isHighlighted ? FontWeight.w900 : lineFontWeight,
                    letterSpacing: isActive ? -0.3 : 0.0,
                    shadows: isHighlighted
                        ? [BoxShadow(color: AppTheme.neonPurple.withValues(alpha: 0.7), blurRadius: 12)]
                        : null,
                  ),
                  child: Text('${word.word} '),
                );
              }).toList(),
            );
          } else {
            lineContent = Text(
              line.text,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            );
          }

          return GestureDetector(
            onTap: () => widget.onSeek(line.startMs),
            child: Container(
              height: _itemHeight,
              alignment: Alignment.center,
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                style: TextStyle(
                  color: lineColor,
                  fontSize: lineFontSize,
                  fontWeight: lineFontWeight,
                  letterSpacing: isActive ? -0.3 : 0.0,
                  shadows: isActive && !useWordSync
                      ? [
                          BoxShadow(
                            color: AppTheme.neonPurple.withValues(alpha: 0.5),
                            blurRadius: 18,
                            spreadRadius: 3,
                          )
                        ]
                      : null,
                ),
                child: lineContent,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
