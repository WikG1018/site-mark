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
        let safe_number = safe_archive_component(&photo.photo_number)?;
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
    Ok(())
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
}

/// Pure layout calculation for the engineering watermark card.
///
/// `line_count` is the number of display lines that will be rendered. The
/// returned `left`/`top` use the bottom-left anchor (the strictest horizontal
/// fit: `left = margin`), which is the worst case for the `card_width + margin`
/// constraint. Bottom-right rendering only ever shifts the card leftward, so it
/// never exceeds the bounds validated here.
pub fn watermark_layout(
    width: u32,
    height: u32,
    line_count: usize,
) -> Result<WatermarkLayout, String> {
    let margin = ((width.min(height) as f32) * 0.025).round() as u32;
    let padding = ((width as f32) * 0.0216).round().max(22.0) as u32;
    let font_size = ((width as f32) * 0.0312).clamp(31.2, 69.6);
    let title_size = font_size * 1.18;
    let line_height = (font_size * 1.42).round() as u32;
    let card_width = ((width as f32) * 0.62).round() as u32;
    let card_height = padding * 2 + line_height * line_count.max(1) as u32;
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
    let left = margin;
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
    })
}

fn fit_line(text: &str, max_width: u32, size: f32, font: &FontArc) -> String {
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

fn draw_watermark_card(canvas: &mut RgbaImage, request: &RenderPhotoRequest) -> Result<(), String> {
    let (width, height) = canvas.dimensions();
    let mut lines = vec![
        format!("现场记录 · {}", request.project_name),
        format!("位置  {}", request.work_location),
        format!("内容  {}", request.work_content),
        format!("拍摄人  {}", request.photographer),
        format!("编号  {}", request.photo_number),
        format!("时间  {}", request.captured_at),
    ];
    if let Some(address) = non_empty(&request.address) {
        lines.push(format!("地址  {address}"));
    }
    if let Some(coordinates) = non_empty(&request.coordinates) {
        lines.push(format!("坐标  {coordinates}"));
    }
    if let Some(notes) = non_empty(&request.notes) {
        lines.push(format!("备注  {notes}"));
    }
    let layout = watermark_layout(width, height, lines.len())?;
    let WatermarkLayout {
        font_size,
        title_size,
        line_height,
        padding,
        margin,
        card_width,
        card_height,
        ..
    } = layout;
    let left = match request.position {
        WatermarkPosition::BottomLeft => margin,
        WatermarkPosition::BottomRight => width - margin - card_width,
    };
    let top = height - margin - card_height;
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

    let font = FontArc::try_from_slice(FONT_BYTES)
        .map_err(|error| invalid_data("load bundled font", error))?;
    let text_left = (left + padding) as i32;
    let mut text_top = (top + padding) as i32;
    let max_text_width = card_width.saturating_sub(padding * 2);
    for (index, line) in lines.iter().enumerate() {
        let size = if index == 0 { title_size } else { font_size };
        let color = if index == 0 {
            Rgba([255, 255, 255, 255])
        } else {
            Rgba([238, 244, 242, 255])
        };
        let fitted = fit_line(line, max_text_width, size, &font);
        draw_text_mut(
            canvas,
            color,
            text_left,
            text_top,
            PxScale::from(size),
            &font,
            &fitted,
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
