use std::fs;
use std::io::{Read, Write};

use image::{ImageBuffer, Rgb};
use sitemark_core::api::image_core::{
    export_project, export_selection, extract_archive_photo, read_project_archive, render_photo,
    sha256_file, ExportPhotoRecord, ExportProjectRequest, ExportSelectionProject,
    ExportSelectionRequest, ExportWatermarkSettings, ExtractArchivePhotoRequest,
    RenderPhotoRequest, WatermarkPosition,
};
use tempfile::tempdir;
use zip::{ZipArchive, ZipWriter};

fn sample_watermark() -> ExportWatermarkSettings {
    ExportWatermarkSettings {
        position: "bottomRight".to_string(),
        opacity: 0.66,
        accent_color_argb: 0xff3366cc,
        font_scale: 1.2,
    }
}

/// Writes a ZIP with the given `(entry name, bytes)` pairs. Test helper for
/// crafting archives (valid, malicious, or legacy) without `export_project`.
fn write_zip(path: &std::path::Path, entries: &[(&str, &[u8])]) {
    let file = fs::File::create(path).unwrap();
    let mut writer = ZipWriter::new(file);
    let options = zip::write::SimpleFileOptions::default();
    for (name, bytes) in entries {
        writer.start_file(*name, options).unwrap();
        writer.write_all(bytes).unwrap();
    }
    writer.finish().unwrap();
}

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
        watermark: sample_watermark(),
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
            latitude: Some(24.513),
            longitude: Some(117.6471),
            accuracy_meters: Some(8.0),
            watermark_locale_code: Some("zh".to_string()),
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
    assert!(manifest.contains("\"schema_version\": 2"));
    assert!(manifest.contains("\"watermark\""));
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
                    latitude: None,
                    longitude: None,
                    accuracy_meters: None,
                    watermark_locale_code: None,
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
                    latitude: None,
                    longitude: None,
                    accuracy_meters: None,
                    watermark_locale_code: None,
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
                latitude: None,
                longitude: None,
                accuracy_meters: None,
                watermark_locale_code: None,
            }],
        }],
    });

    assert!(result.is_err());
}

// ---------------------------------------------------------------------------
// Backup restore (import)
// ---------------------------------------------------------------------------

#[test]
fn restores_a_v2_project_archive_round_trip() {
    let directory = tempdir().unwrap();
    let rendered = directory.path().join("rendered-source.jpg");
    let original = directory.path().join("original-source.jpg");
    fs::write(&rendered, b"watermarked-bytes").unwrap();
    fs::write(&original, b"original-bytes").unwrap();
    let original_sha = sha256_file(original.to_string_lossy().into_owned()).unwrap();
    let archive_path = directory.path().join("project.zip");

    export_project(ExportProjectRequest {
        project_id: "project-1".to_string(),
        project_name: "东区厂房改造".to_string(),
        output_zip_path: archive_path.to_string_lossy().into_owned(),
        include_originals: true,
        watermark: sample_watermark(),
        photos: vec![ExportPhotoRecord {
            photo_number: "SM-20260716-001".to_string(),
            watermarked_path: rendered.to_string_lossy().into_owned(),
            original_path: Some(original.to_string_lossy().into_owned()),
            original_sha256: original_sha.clone(),
            captured_at: "2026-07-16 09:32:18 +08:00".to_string(),
            work_location: "A 区三层".to_string(),
            work_content: "风管安装检查".to_string(),
            photographer: "张工".to_string(),
            address: Some("福建省漳州市".to_string()),
            coordinates: Some("24.5130, 117.6471 · ±8m".to_string()),
            notes: Some("复验合格".to_string()),
            latitude: Some(24.513),
            longitude: Some(117.6471),
            accuracy_meters: Some(8.0),
            watermark_locale_code: Some("zh".to_string()),
        }],
    })
    .unwrap();

    let preview = read_project_archive(archive_path.to_string_lossy().into_owned()).unwrap();
    assert_eq!(preview.schema_version, 2);
    assert_eq!(preview.project_name, "东区厂房改造");
    assert!(preview.includes_originals);
    let watermark = preview.watermark.expect("v2 archives carry the watermark");
    assert_eq!(watermark.position, "bottomRight");
    assert_eq!(watermark.accent_color_argb, 0xff3366cc);
    assert!((watermark.opacity - 0.66).abs() < f64::EPSILON);
    assert!((watermark.font_scale - 1.2).abs() < f64::EPSILON);

    let photo = preview.photos.first().expect("one photo");
    assert_eq!(photo.photo_number, "SM-20260716-001");
    assert!(photo.has_original);
    assert_eq!(photo.original_sha256, original_sha);
    assert_eq!(photo.latitude, Some(24.513));
    assert_eq!(photo.longitude, Some(117.6471));
    assert_eq!(photo.accuracy_meters, Some(8.0));
    assert_eq!(photo.watermark_locale_code.as_deref(), Some("zh"));
    assert_eq!(photo.notes.as_deref(), Some("复验合格"));

    let restore_dir = tempdir().unwrap();
    let restored_rendered = restore_dir.path().join("new-capture-id.jpg");
    let restored_original = restore_dir.path().join("new-capture-id-original.jpg");
    let extracted = extract_archive_photo(ExtractArchivePhotoRequest {
        zip_path: archive_path.to_string_lossy().into_owned(),
        photo_number: "SM-20260716-001".to_string(),
        rendered_destination: restored_rendered.to_string_lossy().into_owned(),
        original_destination: Some(restored_original.to_string_lossy().into_owned()),
    })
    .unwrap();
    assert_eq!(fs::read(&restored_rendered).unwrap(), b"watermarked-bytes");
    assert_eq!(fs::read(&restored_original).unwrap(), b"original-bytes");
    assert_eq!(
        extracted.original_path.as_deref(),
        restored_original.to_str()
    );
}

