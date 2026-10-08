use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum OutputType {
    Bluetooth,
    UsbDac,
    Wired,
    BuiltinSpeaker,
    Unknown,
}

impl Default for OutputType {
    fn default() -> Self {
        OutputType::BuiltinSpeaker
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AudioQuality {
    // 1. File / Source Layer
    pub container: Option<String>,
    pub codec: Option<String>,
    pub bitrate_kbps: Option<u32>,
    pub sample_rate_hz: Option<u32>,
    pub bit_depth: Option<u8>,
    pub channels: Option<u8>,
    pub lossless: Option<bool>,

    // 2. Decoder Layer
    pub pcm_sample_rate_hz: Option<u32>,
    pub pcm_bit_depth: Option<u8>,

    // 3. Android Platform & Transport Output Layer
    pub output_type: OutputType,
    pub output_device_name: Option<String>,
    pub output_codec: Option<String>,
    pub output_bitrate_kbps: Option<u32>,
    pub output_sample_rate_hz: Option<u32>,
    pub output_bit_depth: Option<u8>,
}

impl Default for AudioQuality {
    fn default() -> Self {
        Self {
            container: None,
            codec: None,
            bitrate_kbps: None,
            sample_rate_hz: None,
            bit_depth: None,
            channels: None,
            lossless: None,
            pcm_sample_rate_hz: None,
            pcm_bit_depth: None,
            output_type: OutputType::BuiltinSpeaker,
            output_device_name: Some("Phone Speaker".to_string()),
            output_codec: Some("PCM Built-in".to_string()),
            output_bitrate_kbps: None,
            output_sample_rate_hz: Some(48000),
            output_bit_depth: Some(16),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct OutputStatus {
    pub output_type: OutputType,
    pub device_name: String,
    pub codec: Option<String>,
    pub bitrate_kbps: Option<u32>,
    pub sample_rate_hz: Option<u32>,
    pub bit_depth: Option<u8>,
    pub is_connected: bool,
}

impl Default for OutputStatus {
    fn default() -> Self {
        Self {
            output_type: OutputType::BuiltinSpeaker,
            device_name: "Phone Speaker".to_string(),
            codec: Some("Built-in Audio".to_string()),
            bitrate_kbps: None,
            sample_rate_hz: Some(48000),
            bit_depth: Some(16),
            is_connected: true,
        }
    }
}
