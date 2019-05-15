// Copyright 2018-present 650 Industries. All rights reserved.

#import <EXVideoThumbnails/EXVideoThumbnailsModule.h>
#import <AVFoundation/AVFoundation.h>
#import <AVFoundation/AVAsset.h>
#import <UIKit/UIKit.h>

NSString* const EX_VT_OPTIONS_KEY_QUALITY = @"quality";
NSString* const EX_VT_OPTIONS_KEY_TIME = @"time";
NSString* const EX_VT_OPTIONS_KEY_HEADERS = @"headers";

@implementation EXVideoThumbnailsModule

UM_EXPORT_MODULE(ExpoVideoThumbnails);

- (void)setModuleRegistry:(UMModuleRegistry *)moduleRegistry
{
    _moduleRegistry = moduleRegistry;
    _fileSystem = [moduleRegistry getModuleImplementingProtocol:@protocol(UMFileSystemInterface)];
}

UM_EXPORT_METHOD_AS(getThumbnail,
                    sourceFilename:(NSString *)source
                    options:(NSDictionary *)options
                    resolve:(UMPromiseResolveBlock)resolve
                    reject:(UMPromiseRejectBlock)reject)
{
    NSURL *url = [NSURL URLWithString:source];
    if ([url isFileURL]) {
      if (!_fileSystem) {
        return reject(@"E_MISSING_MODULE", @"No FileSystem module.", nil);
      }
      if (!([_fileSystem permissionsForURI:url] & UMFileSystemPermissionRead)) {
        return reject(@"E_FILESYSTEM_PERMISSIONS", [NSString stringWithFormat:@"File '%@' isn't readable.", source], nil);
      }
    }
    
    long timeInMs = [(NSNumber *)options[EX_VT_OPTIONS_KEY_TIME] integerValue] ?: 0;
    float quality = [(NSNumber *)options[EX_VT_OPTIONS_KEY_QUALITY] floatValue] ?: 1.0;
    NSDictionary *headers = options[EX_VT_OPTIONS_KEY_HEADERS] ?: @{};
    
    
    AVURLAsset *asset = [[AVURLAsset alloc] initWithURL:url options:@{@"AVURLAssetHTTPHeaderFieldsKey": headers}];
    AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    generator.appliesPreferredTrackTransform = YES;
    
    NSError *err = NULL;
    CMTime time = CMTimeMake(timeInMs, 1000);
    
    CGImageRef imgRef = [generator copyCGImageAtTime:time actualTime:NULL error:&err];
    if (err) {
      return reject(@"E_THUM_FAIL", err.localizedFailureReason, err);
    }
    UIImage *thumbnail = [UIImage imageWithCGImage:imgRef];
    
    NSString *directory = [_fileSystem.cachesDirectory stringByAppendingPathComponent:@"VideoThumbnails"];
    [_fileSystem ensureDirExistsWithPath:directory];
    
    NSString *fileName = [[[NSUUID UUID] UUIDString] stringByAppendingString:@".jpg"];
    NSString *newPath = [directory stringByAppendingPathComponent:fileName];
    NSData *data = UIImageJPEGRepresentation(thumbnail, quality);
    if (![data writeToFile:newPath atomically:YES]) {
        return reject(@"E_WRITE_ERROR", @"Can't write to file.", nil);
    }
    NSURL *fileURL = [NSURL fileURLWithPath:newPath];
    NSString *filePath = [fileURL absoluteString];
    
    resolve(@{
              @"uri" : filePath,
              @"width" : @(thumbnail.size.width),
              @"height" : @(thumbnail.size.height),
              });
}

@end