#[test]
fn accepts_v1_manifests_without_restore_fields() {
    let directory = tempdir().unwrap();
    let archive_path = directory.path().join("v1.zip");
    let manifest = serde_json::json!({
        "schema_version": 1,
        "app": "SiteMark",
        "project_id": "project-1",
        "project_name": "旧版导出",
        "includes_originals": false,
        "photos": [{
            "photo_number": "SM-20260716-001",
            "watermarked_path": "/data/old/rendered/x.jpg",
            "original_path": null,
            "original_sha256": "a".repeat(64),
            "captured_at": "2026-07-16 09:32:18 +08:00",
            "work_location": "A 区",
            "work_content": "风管检查",
            "photographer": "张工",
            "address": null,
            "coordinates": null,
            "notes": "v1 备注"
        }]
    });
    write_zip(
        &archive_path,
        &[
            ("manifest.json", manifest.to_string().as_bytes()),
            ("photos/SM-20260716-001.jpg", b"jpeg"),
        ],
    );

    let preview = read_project_archive(archive_path.to_string_lossy().into_owned()).unwrap();
    assert_eq!(preview.schema_version, 1);
    assert!(preview.watermark.is_none());
    let photo = preview.photos.first().unwrap();
    assert!(!photo.has_original);
    assert_eq!(photo.latitude, None);
    assert_eq!(photo.watermark_locale_code, None);
    assert_eq!(photo.notes.as_deref(), Some("v1 备注"));
}

#[test]
fn rejects_selection_archives_for_restore() {
    let directory = tempdir().unwrap();
    let photo = directory.path().join("SM-20260716-001.jpg");
    fs::write(&photo, b"jpeg").unwrap();
    let archive_path = directory.path().join("selection.zip");
    export_selection(ExportSelectionRequest {
        output_zip_path: archive_path.to_string_lossy().into_owned(),
        include_originals: false,
        projects: vec![ExportSelectionProject {
            project_id: "project-a".to_string(),
            project_name: "东区厂房改造".to_string(),
            photos: vec![ExportPhotoRecord {
                photo_number: "SM-20260716-001".to_string(),
                watermarked_path: photo.to_string_lossy().into_owned(),
                original_path: None,
                original_sha256: "0123456789abcdef".repeat(4),
                captured_at: "2026-07-16 09:32:18 +08:00".to_string(),
                work_location: "A 区".to_string(),
                work_content: "风管检查".to_string(),
                photographer: "张工".to_string(),
                address: None,
                coordinates: None,
                notes: None,
                latitude: None,
                longitude: None,
                accuracy_meters: None,
                watermark_locale_code: None,
            }],
        }],
    })
    .unwrap();

    let error = read_project_archive(archive_path.to_string_lossy().into_owned()).unwrap_err();
    assert!(error.contains("selection archive"), "{error}");
}

#[test]
fn rejects_archives_from_other_apps_and_unsupported_versions() {
    let directory = tempdir().unwrap();
    let foreign = directory.path().join("foreign.zip");
    let manifest = serde_json::json!({
        "schema_version": 1,
        "app": "OtherApp",
        "project_name": "x",
        "includes_originals": false,
        "photos": []
    });
    write_zip(
        &foreign,
        &[("manifest.json", manifest.to_string().as_bytes())],
    );
    let error = read_project_archive(foreign.to_string_lossy().into_owned()).unwrap_err();
    assert!(error.contains("not a SiteMark archive"), "{error}");

    let future = directory.path().join("future.zip");
    let manifest = serde_json::json!({
        "schema_version": 99,
        "app": "SiteMark",
        "project_name": "x",
        "includes_originals": false,
        "photos": []
    });
    write_zip(
        &future,
        &[("manifest.json", manifest.to_string().as_bytes())],
    );
    let error = read_project_archive(future.to_string_lossy().into_owned()).unwrap_err();
    assert!(error.contains("unsupported schema version"), "{error}");
}

