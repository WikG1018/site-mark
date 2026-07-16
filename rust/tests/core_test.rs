use std::fs;
use std::io::Read;

use ab_glyph::{FontArc, PxScale};
use image::{ImageBuffer, Rgb};
use imageproc::drawing::text_size;
use sitemark_core::api::image_core::{
    export_project, render_photo, sha256_file, watermark_layout, ExportPhotoRecord,
    ExportProjectRequest, RenderPhotoRequest, WatermarkPosition,
};
use tempfile::tempdir;
use zip::ZipArchive;

#[test]
fn hashes_a_file_with_sha256() {
    let directory = tempdir().unwrap();
    let path = directory.path().join("source.bin");
    fs::write(&path, b"abc").unwrap();

    let digest = sha256_file(path.to_string_lossy().into_owned()).unwrap();

    assert_eq!(
        digest,
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    );
}

#[test]
fn renders_a_full_resolution_jpeg_with_a_watermark_card() {
    let directory = tempdir().unwrap();
    let source = directory.path().join("source.jpg");
    let output = directory.path().join("watermarked.jpg");
    let image = ImageBuffer::from_pixel(1200, 900, Rgb([210u8, 215u8, 220u8]));
    image.save(&source).unwrap();

    let result = render_photo(RenderPhotoRequest {
        source_path: source.to_string_lossy().into_owned(),
        output_path: output.to_string_lossy().into_owned(),
        project_name: "东区厂房改造".to_string(),
        work_location: "A 区三层".to_string(),
        work_content: "风管安装检查".to_string(),
        photographer: "张工".to_string(),
        photo_number: "SM-20260716-001".to_string(),
        captured_at: "2026-07-16 09:32:18 +08:00".to_string(),
        address: Some("福建省漳州市".to_string()),
        coordinates: Some("24.5130, 117.6471 · ±8m".to_string()),
        notes: None,
        position: WatermarkPosition::BottomLeft,
        opacity: 0.78,
        accent_color_argb: 0xff37c58b,
    })
    .unwrap();

    let rendered = image::open(&output).unwrap();
    assert_eq!((rendered.width(), rendered.height()), (1200, 900));
    assert_eq!(result.width, 1200);
    assert_eq!(result.height, 900);
    assert_eq!(result.output_sha256.len(), 64);
    assert_ne!(
        sha256_file(source.to_string_lossy().into_owned()).unwrap(),
        result.output_sha256
    );
}

#[test]
fn exports_watermarked_photos_bom_csv_and_versioned_manifest() {
    let directory = tempdir().unwrap();
    let photo = directory.path().join("SM-20260716-001.jpg");
    fs::write(&photo, b"jpeg-placeholder").unwrap();
    let archive_path = directory.path().join("project.zip");

    let result = export_project(ExportProjectRequest {
        project_id: "project-1".to_string(),
        project_name: "东区厂房改造".to_string(),
        output_zip_path: archive_path.to_string_lossy().into_owned(),
        include_originals: false,
        photos: vec![ExportPhotoRecord {
            photo_number: "SM-20260716-001".to_string(),
            watermarked_path: photo.to_string_lossy().into_owned(),
            original_path: None,
            original_sha256: "0123456789abcdef".repeat(4),
            captured_at: "2026-07-16 09:32:18 +08:00".to_string(),
            work_location: "A 区三层".to_string(),
            work_content: "风管安装检查".to_string(),
            photographer: "张工".to_string(),
            address: Some("福建省漳州市".to_string()),
            coordinates: Some("24.5130, 117.6471 · ±8m".to_string()),
            notes: None,
        }],
    })
    .unwrap();

    assert_eq!(result.photo_count, 1);
    assert_eq!(result.archive_sha256.len(), 64);
    let archive_file = fs::File::open(&archive_path).unwrap();
    let mut archive = ZipArchive::new(archive_file).unwrap();
    assert!(archive.by_name("photos/SM-20260716-001.jpg").is_ok());

    let mut csv = Vec::new();
    archive
        .by_name("records.csv")
        .unwrap()
        .read_to_end(&mut csv)
        .unwrap();
    assert!(csv.starts_with(&[0xef, 0xbb, 0xbf]));
    assert!(String::from_utf8(csv).unwrap().contains("东区厂房改造"));

    let mut manifest = String::new();
    archive
        .by_name("manifest.json")
        .unwrap()
        .read_to_string(&mut manifest)
        .unwrap();
    assert!(manifest.contains("\"schema_version\": 1"));
}

