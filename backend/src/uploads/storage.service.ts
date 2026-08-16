import { Injectable, Logger, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'crypto';
import {
  GetObjectCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

const ALLOWED: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/jpg': 'jpg',
  'image/pjpeg': 'jpg',
  'image/png': 'png',
  'image/x-png': 'png',
  'image/webp': 'webp',
  'image/gif': 'gif',
  'image/heic': 'heic',
  'image/heif': 'heif',
  'image/heic-sequence': 'heic',
  'image/heif-sequence': 'heif',
};

const EXT_MIME: Record<string, string> = {
  jpg: 'image/jpeg',
  jpeg: 'image/jpeg',
  png: 'image/png',
  webp: 'image/webp',
  gif: 'image/gif',
  heic: 'image/heic',
  heif: 'image/heif',
};

const GET_TTL_SECONDS = 60 * 60 * 24 * 7; // 7 days
const PUT_TTL_SECONDS = 60 * 10;

export type UploadedImage = {
  key: string;
  url: string;
};

@Injectable()
export class StorageService {
  private readonly logger = new Logger(StorageService.name);
  private readonly client: S3Client | null;
  private readonly bucket: string;
  private readonly region: string;

  constructor(config: ConfigService) {
    this.bucket = config.get<string>('s3.bucket') ?? '';
    this.region = config.get<string>('s3.region') ?? 'ap-southeast-1';
    const accessKeyId = (config.get<string>('s3.accessKeyId') ?? '').trim();
    const secretAccessKey = (config.get<string>('s3.secretAccessKey') ?? '').trim();
    if (this.bucket && accessKeyId && secretAccessKey) {
      this.client = new S3Client({
        region: this.region,
        credentials: { accessKeyId, secretAccessKey },
        requestChecksumCalculation: 'WHEN_REQUIRED',
        responseChecksumValidation: 'WHEN_REQUIRED',
      });
    } else {
      this.client = null;
      this.logger.warn('S3 is not configured — image uploads disabled.');
    }
  }

  get configured() {
    return !!this.client && !!this.bucket;
  }

  assertReady() {
    if (!this.configured) {
      throw new ServiceUnavailableException('Image uploads are not configured');
    }
  }

  extensionFor(contentType: string): string | null {
    return ALLOWED[contentType.toLowerCase().split(';')[0].trim()] ?? null;
  }

  /** Resolve a real image MIME from magic bytes, then header/filename. */
  sniffImageType(opts: {
    buffer?: Buffer;
    mimetype?: string;
    filename?: string;
  }): { contentType: string; ext: string } | null {
    const fromBytes = this.sniffMagic(opts.buffer);
    if (fromBytes) return fromBytes;

    const header = (opts.mimetype ?? '').toLowerCase().split(';')[0].trim();
    const headerExt = this.extensionFor(header);
    if (headerExt) return { contentType: header.startsWith('image/') ? header : `image/${headerExt}`, ext: headerExt };

    const ext = (opts.filename ?? '').split('.').pop()?.toLowerCase() ?? '';
    const mapped = EXT_MIME[ext];
    if (mapped) return { contentType: mapped, ext: this.extensionFor(mapped) ?? ext };
    return null;
  }

  private sniffMagic(buf?: Buffer): { contentType: string; ext: string } | null {
    if (!buf || buf.length < 12) return null;
    if (buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) {
      return { contentType: 'image/jpeg', ext: 'jpg' };
    }
    if (buf[0] === 0x89 && buf[1] === 0x50 && buf[2] === 0x4e && buf[3] === 0x47) {
      return { contentType: 'image/png', ext: 'png' };
    }
    if (buf[0] === 0x47 && buf[1] === 0x49 && buf[2] === 0x46 && buf[3] === 0x38) {
      return { contentType: 'image/gif', ext: 'gif' };
    }
    if (
      buf.toString('ascii', 0, 4) === 'RIFF' &&
      buf.toString('ascii', 8, 12) === 'WEBP'
    ) {
      return { contentType: 'image/webp', ext: 'webp' };
    }
    // ISO BMFF (HEIC/HEIF): ....ftyp + brand
    if (buf.toString('ascii', 4, 8) === 'ftyp') {
      const brand = buf.toString('ascii', 8, 12).replace(/\0/g, '').toLowerCase();
      if (['heic', 'heix', 'hevc', 'hevx', 'mif1', 'msf1', 'heif'].some((b) => brand.startsWith(b))) {
        return { contentType: 'image/heic', ext: 'heic' };
      }
    }
    return null;
  }

  makeKey(userId: string, contentType: string): string {
    const ext = this.extensionFor(contentType) ?? 'bin';
    return `images/${userId}/${randomUUID()}.${ext}`;
  }

  async uploadBuffer(opts: {
    userId: string;
    buffer: Buffer;
    contentType: string;
  }): Promise<UploadedImage> {
    this.assertReady();
    const key = this.makeKey(opts.userId, opts.contentType);
    await this.client!.send(
      new PutObjectCommand({
        Bucket: this.bucket,
        Key: key,
        Body: opts.buffer,
        ContentType: opts.contentType,
      }),
    );
    return { key, url: await this.signGet(key) };
  }

  async presignPut(opts: {
    userId: string;
    contentType: string;
  }): Promise<{ key: string; uploadUrl: string; url: string; headers: Record<string, string> }> {
    this.assertReady();
    const key = this.makeKey(opts.userId, opts.contentType);
    const uploadUrl = await getSignedUrl(
      this.client!,
      new PutObjectCommand({
        Bucket: this.bucket,
        Key: key,
        ContentType: opts.contentType,
      }),
      { expiresIn: PUT_TTL_SECONDS },
    );
    return {
      key,
      uploadUrl,
      url: await this.signGet(key),
      headers: { 'Content-Type': opts.contentType },
    };
  }

  async signGet(key: string): Promise<string> {
    this.assertReady();
    return getSignedUrl(
      this.client!,
      new GetObjectCommand({ Bucket: this.bucket, Key: key }),
      { expiresIn: GET_TTL_SECONDS },
    );
  }

  isStoredKey(value: string | null | undefined): boolean {
    return !!value && value.startsWith('images/');
  }

  async resolveMedia(media: string | null | undefined): Promise<string | null> {
    if (!media) return null;
    if (!this.isStoredKey(media)) return media;
    if (!this.configured) return media;
    try {
      return await this.signGet(media);
    } catch (e) {
      this.logger.error(`signGet failed: ${(e as Error).message}`);
      return media;
    }
  }
}
