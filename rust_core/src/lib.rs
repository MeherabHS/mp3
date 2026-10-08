pub mod api;
pub mod audio;
pub mod database;
pub mod downloader;
pub mod error;
pub mod library;
pub mod lyrics;
pub mod metadata;
pub mod models;
pub mod queue;
pub mod storage;

pub use api::*;
pub use audio::AudioEngineCore;
pub use database::{Database, Schema};
pub use error::{CoreError, Result};
pub use library::LibraryScanner;
pub use lyrics::{LrcParser, LyricsCache, LyricsSynchronizer};
pub use metadata::{ArtworkProcessor, MetadataParser, ParsedAudioMetadata, ProcessedArtwork};
pub use models::*;
pub use queue::QueueManager;
pub use storage::StorageManager;

