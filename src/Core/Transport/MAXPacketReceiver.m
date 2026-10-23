//
//  MAXPacketReceiver.m
//

#import "MAXPacketReceiver.h"
#import "MAXPacket.h"

const NSUInteger MAXReceiverMaxBufferSize = 16 * 1024 * 1024;

@implementation MAXPacketReceiver {
    NSMutableData *_buffer;
}

- (id)init {
    self = [super init];
    if (self) {
        _buffer = [NSMutableData data];
    }
    return self;
}

- (NSArray *)feed:(NSData *)data {
    if (data.length > 0) [_buffer appendData:data];

    if (_buffer.length > MAXReceiverMaxBufferSize) {
        [self reset];
        return nil;
    }

    NSMutableArray *packets = [NSMutableArray array];
    NSUInteger start = 0;

    while (_buffer.length - start >= MAXPacketHeaderSize) {
        const uint8_t *bytes = (const uint8_t *)_buffer.bytes + start;
        NSUInteger payloadLength = ((NSUInteger)bytes[7] << 16)
                                 | ((NSUInteger)bytes[8] << 8)
                                 | (NSUInteger)bytes[9];
        NSUInteger totalLength = MAXPacketHeaderSize + payloadLength;

        if (_buffer.length - start < totalLength) break;

        [packets addObject:[_buffer subdataWithRange:NSMakeRange(start, totalLength)]];
        start += totalLength;
    }

    if (start > 0) {
        [_buffer replaceBytesInRange:NSMakeRange(0, start) withBytes:NULL length:0];
    }

    return packets;
}

- (void)reset {
    _buffer = [NSMutableData data];
}

@end
