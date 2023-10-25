#import <Foundation/Foundation.h>

@interface NSData (DEGzip)

+ (NSData *)gzipData:(NSData *)pUncompressedData;

@end
