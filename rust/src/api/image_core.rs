use std::fs::{self, File, OpenOptions};
use std::io::{BufReader, BufWriter, Read, Write};
use std::path::{Path, PathBuf};

use ab_glyph::{FontArc, PxScale};
use image::codecs::jpeg::JpegEncoder;
use image::{DynamicImage, GenericImageView, ImageDecoder, ImageReader, Pixel, Rgba, RgbaImage};
use imageproc::drawing::{draw_filled_rect_mut, draw_text_mut, text_size};
use imageproc::rect::Rect;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use zip::write::SimpleFileOptions;
use zip::{CompressionMethod, ZipWriter};

const FONT_BYTES: &[u8] = include_bytes!("../../assets/fonts/NotoSansSC-Regular.otf");

#[derive(Clone, Copy, Debug, Deserialize, Serialize)]
pub enum WatermarkPosition {
    BottomLeft,
    BottomRight,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct RenderPhotoRequest {
    pub source_path: String,
    pub output_path: String,
    pub project_name: String,
    pub work_location: String,
    pub work_content: String,
    pub photographer: String,
    pub photo_number: String,
    pub captured_at: String,
    pub address: Option<String>,
    pub coordinates: Option<String>,
    pub notes: Option<String>,
    pub position: WatermarkPosition,
    pub opacity: f64,
    pub accent_color_argb: u32,
    pub font_scale: f64,
    pub locale_code: String,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct RenderPhotoResult {
    pub output_path: String,
    pub output_sha256: String,
    pub width: u32,
    pub height: u32,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct ExportPhotoRecord {
    pub photo_number: String,
    pub watermarked_path: String,
    pub original_path: Option<String>,
    pub original_sha256: String,
    pub captured_at: String,
    pub work_location: String,
    pub work_content: String,
    pub photographer: String,
    pub address: Option<String>,
    pub coordinates: Option<String>,
    pub notes: Option<String>,
    // Backup-restore fields (manifest schema v2). Optional so v1 archives
    // remain readable by the importer.
    #[serde(default)]
    pub latitude: Option<f64>,
    #[serde(default)]
    pub longitude: Option<f64>,
    #[serde(default)]
    pub accuracy_meters: Option<f64>,
    #[serde(default)]
    pub watermark_locale_code: Option<String>,
}

/// Project-level watermark template persisted in v2 manifests so a restored
/// project keeps its original look instead of falling back to defaults.
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct ExportWatermarkSettings {
    pub position: String,
    pub opacity: f64,
    pub accent_color_argb: u32,
    pub font_scale: f64,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct ExportCaptureTemplate {
    pub name: String,
    pub work_location: String,
    pub work_content: String,
    pub photographer: String,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct ExportProjectRequest {
    pub project_id: String,
    pub project_name: String,
    pub project_description: Option<String>,
    pub project_created_at: String,
    pub snapshot_at: String,
    pub omitted_processing_count: u32,
    pub omitted_failed_count: u32,
    pub output_zip_path: String,
    pub include_originals: bool,
    pub project_lifecycle_status: String,
    pub project_is_pinned: bool,
    pub watermark: ExportWatermarkSettings,
    pub photos: Vec<ExportPhotoRecord>,
    pub templates: Vec<ExportCaptureTemplate>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct ExportProjectResult {
    pub output_zip_path: String,
    pub archive_sha256: String,
    pub photo_count: u32,
}

/// A multi-project backup contains at most one hundred already-exported
/// project ZIPs. The outer archive never unpacks these ZIPs; it merely stores
/// and integrity-checks them for later restore orchestration in Dart.
pub const MAX_BUNDLE_PROJECTS: usize = 100;
pub const MAX_BUNDLE_ENTRY_BYTES: u64 = 8 * 1024 * 1024 * 1024;
pub const MAX_BUNDLE_TOTAL_BYTES: u64 = 16 * 1024 * 1024 * 1024;

const PROJECT_BUNDLE_KIND: &str = "sitemark-project-bundle";
const PROJECT_BUNDLE_SCHEMA_VERSION: u32 = 1;

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct ProjectBundleSource {
    pub project_id: String,
    pub project_name: String,
    pub archive_path: String,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct ExportProjectBundleRequest {
    pub output_zip_path: String,
    pub projects: Vec<ProjectBundleSource>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct ProjectBundleEntryPreview {
    pub project_id: String,
    pub project_name: String,
    pub archive_path: String,
    pub archive_sha256: String,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct ProjectBundlePreview {
    pub schema_version: u32,
    pub created_at: String,
    pub projects: Vec<ProjectBundleEntryPreview>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct ExtractProjectBundleEntryRequest {
    pub zip_path: String,
    pub archive_path: String,
    pub output_path: String,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct ExportSelectionProject {
    pub project_id: String,
    pub project_name: String,
    pub photos: Vec<ExportPhotoRecord>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct ExportSelectionRequest {
    pub output_zip_path: String,
    pub include_originals: bool,
    pub projects: Vec<ExportSelectionProject>,
}

#[derive(Serialize)]
struct ExportManifest<'a> {
    schema_version: u32,
    app: &'static str,
    project_id: &'a str,
    project_name: &'a str,
    project_description: &'a Option<String>,
    project_created_at: &'a str,
    snapshot_at: &'a str,
    omitted_processing_count: u32,
    omitted_failed_count: u32,
    includes_originals: bool,
    project_lifecycle_status: &'a str,
    project_is_pinned: bool,
    watermark: &'a ExportWatermarkSettings,
    photos: &'a [ExportPhotoRecord],
    templates: &'a [ExportCaptureTemplate],
}

#[derive(Serialize)]
struct SelectionManifestProject<'a> {
    project_id: &'a str,
    project_name: &'a str,
    photos: &'a [ExportPhotoRecord],
}

#[derive(Serialize)]
struct SelectionManifest<'a> {
    schema_version: u32,
    app: &'static str,
    includes_originals: bool,
    projects: Vec<SelectionManifestProject<'a>>,
}

#[derive(Serialize)]
struct CsvRow<'a> {
    project_name: &'a str,
    photo_number: &'a str,
    captured_at: &'a str,
    work_location: &'a str,
    work_content: &'a str,
    photographer: &'a str,
    address: &'a str,
    coordinates: &'a str,
    notes: &'a str,
    original_sha256: &'a str,
}

fn io_failure(context: &str, error: std::io::Error) -> String {
    let prefix = if error.kind() == std::io::ErrorKind::NotFound {
        "not_found:"
    } else {
        "io:"
    };
    format!("{prefix}{context}: {error}")
}

fn invalid_data(context: &str, error: impl std::fmt::Display) -> String {
    format!("invalid_data:{context}: {error}")
}

fn image_failure(context: &str, error: image::ImageError) -> String {
    match error {
        image::ImageError::IoError(error) => io_failure(context, error),
        error => invalid_data(context, error),
    }
}

fn zip_failure(context: &str, error: zip::result::ZipError) -> String {
    match error {
        zip::result::ZipError::Io(error) => io_failure(context, error),
        error => invalid_data(context, error),
    }
}

pub fn sha256_file(path: String) -> Result<String, String> {
    let file = File::open(&path).map_err(|error| io_failure(&format!("open {path}"), error))?;
    let mut reader = BufReader::new(file);
    let mut hasher = Sha256::new();
    let mut buffer = [0u8; 64 * 1024];
    loop {
        let count = reader
            .read(&mut buffer)
            .map_err(|error| io_failure(&format!("read {path}"), error))?;
        if count == 0 {
            break;
        }
        hasher.update(&buffer[..count]);
    }
    Ok(hex::encode(hasher.finalize()))
}

fn verify_file(path: String, expected_sha256: String) -> Result<bool, String> {
    Ok(sha256_file(path)?.eq_ignore_ascii_case(expected_sha256.trim()))
}

pub fn render_photo(request: RenderPhotoRequest) -> Result<RenderPhotoResult, String> {
    validate_render_request(&request)?;
    let mut decoder = ImageReader::open(&request.source_path)
        .map_err(|error| io_failure("open source image", error))?
        .into_decoder()
        .map_err(|error| image_failure("decode source image", error))?;
    let orientation = decoder
        .orientation()
        .map_err(|error| image_failure("read image orientation", error))?;
    let mut image = DynamicImage::from_decoder(decoder)
        .map_err(|error| image_failure("decode source pixels", error))?;
    image.apply_orientation(orientation);
    let (width, height) = image.dimensions();
    let mut canvas = image.to_rgba8();
    draw_watermark_card(&mut canvas, &request)?;
    let output = Path::new(&request.output_path);
    if let Some(parent) = output.parent() {
        fs::create_dir_all(parent).map_err(|error| io_failure("create output directory", error))?;
    }
    let file = File::create(output).map_err(|error| io_failure("create output image", error))?;
    let writer = BufWriter::new(file);
    let mut encoder = JpegEncoder::new_with_quality(writer, 92);
    encoder
        .encode_image(&DynamicImage::ImageRgba8(canvas))
        .map_err(|error| image_failure("encode output JPEG", error))?;

    Ok(RenderPhotoResult {
        output_path: request.output_path.clone(),
        output_sha256: sha256_file(request.output_path)?,
        width,
        height,
    })
}

pub fn export_project(request: ExportProjectRequest) -> Result<ExportProjectResult, String> {
    if request.project_name.trim().is_empty() {
        return Err(invalid_data(
            "validate export request",
            "project name is required",
        ));
    }
    if !is_valid_lifecycle_status(&request.project_lifecycle_status) {
        return Err(invalid_data(
            "validate export request",
            format!(
                "unsupported project lifecycle status {}",
                request.project_lifecycle_status
            ),
        ));
    }
    let output = Path::new(&request.output_zip_path);
    if let Some(parent) = output.parent() {
        fs::create_dir_all(parent).map_err(|error| io_failure("create export directory", error))?;
    }
    let file = File::create(output).map_err(|error| io_failure("create ZIP", error))?;
    let mut archive = ZipWriter::new(BufWriter::new(file));
    let options = SimpleFileOptions::default().compression_method(CompressionMethod::Deflated);

    for photo in &request.photos {
        let safe_number = safe_photo_number_component(&photo.photo_number)?;
        add_file_to_zip(
            &mut archive,
            &photo.watermarked_path,
            &format!("photos/{safe_number}.jpg"),
            options,
        )?;
        if request.include_originals {
            let original = photo.original_path.as_deref().ok_or_else(|| {
                invalid_data(
                    "validate export request",
                    format!("missing original for {}", photo.photo_number),
                )
            })?;
            let extension = Path::new(original)
                .extension()
                .and_then(|value| value.to_str())
                .unwrap_or("jpg")
                .to_ascii_lowercase();
            add_file_to_zip(
                &mut archive,
                original,
                &format!("originals/{safe_number}.{extension}"),
                options,
            )?;
        }
    }

    let mut csv_bytes = vec![0xef, 0xbb, 0xbf];
    {
        let mut csv = csv::WriterBuilder::new()
            .has_headers(true)
            .from_writer(&mut csv_bytes);
        for photo in &request.photos {
            csv.serialize(CsvRow {
                project_name: &request.project_name,
                photo_number: &photo.photo_number,
                captured_at: &photo.captured_at,
                work_location: &photo.work_location,
                work_content: &photo.work_content,
                photographer: &photo.photographer,
                address: photo.address.as_deref().unwrap_or(""),
                coordinates: photo.coordinates.as_deref().unwrap_or(""),
                notes: photo.notes.as_deref().unwrap_or(""),
                original_sha256: &photo.original_sha256,
            })
            .map_err(|error| invalid_data("write CSV record", error))?;
        }
        csv.flush()
            .map_err(|error| io_failure("finish CSV", error))?;
    }
    archive
        .start_file("records.csv", options)
        .map_err(|error| zip_failure("start CSV entry", error))?;
    archive
        .write_all(&csv_bytes)
        .map_err(|error| io_failure("write CSV entry", error))?;

    // Single-project exports are the restorable backup format: schema v5
    // records lifecycle status and pin flag with the watermark template.
    // Selection archives intentionally stay at v1 and are not restorable.
    let manifest = serde_json::to_vec_pretty(&ExportManifest {
        schema_version: 5,
        app: "SiteMark",
        project_id: &request.project_id,
        project_name: &request.project_name,
        project_description: &request.project_description,
        project_created_at: &request.project_created_at,
        snapshot_at: &request.snapshot_at,
        omitted_processing_count: request.omitted_processing_count,
        omitted_failed_count: request.omitted_failed_count,
        includes_originals: request.include_originals,
        project_lifecycle_status: &request.project_lifecycle_status,
        project_is_pinned: request.project_is_pinned,
        watermark: &request.watermark,
        photos: &request.photos,
        templates: &request.templates,
    })
    .map_err(|error| invalid_data("serialize manifest", error))?;
    archive
        .start_file("manifest.json", options)
        .map_err(|error| zip_failure("start manifest entry", error))?;
    archive
        .write_all(&manifest)
        .map_err(|error| io_failure("write manifest entry", error))?;
    archive
        .finish()
        .map_err(|error| zip_failure("finish ZIP", error))?;

    Ok(ExportProjectResult {
        output_zip_path: request.output_zip_path.clone(),
        archive_sha256: sha256_file(request.output_zip_path)?,
        photo_count: request.photos.len() as u32,
    })
}

pub fn export_selection(request: ExportSelectionRequest) -> Result<ExportProjectResult, String> {
    if request.projects.is_empty() {
        return Err(invalid_data(
            "validate export request",
            "project list is empty",
        ));
    }
    let total_photos: usize = request.projects.iter().map(|p| p.photos.len()).sum();
    if total_photos == 0 {
        return Err(invalid_data(
            "validate export request",
            "no photos to export",
        ));
    }
    for project in &request.projects {
        safe_archive_component(&project.project_id)?;
        if project.project_name.trim().is_empty() {
            return Err(invalid_data(
                "validate export request",
                "project name is required",
            ));
        }
        for photo in &project.photos {
            safe_photo_number_component(&photo.photo_number)?;
        }
    }

    let output = Path::new(&request.output_zip_path);
    if let Some(parent) = output.parent() {
        fs::create_dir_all(parent).map_err(|error| io_failure("create export directory", error))?;
    }
    let file = File::create(output).map_err(|error| io_failure("create ZIP", error))?;
    let mut archive = ZipWriter::new(BufWriter::new(file));
    let options = SimpleFileOptions::default().compression_method(CompressionMethod::Deflated);

    for project in &request.projects {
        let safe_project_id = safe_archive_component(&project.project_id)?;
        for photo in &project.photos {
            let safe_number = safe_photo_number_component(&photo.photo_number)?;
            add_file_to_zip(
                &mut archive,
                &photo.watermarked_path,
                &format!("projects/{safe_project_id}/photos/{safe_number}.jpg"),
                options,
            )?;
            if request.include_originals {
                let original = photo.original_path.as_deref().ok_or_else(|| {
                    invalid_data(
                        "validate export request",
                        format!("missing original for {}", photo.photo_number),
                    )
                })?;
                let extension = Path::new(original)
                    .extension()
                    .and_then(|value| value.to_str())
                    .unwrap_or("jpg")
                    .to_ascii_lowercase();
                add_file_to_zip(
                    &mut archive,
                    original,
                    &format!("projects/{safe_project_id}/originals/{safe_number}.{extension}"),
                    options,
                )?;
            }
        }
    }

    let mut csv_bytes = vec![0xef, 0xbb, 0xbf];
    {
        let mut csv = csv::WriterBuilder::new()
            .has_headers(true)
            .from_writer(&mut csv_bytes);
        for project in &request.projects {
            for photo in &project.photos {
                csv.serialize(CsvRow {
                    project_name: &project.project_name,
                    photo_number: &photo.photo_number,
                    captured_at: &photo.captured_at,
                    work_location: &photo.work_location,
                    work_content: &photo.work_content,
                    photographer: &photo.photographer,
                    address: photo.address.as_deref().unwrap_or(""),
                    coordinates: photo.coordinates.as_deref().unwrap_or(""),
                    notes: photo.notes.as_deref().unwrap_or(""),
                    original_sha256: &photo.original_sha256,
                })
                .map_err(|error| invalid_data("write CSV record", error))?;
            }
        }
        csv.flush()
            .map_err(|error| io_failure("finish CSV", error))?;
    }
    archive
        .start_file("records.csv", options)
        .map_err(|error| zip_failure("start CSV entry", error))?;
    archive
        .write_all(&csv_bytes)
        .map_err(|error| io_failure("write CSV entry", error))?;

    let manifest_projects: Vec<SelectionManifestProject> = request
        .projects
        .iter()
        .map(|project| SelectionManifestProject {
            project_id: &project.project_id,
            project_name: &project.project_name,
            photos: &project.photos,
        })
        .collect();
    let manifest = serde_json::to_vec_pretty(&SelectionManifest {
        schema_version: 1,
        app: "SiteMark",
        includes_originals: request.include_originals,
        projects: manifest_projects,
    })
    .map_err(|error| invalid_data("serialize manifest", error))?;
    archive
        .start_file("manifest.json", options)
        .map_err(|error| zip_failure("start manifest entry", error))?;
    archive
        .write_all(&manifest)
        .map_err(|error| io_failure("write manifest entry", error))?;
    archive
        .finish()
        .map_err(|error| zip_failure("finish ZIP", error))?;

    Ok(ExportProjectResult {
        output_zip_path: request.output_zip_path.clone(),
        archive_sha256: sha256_file(request.output_zip_path)?,
        photo_count: total_photos as u32,
    })
}

/// Writes a restorable outer bundle from complete, single-project ZIPs.
/// Inner archives are deliberately stored rather than recompressed: this
/// keeps export CPU predictable and makes the outer entry hash a direct hash
/// of the original project archive bytes.
pub fn export_project_bundle(
    request: ExportProjectBundleRequest,
) -> Result<ExportProjectResult, String> {
    if request.projects.is_empty() {
        return Err(invalid_data(
            "validate project bundle",
            "project list is empty",
        ));
    }
    if request.projects.len() > MAX_BUNDLE_PROJECTS {
        return Err(invalid_data(
            "validate project bundle",
            format!("bundle has more than {MAX_BUNDLE_PROJECTS} projects"),
        ));
    }

    let mut seen_ids = std::collections::HashSet::new();
    let mut entries = Vec::with_capacity(request.projects.len());
    let mut total_source_bytes = 0u64;
    for project in &request.projects {
        let project_id = safe_archive_component(&project.project_id)?;
        if project.project_name.trim().is_empty() {
            return Err(invalid_data(
                "validate project bundle",
                "project name is required",
            ));
        }
        if !seen_ids.insert(project_id) {
            return Err(invalid_data(
                "validate project bundle",
                format!("duplicate project ID {project_id}"),
            ));
        }
        let archive_path = format!("projects/{project_id}.zip");
        let source_size = fs::metadata(&project.archive_path)
            .map_err(|error| io_failure(&format!("inspect {}", project.archive_path), error))?
            .len();
        if source_size > MAX_BUNDLE_ENTRY_BYTES {
            return Err(invalid_data(
                "validate project bundle",
                format!("{} exceeds the 8 GiB entry limit", project.archive_path),
            ));
        }
        total_source_bytes = total_source_bytes
            .checked_add(source_size)
            .ok_or_else(|| invalid_data("validate project bundle", "bundle total size overflow"))?;
        if total_source_bytes > MAX_BUNDLE_TOTAL_BYTES {
            return Err(invalid_data(
                "validate project bundle",
                "bundle exceeds the 16 GiB total size limit",
            ));
        }
        entries.push(ProjectBundleManifestEntry {
            project_id: project.project_id.clone(),
            project_name: project.project_name.clone(),
            archive_path,
            archive_sha256: sha256_file(project.archive_path.clone())?,
        });
    }

    let manifest = serde_json::to_vec_pretty(&ProjectBundleManifest {
        app: "SiteMark".to_string(),
        kind: PROJECT_BUNDLE_KIND.to_string(),
        schema_version: PROJECT_BUNDLE_SCHEMA_VERSION,
        created_at: unix_time_millis(),
        projects: entries.clone(),
    })
    .map_err(|error| invalid_data("serialize bundle manifest", error))?;
    if manifest.len() as u64 > MAX_MANIFEST_BYTES {
        return Err(invalid_data(
            "serialize bundle manifest",
            "manifest exceeds the 4 MiB size limit",
        ));
    }

    let output = Path::new(&request.output_zip_path);
    if let Some(parent) = output.parent() {
        fs::create_dir_all(parent).map_err(|error| io_failure("create bundle directory", error))?;
    }
    let file = File::create(output).map_err(|error| io_failure("create bundle ZIP", error))?;
    let mut archive = ZipWriter::new(BufWriter::new(file));
    let manifest_options =
        SimpleFileOptions::default().compression_method(CompressionMethod::Deflated);
    let project_options =
        SimpleFileOptions::default().compression_method(CompressionMethod::Stored);
    archive
        .start_file("bundle.json", manifest_options)
        .map_err(|error| zip_failure("start bundle manifest", error))?;
    archive
        .write_all(&manifest)
        .map_err(|error| io_failure("write bundle manifest", error))?;
    for (project, entry) in request.projects.iter().zip(entries.iter()) {
        add_file_to_zip(
            &mut archive,
            &project.archive_path,
            &entry.archive_path,
            project_options,
        )?;
    }
    archive
        .finish()
        .map_err(|error| zip_failure("finish bundle ZIP", error))?;

    Ok(ExportProjectResult {
        output_zip_path: request.output_zip_path.clone(),
        archive_sha256: sha256_file(request.output_zip_path)?,
        photo_count: entries.len() as u32,
    })
}

fn validate_render_request(request: &RenderPhotoRequest) -> Result<(), String> {
    for (label, value) in [
        ("project name", request.project_name.as_str()),
        ("work location", request.work_location.as_str()),
        ("work content", request.work_content.as_str()),
        ("photographer", request.photographer.as_str()),
        ("photo number", request.photo_number.as_str()),
        ("capture time", request.captured_at.as_str()),
    ] {
        if value.trim().is_empty() {
            return Err(invalid_data(
                "validate render request",
                format!("{label} is required"),
            ));
        }
    }
    if !(0.2..=0.95).contains(&request.opacity) {
        return Err(invalid_data(
            "validate render request",
            "watermark opacity must be between 0.2 and 0.95",
        ));
    }
    if !(0.80..=1.60).contains(&request.font_scale) {
        return Err(invalid_data(
            "validate render request",
            "font scale must be between 0.80 and 1.60",
        ));
    }
    if !matches!(request.locale_code.as_str(), "zh" | "en") {
        return Err(invalid_data(
            "validate render request",
            "locale must be zh or en",
        ));
    }
    Ok(())
}

struct WatermarkLabels {
    title: &'static str,
    location: &'static str,
    content: &'static str,
    photographer: &'static str,
    time: &'static str,
    address: &'static str,
    coordinates: &'static str,
    notes: &'static str,
}

fn labels(locale: &str) -> WatermarkLabels {
    if locale == "en" {
        WatermarkLabels {
            title: "Site record",
            location: "Location",
            content: "Work",
            photographer: "Photographer",
            time: "Time",
            address: "Address",
            coordinates: "Coordinates",
            notes: "Notes",
        }
    } else {
        WatermarkLabels {
            title: "现场记录",
            location: "位置",
            content: "内容",
            photographer: "拍摄人",
            time: "时间",
            address: "地址",
            coordinates: "坐标",
            notes: "备注",
        }
    }
}

fn logical_watermark_lines(request: &RenderPhotoRequest) -> Vec<String> {
    let labels = labels(&request.locale_code);
    let mut lines = vec![
        format!("{} · {}", labels.title, request.project_name),
        format!("{}  {}", labels.location, request.work_location),
        format!("{}  {}", labels.content, request.work_content),
        format!("{}  {}", labels.photographer, request.photographer),
        format!("{}  {}", labels.time, request.captured_at),
    ];
    if let Some(address) = non_empty(&request.address) {
        lines.push(format!("{}  {address}", labels.address));
    }
    if let Some(coordinates) = non_empty(&request.coordinates) {
        lines.push(format!("{}  {coordinates}", labels.coordinates));
    }
    if let Some(notes) = non_empty(&request.notes) {
        lines.push(format!("{}  {notes}", labels.notes));
    }
    lines
}

#[derive(Clone, Copy, Debug)]
pub struct WatermarkLayout {
    pub font_size: f32,
    pub title_size: f32,
    pub line_height: u32,
    pub padding: u32,
    pub margin: u32,
    pub card_width: u32,
    pub card_height: u32,
    pub left: u32,
    pub top: u32,
    pub max_text_width: u32,
}

/// Pure measured layout calculation for the engineering watermark card.
///
/// The card width is derived from the measured width of the wrapped display
/// lines (plus padding and the accent strip), capped at 92% of the source
/// width. `left`/`top` anchor the card for the request's position.
fn layout_for_request(
    width: u32,
    height: u32,
    request: &RenderPhotoRequest,
    font: &FontArc,
) -> Result<WatermarkLayout, String> {
    let margin = ((width.min(height) as f32) * 0.025).round() as u32;
    let scale = request.font_scale as f32;
    let font_size = (((width as f32) * 0.0312).clamp(31.2, 69.6)) * scale;
    let title_size = font_size * 1.18;
    let line_height = (font_size * 1.42).round() as u32;
    let padding = ((((width as f32) * 0.0216).round()).max(22.0) * scale).round() as u32;
    let max_card_width = ((width as f32) * 0.92).round() as u32;
    let max_text_width = max_card_width.saturating_sub(padding * 2);

    let rendered_lines =
        compute_rendered_lines(request, font, max_text_width, title_size, font_size);

    let mut measured_text_width = 1u32;
    for (index, line) in rendered_lines.iter().enumerate() {
        let size = if index == 0 { title_size } else { font_size };
        let (line_width, _) = text_size(PxScale::from(size), font, line);
        measured_text_width = measured_text_width.max(line_width);
    }
    let accent_width = (font_size * 0.24).round() as u32;
    let card_width = (measured_text_width + padding * 2 + accent_width).min(max_card_width);
    let card_height = padding * 2 + line_height * rendered_lines.len() as u32;

    if width < margin || height < margin {
        return Err(invalid_data(
            "layout watermark",
            "source image is too small for the watermark card",
        ));
    }
    if card_width + margin > width || card_height + margin > height {
        return Err(invalid_data(
            "layout watermark",
            "source image is too small for the watermark card",
        ));
    }
    let left = match request.position {
        WatermarkPosition::BottomLeft => margin,
        WatermarkPosition::BottomRight => width - margin - card_width,
    };
    let top = height - margin - card_height;
    Ok(WatermarkLayout {
        font_size,
        title_size,
        line_height,
        padding,
        margin,
        card_width,
        card_height,
        left,
        top,
        max_text_width,
    })
}

fn compute_rendered_lines(
    request: &RenderPhotoRequest,
    font: &FontArc,
    max_text_width: u32,
    title_size: f32,
    font_size: f32,
) -> Vec<String> {
    let logical_lines = logical_watermark_lines(request);
    let mut rendered: Vec<String> = Vec::new();
    for (index, line) in logical_lines.iter().enumerate() {
        let size = if index == 0 { title_size } else { font_size };
        rendered.extend(wrap_text(line, max_text_width, size, font));
    }
    rendered
}

/// Tokenize text for wrapping: ASCII words stay together as one token, each
/// non-ASCII character is its own token, and each whitespace character is its
/// own token so wrapped lines can drop leading spaces.
fn tokenize(text: &str) -> Vec<String> {
    let mut tokens = Vec::new();
    let mut word = String::new();
    for ch in text.chars() {
        if ch.is_ascii_whitespace() {
            if !word.is_empty() {
                tokens.push(std::mem::take(&mut word));
            }
            tokens.push(ch.to_string());
        } else if ch.is_ascii() {
            word.push(ch);
        } else {
            if !word.is_empty() {
                tokens.push(std::mem::take(&mut word));
            }
            tokens.push(ch.to_string());
        }
    }
    if !word.is_empty() {
        tokens.push(word);
    }
    tokens
}

/// Wrap text to fit within `max_width` using greedy line filling. Tokens that
/// exceed the available width on their own are split by character so every
/// emitted line fits within `max_width`.
fn wrap_text(text: &str, max_width: u32, size: f32, font: &FontArc) -> Vec<String> {
    let scale = PxScale::from(size);
    let (full_width, _) = text_size(scale, font, text);
    if full_width <= max_width || max_width == 0 {
        return vec![text.to_string()];
    }
    let tokens = tokenize(text);
    let mut lines: Vec<String> = Vec::new();
    let mut current = String::new();

    for token in tokens {
        let is_space = token.chars().all(|c| c.is_ascii_whitespace());
        if current.is_empty() && is_space {
            continue;
        }
        let candidate = format!("{current}{token}");
        let (cw, _) = text_size(scale, font, &candidate);
        if cw <= max_width {
            current = candidate;
            continue;
        }
        if !current.is_empty() {
            let trimmed = current.trim_end().to_string();
            if !trimmed.is_empty() {
                lines.push(trimmed);
            }
            current.clear();
        }
        if is_space {
            continue;
        }
        let (tw, _) = text_size(scale, font, &token);
        if tw <= max_width {
            current = token;
            continue;
        }
        let mut piece = String::new();
        for ch in token.chars() {
            let attempt = format!("{piece}{ch}");
            let (pw, _) = text_size(scale, font, &attempt);
            if pw <= max_width {
                piece = attempt;
                continue;
            }
            if !piece.is_empty() {
                lines.push(std::mem::take(&mut piece));
            }
            piece = ch.to_string();
        }
        if !piece.is_empty() {
            current = piece;
        }
    }
    let trimmed = current.trim_end().to_string();
    if !trimmed.is_empty() {
        lines.push(trimmed);
    }
    if lines.is_empty() {
        lines.push(text.to_string());
    }
    lines
}

fn draw_watermark_card(canvas: &mut RgbaImage, request: &RenderPhotoRequest) -> Result<(), String> {
    let (width, height) = canvas.dimensions();
    let font = FontArc::try_from_slice(FONT_BYTES)
        .map_err(|error| invalid_data("load bundled font", error))?;
    let layout = layout_for_request(width, height, request, &font)?;
    let WatermarkLayout {
        font_size,
        title_size,
        line_height,
        padding,
        margin: _,
        card_width,
        card_height,
        left,
        top,
        max_text_width,
    } = layout;

    blend_rect(
        canvas,
        left,
        top,
        card_width,
        card_height,
        Rgba([8, 20, 18, (request.opacity * 255.0).round() as u8]),
    );
    let accent = argb_to_rgba(request.accent_color_argb);
    draw_filled_rect_mut(
        canvas,
        Rect::at(left as i32, top as i32).of_size((font_size * 0.24) as u32, card_height),
        accent,
    );

    let rendered_lines =
        compute_rendered_lines(request, &font, max_text_width, title_size, font_size);
    let text_left = (left + padding) as i32;
    let mut text_top = (top + padding) as i32;
    for (index, line) in rendered_lines.iter().enumerate() {
        let size = if index == 0 { title_size } else { font_size };
        let color = if index == 0 {
            Rgba([255, 255, 255, 255])
        } else {
            Rgba([238, 244, 242, 255])
        };
        draw_text_mut(
            canvas,
            color,
            text_left,
            text_top,
            PxScale::from(size),
            &font,
            line,
        );
        text_top += line_height as i32;
    }
    Ok(())
}

fn blend_rect(
    canvas: &mut RgbaImage,
    left: u32,
    top: u32,
    width: u32,
    height: u32,
    overlay: Rgba<u8>,
) {
    for y in top..top + height {
        for x in left..left + width {
            canvas.get_pixel_mut(x, y).blend(&overlay);
        }
    }
}

fn argb_to_rgba(argb: u32) -> Rgba<u8> {
    Rgba([
        ((argb >> 16) & 0xff) as u8,
        ((argb >> 8) & 0xff) as u8,
        (argb & 0xff) as u8,
        ((argb >> 24) & 0xff) as u8,
    ])
}

fn non_empty(value: &Option<String>) -> Option<&str> {
    value
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
}

/// Strict validation for app-generated identifiers (project IDs, UUIDs).
/// Only ASCII alphanumeric, hyphen, and underscore are permitted.
fn safe_archive_component(value: &str) -> Result<&str, String> {
    if value.is_empty()
        || !value
            .chars()
            .all(|character| character.is_ascii_alphanumeric() || matches!(character, '-' | '_'))
    {
        return Err(invalid_data(
            "validate archive file name",
            format!("unsafe archive file name: {value}"),
        ));
    }
    Ok(value)
}

/// Blacklist validation for user-content-derived photo numbers.
/// Accepts any character except: control chars (Cc incl. C1), Unicode
/// whitespace, ZWNBSP/BOM (U+FEFF), and the path/shell metacharacters
/// `/ \ : * ? " < > |`. This mirrors the Dart `safePhotoProjectName`
/// forbidden set so names produced by Dart are always accepted.
fn safe_photo_number_component(value: &str) -> Result<&str, String> {
    if value.is_empty()
        || value.chars().any(|character| {
            character.is_control()
                || character.is_whitespace()
                || character == '\u{FEFF}'
                || matches!(
                    character,
                    '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|'
                )
        })
    {
        return Err(invalid_data(
            "validate photo number",
            format!("unsafe photo number: {value}"),
        ));
    }
    Ok(value)
}

fn add_file_to_zip(
    archive: &mut ZipWriter<BufWriter<File>>,
    source: &str,
    destination: &str,
    options: SimpleFileOptions,
) -> Result<(), String> {
    let source_path = PathBuf::from(source);
    let mut file = File::open(&source_path)
        .map_err(|error| io_failure(&format!("open {}", source_path.display()), error))?;
    archive
        .start_file(destination, options)
        .map_err(|error| zip_failure(&format!("start ZIP entry {destination}"), error))?;
    std::io::copy(&mut file, archive)
        .map_err(|error| io_failure(&format!("copy ZIP entry {destination}"), error))?;
    Ok(())
}

#[cfg(test)]
mod watermark_tests {
    use super::*;

    #[test]
    fn english_labels_contain_no_fixed_chinese_labels() {
        let request = sample_request("en", 1.0, "East Plant");
        let lines = logical_watermark_lines(&request);
        let joined = lines.join("\n");
        assert!(joined.contains("Site record"));
        assert!(joined.contains("Location"));
        assert!(!joined.contains("现场记录"));
        assert!(!joined.contains("位置"));
    }

    #[test]
    fn short_content_produces_a_narrower_card_than_long_content() {
        let font = FontArc::try_from_slice(FONT_BYTES).unwrap();
        let short =
            layout_for_request(4000, 3000, &sample_request("zh", 1.0, "甲"), &font).unwrap();
        let long = layout_for_request(
            4000,
            3000,
            &sample_request("zh", 1.0, "东区厂房通风空调系统综合改造工程"),
            &font,
        )
        .unwrap();
        assert!(short.card_width < long.card_width);
        assert!(long.card_width <= (4000.0 * 0.92) as u32);
    }

    #[test]
    fn font_scale_bounds_are_enforced() {
        assert!(validate_render_request(&sample_request("zh", 0.79, "甲")).is_err());
        assert!(validate_render_request(&sample_request("zh", 1.61, "甲")).is_err());
        assert!(validate_render_request(&sample_request("en", 1.60, "A")).is_ok());
    }

    #[test]
    fn watermark_typography_scales_with_font_scale() {
        let font = FontArc::try_from_slice(FONT_BYTES).unwrap();
        let layout = layout_for_request(
            4000,
            3000,
            &sample_request("zh", 1.0, "东区厂房改造"),
            &font,
        )
        .unwrap();
        assert!((layout.font_size - 69.6).abs() < f32::EPSILON);
        assert!((layout.title_size - 82.128).abs() < 0.001);
        assert_eq!(layout.line_height, 99);
        assert!(layout.card_height + layout.margin <= 3000);
    }

    #[test]
    fn measured_layout_fits_supported_landscape_and_portrait_images() {
        let font = FontArc::try_from_slice(FONT_BYTES).unwrap();
        for (width, height) in [(4000, 3000), (3000, 4000), (3840, 2160), (2160, 3840)] {
            let request = sample_request("zh", 1.0, "东区厂房改造");
            let layout = layout_for_request(width, height, &request, &font).unwrap();
            assert!(
                layout.left + layout.card_width <= width,
                "card overflows horizontally at {width}x{height}"
            );
            assert!(
                layout.top + layout.card_height <= height,
                "card overflows vertically at {width}x{height}"
            );
        }
    }

    #[test]
    fn chinese_and_english_watermarks_omit_photo_number() {
        for locale in ["zh", "en"] {
            let request = sample_request(locale, 1.0, "东区厂房改造");
            let lines = logical_watermark_lines(&request);
            let text = lines.join("\n");

            assert!(!text.contains(&request.photo_number), "{locale}: {text}");
            assert!(!text.contains("编号"), "{locale}: {text}");
            assert!(!text.contains("Number"), "{locale}: {text}");
            assert_eq!(lines.len(), 5);
        }
    }

    fn sample_request(locale: &str, font_scale: f64, project: &str) -> RenderPhotoRequest {
        RenderPhotoRequest {
            source_path: "source.jpg".to_string(),
            output_path: "output.jpg".to_string(),
            project_name: project.to_string(),
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
            font_scale,
            locale_code: locale.to_string(),
        }
    }
}

#[cfg(test)]
mod archive_tests {
    use super::*;

    // --- project_id: strict whitelist (safe_archive_component) ---

    #[test]
    fn project_id_accepts_ascii_alphanumeric_hyphen_underscore() {
        assert!(safe_archive_component("project-a").is_ok());
        assert!(safe_archive_component("Project_1").is_ok());
        assert!(safe_archive_component("a1b2c3").is_ok());
    }

    #[test]
    fn project_id_rejects_path_navigation_and_punctuation() {
        assert!(safe_archive_component(".").is_err());
        assert!(safe_archive_component("..").is_err());
        assert!(safe_archive_component("project/1").is_err());
        assert!(safe_archive_component("project.1").is_err());
        assert!(safe_archive_component("project(1)").is_err());
        assert!(safe_archive_component("").is_err());
    }

    #[test]
    fn project_id_rejects_unicode_letters() {
        // is_alphanumeric accepts Unicode; contract requires ASCII only.
        assert!(safe_archive_component("项目一").is_err());
        assert!(safe_archive_component("１２３").is_err());
    }

    // --- photo_number: Dart-aligned blacklist (safe_photo_number_component) ---

    #[test]
    fn photo_number_accepts_punctuation_preserved_by_dart() {
        assert!(safe_photo_number_component("东区厂房改造-SM-20260717-001").is_ok());
        assert!(safe_photo_number_component("东区厂房改造（一期）-SM-20260717-001").is_ok());
        assert!(safe_photo_number_component("A.B-SM-20260717-001").is_ok());
        assert!(safe_photo_number_component("--A-SM-20260717-001").is_ok());
        assert!(safe_photo_number_component("C&D-SM-20260717-001").is_ok());
        assert!(safe_photo_number_component("Project-SM-20260717-001").is_ok());
    }

    #[test]
    fn photo_number_rejects_path_separators_and_shell_metacharacters() {
        assert!(safe_photo_number_component("project/SM-001").is_err());
        assert!(safe_photo_number_component("project\\SM-001").is_err());
        assert!(safe_photo_number_component("project:SM-001").is_err());
        assert!(safe_photo_number_component("project*SM-001").is_err());
        assert!(safe_photo_number_component("project?SM-001").is_err());
        assert!(safe_photo_number_component("project<SM-001").is_err());
        assert!(safe_photo_number_component("project>SM-001").is_err());
        assert!(safe_photo_number_component("project|SM-001").is_err());
        assert!(safe_photo_number_component("").is_err());
    }

    #[test]
    fn photo_number_rejects_unicode_whitespace_and_control_chars() {
        // C1 control (U+0080)
        assert!(safe_photo_number_component("A\u{0080}B").is_err());
        // NBSP (U+00A0)
        assert!(safe_photo_number_component("A\u{00A0}B").is_err());
        // EM SPACE (U+2003)
        assert!(safe_photo_number_component("A\u{2003}B").is_err());
        // LINE SEPARATOR (U+2028)
        assert!(safe_photo_number_component("A\u{2028}B").is_err());
        // ZWNBSP / BOM (U+FEFF)
        assert!(safe_photo_number_component("A\u{FEFF}B").is_err());
    }

    #[test]
    fn dart_trim_and_regexp_whitespace_sets_are_distinct_and_explicit() {
        for (character, dart_trim, dart_regexp) in [
            ('\u{0009}', true, true),
            ('\u{000A}', true, true),
            ('\u{000B}', true, true),
            ('\u{000C}', true, true),
            ('\u{000D}', true, true),
            ('\u{001C}', false, false),
            ('\u{0020}', true, true),
            ('\u{0085}', true, false),
            ('\u{00A0}', true, true),
            ('\u{1680}', true, true),
            ('\u{180E}', false, false),
            ('\u{2000}', true, true),
            ('\u{200A}', true, true),
            ('\u{200B}', false, false),
            ('\u{2028}', true, true),
            ('\u{2029}', true, true),
            ('\u{202F}', true, true),
            ('\u{205F}', true, true),
            ('\u{3000}', true, true),
            ('\u{FEFF}', true, true),
        ] {
            assert_eq!(
                is_dart_trim_whitespace(character),
                dart_trim,
                "unexpected Dart trim classification for U+{:04X}",
                character as u32
            );
            assert_eq!(
                is_dart_regexp_whitespace(character),
                dart_regexp,
                "unexpected Dart RegExp whitespace classification for U+{:04X}",
                character as u32
            );
        }
    }

    #[test]
    fn template_name_normalization_matches_dart_two_stage_whitespace_behavior() {
        for (input, normalized, key) in [
            ("\u{0085}A\u{0085}B\u{0085}", "A\u{0085}B", "a\u{0085}b"),
            ("\u{FEFF}A\u{FEFF}B\u{FEFF}", "A B", "a b"),
            (
                "\u{200B}A\u{200B}B\u{200B}",
                "\u{200B}A\u{200B}B\u{200B}",
                "\u{200B}a\u{200B}b\u{200B}",
            ),
            (
                " \t\r\n\u{000C}A \t\r\n\u{000C}B \t\r\n\u{000C}",
                "A B",
                "a b",
            ),
            (
                "\u{00A0}A\u{1680}\u{2028}\u{202F}\u{205F}\u{3000}B\u{00A0}",
                "A B",
                "a b",
            ),
        ] {
            assert_eq!(normalized_template_name(input), normalized);
            assert_eq!(template_name_key(input), key);
        }
    }
}

#[cfg(test)]
mod bundle_extraction_tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn bundle_commit_refuses_a_destination_created_after_copy() {
        let directory = tempdir().unwrap();
        let project_archive = directory.path().join("project-1.zip");
        fs::write(&project_archive, b"project archive").unwrap();
        let bundle = directory.path().join("bundle.zip");
        export_project_bundle(ExportProjectBundleRequest {
            output_zip_path: bundle.to_string_lossy().into_owned(),
            projects: vec![ProjectBundleSource {
                project_id: "project-1".to_string(),
                project_name: "东区".to_string(),
                archive_path: project_archive.to_string_lossy().into_owned(),
            }],
        })
        .unwrap();
        let destination = directory.path().join("staging/project-1.zip");
        let request = ExtractProjectBundleEntryRequest {
            zip_path: bundle.to_string_lossy().into_owned(),
            archive_path: "projects/project-1.zip".to_string(),
            output_path: destination.to_string_lossy().into_owned(),
        };

        let error = extract_project_bundle_entry_with_before_commit(request, |output| {
            fs::write(output, b"written-by-a-competing-operation")
                .map_err(|source| io_failure("create competing destination", source))
        })
        .unwrap_err();

        assert!(error.contains("already exists"), "{error}");
        assert_eq!(
            fs::read(&destination).unwrap(),
            b"written-by-a-competing-operation"
        );
        assert!(!destination.with_file_name("project-1.zip.tmp").exists());
    }
}

// ---------------------------------------------------------------------------
// Backup restore (import)
// ---------------------------------------------------------------------------

/// One restorable photo entry from a project backup manifest.
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct ArchivePhotoPreview {
    pub photo_number: String,
    pub has_original: bool,
    pub original_sha256: String,
    pub captured_at: String,
    pub work_location: String,
    pub work_content: String,
    pub photographer: String,
    pub address: Option<String>,
    pub notes: Option<String>,
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
    pub accuracy_meters: Option<f64>,
    pub watermark_locale_code: Option<String>,
}

/// Watermark template recovered from a v2 manifest.
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct ArchiveWatermarkSettings {
    pub position: String,
    pub opacity: f64,
    pub accent_color_argb: u32,
    pub font_scale: f64,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct ArchiveCaptureTemplate {
    pub name: String,
    pub work_location: String,
    pub work_content: String,
    pub photographer: String,
    pub created_at: String,
    pub updated_at: String,
}

/// Validated content of a restorable single-project backup ZIP.
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct ProjectArchivePreview {
    pub schema_version: u32,
    pub project_name: String,
    pub project_description: Option<String>,
    pub project_created_at: Option<String>,
    pub snapshot_at: Option<String>,
    pub omitted_processing_count: u32,
    pub omitted_failed_count: u32,
    pub is_partial: bool,
    pub includes_originals: bool,
    /// Normalized lifecycle status: always one of `active`, `completed`, `archived`.
    /// Schema 1..=4 archives are normalized to `active`.
    pub project_lifecycle_status: String,
    /// Normalized pin flag. Schema 1..=4 archives are normalized to `false`.
    pub project_is_pinned: bool,
    pub watermark: Option<ArchiveWatermarkSettings>,
    pub photos: Vec<ArchivePhotoPreview>,
    pub templates: Vec<ArchiveCaptureTemplate>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct ExtractArchivePhotoRequest {
    pub zip_path: String,
    pub photo_number: String,
    pub rendered_destination: String,
    pub original_destination: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct ExtractedArchivePhoto {
    pub rendered_path: String,
    pub original_path: Option<String>,
}

#[derive(Deserialize)]
struct ManifestWatermark {
    position: String,
    opacity: f64,
    accent_color_argb: u32,
    font_scale: f64,
}

/// Tolerant view of one manifest photo entry. v1 fields that the restore
/// flow does not need (`watermarked_path`, `original_path`, `coordinates`)
/// are ignored; v2 restore fields default to `None` for v1 archives.
#[derive(Deserialize)]
struct ManifestPhoto {
    photo_number: String,
    original_sha256: String,
    captured_at: String,
    work_location: String,
    work_content: String,
    photographer: String,
    #[serde(default)]
    address: Option<String>,
    #[serde(default)]
    notes: Option<String>,
    #[serde(default)]
    latitude: Option<f64>,
    #[serde(default)]
    longitude: Option<f64>,
    #[serde(default)]
    accuracy_meters: Option<f64>,
    #[serde(default)]
    watermark_locale_code: Option<String>,
}

#[derive(Deserialize)]
struct ManifestCaptureTemplate {
    name: String,
    work_location: String,
    work_content: String,
    photographer: String,
    created_at: String,
    updated_at: String,
}

#[derive(Deserialize)]
struct ProjectManifestFile {
    schema_version: u32,
    app: String,
    project_name: String,
    #[serde(default)]
    project_description: Option<String>,
    #[serde(default)]
    project_created_at: Option<String>,
    #[serde(default)]
    snapshot_at: Option<String>,
    #[serde(default)]
    omitted_processing_count: u32,
    #[serde(default)]
    omitted_failed_count: u32,
    includes_originals: bool,
    #[serde(default)]
    project_lifecycle_status: Option<String>,
    #[serde(default)]
    project_is_pinned: Option<bool>,
    #[serde(default)]
    watermark: Option<ManifestWatermark>,
    photos: Vec<ManifestPhoto>,
    #[serde(default)]
    templates: Vec<ManifestCaptureTemplate>,
}

fn is_valid_lifecycle_status(value: &str) -> bool {
    matches!(value, "active" | "completed" | "archived")
}

/// Normalizes lifecycle fields according to schema version:
/// - schema 5 requires both fields, status must be active/completed/archived
/// - schema 1..=4 always normalize to active / unpinned
fn normalize_lifecycle_fields(
    schema_version: u32,
    project_lifecycle_status: Option<String>,
    project_is_pinned: Option<bool>,
) -> Result<(String, bool), String> {
    if schema_version >= 5 {
        let status = project_lifecycle_status.ok_or_else(|| {
            invalid_data(
                "validate manifest",
                "schema 5 requires project_lifecycle_status",
            )
        })?;
        if !is_valid_lifecycle_status(&status) {
            return Err(invalid_data(
                "validate manifest",
                format!("unsupported project lifecycle status {status}"),
            ));
        }
        let is_pinned = project_is_pinned.ok_or_else(|| {
            invalid_data("validate manifest", "schema 5 requires project_is_pinned")
        })?;
        Ok((status, is_pinned))
    } else {
        Ok(("active".to_string(), false))
    }
}

#[derive(Clone, Debug, Deserialize, Serialize)]
struct ProjectBundleManifestEntry {
    project_id: String,
    project_name: String,
    archive_path: String,
    archive_sha256: String,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
struct ProjectBundleManifest {
    app: String,
    kind: String,
    schema_version: u32,
    created_at: String,
    projects: Vec<ProjectBundleManifestEntry>,
}

/// Backup-restore extraction limits. Generous enough for real camera
/// originals (a phone JPEG rarely exceeds 30 MiB) while still stopping a
/// decompression bomb long before it can fill the device storage.
const MAX_MANIFEST_BYTES: u64 = 4 * 1024 * 1024;
const MAX_ARCHIVE_PHOTOS: usize = 2000;
const MAX_ENTRY_UNCOMPRESSED_BYTES: u64 = 128 * 1024 * 1024;
const MAX_TOTAL_UNCOMPRESSED_BYTES: u64 = 8 * 1024 * 1024 * 1024;
const MAX_CAPTURE_TEMPLATES_PER_PROJECT: usize = 100;
const MAX_TEMPLATE_NAME_CHARS: usize = 80;
const MAX_WORK_LOCATION_CHARS: usize = 160;
const MAX_WORK_CONTENT_CHARS: usize = 240;
const MAX_PHOTOGRAPHER_CHARS: usize = 80;

fn open_zip(zip_path: &str) -> Result<zip::ZipArchive<BufReader<File>>, String> {
    let file =
        File::open(zip_path).map_err(|error| io_failure(&format!("open {zip_path}"), error))?;
    zip::ZipArchive::new(BufReader::new(file)).map_err(|error| zip_failure("open archive", error))
}

fn unix_time_millis() -> String {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
        .to_string()
}

fn is_valid_sha256(value: &str) -> bool {
    value.len() == 64 && value.chars().all(|character| character.is_ascii_hexdigit())
}

/// The explicit set recognized by the repository's current Dart SDK
/// `String.trim()`. It intentionally includes U+0085.
fn is_dart_trim_whitespace(character: char) -> bool {
    matches!(
        character,
        '\u{0009}'..='\u{000D}'
            | '\u{0020}'
            | '\u{0085}'
            | '\u{00A0}'
            | '\u{1680}'
            | '\u{2000}'..='\u{200A}'
            | '\u{2028}'
            | '\u{2029}'
            | '\u{202F}'
            | '\u{205F}'
            | '\u{3000}'
            | '\u{FEFF}'
    )
}

/// The explicit set recognized by the repository's current Dart SDK
/// ECMAScript `RegExp(r'\s')`. Unlike `trim`, it excludes U+0085.
fn is_dart_regexp_whitespace(character: char) -> bool {
    matches!(
        character,
        '\u{0009}'..='\u{000D}'
            | '\u{0020}'
            | '\u{00A0}'
            | '\u{1680}'
            | '\u{2000}'..='\u{200A}'
            | '\u{2028}'
            | '\u{2029}'
            | '\u{202F}'
            | '\u{205F}'
            | '\u{3000}'
            | '\u{FEFF}'
    )
}

fn normalized_template_name(value: &str) -> String {
    let value = value.trim_matches(is_dart_trim_whitespace);
    let mut normalized = String::new();
    let mut in_whitespace = false;
    for character in value.chars() {
        if is_dart_regexp_whitespace(character) {
            if !in_whitespace && !normalized.is_empty() {
                normalized.push(' ');
            }
            in_whitespace = true;
        } else {
            normalized.push(character);
            in_whitespace = false;
        }
    }
    normalized
}

fn template_name_key(value: &str) -> String {
    normalized_template_name(value)
        .chars()
        .map(|character| {
            if character.is_ascii_uppercase() {
                character.to_ascii_lowercase()
            } else {
                character
            }
        })
        .collect()
}

fn trimmed_template_field(value: &str) -> &str {
    value.trim_matches(is_dart_trim_whitespace)
}

fn parse_two_digits(bytes: &[u8], start: usize) -> Option<u32> {
    let tens = bytes.get(start)?.checked_sub(b'0')?;
    let ones = bytes.get(start + 1)?.checked_sub(b'0')?;
    if tens > 9 || ones > 9 {
        return None;
    }
    Some(u32::from(tens) * 10 + u32::from(ones))
}

fn is_leap_year(year: u32) -> bool {
    year.is_multiple_of(4) && (!year.is_multiple_of(100) || year.is_multiple_of(400))
}

/// Matches the existing Dart archive timestamp parser's exported shape:
/// `yyyy-MM-dd HH:mm:ss +/-HH:MM`.
fn is_valid_exported_timestamp(value: &str) -> bool {
    let value = trimmed_template_field(value);
    let bytes = value.as_bytes();
    if bytes.len() != 26
        || bytes[4] != b'-'
        || bytes[7] != b'-'
        || bytes[10] != b' '
        || bytes[13] != b':'
        || bytes[16] != b':'
        || bytes[19] != b' '
        || !matches!(bytes[20], b'+' | b'-')
        || bytes[23] != b':'
    {
        return false;
    }
    let Some(year) = value[..4].parse::<u32>().ok() else {
        return false;
    };
    let Some(month) = parse_two_digits(bytes, 5) else {
        return false;
    };
    let Some(day) = parse_two_digits(bytes, 8) else {
        return false;
    };
    let Some(hour) = parse_two_digits(bytes, 11) else {
        return false;
    };
    let Some(minute) = parse_two_digits(bytes, 14) else {
        return false;
    };
    let Some(second) = parse_two_digits(bytes, 17) else {
        return false;
    };
    let Some(offset_hour) = parse_two_digits(bytes, 21) else {
        return false;
    };
    let Some(offset_minute) = parse_two_digits(bytes, 24) else {
        return false;
    };
    let days_in_month = match month {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 if is_leap_year(year) => 29,
        2 => 28,
        _ => return false,
    };
    (1..=days_in_month).contains(&day)
        && hour <= 23
        && minute <= 59
        && second <= 59
        && offset_hour <= 23
        && offset_minute <= 59
}

fn validate_archive_templates(templates: &[ManifestCaptureTemplate]) -> Result<(), String> {
    if templates.len() > MAX_CAPTURE_TEMPLATES_PER_PROJECT {
        return Err(invalid_data(
            "validate manifest",
            format!(
                "archive holds more than {MAX_CAPTURE_TEMPLATES_PER_PROJECT} capture templates"
            ),
        ));
    }
    let mut name_keys = std::collections::HashSet::new();
    for template in templates {
        for (label, value) in [
            ("template name", template.name.as_str()),
            ("template work location", template.work_location.as_str()),
            ("template work content", template.work_content.as_str()),
            ("template photographer", template.photographer.as_str()),
        ] {
            if value.contains('\0') {
                return Err(invalid_data(
                    "validate manifest",
                    format!("{label} contains U+0000"),
                ));
            }
        }

        let normalized_name = normalized_template_name(&template.name);
        if normalized_name.is_empty() {
            return Err(invalid_data("validate manifest", "template name is empty"));
        }
        if normalized_name.chars().count() > MAX_TEMPLATE_NAME_CHARS {
            return Err(invalid_data(
                "validate manifest",
                format!("template name exceeds {MAX_TEMPLATE_NAME_CHARS} characters"),
            ));
        }
        for (label, value, maximum) in [
            (
                "template work location",
                template.work_location.as_str(),
                MAX_WORK_LOCATION_CHARS,
            ),
            (
                "template work content",
                template.work_content.as_str(),
                MAX_WORK_CONTENT_CHARS,
            ),
            (
                "template photographer",
                template.photographer.as_str(),
                MAX_PHOTOGRAPHER_CHARS,
            ),
        ] {
            let value = trimmed_template_field(value);
            if value.is_empty() {
                return Err(invalid_data(
                    "validate manifest",
                    format!("{label} is empty"),
                ));
            }
            if value.chars().count() > maximum {
                return Err(invalid_data(
                    "validate manifest",
                    format!("{label} exceeds {maximum} characters"),
                ));
            }
        }

        let name_key = template_name_key(&template.name);
        if !name_keys.insert(name_key) {
            return Err(invalid_data(
                "validate manifest",
                format!("duplicate capture template name {normalized_name}"),
            ));
        }
        for (label, value) in [
            ("template created_at", template.created_at.as_str()),
            ("template updated_at", template.updated_at.as_str()),
        ] {
            if !is_valid_exported_timestamp(value) {
                return Err(invalid_data(
                    "validate manifest",
                    format!("invalid {label}"),
                ));
            }
        }
    }
    Ok(())
}

fn expected_bundle_archive_path(project_id: &str) -> Result<String, String> {
    Ok(format!(
        "projects/{}.zip",
        safe_archive_component(project_id)?
    ))
}

fn read_project_bundle_manifest(zip_path: &str) -> Result<(ProjectBundleManifest, u64), String> {
    let mut archive = open_zip(zip_path)?;
    let mut entry = archive
        .by_name("bundle.json")
        .map_err(|_| invalid_data("read bundle manifest", "archive has no bundle.json"))?;
    if entry.size() > MAX_MANIFEST_BYTES {
        return Err(invalid_data(
            "read bundle manifest",
            "manifest exceeds the 4 MiB size limit",
        ));
    }
    let mut text = String::new();
    entry
        .by_ref()
        .take(MAX_MANIFEST_BYTES + 1)
        .read_to_string(&mut text)
        .map_err(|error| io_failure("read bundle manifest", error))?;
    if text.len() as u64 > MAX_MANIFEST_BYTES {
        return Err(invalid_data(
            "read bundle manifest",
            "manifest exceeds the 4 MiB size limit",
        ));
    }
    let manifest: ProjectBundleManifest = serde_json::from_str(&text)
        .map_err(|error| invalid_data("parse bundle manifest", error))?;
    if manifest.app != "SiteMark" || manifest.kind != PROJECT_BUNDLE_KIND {
        return Err(invalid_data(
            "validate bundle manifest",
            "not a SiteMark project bundle",
        ));
    }
    if manifest.schema_version != PROJECT_BUNDLE_SCHEMA_VERSION {
        return Err(invalid_data(
            "validate bundle manifest",
            format!("unsupported schema version {}", manifest.schema_version),
        ));
    }
    if manifest.created_at.trim().is_empty() {
        return Err(invalid_data(
            "validate bundle manifest",
            "created_at is empty",
        ));
    }
    if manifest.projects.is_empty() {
        return Err(invalid_data(
            "validate bundle manifest",
            "project list is empty",
        ));
    }
    if manifest.projects.len() > MAX_BUNDLE_PROJECTS {
        return Err(invalid_data(
            "validate bundle manifest",
            format!("bundle has more than {MAX_BUNDLE_PROJECTS} projects"),
        ));
    }

    let mut project_ids = std::collections::HashSet::new();
    let mut archive_paths = std::collections::HashSet::new();
    for project in &manifest.projects {
        let expected_path = expected_bundle_archive_path(&project.project_id)?;
        if project.project_name.trim().is_empty() {
            return Err(invalid_data(
                "validate bundle manifest",
                "project name is empty",
            ));
        }
        if project.archive_path != expected_path {
            return Err(invalid_data(
                "validate bundle manifest",
                format!("unsafe archive path {}", project.archive_path),
            ));
        }
        if !project_ids.insert(project.project_id.as_str()) {
            return Err(invalid_data(
                "validate bundle manifest",
                format!("duplicate project ID {}", project.project_id),
            ));
        }
        if !archive_paths.insert(project.archive_path.as_str()) {
            return Err(invalid_data(
                "validate bundle manifest",
                format!("duplicate archive path {}", project.archive_path),
            ));
        }
        if !is_valid_sha256(&project.archive_sha256) {
            return Err(invalid_data(
                "validate bundle manifest",
                format!("invalid SHA-256 digest for {}", project.project_id),
            ));
        }
    }
    Ok((manifest, text.len() as u64))
}

fn hash_bundle_entry(
    archive: &mut zip::ZipArchive<BufReader<File>>,
    archive_path: &str,
    total_remaining: u64,
) -> Result<(String, u64), String> {
    let mut entry = archive
        .by_name(archive_path)
        .map_err(|error| zip_failure(&format!("open bundle entry {archive_path}"), error))?;
    if entry.size() > MAX_BUNDLE_ENTRY_BYTES {
        return Err(invalid_data(
            "validate bundle",
            format!("entry {archive_path} exceeds the 8 GiB size limit"),
        ));
    }
    let cap = MAX_BUNDLE_ENTRY_BYTES.min(total_remaining);
    let mut limited = entry.by_ref().take(cap.saturating_add(1));
    let mut hasher = Sha256::new();
    let mut bytes_read = 0u64;
    let mut buffer = [0u8; 64 * 1024];
    loop {
        let count = limited
            .read(&mut buffer)
            .map_err(|error| io_failure(&format!("read bundle entry {archive_path}"), error))?;
        if count == 0 {
            break;
        }
        bytes_read += count as u64;
        hasher.update(&buffer[..count]);
    }
    if bytes_read > MAX_BUNDLE_ENTRY_BYTES {
        return Err(invalid_data(
            "validate bundle",
            format!("entry {archive_path} exceeds the 8 GiB size limit"),
        ));
    }
    if bytes_read > total_remaining {
        return Err(invalid_data(
            "validate bundle",
            "bundle exceeds the 16 GiB total size limit",
        ));
    }
    Ok((hex::encode(hasher.finalize()), bytes_read))
}

/// Re-reads every outer entry, validates the fixed entry set and checks each
/// inner project ZIP hash. This is deliberately shared by preview and
/// extraction so extraction cannot trust an earlier, stale preview.
fn validate_project_bundle(zip_path: &str) -> Result<ProjectBundlePreview, String> {
    let (manifest, manifest_bytes) = read_project_bundle_manifest(zip_path)?;
    let expected_entries: std::collections::HashSet<&str> = manifest
        .projects
        .iter()
        .map(|project| project.archive_path.as_str())
        .collect();
    let mut archive = open_zip(zip_path)?;
    let mut seen_entries = std::collections::HashSet::new();
    let mut declared_total = 0u64;
    for index in 0..archive.len() {
        let entry = archive
            .by_index(index)
            .map_err(|error| zip_failure("read bundle entry", error))?;
        let name = entry.name().to_string();
        if name != "bundle.json" && !expected_entries.contains(name.as_str()) {
            return Err(invalid_data(
                "validate bundle",
                format!("unexpected archive entry {name}"),
            ));
        }
        if !seen_entries.insert(name.clone()) {
            return Err(invalid_data(
                "validate bundle",
                format!("duplicate archive entry {name}"),
            ));
        }
        if entry.size() > MAX_BUNDLE_ENTRY_BYTES {
            return Err(invalid_data(
                "validate bundle",
                format!("entry {name} exceeds the 8 GiB size limit"),
            ));
        }
        declared_total = declared_total
            .checked_add(entry.size())
            .ok_or_else(|| invalid_data("validate bundle", "bundle total size overflow"))?;
        if declared_total > MAX_BUNDLE_TOTAL_BYTES {
            return Err(invalid_data(
                "validate bundle",
                "bundle exceeds the 16 GiB total size limit",
            ));
        }
        if name != "bundle.json" && entry.compression() != CompressionMethod::Stored {
            return Err(invalid_data(
                "validate bundle",
                format!("project archive {name} must be stored without recompression"),
            ));
        }
    }
    if seen_entries.len() != expected_entries.len() + 1 || !seen_entries.contains("bundle.json") {
        return Err(invalid_data(
            "validate bundle",
            "bundle entry set does not match its manifest",
        ));
    }
    for path in &expected_entries {
        if !seen_entries.contains(*path) {
            return Err(invalid_data(
                "validate bundle",
                format!("bundle is missing {path}"),
            ));
        }
    }

    let mut actual_total = manifest_bytes;
    let mut projects = Vec::with_capacity(manifest.projects.len());
    for project in manifest.projects {
        let remaining = MAX_BUNDLE_TOTAL_BYTES
            .checked_sub(actual_total)
            .ok_or_else(|| {
                invalid_data(
                    "validate bundle",
                    "bundle exceeds the 16 GiB total size limit",
                )
            })?;
        let (actual_sha256, bytes_read) =
            hash_bundle_entry(&mut archive, &project.archive_path, remaining)?;
        actual_total += bytes_read;
        if !actual_sha256.eq_ignore_ascii_case(&project.archive_sha256) {
            return Err(invalid_data(
                "validate bundle",
                format!("SHA-256 mismatch for {}", project.archive_path),
            ));
        }
        projects.push(ProjectBundleEntryPreview {
            project_id: project.project_id,
            project_name: project.project_name,
            archive_path: project.archive_path,
            archive_sha256: project.archive_sha256,
        });
    }
    Ok(ProjectBundlePreview {
        schema_version: PROJECT_BUNDLE_SCHEMA_VERSION,
        created_at: manifest.created_at,
        projects,
    })
}

/// Reads a multi-project bundle only after validating its manifest, exact
/// outer entry set, size limits, and every inner project ZIP hash.
pub fn read_project_bundle(zip_path: String) -> Result<ProjectBundlePreview, String> {
    validate_project_bundle(&zip_path)
}

fn copy_bundle_entry_to(
    archive: &mut zip::ZipArchive<BufReader<File>>,
    archive_path: &str,
    destination: &mut File,
) -> Result<(), String> {
    let mut entry = archive
        .by_name(archive_path)
        .map_err(|error| zip_failure(&format!("open bundle entry {archive_path}"), error))?;
    if entry.size() > MAX_BUNDLE_ENTRY_BYTES {
        return Err(invalid_data(
            "extract bundle entry",
            format!("entry {archive_path} exceeds the 8 GiB size limit"),
        ));
    }
    let mut limited = entry.by_ref().take(MAX_BUNDLE_ENTRY_BYTES + 1);
    let copied = std::io::copy(&mut limited, destination)
        .map_err(|error| io_failure("copy extracted project archive", error))?;
    if copied > MAX_BUNDLE_ENTRY_BYTES {
        return Err(invalid_data(
            "extract bundle entry",
            format!("entry {archive_path} exceeds the 8 GiB extraction limit"),
        ));
    }
    Ok(())
}

/// Atomically publishes an owned temporary file without replacing a file that
/// appeared after the caller's initial destination check. A hard link is a
/// no-replace create operation on the same filesystem; the temporary name is
/// then removed to leave the expected single destination path.
fn commit_bundle_temporary_no_replace(temporary: &Path, output: &Path) -> Result<(), String> {
    fs::hard_link(temporary, output).map_err(|error| {
        if error.kind() == std::io::ErrorKind::AlreadyExists {
            invalid_data(
                "extract bundle entry",
                "destination already exists at commit time",
            )
        } else {
            io_failure("finalize extracted project archive", error)
        }
    })?;
    fs::remove_file(temporary)
        .map_err(|error| io_failure("remove committed bundle temporary", error))?;
    Ok(())
}

/// Extracts one validated inner project ZIP into a caller-selected staging
/// location. The destination must not already exist, and all bytes are first
/// written to `<destination>.tmp`; only a final hash match permits rename.
pub fn extract_project_bundle_entry(
    request: ExtractProjectBundleEntryRequest,
) -> Result<(), String> {
    extract_project_bundle_entry_with_before_commit(request, |_| Ok(()))
}

/// Private test seam: the public extraction path always uses a no-op closure.
/// It lets the unit test deterministically create a competing destination in
/// the otherwise tiny interval between verified temporary output and commit.
fn extract_project_bundle_entry_with_before_commit<F>(
    request: ExtractProjectBundleEntryRequest,
    before_commit: F,
) -> Result<(), String>
where
    F: FnOnce(&Path) -> Result<(), String>,
{
    if request.output_path.trim().is_empty() {
        return Err(invalid_data("extract bundle entry", "output path is empty"));
    }
    let preview = validate_project_bundle(&request.zip_path)?;
    let expected = preview
        .projects
        .iter()
        .find(|project| project.archive_path == request.archive_path)
        .ok_or_else(|| {
            invalid_data(
                "extract bundle entry",
                format!("bundle has no entry {}", request.archive_path),
            )
        })?;
    let output = PathBuf::from(&request.output_path);
    let temporary = PathBuf::from(format!("{}.tmp", request.output_path));
    if output.exists() || temporary.exists() {
        return Err(invalid_data(
            "extract bundle entry",
            "destination or temporary path already exists",
        ));
    }

    let mut temporary_created = false;
    let extraction = (|| -> Result<(), String> {
        let mut archive = open_zip(&request.zip_path)?;
        if let Some(parent) = temporary.parent() {
            fs::create_dir_all(parent)
                .map_err(|error| io_failure("create bundle extraction directory", error))?;
        }
        let mut temporary_file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temporary)
            .map_err(|error| io_failure("create exclusive bundle temporary", error))?;
        temporary_created = true;
        copy_bundle_entry_to(&mut archive, &request.archive_path, &mut temporary_file)?;
        drop(temporary_file);
        if !verify_file(
            temporary.to_string_lossy().into_owned(),
            expected.archive_sha256.clone(),
        )? {
            return Err(invalid_data(
                "extract bundle entry",
                format!("SHA-256 mismatch for {}", request.archive_path),
            ));
        }
        before_commit(&output)?;
        commit_bundle_temporary_no_replace(&temporary, &output)?;
        Ok(())
    })();
    if let Err(error) = extraction {
        if temporary_created {
            let _ = fs::remove_file(&temporary);
        }
        return Err(error);
    }
    Ok(())
}

/// Reads and validates the manifest of a single-project backup archive.
/// Selection exports (`projects` key) are explicitly rejected.
fn read_project_manifest(zip_path: &str) -> Result<ProjectManifestFile, String> {
    let mut archive = open_zip(zip_path)?;
    let mut entry = archive
        .by_name("manifest.json")
        .map_err(|_| invalid_data("read manifest", "archive has no manifest.json"))?;
    if entry.size() > MAX_MANIFEST_BYTES {
        return Err(invalid_data(
            "read manifest",
            "manifest exceeds the 4 MiB size limit",
        ));
    }
    // The header size can lie; cap the stream as well.
    let mut text = String::new();
    entry
        .by_ref()
        .take(MAX_MANIFEST_BYTES + 1)
        .read_to_string(&mut text)
        .map_err(|error| io_failure("read manifest entry", error))?;
    if text.len() as u64 > MAX_MANIFEST_BYTES {
        return Err(invalid_data(
            "read manifest",
            "manifest exceeds the 4 MiB size limit",
        ));
    }
    drop(entry);
    let value: serde_json::Value =
        serde_json::from_str(&text).map_err(|error| invalid_data("parse manifest", error))?;
    if value.get("projects").is_some() {
        return Err(invalid_data(
            "parse manifest",
            "selection archive: multi-project selection exports cannot be restored",
        ));
    }
    let manifest: ProjectManifestFile =
        serde_json::from_value(value).map_err(|error| invalid_data("parse manifest", error))?;
    if manifest.app != "SiteMark" {
        return Err(invalid_data("validate manifest", "not a SiteMark archive"));
    }
    if !(1..=5).contains(&manifest.schema_version) {
        return Err(invalid_data(
            "validate manifest",
            format!("unsupported schema version {}", manifest.schema_version),
        ));
    }
    if manifest.schema_version < 4 && !manifest.templates.is_empty() {
        return Err(invalid_data(
            "validate manifest",
            "capture templates require schema version 4",
        ));
    }
    // Reject invalid lifecycle values early even on legacy schemas when present,
    // but only require them for schema 5. Normalization happens in preview.
    if manifest.schema_version >= 5 {
        normalize_lifecycle_fields(
            manifest.schema_version,
            manifest.project_lifecycle_status.clone(),
            manifest.project_is_pinned,
        )?;
    } else if let Some(status) = manifest.project_lifecycle_status.as_deref() {
        // Legacy schemas ignore unknown lifecycle values by normalizing away.
        let _ = status;
    }
    if manifest.project_name.trim().is_empty() {
        return Err(invalid_data("validate manifest", "project name is empty"));
    }
    if manifest.photos.is_empty() && manifest.schema_version < 3 {
        return Err(invalid_data(
            "validate manifest",
            "archive contains no photos",
        ));
    }
    if manifest.photos.len() > MAX_ARCHIVE_PHOTOS {
        return Err(invalid_data(
            "validate manifest",
            format!("archive holds more than {MAX_ARCHIVE_PHOTOS} photos"),
        ));
    }
    validate_archive_templates(&manifest.templates)?;
    let mut seen = std::collections::HashSet::new();
    for photo in &manifest.photos {
        safe_photo_number_component(&photo.photo_number)?;
        if !seen.insert(photo.photo_number.as_str()) {
            return Err(invalid_data(
                "validate manifest",
                format!("duplicate photo number {}", photo.photo_number),
            ));
        }
        if photo.original_sha256.len() != 64
            || !photo
                .original_sha256
                .chars()
                .all(|character| character.is_ascii_hexdigit())
        {
            return Err(invalid_data(
                "validate manifest",
                format!("invalid SHA-256 digest for {}", photo.photo_number),
            ));
        }
    }
    Ok(manifest)
}

/// An archive entry name plus its declared uncompressed size in bytes.
type SizedEntry = (String, u64);

/// Locates the `photos/<number>.jpg` and `originals/<number>.<ext>` entries
/// for one photo, returning their names and declared uncompressed sizes.
/// Entry names are only ever *matched*, never used as output paths —
/// extraction always writes to caller-chosen destinations, so a crafted
/// archive cannot escape the app-private directory (no Zip Slip).
fn find_archive_entries(
    archive: &mut zip::ZipArchive<BufReader<File>>,
    photo_number: &str,
) -> Result<(SizedEntry, Option<SizedEntry>), String> {
    let rendered_name = format!("photos/{photo_number}.jpg");
    let original_prefix = format!("originals/{photo_number}.");
    let mut rendered: Option<(String, u64)> = None;
    let mut original: Option<(String, u64)> = None;
    for index in 0..archive.len() {
        let entry = archive
            .by_index(index)
            .map_err(|error| zip_failure("read archive entry", error))?;
        let name = entry.name();
        if name == rendered_name {
            rendered = Some((rendered_name.clone(), entry.size()));
        } else if let Some(remainder) = name.strip_prefix(&original_prefix) {
            // Require a plain extension with no nested path components.
            if !remainder.is_empty()
                && remainder
                    .chars()
                    .all(|character| character.is_ascii_alphanumeric())
            {
                original = Some((name.to_string(), entry.size()));
            }
        }
    }
    let rendered = rendered.ok_or_else(|| {
        invalid_data(
            "validate archive",
            format!("archive is missing the watermarked photo for {photo_number}"),
        )
    })?;
    if rendered.1 > MAX_ENTRY_UNCOMPRESSED_BYTES
        || original
            .as_ref()
            .is_some_and(|entry| entry.1 > MAX_ENTRY_UNCOMPRESSED_BYTES)
    {
        return Err(invalid_data(
            "validate archive",
            format!("an entry for {photo_number} exceeds the 128 MiB size limit"),
        ));
    }
    Ok((rendered, original))
}

/// Copies at most `cap` bytes from `reader` to `writer`; fails when the
/// source holds more. Used together with the header-size precheck so a
/// forged (lying) ZIP header cannot push the extraction past the limit.
fn copy_capped(reader: &mut impl Read, writer: &mut impl Write, cap: u64) -> Result<u64, String> {
    let mut limited = reader.take(cap + 1);
    let copied =
        std::io::copy(&mut limited, writer).map_err(|error| io_failure("copy ZIP entry", error))?;
    if copied > cap {
        return Err(invalid_data(
            "extract entry",
            "ZIP entry exceeds the 128 MiB extraction limit",
        ));
    }
    Ok(copied)
}

/// Extracts one archive entry to `destination`, creating parent directories.
fn extract_entry_to(
    archive: &mut zip::ZipArchive<BufReader<File>>,
    entry_name: &str,
    destination: &str,
) -> Result<(), String> {
    let mut entry = archive
        .by_name(entry_name)
        .map_err(|error| zip_failure(&format!("open archive entry {entry_name}"), error))?;
    if entry.size() > MAX_ENTRY_UNCOMPRESSED_BYTES {
        return Err(invalid_data(
            "validate archive",
            format!("entry {entry_name} exceeds the 128 MiB size limit"),
        ));
    }
    let output = Path::new(destination);
    if let Some(parent) = output.parent() {
        fs::create_dir_all(parent).map_err(|error| io_failure("create import directory", error))?;
    }
    let mut file =
        File::create(output).map_err(|error| io_failure("create imported file", error))?;
    copy_capped(&mut entry, &mut file, MAX_ENTRY_UNCOMPRESSED_BYTES)?;
    Ok(())
}

/// Validates a backup ZIP and returns its restorable content. Only
/// single-project archives (schema v1-v5) are restorable.
pub fn read_project_archive(zip_path: String) -> Result<ProjectArchivePreview, String> {
    let manifest = read_project_manifest(&zip_path)?;
    let (project_lifecycle_status, project_is_pinned) = normalize_lifecycle_fields(
        manifest.schema_version,
        manifest.project_lifecycle_status.clone(),
        manifest.project_is_pinned,
    )?;
    let mut archive = open_zip(&zip_path)?;
    let mut total_uncompressed: u64 = 0;
    let mut photos = Vec::with_capacity(manifest.photos.len());
    for photo in &manifest.photos {
        let (rendered_entry, original_entry) =
            find_archive_entries(&mut archive, &photo.photo_number)?;
        if manifest.includes_originals && original_entry.is_none() {
            return Err(invalid_data(
                "validate archive",
                format!("archive is missing the original for {}", photo.photo_number),
            ));
        }
        total_uncompressed += rendered_entry.1 + original_entry.as_ref().map_or(0, |entry| entry.1);
        if total_uncompressed > MAX_TOTAL_UNCOMPRESSED_BYTES {
            return Err(invalid_data(
                "validate archive",
                "archive exceeds the 8 GiB total extraction limit",
            ));
        }
        photos.push(ArchivePhotoPreview {
            photo_number: photo.photo_number.clone(),
            has_original: original_entry.is_some(),
            original_sha256: photo.original_sha256.clone(),
            captured_at: photo.captured_at.clone(),
            work_location: photo.work_location.clone(),
            work_content: photo.work_content.clone(),
            photographer: photo.photographer.clone(),
            address: photo.address.clone(),
            notes: photo.notes.clone(),
            latitude: photo.latitude,
            longitude: photo.longitude,
            accuracy_meters: photo.accuracy_meters,
            watermark_locale_code: photo.watermark_locale_code.clone(),
        });
    }
    let templates = manifest
        .templates
        .into_iter()
        .map(|template| ArchiveCaptureTemplate {
            name: normalized_template_name(&template.name),
            work_location: trimmed_template_field(&template.work_location).to_string(),
            work_content: trimmed_template_field(&template.work_content).to_string(),
            photographer: trimmed_template_field(&template.photographer).to_string(),
            created_at: template.created_at,
            updated_at: template.updated_at,
        })
        .collect();
    Ok(ProjectArchivePreview {
        schema_version: manifest.schema_version,
        project_name: manifest.project_name,
        project_description: manifest.project_description,
        project_created_at: manifest.project_created_at,
        snapshot_at: manifest.snapshot_at,
        omitted_processing_count: manifest.omitted_processing_count,
        omitted_failed_count: manifest.omitted_failed_count,
        is_partial: manifest.omitted_processing_count > 0 || manifest.omitted_failed_count > 0,
        includes_originals: manifest.includes_originals,
        project_lifecycle_status,
        project_is_pinned,
        watermark: manifest
            .watermark
            .map(|watermark| ArchiveWatermarkSettings {
                position: watermark.position,
                opacity: watermark.opacity,
                accent_color_argb: watermark.accent_color_argb,
                font_scale: watermark.font_scale,
            }),
        photos,
        templates,
    })
}

/// Extracts one photo (and its original when requested) from a backup ZIP.
///
/// Everything lands in `<destination>.tmp` first; only after the original's
/// SHA-256 verifies are the files atomically renamed into place. Any failure
/// removes every temporary file, so a failed extraction never leaves
/// half-written files behind for the caller to clean up.
pub fn extract_archive_photo(
    request: ExtractArchivePhotoRequest,
) -> Result<ExtractedArchivePhoto, String> {
    safe_photo_number_component(&request.photo_number)?;
    let manifest = read_project_manifest(&request.zip_path)?;
    let photo = manifest
        .photos
        .iter()
        .find(|candidate| candidate.photo_number == request.photo_number)
        .ok_or_else(|| {
            invalid_data(
                "validate archive",
                format!("manifest has no entry for {}", request.photo_number),
            )
        })?;
    let mut archive = open_zip(&request.zip_path)?;
    let (rendered_entry, original_entry) = find_archive_entries(&mut archive, &photo.photo_number)?;
    let rendered_tmp = format!("{}.tmp", request.rendered_destination);
    let original_tmp = request
        .original_destination
        .as_ref()
        .map(|destination| format!("{destination}.tmp"));

    let extraction = (|| -> Result<(), String> {
        extract_entry_to(&mut archive, &rendered_entry.0, &rendered_tmp)?;
        if let Some(tmp) = original_tmp.as_ref() {
            let Some((entry_name, _)) = original_entry.as_ref() else {
                return Err(invalid_data(
                    "validate archive",
                    format!("archive is missing the original for {}", photo.photo_number),
                ));
            };
            extract_entry_to(&mut archive, entry_name, tmp)?;
            if !verify_file(tmp.clone(), photo.original_sha256.clone())? {
                return Err(invalid_data(
                    "verify original",
                    format!("SHA-256 mismatch for {}", photo.photo_number),
                ));
            }
        }
        Ok(())
    })();
    if let Err(error) = extraction {
        let _ = fs::remove_file(&rendered_tmp);
        if let Some(tmp) = original_tmp.as_ref() {
            let _ = fs::remove_file(tmp);
        }
        return Err(error);
    }

    // Commit point: same-volume renames are atomic.
    fs::rename(&rendered_tmp, &request.rendered_destination).map_err(|error| {
        let _ = fs::remove_file(&rendered_tmp);
        if let Some(tmp) = original_tmp.as_ref() {
            let _ = fs::remove_file(tmp);
        }
        io_failure("finalize rendered photo", error)
    })?;
    if let (Some(tmp), Some(destination)) = (original_tmp, request.original_destination.as_ref()) {
        fs::rename(&tmp, destination)
            .map_err(|error| io_failure("finalize original photo", error))?;
    }
    Ok(ExtractedArchivePhoto {
        rendered_path: request.rendered_destination.clone(),
        original_path: request.original_destination.clone(),
    })
}
