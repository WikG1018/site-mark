use std::fs;
use std::io::{Read, Write};

use image::{ImageBuffer, Rgb};
use sitemark_core::api::image_core::{
    export_project, export_project_bundle, export_selection, extract_archive_photo,
    extract_project_bundle_entry, read_project_archive, read_project_bundle, render_photo,
    sha256_file, ExportCaptureTemplate, ExportPhotoRecord, ExportProjectBundleRequest,
    ExportProjectRequest, ExportSelectionProject, ExportSelectionRequest, ExportWatermarkSettings,
    ExtractArchivePhotoRequest, ExtractProjectBundleEntryRequest, ProjectBundleSource,
    RenderPhotoRequest, WatermarkPosition, MAX_BUNDLE_ENTRY_BYTES, MAX_BUNDLE_PROJECTS,
    MAX_BUNDLE_TOTAL_BYTES,
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

/// Writes a deliberately crafted outer bundle. The bundle reader must reject
/// malformed manifests before it ever trusts an inner archive path.
fn write_bundle_zip(
    path: &std::path::Path,
    manifest: serde_json::Value,
    entries: &[(&str, &[u8])],
) {
    let manifest_text = manifest.to_string();
    let file = fs::File::create(path).unwrap();
    let mut writer = ZipWriter::new(file);
    writer
        .start_file("bundle.json", zip::write::SimpleFileOptions::default())
        .unwrap();
    writer.write_all(manifest_text.as_bytes()).unwrap();
    let stored =
        zip::write::SimpleFileOptions::default().compression_method(zip::CompressionMethod::Stored);
    for (name, bytes) in entries {
        writer.start_file(*name, stored).unwrap();
        writer.write_all(bytes).unwrap();
    }
    writer.finish().unwrap();
}

/// Crafts ZIP64 central-directory sizes without allocating giant test files.
/// The reader must reject the declared limits before it ever attempts to
/// stream a project entry, so one-byte payloads safely exercise 8/16 GiB
/// boundary checks.
fn write_bundle_with_declared_sizes(
    path: &std::path::Path,
    manifest: serde_json::Value,
    entries: &[(&str, &[u8], u64)],
) {
    let manifest_text = manifest.to_string();
    let file = fs::File::create(path).unwrap();
    let mut writer = ZipWriter::new(file);
    writer
        .start_file("bundle.json", zip::write::SimpleFileOptions::default())
        .unwrap();
    writer.write_all(manifest_text.as_bytes()).unwrap();
    let stored = zip::write::SimpleFileOptions::default()
        .compression_method(zip::CompressionMethod::Stored)
        .large_file(true);
    for (name, bytes, _) in entries {
        writer.start_file(*name, stored).unwrap();
        writer.write_all(bytes).unwrap();
    }
    writer.finish().unwrap();

    let mut raw = fs::read(path).unwrap();
    for (name, _, declared_size) in entries {
        let mut found = false;
        for index in 0..raw.len().saturating_sub(46) {
            if raw[index..].starts_with(b"PK\x01\x02") {
                let name_len = u16::from_le_bytes([raw[index + 28], raw[index + 29]]) as usize;
                let extra_len = u16::from_le_bytes([raw[index + 30], raw[index + 31]]) as usize;
                let name_start = index + 46;
                let extra_start = name_start + name_len;
                if raw[name_start..name_start + name_len] != *name.as_bytes() {
                    continue;
                }
                assert!(extra_len >= 20, "ZIP64 extra block is required");
                assert_eq!(&raw[extra_start..extra_start + 4], &[1, 0, 16, 0]);
                raw[extra_start + 4..extra_start + 12]
                    .copy_from_slice(&declared_size.to_le_bytes());
                raw[extra_start + 12..extra_start + 20]
                    .copy_from_slice(&declared_size.to_le_bytes());
                found = true;
                break;
            }
        }
        assert!(found, "missing central ZIP64 entry for {name}");
    }
    fs::write(path, raw).unwrap();
}

fn bundle_manifest(projects: serde_json::Value) -> serde_json::Value {
    serde_json::json!({
        "app": "SiteMark",
        "kind": "sitemark-project-bundle",
        "schema_version": 1,
        "created_at": "1720000000000",
        "projects": projects,
    })
}

// ---------------------------------------------------------------------------
// Multi-project restorable bundles
// ---------------------------------------------------------------------------

#[test]
fn project_bundle_round_trip_and_hash_validation() {
    let directory = tempdir().unwrap();
    let project_zip = directory.path().join("project-1.zip");
    write_zip(&project_zip, &[("manifest.json", b"project archive")]);
    let bundle_path = directory.path().join("bundle.zip");

    let result = export_project_bundle(ExportProjectBundleRequest {
        output_zip_path: bundle_path.to_string_lossy().into_owned(),
        projects: vec![ProjectBundleSource {
            project_id: "project-1".to_string(),
            project_name: "东区".to_string(),
            archive_path: project_zip.to_string_lossy().into_owned(),
        }],
    })
    .unwrap();

    let preview = read_project_bundle(bundle_path.to_string_lossy().into_owned()).unwrap();
    assert_eq!(preview.schema_version, 1);
    assert_eq!(preview.projects.len(), 1);
    assert_eq!(preview.projects[0].project_id, "project-1");
    assert_eq!(preview.projects[0].project_name, "东区");
    assert_eq!(
        preview.projects[0].archive_sha256,
        sha256_file(project_zip.to_string_lossy().into_owned()).unwrap()
    );
    assert_eq!(result.archive_sha256.len(), 64);
}

#[test]
fn project_bundle_extraction_uses_a_temporary_file_and_rejects_overwrite() {
    let directory = tempdir().unwrap();
    let project_zip = directory.path().join("project-1.zip");
    write_zip(&project_zip, &[("manifest.json", b"project archive")]);
    let bundle_path = directory.path().join("bundle.zip");
    export_project_bundle(ExportProjectBundleRequest {
        output_zip_path: bundle_path.to_string_lossy().into_owned(),
        projects: vec![ProjectBundleSource {
            project_id: "project-1".to_string(),
            project_name: "东区".to_string(),
            archive_path: project_zip.to_string_lossy().into_owned(),
        }],
    })
    .unwrap();
    let destination = directory.path().join("staging/project-1.zip");

    extract_project_bundle_entry(ExtractProjectBundleEntryRequest {
        zip_path: bundle_path.to_string_lossy().into_owned(),
        archive_path: "projects/project-1.zip".to_string(),
        output_path: destination.to_string_lossy().into_owned(),
    })
    .unwrap();
    assert_eq!(
        fs::read(&destination).unwrap(),
        fs::read(&project_zip).unwrap()
    );
    assert!(!destination.with_file_name("project-1.zip.tmp").exists());

    let overwrite_error = extract_project_bundle_entry(ExtractProjectBundleEntryRequest {
        zip_path: bundle_path.to_string_lossy().into_owned(),
        archive_path: "projects/project-1.zip".to_string(),
        output_path: destination.to_string_lossy().into_owned(),
    })
    .unwrap_err();
    assert!(
        overwrite_error.contains("already exists"),
        "{overwrite_error}"
    );
}

#[test]
fn project_bundle_extraction_preserves_a_preexisting_temporary_file() {
    let directory = tempdir().unwrap();
    let project_zip = directory.path().join("project-1.zip");
    write_zip(&project_zip, &[("manifest.json", b"project archive")]);
    let bundle_path = directory.path().join("bundle.zip");
    export_project_bundle(ExportProjectBundleRequest {
        output_zip_path: bundle_path.to_string_lossy().into_owned(),
        projects: vec![ProjectBundleSource {
            project_id: "project-1".to_string(),
            project_name: "东区".to_string(),
            archive_path: project_zip.to_string_lossy().into_owned(),
        }],
    })
    .unwrap();
    let destination = directory.path().join("staging/project-1.zip");
    let temporary = destination.with_file_name("project-1.zip.tmp");
    fs::create_dir_all(temporary.parent().unwrap()).unwrap();
    fs::write(&temporary, b"belongs-to-another-operation").unwrap();

    let error = extract_project_bundle_entry(ExtractProjectBundleEntryRequest {
        zip_path: bundle_path.to_string_lossy().into_owned(),
        archive_path: "projects/project-1.zip".to_string(),
        output_path: destination.to_string_lossy().into_owned(),
    })
    .unwrap_err();
    assert!(error.contains("already exists"), "{error}");
    assert_eq!(
        fs::read(&temporary).unwrap(),
        b"belongs-to-another-operation"
    );
    assert!(!destination.exists());
}

#[test]
fn project_bundle_rejects_traversal_and_duplicate_project_ids() {
    let directory = tempdir().unwrap();
    let traversal = directory.path().join("traversal.zip");
    write_bundle_zip(
        &traversal,
        bundle_manifest(serde_json::json!([{
            "project_id": "project-1",
            "project_name": "东区",
            "archive_path": "../escape.zip",
            "archive_sha256": "a".repeat(64),
        }])),
        &[("../escape.zip", b"evil")],
    );
    let traversal_error =
        read_project_bundle(traversal.to_string_lossy().into_owned()).unwrap_err();
    assert!(
        traversal_error.contains("archive path"),
        "{traversal_error}"
    );

    let duplicate = directory.path().join("duplicate.zip");
    write_bundle_zip(
        &duplicate,
        bundle_manifest(serde_json::json!([
            {
                "project_id": "project-1",
                "project_name": "东区",
                "archive_path": "projects/project-1.zip",
                "archive_sha256": "a".repeat(64),
            },
            {
                "project_id": "project-1",
                "project_name": "西区",
                "archive_path": "projects/project-1.zip",
                "archive_sha256": "b".repeat(64),
            }
        ])),
        &[],
    );
    let duplicate_error =
        read_project_bundle(duplicate.to_string_lossy().into_owned()).unwrap_err();
    assert!(
        duplicate_error.contains("duplicate project ID"),
        "{duplicate_error}"
    );
}

#[test]
fn project_bundle_rejects_more_than_one_hundred_projects_and_hash_mismatches() {
    let directory = tempdir().unwrap();
    let too_many = directory.path().join("too-many.zip");
    let projects: Vec<serde_json::Value> = (0..=MAX_BUNDLE_PROJECTS)
        .map(|index| {
            serde_json::json!({
                "project_id": format!("project-{index}"),
                "project_name": format!("项目 {index}"),
                "archive_path": format!("projects/project-{index}.zip"),
                "archive_sha256": "a".repeat(64),
            })
        })
        .collect();
    write_bundle_zip(
        &too_many,
        bundle_manifest(serde_json::Value::Array(projects)),
        &[],
    );
    let too_many_error = read_project_bundle(too_many.to_string_lossy().into_owned()).unwrap_err();
    assert!(too_many_error.contains("more than 100"), "{too_many_error}");

    let mismatch = directory.path().join("mismatch.zip");
    write_bundle_zip(
        &mismatch,
        bundle_manifest(serde_json::json!([{
            "project_id": "project-1",
            "project_name": "东区",
            "archive_path": "projects/project-1.zip",
            "archive_sha256": "a".repeat(64),
        }])),
        &[("projects/project-1.zip", b"not the declared hash")],
    );
    let mismatch_error = read_project_bundle(mismatch.to_string_lossy().into_owned()).unwrap_err();
    assert!(
        mismatch_error.contains("SHA-256 mismatch"),
        "{mismatch_error}"
    );
}

#[test]
fn project_bundle_rejects_selection_archives_and_exposes_explicit_size_limits() {
    let directory = tempdir().unwrap();
    let selection = directory.path().join("selection.zip");
    write_zip(
        &selection,
        &[(
            "manifest.json",
            br#"{\"app\":\"SiteMark\",\"projects\":[]}"#,
        )],
    );

    let error = read_project_bundle(selection.to_string_lossy().into_owned()).unwrap_err();
    assert!(error.contains("bundle"), "{error}");
    assert_eq!(MAX_BUNDLE_ENTRY_BYTES, 8 * 1024 * 1024 * 1024);
    assert_eq!(MAX_BUNDLE_TOTAL_BYTES, 16 * 1024 * 1024 * 1024);
}

#[test]
fn project_bundle_rejects_declared_entry_and_total_size_limits() {
    let directory = tempdir().unwrap();
    let entry_limit = directory.path().join("entry-limit.zip");
    write_bundle_with_declared_sizes(
        &entry_limit,
        bundle_manifest(serde_json::json!([{
            "project_id": "project-1",
            "project_name": "东区",
            "archive_path": "projects/project-1.zip",
            "archive_sha256": "a".repeat(64),
        }])),
        &[("projects/project-1.zip", b"x", MAX_BUNDLE_ENTRY_BYTES + 1)],
    );
    let entry_error = read_project_bundle(entry_limit.to_string_lossy().into_owned()).unwrap_err();
    assert!(entry_error.contains("8 GiB"), "{entry_error}");

    let total_limit = directory.path().join("total-limit.zip");
    let projects: Vec<serde_json::Value> = (1..=3)
        .map(|index| {
            serde_json::json!({
                "project_id": format!("project-{index}"),
                "project_name": format!("项目 {index}"),
                "archive_path": format!("projects/project-{index}.zip"),
                "archive_sha256": "a".repeat(64),
            })
        })
        .collect();
    write_bundle_with_declared_sizes(
        &total_limit,
        bundle_manifest(serde_json::Value::Array(projects)),
        &[
            ("projects/project-1.zip", b"x", 6 * 1024 * 1024 * 1024),
            ("projects/project-2.zip", b"y", 6 * 1024 * 1024 * 1024),
            ("projects/project-3.zip", b"z", 6 * 1024 * 1024 * 1024),
        ],
    );
    let total_error = read_project_bundle(total_limit.to_string_lossy().into_owned()).unwrap_err();
    assert!(total_error.contains("16 GiB"), "{total_error}");
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
        project_description: None,
        project_created_at: "2026-07-16T09:00:00+08:00".to_string(),
        snapshot_at: "2026-07-16T10:00:00+08:00".to_string(),
        omitted_processing_count: 0,
        omitted_failed_count: 0,
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
        templates: vec![],
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
    assert!(manifest.contains("\"schema_version\": 4"));
    assert!(manifest.contains("\"watermark\""));
    assert!(manifest.contains("\"templates\": []"));
}

fn valid_manifest_template(name: &str) -> serde_json::Value {
    serde_json::json!({
        "name": name,
        "work_location": "A 区三层",
        "work_content": "风管安装检查",
        "photographer": "张工",
        "created_at": "2026-08-01 09:00:00 +08:00",
        "updated_at": "2026-08-02 10:00:00 +08:00",
    })
}

fn write_schema_v4_archive(
    path: &std::path::Path,
    schema_version: u32,
    templates: Vec<serde_json::Value>,
) {
    let manifest = serde_json::json!({
        "schema_version": schema_version,
        "app": "SiteMark",
        "project_id": "project-templates",
        "project_name": "模板项目",
        "project_created_at": "2026-08-01T08:00:00+08:00",
        "snapshot_at": "2026-08-03T13:00:00+08:00",
        "omitted_processing_count": 0,
        "omitted_failed_count": 0,
        "includes_originals": false,
        "watermark": {
            "position": "bottomRight",
            "opacity": 0.66,
            "accent_color_argb": 0xff3366cc_u32,
            "font_scale": 1.2,
        },
        "photos": [{
            "photo_number": "SM-20260801-001",
            "original_sha256": "a".repeat(64),
            "captured_at": "2026-08-01 09:30:00 +08:00",
            "work_location": "A 区",
            "work_content": "现场检查",
            "photographer": "张工"
        }],
        "templates": templates,
    });
    write_zip(
        path,
        &[
            ("manifest.json", manifest.to_string().as_bytes()),
            ("photos/SM-20260801-001.jpg", b"jpeg"),
        ],
    );
}

fn write_archive_matrix_fixture(
    path: &std::path::Path,
    schema_version: u32,
    include_photo: bool,
    templates: Vec<serde_json::Value>,
) {
    let photos = if include_photo {
        serde_json::json!([{
            "photo_number": "SM-20260801-001",
            "original_sha256": "a".repeat(64),
            "captured_at": "2026-08-01 09:30:00 +08:00",
            "work_location": "A 区",
            "work_content": "现场检查",
            "photographer": "张工"
        }])
    } else {
        serde_json::json!([])
    };
    let manifest = serde_json::json!({
        "schema_version": schema_version,
        "app": "SiteMark",
        "project_id": format!("matrix-v{schema_version}"),
        "project_name": format!("矩阵项目 v{schema_version}"),
        "project_created_at": "2026-08-01T08:00:00+08:00",
        "snapshot_at": "2026-08-03T13:00:00+08:00",
        "omitted_processing_count": 0,
        "omitted_failed_count": 0,
        "includes_originals": false,
        "watermark": {
            "position": "bottomRight",
            "opacity": 0.66,
            "accent_color_argb": 0xff3366cc_u32,
            "font_scale": 1.2,
        },
        "photos": photos,
        "templates": templates,
    });
    let manifest_text = manifest.to_string();
    if include_photo {
        write_zip(
            path,
            &[
                ("manifest.json", manifest_text.as_bytes()),
                ("photos/SM-20260801-001.jpg", b"jpeg"),
            ],
        );
    } else {
        write_zip(path, &[("manifest.json", manifest_text.as_bytes())]);
    }
}

fn assert_schema_v4_templates_rejected(
    directory: &tempfile::TempDir,
    case: &str,
    templates: Vec<serde_json::Value>,
) {
    let archive_path = directory.path().join(format!("{case}.zip"));
    write_schema_v4_archive(&archive_path, 4, templates);
    let result = read_project_archive(archive_path.to_string_lossy().into_owned());
    assert!(result.is_err(), "{case} unexpectedly returned a preview");
}

#[test]
fn reads_empty_schema_v3_project_without_templates() {
    let directory = tempdir().unwrap();
    let archive_path = directory.path().join("empty-project.zip");
    let manifest = serde_json::json!({
        "schema_version": 3,
        "app": "SiteMark",
        "project_id": "empty-project",
        "project_name": "空白项目",
        "project_description": "仅有项目设置",
        "project_created_at": "2026-07-30T08:00:00+08:00",
        "snapshot_at": "2026-07-30T09:00:00+08:00",
        "omitted_processing_count": 0,
        "omitted_failed_count": 0,
        "includes_originals": false,
        "watermark": {
            "position": "bottomRight",
            "opacity": 0.66,
            "accent_color_argb": 0xff3366cc_u32,
            "font_scale": 1.2,
        },
        "photos": [],
    });
    write_zip(
        &archive_path,
        &[("manifest.json", manifest.to_string().as_bytes())],
    );

    let preview = read_project_archive(archive_path.to_string_lossy().into_owned()).unwrap();
    assert_eq!(preview.schema_version, 3);
    assert_eq!(preview.project_description.as_deref(), Some("仅有项目设置"));
    assert_eq!(
        preview.project_created_at.as_deref(),
        Some("2026-07-30T08:00:00+08:00")
    );
    assert!(!preview.is_partial);
    assert!(preview.photos.is_empty());
    assert!(preview.templates.is_empty());
}

#[test]
fn archive_schema_photo_template_matrix_is_explicit() {
    let directory = tempdir().unwrap();
    for (case, schema_version, include_photo, include_template) in [
        ("v1-photo", 1, true, false),
        ("v2-photo", 2, true, false),
        ("v3-empty", 3, false, false),
        ("v4-empty", 4, false, false),
        ("v4-photo", 4, true, false),
        ("v4-template", 4, false, true),
        ("v4-photo-template", 4, true, true),
    ] {
        let archive = directory.path().join(format!("{case}.zip"));
        let templates = if include_template {
            vec![valid_manifest_template("  日常   巡检  ")]
        } else {
            vec![]
        };
        write_archive_matrix_fixture(&archive, schema_version, include_photo, templates);
        let preview = read_project_archive(archive.to_string_lossy().into_owned()).unwrap();
        assert_eq!(preview.schema_version, schema_version, "{case}");
        assert_eq!(preview.photos.len(), usize::from(include_photo), "{case}");
        assert_eq!(
            preview.templates.len(),
            usize::from(include_template),
            "{case}"
        );
        if include_template {
            assert_eq!(preview.templates[0].name, "日常 巡检", "{case}");
        }
    }
}

#[test]
fn legacy_schemas_reject_template_payloads_during_inspection() {
    let directory = tempdir().unwrap();
    for schema_version in [1, 2, 3] {
        let archive = directory
            .path()
            .join(format!("v{schema_version}-with-template.zip"));
        write_archive_matrix_fixture(
            &archive,
            schema_version,
            true,
            vec![valid_manifest_template("日常巡检")],
        );
        let result = read_project_archive(archive.to_string_lossy().into_owned());
        assert!(
            result.is_err(),
            "schema v{schema_version} unexpectedly exposed templates"
        );
    }
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
fn restores_a_v4_project_archive_round_trip() {
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
        project_description: None,
        project_created_at: "2026-07-16T09:00:00+08:00".to_string(),
        snapshot_at: "2026-07-16T10:00:00+08:00".to_string(),
        omitted_processing_count: 0,
        omitted_failed_count: 0,
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
        templates: vec![],
    })
    .unwrap();

    let preview = read_project_archive(archive_path.to_string_lossy().into_owned()).unwrap();
    assert_eq!(preview.schema_version, 4);
    assert_eq!(preview.project_name, "东区厂房改造");
    assert!(preview.includes_originals);
    assert!(preview.templates.is_empty());
    let watermark = preview.watermark.expect("archive carries the watermark");
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
fn exports_and_reads_schema_v4_capture_templates_without_database_ids() {
    let directory = tempdir().unwrap();
    let archive_path = directory.path().join("templates.zip");
    let templates = vec![
        ExportCaptureTemplate {
            name: "  日常   巡检  ".to_string(),
            work_location: "A 区三层".to_string(),
            work_content: "风管安装检查".to_string(),
            photographer: "张工".to_string(),
            created_at: "2026-08-01 09:00:00 +08:00".to_string(),
            updated_at: "2026-08-02 10:00:00 +08:00".to_string(),
        },
        ExportCaptureTemplate {
            name: "收尾复验".to_string(),
            work_location: "B 区屋面".to_string(),
            work_content: "设备复验".to_string(),
            photographer: "李工".to_string(),
            created_at: "2026-08-01 11:00:00 +00:00".to_string(),
            updated_at: "2026-08-03 12:00:00 +00:00".to_string(),
        },
    ];

    export_project(ExportProjectRequest {
        project_id: "project-templates".to_string(),
        project_name: "模板项目".to_string(),
        project_description: None,
        project_created_at: "2026-08-01T08:00:00+08:00".to_string(),
        snapshot_at: "2026-08-03T13:00:00+08:00".to_string(),
        omitted_processing_count: 0,
        omitted_failed_count: 0,
        output_zip_path: archive_path.to_string_lossy().into_owned(),
        include_originals: false,
        watermark: sample_watermark(),
        photos: vec![],
        templates,
    })
    .unwrap();

    let archive_file = fs::File::open(&archive_path).unwrap();
    let mut archive = ZipArchive::new(archive_file).unwrap();
    let mut manifest_text = String::new();
    archive
        .by_name("manifest.json")
        .unwrap()
        .read_to_string(&mut manifest_text)
        .unwrap();
    let manifest: serde_json::Value = serde_json::from_str(&manifest_text).unwrap();
    assert_eq!(manifest["schema_version"], 4);
    assert_eq!(manifest["templates"].as_array().unwrap().len(), 2);
    assert!(manifest["templates"][0].get("id").is_none());
    drop(archive);

    let preview = read_project_archive(archive_path.to_string_lossy().into_owned()).unwrap();
    assert_eq!(preview.schema_version, 4);
    assert_eq!(preview.templates.len(), 2);
    assert_eq!(preview.templates[0].name, "日常 巡检");
    assert_eq!(preview.templates[0].work_location, "A 区三层");
    assert_eq!(preview.templates[0].work_content, "风管安装检查");
    assert_eq!(preview.templates[0].photographer, "张工");
    assert_eq!(
        preview.templates[0].created_at,
        "2026-08-01 09:00:00 +08:00"
    );
    assert_eq!(
        preview.templates[0].updated_at,
        "2026-08-02 10:00:00 +08:00"
    );
    assert_eq!(preview.templates[1].name, "收尾复验");
}

#[test]
fn accepts_unicode_scalar_template_length_boundaries() {
    let directory = tempdir().unwrap();
    let archive_path = directory.path().join("unicode-boundaries.zip");
    let mut template = valid_manifest_template(&"😀".repeat(80));
    template["work_location"] = serde_json::json!("😀".repeat(160));
    template["work_content"] = serde_json::json!("😀".repeat(240));
    template["photographer"] = serde_json::json!("😀".repeat(80));
    write_schema_v4_archive(&archive_path, 4, vec![template]);

    let preview = read_project_archive(archive_path.to_string_lossy().into_owned()).unwrap();
    assert_eq!(preview.templates[0].name.chars().count(), 80);
    assert_eq!(preview.templates[0].work_location.chars().count(), 160);
    assert_eq!(preview.templates[0].work_content.chars().count(), 240);
    assert_eq!(preview.templates[0].photographer.chars().count(), 80);
}

#[test]
fn rejects_template_count_empty_values_and_unicode_scalar_overflow() {
    let directory = tempdir().unwrap();
    let hundred = directory.path().join("one-hundred-templates.zip");
    write_schema_v4_archive(
        &hundred,
        4,
        (0..100)
            .map(|index| valid_manifest_template(&format!("模板 {index}")))
            .collect(),
    );
    let preview = read_project_archive(hundred.to_string_lossy().into_owned()).unwrap();
    assert_eq!(preview.templates.len(), 100);

    assert_schema_v4_templates_rejected(
        &directory,
        "too-many-templates",
        (0..101)
            .map(|index| valid_manifest_template(&format!("模板 {index}")))
            .collect(),
    );

    for field in ["name", "work_location", "work_content", "photographer"] {
        let mut template = valid_manifest_template("有效模板");
        template[field] = serde_json::json!(" \t\n ");
        assert_schema_v4_templates_rejected(&directory, &format!("empty-{field}"), vec![template]);
    }

    for (field, value) in [
        ("name", "😀".repeat(81)),
        ("work_location", "😀".repeat(161)),
        ("work_content", "😀".repeat(241)),
        ("photographer", "😀".repeat(81)),
    ] {
        let mut template = valid_manifest_template("有效模板");
        template[field] = serde_json::json!(value);
        assert_schema_v4_templates_rejected(
            &directory,
            &format!("too-long-{field}"),
            vec![template],
        );
    }
}

#[test]
fn rejects_normalized_duplicate_template_names() {
    let directory = tempdir().unwrap();
    for (case, first, second) in [
        ("collapsed-whitespace", "  日常   巡检  ", "日常 巡检"),
        ("ascii-case", "ABC", "abc"),
        ("mixed-script-ascii-case", "模板A", "模板a"),
    ] {
        assert_schema_v4_templates_rejected(
            &directory,
            case,
            vec![
                valid_manifest_template(first),
                valid_manifest_template(second),
            ],
        );
    }
}

#[test]
fn archive_template_names_match_dart_two_stage_whitespace_and_key_rules() {
    let directory = tempdir().unwrap();
    let accepted = directory.path().join("dart-whitespace-contract.zip");
    write_schema_v4_archive(
        &accepted,
        4,
        vec![
            valid_manifest_template("\u{0085}A\u{0085}B\u{0085}"),
            valid_manifest_template("A B"),
            valid_manifest_template("\u{200B}A\u{200B}B\u{200B}"),
        ],
    );
    let preview = read_project_archive(accepted.to_string_lossy().into_owned()).unwrap();
    assert_eq!(preview.templates[0].name, "A\u{0085}B");
    assert_eq!(preview.templates[1].name, "A B");
    assert_eq!(preview.templates[2].name, "\u{200B}A\u{200B}B\u{200B}");

    assert_schema_v4_templates_rejected(
        &directory,
        "nel-trimmed-ascii-case-duplicate",
        vec![
            valid_manifest_template("\u{0085}ABC\u{0085}"),
            valid_manifest_template("abc"),
        ],
    );
    assert_schema_v4_templates_rejected(
        &directory,
        "feff-collapsed-duplicate",
        vec![
            valid_manifest_template("A\u{FEFF}B"),
            valid_manifest_template("A B"),
        ],
    );
}

#[test]
fn rejects_nul_in_every_archive_template_string() {
    let directory = tempdir().unwrap();
    for field in ["name", "work_location", "work_content", "photographer"] {
        let mut template = valid_manifest_template("有效模板");
        template[field] = serde_json::json!("前\0后");
        assert_schema_v4_templates_rejected(&directory, &format!("nul-{field}"), vec![template]);
    }
}

#[test]
fn rejects_invalid_template_timestamps_and_future_schema_without_partial_preview() {
    let directory = tempdir().unwrap();
    for field in ["created_at", "updated_at"] {
        let mut template = valid_manifest_template("有效模板");
        template[field] = serde_json::json!("not-a-timestamp");
        assert_schema_v4_templates_rejected(&directory, &format!("bad-{field}"), vec![template]);
    }

    let future = directory.path().join("schema-99-with-photo.zip");
    write_schema_v4_archive(&future, 99, vec![valid_manifest_template("有效模板")]);
    let result = read_project_archive(future.to_string_lossy().into_owned());
    assert!(result.is_err(), "schema 99 unexpectedly returned a preview");
}

#[test]
fn archive_template_timestamps_enforce_strict_calendar_time_and_offset_boundaries() {
    let directory = tempdir().unwrap();
    let month_ends = [
        (1, 31),
        (2, 28),
        (3, 31),
        (4, 30),
        (5, 31),
        (6, 30),
        (7, 31),
        (8, 31),
        (9, 30),
        (10, 31),
        (11, 30),
        (12, 31),
    ];
    let mut accepted = vec![
        "2000-02-29 00:00:00 +00:00".to_string(),
        "2024-02-29 00:00:00 +00:00".to_string(),
        "2026-01-01 00:00:00 -23:59".to_string(),
        "2026-12-31 23:59:59 +23:59".to_string(),
    ];
    let mut rejected = vec![
        "1900-02-29 00:00:00 +00:00".to_string(),
        "2026-02-29 00:00:00 +00:00".to_string(),
        "2026-00-01 00:00:00 +00:00".to_string(),
        "2026-13-01 00:00:00 +00:00".to_string(),
        "2026-01-00 00:00:00 +00:00".to_string(),
        "2026-01-01 24:00:00 +00:00".to_string(),
        "2026-01-01 23:60:00 +00:00".to_string(),
        "2026-01-01 23:59:60 +00:00".to_string(),
        "2026-01-01 00:00:00 +24:00".to_string(),
        "2026-01-01 00:00:00 +23:60".to_string(),
        "2026-01-01 00:00:00 08:00".to_string(),
        "2026-01-01 00:00:00 +08:00x".to_string(),
        "２０２６-01-01 00:00:00 +08:00".to_string(),
    ];
    for (month, last_day) in month_ends {
        accepted.push(format!("2026-{month:02}-{last_day:02} 12:34:56 -08:30"));
        rejected.push(format!(
            "2026-{month:02}-{:02} 12:34:56 -08:30",
            last_day + 1
        ));
    }

    for field in ["created_at", "updated_at"] {
        for (index, timestamp) in accepted.iter().enumerate() {
            let archive = directory
                .path()
                .join(format!("accepted-{field}-{index}.zip"));
            let mut template = valid_manifest_template("有效模板");
            template[field] = serde_json::json!(timestamp);
            write_schema_v4_archive(&archive, 4, vec![template]);
            let preview = read_project_archive(archive.to_string_lossy().into_owned()).unwrap();
            assert_eq!(preview.templates.len(), 1, "{field}: {timestamp}");
        }
        for (index, timestamp) in rejected.iter().enumerate() {
            let mut template = valid_manifest_template("有效模板");
            template[field] = serde_json::json!(timestamp);
            assert_schema_v4_templates_rejected(
                &directory,
                &format!("rejected-{field}-{index}"),
                vec![template],
            );
        }
    }
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
    assert!(preview.templates.is_empty());
}

#[test]
fn accepts_v2_manifests_without_capture_templates() {
    let directory = tempdir().unwrap();
    let archive_path = directory.path().join("v2.zip");
    let manifest = serde_json::json!({
        "schema_version": 2,
        "app": "SiteMark",
        "project_id": "project-v2",
        "project_name": "旧版 v2 导出",
        "includes_originals": false,
        "watermark": {
            "position": "bottomLeft",
            "opacity": 0.78,
            "accent_color_argb": 0xff37c58b_u32,
            "font_scale": 1.0,
        },
        "photos": [{
            "photo_number": "SM-20260716-002",
            "original_sha256": "b".repeat(64),
            "captured_at": "2026-07-16 09:33:18 +08:00",
            "work_location": "B 区",
            "work_content": "设备检查",
            "photographer": "李工"
        }]
    });
    write_zip(
        &archive_path,
        &[
            ("manifest.json", manifest.to_string().as_bytes()),
            ("photos/SM-20260716-002.jpg", b"jpeg"),
        ],
    );

    let preview = read_project_archive(archive_path.to_string_lossy().into_owned()).unwrap();
    assert_eq!(preview.schema_version, 2);
    assert_eq!(preview.photos.len(), 1);
    assert!(preview.watermark.is_some());
    assert!(preview.templates.is_empty());
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
    assert!(!rendered_dest.with_file_name("rendered.jpg.tmp").exists());
    assert!(!original_dest.with_file_name("original.jpg.tmp").exists());
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

/// Builds a small valid archive with one photo plus original on disk.
fn build_restorable_zip(directory: &tempfile::TempDir) -> std::path::PathBuf {
    let rendered = directory.path().join("rendered-source.jpg");
    let original = directory.path().join("original-source.jpg");
    fs::write(&rendered, b"watermarked-bytes").unwrap();
    fs::write(&original, b"original-bytes").unwrap();
    let original_sha = sha256_file(original.to_string_lossy().into_owned()).unwrap();
    let archive_path = directory.path().join("project.zip");
    export_project(ExportProjectRequest {
        project_id: "project-1".to_string(),
        project_name: "东区厂房改造".to_string(),
        project_description: None,
        project_created_at: "2026-07-16T09:00:00+08:00".to_string(),
        snapshot_at: "2026-07-16T10:00:00+08:00".to_string(),
        omitted_processing_count: 0,
        omitted_failed_count: 0,
        output_zip_path: archive_path.to_string_lossy().into_owned(),
        include_originals: true,
        watermark: sample_watermark(),
        photos: vec![ExportPhotoRecord {
            photo_number: "SM-20260716-001".to_string(),
            watermarked_path: rendered.to_string_lossy().into_owned(),
            original_path: Some(original.to_string_lossy().into_owned()),
            original_sha256: original_sha,
            captured_at: "2026-07-16 09:32:18 +08:00".to_string(),
            work_location: "A 区三层".to_string(),
            work_content: "风管安装检查".to_string(),
            photographer: "张工".to_string(),
            address: None,
            coordinates: None,
            notes: None,
            latitude: None,
            longitude: None,
            accuracy_meters: None,
            watermark_locale_code: None,
        }],
        templates: vec![],
    })
    .unwrap();
    archive_path
}

#[test]
fn rendered_copy_failure_leaves_no_files_behind() {
    let directory = tempdir().unwrap();
    let archive_path = build_restorable_zip(&directory);
    // Force the rendered write to fail: the destination's parent is an
    // existing *file*, so create_dir_all cannot make the directory.
    let blocker = directory.path().join("blocker");
    fs::write(&blocker, b"file").unwrap();
    let rendered_dest = blocker.join("rendered.jpg");
    let original_dest = directory.path().join("out-original.jpg");

    let error = extract_archive_photo(ExtractArchivePhotoRequest {
        zip_path: archive_path.to_string_lossy().into_owned(),
        photo_number: "SM-20260716-001".to_string(),
        rendered_destination: rendered_dest.to_string_lossy().into_owned(),
        original_destination: Some(original_dest.to_string_lossy().into_owned()),
    })
    .unwrap_err();

    assert!(error.starts_with("io:"), "{error}");
    assert!(!rendered_dest.exists());
    assert!(!blocker.join("rendered.jpg.tmp").exists());
    assert!(!original_dest.exists());
    assert!(!directory.path().join("out-original.jpg.tmp").exists());
}

#[test]
fn original_copy_failure_removes_the_staged_rendered_tmp() {
    let directory = tempdir().unwrap();
    let archive_path = build_restorable_zip(&directory);
    let rendered_dest = directory.path().join("rendered.jpg");
    // The original's parent is an existing file, so its extraction fails
    // *after* the rendered tmp was already written.
    let blocker = directory.path().join("blocker");
    fs::write(&blocker, b"file").unwrap();
    let original_dest = blocker.join("original.jpg");

    let error = extract_archive_photo(ExtractArchivePhotoRequest {
        zip_path: archive_path.to_string_lossy().into_owned(),
        photo_number: "SM-20260716-001".to_string(),
        rendered_destination: rendered_dest.to_string_lossy().into_owned(),
        original_destination: Some(original_dest.to_string_lossy().into_owned()),
    })
    .unwrap_err();

    assert!(error.starts_with("io:"), "{error}");
    // Neither the final files nor their .tmp staging files may remain.
    assert!(!rendered_dest.exists());
    assert!(!directory.path().join("rendered.jpg.tmp").exists());
    assert!(!original_dest.exists());
    assert!(!blocker.join("original.jpg.tmp").exists());
}

#[test]
fn oversized_manifest_is_rejected() {
    let directory = tempdir().unwrap();
    let archive_path = directory.path().join("big-manifest.zip");
    let huge = " ".repeat(4 * 1024 * 1024 + 16);
    write_zip(&archive_path, &[("manifest.json", huge.as_bytes())]);

    let error = read_project_archive(archive_path.to_string_lossy().into_owned()).unwrap_err();
    assert!(
        error.contains("manifest exceeds the 4 MiB size limit"),
        "{error}"
    );
}

#[test]
fn archives_with_too_many_photos_are_rejected() {
    let directory = tempdir().unwrap();
    let archive_path = directory.path().join("many.zip");
    let photos: Vec<serde_json::Value> = (0..2001)
        .map(|index| {
            serde_json::json!({
                "photo_number": format!("SM-{index}"),
                "original_sha256": "a".repeat(64),
                "captured_at": "2026-07-16 09:32:18 +08:00",
                "work_location": "A",
                "work_content": "B",
                "photographer": "C"
            })
        })
        .collect();
    let manifest = serde_json::json!({
        "schema_version": 1,
        "app": "SiteMark",
        "project_name": "x",
        "includes_originals": false,
        "photos": photos,
    });
    write_zip(
        &archive_path,
        &[("manifest.json", manifest.to_string().as_bytes())],
    );

    let error = read_project_archive(archive_path.to_string_lossy().into_owned()).unwrap_err();
    assert!(error.contains("more than 2000 photos"), "{error}");
}
