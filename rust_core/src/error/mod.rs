use thiserror::Error;

#[derive(Error, Debug)]
pub enum CoreError {
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Database error: {0}")]
    Database(#[from] rusqlite::Error),

    #[error("Serialization error: {0}")]
    Serialization(#[from] serde_json::Error),

    #[error("Metadata parse error: {0}")]
    Metadata(String),

    #[error("Lyrics parse error: {0}")]
    Lyrics(String),

    #[error("Storage error: {0}")]
    Storage(String),

    #[error("Audio error: {0}")]
    Audio(String),

    #[error("Downloader error: {0}")]
    Downloader(String),

    #[error("Not found: {0}")]
    NotFound(String),

    #[error("Invalid state: {0}")]
    InvalidState(String),
}

pub type Result<T> = std::result::Result<T, CoreError>;
