use crate::error::{CoreError, Result};
use crate::storage::StorageManager;
use image::GenericImageView;

pub struct ArtworkProcessor;

pub struct ProcessedArtwork {
    pub dominant_color_hex: String,
    pub path_64: String,
    pub path_200: String,
    pub path_500: String,
}

impl ArtworkProcessor {
    /// Maximum raw artwork bytes we'll process — anything larger risks OOM on
    /// low-memory devices when decoding a giant embedded image during library scan.
    const MAX_RAW_BYTES: usize = 3 * 1024 * 1024; // 3 MB

    /// Maximum source dimension before we pre-shrink to keep decode RAM bounded.
    const MAX_SRC_SIDE: u32 = 800;

    pub fn process_and_cache(
        storage: &StorageManager,
        track_id: &str,
        raw_bytes: &[u8],
    ) -> Result<ProcessedArtwork> {
        // Guard: skip artwork that is suspiciously large to prevent OOM
        if raw_bytes.len() > Self::MAX_RAW_BYTES {
            return Err(CoreError::Metadata(format!(
                "Artwork too large ({} KB), skipping",
                raw_bytes.len() / 1024
            )));
        }

        let img = image::load_from_memory(raw_bytes)
            .map_err(|e| CoreError::Metadata(format!("Failed to decode image: {}", e)))?;

        // Pre-shrink huge source images before any resize step.
        // This bounds the in-memory pixel buffer and makes all subsequent
        // resize operations cheap. Triangle filter is fast and good enough here.
        let img = if img.width() > Self::MAX_SRC_SIDE || img.height() > Self::MAX_SRC_SIDE {
            img.thumbnail(Self::MAX_SRC_SIDE, Self::MAX_SRC_SIDE)
        } else {
            img
        };

        let dominant_color_hex = Self::extract_dominant_color(&img);

        // 1. 64×64 — notification icon & list thumbnails
        let thumb_64 = img.thumbnail(64, 64);
        let path_64 = storage.get_artwork_path_for_track(track_id, 64);
        thumb_64
            .save_with_format(&path_64, image::ImageFormat::Jpeg)
            .map_err(|e| CoreError::Metadata(format!("Failed to save 64px artwork: {}", e)))?;

        // 2. 200×200 — album grid in library
        let thumb_200 = img.thumbnail(200, 200);
        let path_200 = storage.get_artwork_path_for_track(track_id, 200);
        thumb_200
            .save_with_format(&path_200, image::ImageFormat::Jpeg)
            .map_err(|e| CoreError::Metadata(format!("Failed to save 200px artwork: {}", e)))?;

        // 3. 500×500 — Now Playing view
        // Use Triangle (fast) not Lanczos3 (slow/memory-heavy) during bulk scan.
        let thumb_500 = img.thumbnail(500, 500);
        let path_500 = storage.get_artwork_path_for_track(track_id, 500);
        thumb_500
            .save_with_format(&path_500, image::ImageFormat::Jpeg)
            .map_err(|e| CoreError::Metadata(format!("Failed to save 500px artwork: {}", e)))?;

        Ok(ProcessedArtwork {
            dominant_color_hex,
            path_64: path_64.to_string_lossy().to_string(),
            path_200: path_200.to_string_lossy().to_string(),
            path_500: path_500.to_string_lossy().to_string(),
        })
    }

    pub fn extract_dominant_color(img: &image::DynamicImage) -> String {
        let (width, height) = img.dimensions();
        if width == 0 || height == 0 {
            return "#121212".to_string();
        }

        // Fast sample 16x16 grid
        let small = img.thumbnail_exact(16, 16);
        let rgb_img = small.to_rgb8();

        let mut r_total: u64 = 0;
        let mut g_total: u64 = 0;
        let mut b_total: u64 = 0;
        let mut count: u64 = 0;

        for pixel in rgb_img.pixels() {
            r_total += pixel[0] as u64;
            g_total += pixel[1] as u64;
            b_total += pixel[2] as u64;
            count += 1;
        }

        if count == 0 {
            return "#121212".to_string();
        }

        let r_avg = (r_total / count) as u8;
        let g_avg = (g_total / count) as u8;
        let b_avg = (b_total / count) as u8;

        format!("#{:02X}{:02X}{:02X}", r_avg, g_avg, b_avg)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;
    use tempfile::TempDir;

    #[test]
    fn test_artwork_thumbnailing_and_dominant_color() {
        let internal = TempDir::new().unwrap();
        let sd = TempDir::new().unwrap();
        let storage = StorageManager::new(internal.path(), sd.path()).unwrap();

        // Create a 100x100 solid orange test image in memory
        let mut img_buf = image::RgbImage::new(100, 100);
        for pixel in img_buf.pixels_mut() {
            *pixel = image::Rgb([255, 128, 0]);
        }
        let dynamic_img = image::DynamicImage::ImageRgb8(img_buf);
        let mut raw_png = Vec::new();
        dynamic_img
            .write_to(&mut Cursor::new(&mut raw_png), image::ImageFormat::Png)
            .unwrap();

        let processed =
            ArtworkProcessor::process_and_cache(&storage, "test_track_art", &raw_png).unwrap();

        assert_eq!(processed.dominant_color_hex, "#FF8000");
        assert!(std::path::Path::new(&processed.path_64).exists());
        assert!(std::path::Path::new(&processed.path_200).exists());
        assert!(std::path::Path::new(&processed.path_500).exists());
    }
}
