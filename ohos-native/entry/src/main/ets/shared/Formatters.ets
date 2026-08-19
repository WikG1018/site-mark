import { fileUri } from '@kit.CoreFileKit';
import { tr } from './AppText';

export function formatDateTime(value: number): string {
  if (value <= 0) {
    return '—';
  }
  const date = new Date(value);
  return `${date.getFullYear()}-${two(date.getMonth() + 1)}-${two(date.getDate())} ${
    two(date.getHours())}:${two(date.getMinutes())}`;
}

export function formatDay(value: number): string {
  if (value <= 0) {
    return '—';
  }
  const date = new Date(value);
  return `${date.getFullYear()}-${two(date.getMonth() + 1)}-${two(date.getDate())}`;
}

export function formatBytes(value: number): string {
  if (value < 1024) {
    return `${value} B`;
  }
  if (value < 1024 * 1024) {
    return `${(value / 1024).toFixed(1)} KB`;
  }
  if (value < 1024 * 1024 * 1024) {
    return `${(value / (1024 * 1024)).toFixed(1)} MB`;
  }
  return `${(value / (1024 * 1024 * 1024)).toFixed(2)} GB`;
}

export function imageUri(path: string): string {
  if (path.length === 0) {
    return '';
  }
  try {
    return fileUri.getUriFromPath(path);
  } catch (_) {
    return path;
  }
}

export function statusLabel(status: string): string {
  if (status === 'ready') {
    return tr('已完成', 'Completed');
  }
  if (status === 'failed') {
    return tr('失败', 'Failed');
  }
  if (status === 'rendering') {
    return tr('处理中', 'Processing');
  }
  return tr('等待处理', 'Pending');
}

export function lifecycleLabel(status: string): string {
  if (status === 'completed') {
    return tr('已完成', 'Completed');
  }
  if (status === 'archived') {
    return tr('已归档', 'Archived');
  }
  return tr('进行中', 'Active');
}

function two(value: number): string {
  return value.toString().padStart(2, '0');
}
