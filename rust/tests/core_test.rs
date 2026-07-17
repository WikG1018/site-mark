use std::fs;
use std::io::Read;

use image::{ImageBuffer, Rgb};
use sitemark_core::api::image_core::{
    export_project, export_selection, render_photo, sha256_file, ExportPhotoRecord,
    ExportProjectRequest, ExportSelectionProject, ExportSelectionRequest, RenderPhotoRequest,
    WatermarkPosition,
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
fn missing_file_uses_not_found_error_prefix() {
    let error = sha256_file("definitely-missing-sitemark-file.jpg".into()).unwrap_err();
    assert!(error.starts_with("not_found:"), "{error}");
}

#[test]
fn invalid_source_image_uses_invalid_data_error_prefix() {
    let directory = tempdir().unwrap();
    let source = directory.path().join("invalid.jpg");
    let output = directory.path().join("watermarked.jpg");
    fs::write(&source, b"not a jpeg").unwrap();

    let error = render_photo(RenderPhotoRequest {
        source_path: source.to_string_lossy().into_owned(),
        output_path: output.to_string_lossy().into_owned(),
        project_name: "东区厂房改造".to_string(),
        work_location: "A 区三层".to_string(),
        work_content: "风管安装检查".to_string(),
        photographer: "张工".to_string(),
        photo_number: "SM-20260716-001".to_string(),
        captured_at: "2026-07-16 09:32:18 +08:00".to_string(),
        address: None,
        coordinates: None,
        notes: None,
        position: WatermarkPosition::BottomLeft,
        opacity: 0.78,
        accent_color_argb: 0xff37c58b,
        font_scale: 1.0,
        locale_code: "zh".to_string(),
    })
    .unwrap_err();

    assert!(error.starts_with("invalid_data:"), "{error}");
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
        font_scale: 1.0,
        locale_code: "zh".to_string(),
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
fn wraps_max_length_work_content_within_card_text_area() {
    // The maximum permitted work content is 240 characters. Render a card where
    // the work-content line is filled to that limit and confirm wrapping keeps
    // every line within the card text area (no truncation, no overflow). The
    // renderer errors out if the wrapped card height exceeds the source image,
    // so a successful render proves the content fits.
    let directory = tempdir().unwrap();
    let source = directory.path().join("source.jpg");
    let output = directory.path().join("watermarked.jpg");
    let image = ImageBuffer::from_pixel(4000, 3000, Rgb([210u8, 215u8, 220u8]));
    image.save(&source).unwrap();

    let work_content = "施".repeat(240);
    let result = render_photo(RenderPhotoRequest {
        source_path: source.to_string_lossy().into_owned(),
        output_path: output.to_string_lossy().into_owned(),
        project_name: "东区厂房改造".to_string(),
        work_location: "A 区三层".to_string(),
        work_content,
        photographer: "张工".to_string(),
        photo_number: "SM-20260716-001".to_string(),
        captured_at: "2026-07-16 09:32:18 +08:00".to_string(),
        address: None,
        coordinates: None,
        notes: None,
        position: WatermarkPosition::BottomLeft,
        opacity: 0.78,
        accent_color_argb: 0xff37c58b,
        font_scale: 1.0,
        locale_code: "zh".to_string(),
    })
    .unwrap();

    let rendered = image::open(&output).unwrap();
    assert_eq!((rendered.width(), rendered.height()), (4000, 3000));
    assert_eq!(result.width, 4000);
    assert_eq!(result.height, 3000);
}

#[test]
fn exports_selection_zip_grouped_by_project_with_records_and_manifest() {
    let directory = tempdir().unwrap();
    let photo_a = directory.path().join("SM-20260716-001.jpg");
    let photo_b = directory.path().join("SM-20260716-002.jpg");
    fs::write(&photo_a, b"jpeg-a").unwrap();
    fs::write(&photo_b, b"jpeg-b").unwrap();
    let archive_path = directory.path().join("selection.zip");

    let result = export_selection(ExportSelectionRequest {
        output_zip_path: archive_path.to_string_lossy().into_owned(),
        include_originals: false,
        projects: vec![
            ExportSelectionProject {
                project_id: "project-a".to_string(),
                project_name: "东区厂房改造".to_string(),
                photos: vec![ExportPhotoRecord {
                    photo_number: "SM-20260716-001".to_string(),
                    watermarked_path: photo_a.to_string_lossy().into_owned(),
                    original_path: None,
                    original_sha256: "0123456789abcdef".repeat(4),
                    captured_at: "2026-07-16 09:32:18 +08:00".to_string(),
                    work_location: "A 区".to_string(),
                    work_content: "风管检查".to_string(),
                    photographer: "张工".to_string(),
                    address: None,
                    coordinates: None,
                    notes: None,
                }],
            },
            ExportSelectionProject {
                project_id: "project-b".to_string(),
                project_name: "西区市政给水".to_string(),
                photos: vec![ExportPhotoRecord {
                    photo_number: "SM-20260716-002".to_string(),
                    watermarked_path: photo_b.to_string_lossy().into_owned(),
                    original_path: None,
                    original_sha256: "fedcba9876543210".repeat(4),
                    captured_at: "2026-07-16 10:11:42 +08:00".to_string(),
                    work_location: "B 区".to_string(),
                    work_content: "管道试压".to_string(),
                    photographer: "李工".to_string(),
                    address: None,
                    coordinates: None,
                    notes: None,
                }],
            },
        ],
    })
    .unwrap();

    assert_eq!(result.photo_count, 2);
    assert_eq!(result.archive_sha256.len(), 64);
    let archive_file = fs::File::open(&archive_path).unwrap();
    let mut archive = ZipArchive::new(archive_file).unwrap();
    assert!(archive
        .by_name("projects/project-a/photos/SM-20260716-001.jpg")
        .is_ok());
    assert!(archive
        .by_name("projects/project-b/photos/SM-20260716-002.jpg")
        .is_ok());
    assert!(archive.by_name("records.csv").is_ok());
    assert!(archive.by_name("manifest.json").is_ok());

    let mut csv = Vec::new();
    archive
        .by_name("records.csv")
        .unwrap()
        .read_to_end(&mut csv)
        .unwrap();
    assert!(csv.starts_with(&[0xef, 0xbb, 0xbf]));
    let csv_text = String::from_utf8(csv).unwrap();
    assert!(csv_text.contains("东区厂房改造"));
    assert!(csv_text.contains("西区市政给水"));

    let mut manifest = String::new();
    archive
        .by_name("manifest.json")
        .unwrap()
        .read_to_string(&mut manifest)
        .unwrap();
    assert!(manifest.contains("\"schema_version\": 1"));
    assert!(manifest.contains("project-a"));
    assert!(manifest.contains("project-b"));
}

#[test]
fn rejects_path_navigation_in_project_id() {
    let directory = tempdir().unwrap();
    let photo = directory.path().join("SM-001.jpg");
    fs::write(&photo, b"jpeg").unwrap();
    let archive_path = directory.path().join("traversal.zip");

    let result = export_selection(ExportSelectionRequest {
        output_zip_path: archive_path.to_string_lossy().into_owned(),
        include_originals: false,
        projects: vec![ExportSelectionProject {
            project_id: "..".to_string(),
            project_name: "traversal".to_string(),
            photos: vec![ExportPhotoRecord {
                photo_number: "SM-20260717-001".to_string(),
                watermarked_path: photo.to_string_lossy().into_owned(),
                original_path: None,
                original_sha256: "0123456789abcdef".repeat(4),
                captured_at: "2026-07-17 09:00:00 +08:00".to_string(),
                work_location: "A".to_string(),
                work_content: "B".to_string(),
                photographer: "C".to_string(),
                address: None,
                coordinates: None,
                notes: None,
            }],
        }],
    });

    assert!(result.is_err());
}