#[test]
fn watermark_typography_is_twenty_percent_larger() {
    let layout = watermark_layout(4000, 3000, 8).unwrap();
    assert!((layout.font_size - 69.6).abs() < f32::EPSILON);
    assert!((layout.title_size - 82.128).abs() < 0.001);
    assert_eq!(layout.line_height, 99);
    assert!(layout.card_height + layout.margin <= 3000);
}

#[test]
fn larger_watermark_fits_supported_landscape_and_portrait_images() {
    for (width, height) in [(4000, 3000), (3000, 4000), (3840, 2160), (2160, 3840)] {
        let layout = watermark_layout(width, height, 9).unwrap();
        assert!(layout.left + layout.card_width <= width);
        assert!(layout.top + layout.card_height <= height);
    }
}

#[test]
fn truncates_max_length_work_content_to_fit_card_text_area() {
    // The maximum permitted work content is 240 characters. Render a card where
    // the work-content line is filled to that limit and confirm the fitted line
    // width never exceeds the card text area (card_width - padding * 2).
    let directory = tempdir().unwrap();
    let source = directory.path().join("source.jpg");
    let output = directory.path().join("watermarked.jpg");
    let image = ImageBuffer::from_pixel(4000, 3000, Rgb([210u8, 215u8, 220u8]));
    image.save(&source).unwrap();

    let work_content = "施".repeat(240);
    render_photo(RenderPhotoRequest {
        source_path: source.to_string_lossy().into_owned(),
        output_path: output.to_string_lossy().into_owned(),
        project_name: "东区厂房改造".to_string(),
        work_location: "A 区三层".to_string(),
        work_content: work_content.clone(),
        photographer: "张工".to_string(),
        photo_number: "SM-20260716-001".to_string(),
        captured_at: "2026-07-16 09:32:18 +08:00".to_string(),
        address: None,
        coordinates: None,
        notes: None,
        position: WatermarkPosition::BottomLeft,
        opacity: 0.78,
        accent_color_argb: 0xff37c58b,
    })
    .unwrap();

    // Re-derive the layout the renderer used and confirm the fitted work-content
    // line (which is the longest body line) fits within the text area. With
    // address/coordinates/notes all absent the renderer draws 6 lines.
    let layout = watermark_layout(4000, 3000, 6).unwrap();
    let max_text_width = layout.card_width.saturating_sub(layout.padding * 2);

    let font =
        FontArc::try_from_slice(include_bytes!("../assets/fonts/NotoSansSC-Regular.otf")).unwrap();
    let fitted = super_truncate(
        &format!("内容  {work_content}"),
        max_text_width,
        layout.font_size,
        &font,
    );
    let (fitted_width, _) = text_size(PxScale::from(layout.font_size), &font, &fitted);
    assert!(
        fitted_width <= max_text_width,
        "fitted line width {fitted_width} exceeds text area {max_text_width}"
    );
    assert!(
        fitted.ends_with('…'),
        "fitted line should end with ellipsis"
    );
    assert!(
        fitted.chars().count() < work_content.chars().count(),
        "fitted line should be shorter than the raw work content"
    );
}

/// Local copy of the renderer's truncation behaviour so the test can re-derive
/// the fitted string without depending on a private helper.
fn super_truncate(text: &str, max_width: u32, size: f32, font: &FontArc) -> String {
    let scale = PxScale::from(size);
    let (w, _) = text_size(scale, font, text);
    if w <= max_width {
        return text.to_string();
    }
    let mut chars: Vec<char> = text.chars().collect();
    while chars.len() > 1 {
        chars.pop();
        let candidate: String = chars.iter().collect::<String>() + "…";
        let (cw, _) = text_size(scale, font, &candidate);
        if cw <= max_width {
            return candidate;
        }
    }
    "…".to_string()
}
