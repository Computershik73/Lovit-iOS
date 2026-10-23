//
//  MAXWebP.m
//

#import "MAXWebP.h"
#import "src/webp/decode.h"

@implementation MAXWebP

+ (BOOL)isWebPData:(NSData *)data {
    if (data.length < 12) return NO;

    const uint8_t *bytes = (const uint8_t *)data.bytes;
    return bytes[0] == 'R' && bytes[1] == 'I' && bytes[2] == 'F' && bytes[3] == 'F'
        && bytes[8] == 'W' && bytes[9] == 'E' && bytes[10] == 'B' && bytes[11] == 'P';
}

/// Освобождает буфер, выданный libwebp, когда CGImage с ним закончил.
/// Отдавать его free() нельзя: libwebp выделяет своим распределителем.
static void MAXWebPReleaseData(void *info, const void *data, size_t size) {
    WebPFree((void *)data);
}

+ (UIImage *)imageWithData:(NSData *)data {
    if (![self isWebPData:data]) return nil;

    int width = 0;
    int height = 0;
    uint8_t *pixels = WebPDecodeRGBA((const uint8_t *)data.bytes, data.length,
                                     &width, &height);
    if (pixels == NULL || width <= 0 || height <= 0) {
        if (pixels != NULL) WebPFree(pixels);
        return nil;
    }

    size_t stride = (size_t)width * 4;
    CGDataProviderRef provider = CGDataProviderCreateWithData(
        NULL, pixels, stride * (size_t)height, MAXWebPReleaseData);
    if (provider == NULL) {
        WebPFree(pixels);
        return nil;
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGImageRef cgImage = CGImageCreate((size_t)width, (size_t)height, 8, 32, stride,
                                       colorSpace,
                                       kCGBitmapByteOrderDefault | kCGImageAlphaLast,
                                       provider, NULL, NO, kCGRenderingIntentDefault);

    CGColorSpaceRelease(colorSpace);
    CGDataProviderRelease(provider);

    if (cgImage == NULL) return nil;

    UIImage *image = [UIImage imageWithCGImage:cgImage];
    CGImageRelease(cgImage);
    return image;
}

@end
