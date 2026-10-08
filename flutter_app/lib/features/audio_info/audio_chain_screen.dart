import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme.dart';
import '../../models/audio_quality.dart';
import '../../providers/player_provider.dart';

class AudioChainScreen extends ConsumerWidget {
  const AudioChainScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final quality = playerState.audioQuality;
    final track = playerState.currentTrack;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio Signal Chain'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          // Track Header Card
          if (track != null)
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: const Icon(
                      Icons.audiotrack_rounded,
                      color: AppTheme.accentGold,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          track.artist,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Stage 1: SOURCE FILE
          _buildStageCard(
            stageNumber: '1',
            stageTitle: 'SOURCE FILE',
            icon: Icons.folder_zip_rounded,
            details: [
              _buildRow('Container', quality.container ?? track?.container ?? 'Unknown'),
              _buildRow('Codec', quality.codec ?? track?.codec ?? 'Unknown'),
              _buildRow('Resolution', track?.bitDepth != null ? '${track!.bitDepth}-bit' : 'N/A'),
              _buildRow('Sample Rate', track?.sampleRateHz != null ? '${track!.sampleRateHz! ~/ 1000} kHz' : 'N/A'),
              _buildRow('Bitrate', track?.bitrateKbps != null ? '${track!.bitrateKbps} kbps' : 'N/A'),
              _buildRow('Fidelity', (quality.lossless ?? track?.lossless ?? false) ? 'Lossless Audio' : 'Lossy Stream'),
            ],
          ),

          _buildConnectorArrow(),

          // Stage 2: RUST DECODER
          _buildStageCard(
            stageNumber: '2',
            stageTitle: 'RUST DECODER',
            icon: Icons.memory_rounded,
            details: [
              _buildRow('Engine', 'Rust Symphonia / Audio Core'),
              _buildRow('Decoded Format', 'Linear PCM (Interleaved)'),
              _buildRow('Internal Depth', track?.bitDepth != null ? '${track!.bitDepth}-bit' : '16-bit'),
              _buildRow('Internal Rate', track?.sampleRateHz != null ? '${track!.sampleRateHz! ~/ 1000} kHz' : '48 kHz'),
            ],
          ),

          _buildConnectorArrow(),

          // Stage 3: ANDROID AUDIO
          _buildStageCard(
            stageNumber: '3',
            stageTitle: 'ANDROID PLATFORM AUDIO',
            icon: Icons.android_rounded,
            details: [
              _buildRow('Subsystem', 'Jetpack Media3 / AudioTrack'),
              _buildRow('Focus Control', 'Active (Foreground Service)'),
              _buildRow('Resampling', 'Preserved (Native Sample Rate)'),
            ],
          ),

          _buildConnectorArrow(),

          // Stage 4: OUTPUT TRANSPORT & DEVICE
          _buildStageCard(
            stageNumber: '4',
            stageTitle: 'OUTPUT TRANSPORT',
            icon: quality.outputType == OutputType.bluetooth
                ? Icons.bluetooth_audio_rounded
                : (quality.outputType == OutputType.usbDac
                    ? Icons.usb_rounded
                    : Icons.headphones_rounded),
            isHighlighted: true,
            details: [
              _buildRow('Device', quality.outputDeviceName ?? 'Phone Speaker'),
              _buildRow('Transport', quality.outputType.name.toUpperCase()),
              _buildRow('Negotiated Codec', quality.outputCodec ?? 'PCM Built-in'),
              _buildRow('Reported Bitrate', quality.outputBitrateKbps != null ? '${quality.outputBitrateKbps} kbps' : 'Not reported by OS'),
              _buildRow('Reported Sample Rate', quality.outputSampleRateHz != null ? '${quality.outputSampleRateHz! ~/ 1000} kHz' : '48 kHz'),
            ],
          ),

          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildStageCard({
    required String stageNumber,
    required String stageTitle,
    required IconData icon,
    required List<Widget> details,
    bool isHighlighted = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isHighlighted ? AppTheme.surfaceElevated : AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isHighlighted ? AppTheme.accentGold.withValues(alpha: 0.5) : AppTheme.border,
          width: isHighlighted ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isHighlighted ? AppTheme.accentGold : AppTheme.border,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  stageNumber,
                  style: TextStyle(
                    color: isHighlighted ? Colors.black : AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                stageTitle,
                style: TextStyle(
                  color: isHighlighted ? AppTheme.accentGold : AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Icon(
                icon,
                color: isHighlighted ? AppTheme.accentGold : AppTheme.textSecondary,
                size: 20,
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...details,
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectorArrow() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      alignment: Alignment.center,
      child: const Icon(
        Icons.keyboard_arrow_down_rounded,
        color: AppTheme.accentGold,
        size: 22,
      ),
    );
  }
}
