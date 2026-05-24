// SharedProtocol.h
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SharedProtocol
- (void)sendCommand:(NSString *)command completion:(void (^)(NSString * _Nullable response))completion;
- (void)transferFileHandle:(NSFileHandle *)fileHandle completion:(void (^)(BOOL success, NSString * _Nullable message))completion;
@end

NS_ASSUME_NONNULL_END
