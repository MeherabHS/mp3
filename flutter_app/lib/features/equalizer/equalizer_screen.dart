import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/theme.dart';

const _eqChannel = MethodChannel('com.hifi.musicplayer/equalizer');

class EqualizerScreen extends StatefulWidget {
  const EqualizerScreen({super.key});

  @override
  State<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen> {
  bool _isEnabled = true;
  String _selectedPreset = 'Audiophile Hi-Fi';

  // ── Enhancement knobs ──────────────────────────────────────────────────────
  double _bassBoost = 0.0;     // 0–100 (maps to 0–1000 Android strength)
  double _stereoWidth = 0.0;   // 0–100 (maps to 0–1000 Android strength)
  double _loudness = 0.0;      // 0–6 dB (maps to 0–600 millibels)

  final List<String> _presets = [
    'Flat',
    'Audiophile Hi-Fi',
    'Bass Boost',
    'Vocal Clarity',
    'Electronic',
    'Rock',
    'Classical',
  ];

  // 60Hz, 150Hz, 400Hz, 1kHz, 2.4kHz, 6kHz, 12kHz
  // "Audiophile Hi-Fi" is tuned for smiley-curve + presence boost:
  //   Sub-bass punch → warm mid-bass → mud cut → neutral mid → presence → crispness → air
  final List<double> _gains = [3.0, 1.5, -1.0, 0.0, 2.0, 3.0, 4.0];
  final List<String> _frequencies = [
    '60 Hz',
    '150 Hz',
    '400 Hz',
    '1 kHz',
    '2.4 kHz',
    '6 kHz',
    '12 kHz',
  ];

  Future<void> _sendToAndroid() async {
    try {
      final gainsMb = _gains.map((g) => (g * 100).round()).toList();
      await _eqChannel.invokeMethod('applyEqualizer', {
        'gainsMb': gainsMb,
        'enabled': _isEnabled,
      });
      await _eqChannel.invokeMethod('applyEnhancements', {
        'bassStrength': (_bassBoost * 10).round(),   // 0-100 → 0-1000
        'stereoWidth': (_stereoWidth * 10).round(),
        'loudnessMb': (_loudness * 100).round(),     // 0-6 dB → 0-600 mb
      });
    } catch (_) {}
  }

  void _applyPreset(String preset) {
    setState(() {
      _selectedPreset = preset;
      switch (preset) {
        case 'Flat':
          _gains.setAll(0, [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]);
          break;
        case 'Audiophile Hi-Fi':
          _gains.setAll(0, [3.0, 1.5, -1.0, 0.0, 2.0, 3.0, 4.0]);
          break;
        case 'Bass Boost':
          _gains.setAll(0, [5.0, 4.0, 2.0, 0.0, 0.0, 0.0, 0.0]);
          break;
        case 'Vocal Clarity':
          _gains.setAll(0, [-1.0, 0.0, 2.0, 4.0, 3.0, 1.0, 0.0]);
          break;
        case 'Electronic':
          _gains.setAll(0, [4.0, 3.0, 0.0, 1.0, 2.0, 3.5, 4.0]);
          break;
        case 'Rock':
          _gains.setAll(0, [3.5, 2.5, -1.0, 0.0, 1.5, 3.0, 3.5]);
          break;
        case 'Classical':
          _gains.setAll(0, [3.0, 2.0, 0.0, 0.0, 1.0, 2.5, 3.0]);
          break;
      }
    });
    _sendToAndroid();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Equalizer'),
        actions: [
          Switch(
            value: _isEnabled,
            activeThumbColor: AppTheme.accentGold,
            onChanged: (val) {
              setState(() => _isEnabled = val);
              _sendToAndroid();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          // Preset Selector Chips
          const Text(
            'Audio Tuning Presets',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _presets.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final p = _presets[index];
                final isSelected = p == _selectedPreset;
                return ChoiceChip(
                  label: Text(p),
                  selected: isSelected,
                  selectedColor: AppTheme.accentGold,
                  backgroundColor: AppTheme.surfaceElevated,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.black : AppTheme.textSecondary,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    fontSize: 12,
                  ),
                  onSelected: _isEnabled ? (_) => _applyPreset(p) : null,
                );
              },
            ),
          ),
          const SizedBox(height: 32),

          // 7-Band Sliders Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '7-Band Parametric Stage',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _isEnabled ? 'ACTIVE' : 'BYPASS',
                      style: TextStyle(
                        color: _isEnabled ? AppTheme.connectedGreen : AppTheme.textTertiary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 220,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(7, (idx) {
                      return Column(
                        children: [
                          Text(
                            '${_gains[idx] >= 0 ? '+' : ''}${_gains[idx].toStringAsFixed(1)}',
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Expanded(
                            child: RotatedBox(
                              quarterTurns: 3,
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  thumbColor: AppTheme.accentGold,
                                  activeTrackColor: AppTheme.accentGold,
                                  inactiveTrackColor: AppTheme.border,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                                  trackHeight: 2,
                                ),
                                child: Slider(
                                  value: _gains[idx],
                                  min: -10.0,
                                  max: 10.0,
                                  onChanged: _isEnabled
                                      ? (val) {
                                          setState(() {
                                            _gains[idx] = val;
                                            _selectedPreset = 'Custom';
                                          });
                                          _sendToAndroid();
                                        }
                                      : null,
                                ),
                              ),
                            ),
                          ),
                          Text(
                            _frequencies[idx],
                            style: const TextStyle(
                              color: AppTheme.textTertiary,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Sound Enhancement Panel ─────────────────────────────────────
          const Text(
            'Sound Enhancement',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Hardware DSP effects applied directly to the audio session.',
            style: TextStyle(color: AppTheme.textTertiary, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              children: [
                _enhancerRow(
                  label: 'Bass Boost',
                  sublabel: 'Sub-bass & punch',
                  icon: Icons.speaker_rounded,
                  value: _bassBoost,
                  max: 100,
                  unit: '%',
                  color: const Color(0xFFFF6B35),
                  onChanged: _isEnabled ? (v) { setState(() => _bassBoost = v); _sendToAndroid(); } : null,
                ),
                const Divider(color: AppTheme.border, height: 28),
                _enhancerRow(
                  label: 'Stereo Width',
                  sublabel: 'Headphone spaciousness',
                  icon: Icons.spatial_audio_rounded,
                  value: _stereoWidth,
                  max: 100,
                  unit: '%',
                  color: const Color(0xFF7C4DFF),
                  onChanged: _isEnabled ? (v) { setState(() => _stereoWidth = v); _sendToAndroid(); } : null,
                ),
                const Divider(color: AppTheme.border, height: 28),
                _enhancerRow(
                  label: 'Loudness',
                  sublabel: 'Perceived fullness',
                  icon: Icons.volume_up_rounded,
                  value: _loudness,
                  max: 6,
                  unit: 'dB',
                  color: AppTheme.connectedGreen,
                  onChanged: _isEnabled ? (v) { setState(() => _loudness = v); _sendToAndroid(); } : null,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Sound Quality Info Card ─────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.accentPurple.withValues(alpha: 0.3)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, color: AppTheme.accentPurple, size: 16),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'EQ and DSP effects work on all sources including Bluetooth LDAC/aptX. '
                    'The 12 kHz "air" band and 2.4 kHz "presence" band have the most '
                    'impact on perceived crispness. Bass Boost adds warmth; Stereo Width '
                    'opens the soundstage on headphones.',
                    style: TextStyle(
                      color: AppTheme.textTertiary,
                      fontSize: 11,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _enhancerRow({
    required String label,
    required String sublabel,
    required IconData icon,
    required double value,
    required double max,
    required String unit,
    required Color color,
    required ValueChanged<double>? onChanged,
  }) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(label, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(
                    value == 0 ? 'Off' : '${value.toStringAsFixed(unit == "dB" ? 1 : 0)}$unit',
                    style: TextStyle(color: value > 0 ? color : AppTheme.textTertiary, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Text(sublabel, style: const TextStyle(color: AppTheme.textTertiary, fontSize: 10)),
              const SizedBox(height: 4),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: color,
                  inactiveTrackColor: AppTheme.border,
                  thumbColor: color,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  trackHeight: 3,
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                ),
                child: Slider(value: value, min: 0, max: max, onChanged: onChanged),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
