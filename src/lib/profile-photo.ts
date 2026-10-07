/** Normalize a user-selected photo to a small, metadata-free square JPEG. */
export async function prepareProfilePhoto(file: File): Promise<Blob> {
  if (!['image/jpeg', 'image/png', 'image/webp'].includes(file.type)) throw new Error('Choose a JPG, PNG, or WebP photo.');
  if (file.size > 10 * 1024 * 1024) throw new Error('Choose a photo smaller than 10 MB.');
  let bitmap: ImageBitmap;
  try { bitmap = await createImageBitmap(file); } catch { throw new Error('This photo could not be read. Please choose another image.'); }
  try {
    const canvas = document.createElement('canvas'); canvas.width = 384; canvas.height = 384;
    const context = canvas.getContext('2d'); if (!context) throw new Error('Photo editing is unavailable in this browser.');
    const size = Math.min(bitmap.width, bitmap.height);
    context.fillStyle = '#f7f7f0'; context.fillRect(0, 0, 384, 384);
    context.drawImage(bitmap, (bitmap.width - size) / 2, (bitmap.height - size) / 2, size, size, 0, 0, 384, 384);
    let blob = await new Promise<Blob | null>(resolve => canvas.toBlob(resolve, 'image/jpeg', .72));
    if (blob && blob.size > 96 * 1024) blob = await new Promise<Blob | null>(resolve => canvas.toBlob(resolve, 'image/jpeg', .55));
    if (!blob || blob.size > 128 * 1024) throw new Error('Could not resize this photo. Please choose a smaller image.');
    return blob;
  } finally { bitmap.close(); }
}
