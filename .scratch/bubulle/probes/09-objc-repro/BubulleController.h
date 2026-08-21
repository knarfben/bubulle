#import <InputMethodKit/InputMethodKit.h>

@protocol BubulleTextInput <NSObject>
- (NSDictionary *)attributesForCharacterIndex:(NSUInteger)index lineHeightRectangle:(NSRect *)lineRect;
- (NSRange)selectedRange;
- (NSString *)bundleIdentifier;
@end

@interface BubulleController : IMKInputController
@end