#[test]
fn crafted_entry_names_are_never_used_as_output_paths() {
    // A Zip-Slip attempt: the archive holds a traversal entry plus a manifest
    // referencing a benign photo number. The restore must fail because the
    // expected `photos/<number>.jpg` entry is absent — the traversal entry
    // name is never matched nor written anywhere.
    let directory = tempdir().unwrap();
    let archive_path = directory.path().join("traversal.zip");
    let manifest = serde_json::json!({
        "schema_version": 1,
        "app": "SiteMark",
        "project_name": "x",
        "includes_originals": false,
        "photos": [{
            "photo_number": "SM-20260717-001",
            "original_sha256": "b".repeat(64),
            "captured_at": "2026-07-17 09:00:00 +08:00",
            "work_location": "A",
            "work_content": "B",
            "photographer": "C"
        }]
    });
    write_zip(
        &archive_path,
        &[
            ("manifest.json", manifest.to_string().as_bytes()),
            ("../escaped.jpg", b"evil"),
        ],
    );

    let error = read_project_archive(archive_path.to_string_lossy().into_owned()).unwrap_err();
    assert!(error.contains("missing the watermarked photo"), "{error}");
    assert!(!directory.path().join("escaped.jpg").exists());
    assert!(!directory
        .path()
        .parent()
        .unwrap()
        .join("escaped.jpg")
        .exists());
}

#[test]
fn sha_mismatch_fails_extraction_and_removes_written_files() {
    let directory = tempdir().unwrap();
    let archive_path = directory.path().join("corrupt.zip");
    let manifest = serde_json::json!({
        "schema_version": 2,
        "app": "SiteMark",
        "project_name": "东区厂房改造",
        "includes_originals": true,
        "photos": [{
            "photo_number": "SM-20260716-001",
            "original_sha256": "c".repeat(64),
            "captured_at": "2026-07-16 09:32:18 +08:00",
            "work_location": "A 区",
            "work_content": "风管检查",
            "photographer": "张工"
        }]
    });
    write_zip(
        &archive_path,
        &[
            ("manifest.json", manifest.to_string().as_bytes()),
            ("photos/SM-20260716-001.jpg", b"watermarked"),
            ("originals/SM-20260716-001.jpg", b"tampered-original"),
        ],
    );

    let rendered_dest = directory.path().join("out/rendered.jpg");
    let original_dest = directory.path().join("out/original.jpg");
    let error = extract_archive_photo(ExtractArchivePhotoRequest {
        zip_path: archive_path.to_string_lossy().into_owned(),
        photo_number: "SM-20260716-001".to_string(),
        rendered_destination: rendered_dest.to_string_lossy().into_owned(),
        original_destination: Some(original_dest.to_string_lossy().into_owned()),
    })
    .unwrap_err();
    assert!(error.contains("SHA-256 mismatch"), "{error}");
    assert!(!rendered_dest.exists());
    assert!(!original_dest.exists());
}

#[test]
fn duplicate_photo_numbers_are_rejected() {
    let directory = tempdir().unwrap();
    let archive_path = directory.path().join("dup.zip");
    let manifest = serde_json::json!({
        "schema_version": 1,
        "app": "SiteMark",
        "project_name": "x",
        "includes_originals": false,
        "photos": [
            {
                "photo_number": "SM-1",
                "original_sha256": "a".repeat(64),
                "captured_at": "2026-07-16 09:32:18 +08:00",
                "work_location": "A",
                "work_content": "B",
                "photographer": "C"
            },
            {
                "photo_number": "SM-1",
                "original_sha256": "b".repeat(64),
                "captured_at": "2026-07-16 09:33:18 +08:00",
                "work_location": "A",
                "work_content": "B",
                "photographer": "C"
            }
        ]
    });
    write_zip(
        &archive_path,
        &[
            ("manifest.json", manifest.to_string().as_bytes()),
            ("photos/SM-1.jpg", b"jpeg"),
        ],
    );

    let error = read_project_archive(archive_path.to_string_lossy().into_owned()).unwrap_err();
    assert!(error.contains("duplicate photo number"), "{error}");
}
