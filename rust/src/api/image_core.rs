use std::fs::{self, File};
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
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct ExportProjectRequest {
    pub project_id: String,
    pub project_name: String,
    pub output_zip_path: String,
    pub include_originals: bool,
    pub photos: Vec<ExportPhotoRecord>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct ExportProjectResult {
    pub output_zip_path: String,
    pub archive_sha256: String,
    pub photo_count: u32,
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
    includes_originals: bool,
    photos: &'a [ExportPhotoRecord],
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

pub fn verify_file(path: String, expected_sha256: String) -> Result<bool, String> {
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

    let manifest = serde_json::to_vec_pretty(&ExportManifest {
        schema_version: 1,
        app: "SiteMark",
        project_id: &request.project_id,
        project_name: &request.project_name,
        includes_originals: request.include_originals,
        photos: &request.photos,
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
            .all(|character| character.is_alphanumeric() || matches!(character, '-' | '_'))
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
}
