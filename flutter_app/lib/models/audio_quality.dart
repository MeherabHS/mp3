enum OutputType {
  bluetooth,
  usbDac,
  wired,
  builtinSpeaker,
  unknown;

  static OutputType fromString(String? val) {
    switch (val?.toLowerCase()) {
      case 'bluetooth':
        return OutputType.bluetooth;
      case 'usb_dac':
      case 'usbdac':
        return OutputType.usbDac;
      case 'wired':
        return OutputType.wired;
      case 'builtin_speaker':
      case 'builtinspeaker':
        return OutputType.builtinSpeaker;
      default:
        return OutputType.unknown;
    }
  }
}

class AudioQuality {
  final String? container;
  final String? codec;
  final int? bitrateKbps;
  final int? sampleRateHz;
  final int? bitDepth;
  final int? channels;
  final bool? lossless;

  final int? pcmSampleRateHz;
  final int? pcmBitDepth;

  final OutputType outputType;
  final String? outputDeviceName;
  final String? outputCodec;
  final int? outputBitrateKbps;
  final int? outputSampleRateHz;
  final int? outputBitDepth;

  const AudioQuality({
    this.container,
    this.codec,
    this.bitrateKbps,
    this.sampleRateHz,
    this.bitDepth,
    this.channels,
    this.lossless,
    this.pcmSampleRateHz,
    this.pcmBitDepth,
    this.outputType = OutputType.builtinSpeaker,
    this.outputDeviceName,
    this.outputCodec,
    this.outputBitrateKbps,
    this.outputSampleRateHz,
    this.outputBitDepth,
  });

  factory AudioQuality.fromJson(Map<String, dynamic> json) {
    return AudioQuality(
      container: json['container'] as String?,
      codec: json['codec'] as String?,
      bitrateKbps: json['bitrate_kbps'] as int?,
      sampleRateHz: json['sample_rate_hz'] as int?,
      bitDepth: json['bit_depth'] as int?,
      channels: json['channels'] as int?,
      lossless: json['lossless'] as bool?,
      pcmSampleRateHz: json['pcm_sample_rate_hz'] as int?,
      pcmBitDepth: json['pcm_bit_depth'] as int?,
      outputType: OutputType.fromString(json['output_type'] as String?),
      outputDeviceName: json['output_device_name'] as String?,
      outputCodec: json['output_codec'] as String?,
      outputBitrateKbps: json['output_bitrate_kbps'] as int?,
      outputSampleRateHz: json['output_sample_rate_hz'] as int?,
      outputBitDepth: json['output_bit_depth'] as int?,
    );
  }
}

class OutputStatus {
  final OutputType outputType;
  final String deviceName;
  final String? codec;
  final int? bitrateKbps;
  final int? sampleRateHz;
  final int? bitDepth;
  final bool isConnected;

  const OutputStatus({
    this.outputType = OutputType.builtinSpeaker,
    this.deviceName = 'Phone Speaker',
    this.codec,
    this.bitrateKbps,
    this.sampleRateHz,
    this.bitDepth,
    this.isConnected = true,
  });

  factory OutputStatus.fromJson(Map<String, dynamic> json) {
    return OutputStatus(
      outputType: OutputType.fromString(json['output_type'] as String?),
      deviceName: (json['device_name'] as String?) ?? 'Phone Speaker',
      codec: json['codec'] as String?,
      bitrateKbps: json['bitrate_kbps'] as int?,
      sampleRateHz: json['sample_rate_hz'] as int?,
      bitDepth: json['bit_depth'] as int?,
      isConnected: (json['is_connected'] as bool?) ?? true,
    );
  }

  String get formattedSummary {
    switch (outputType) {
      case OutputType.bluetooth:
        final codecStr = codec ?? 'Bluetooth Audio';
        final rateStr = bitrateKbps != null ? ' · $bitrateKbps kbps' : '';
        final sampleStr = sampleRateHz != null ? ' · ${sampleRateHz! ~/ 1000} kHz' : '';
        return '$codecStr$rateStr$sampleStr';
      case OutputType.usbDac:
        final depthStr = bitDepth != null ? '$bitDepth-bit' : '';
        final sampleStr = sampleRateHz != null ? ' / ${sampleRateHz! ~/ 1000} kHz' : '';
        return 'USB DAC · $depthStr$sampleStr';
      case OutputType.wired:
        return 'Analog Output · 3.5mm';
      case OutputType.builtinSpeaker:
        return 'Built-in Audio';
      default:
        return 'Output Active';
    }
  }
}
