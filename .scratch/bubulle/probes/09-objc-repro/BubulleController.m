#import "BubulleController.h"

static void logLine(NSString *s) {
    NSString *path = @"/tmp/bubulle_objc_probe.log";
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], s];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
    }
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    [fh seekToEndOfFile];
    [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [fh closeFile];
    fprintf(stderr, "%s", [line UTF8String]);
}

@implementation BubulleController

- (void)activateServer:(id)sender {
    [super activateServer:sender];
    id<BubulleTextInput> client = (id<BubulleTextInput>)sender;
    NSRect rect = NSZeroRect;
    NSDictionary *attrs = [client attributesForCharacterIndex:0 lineHeightRectangle:&rect];
    NSRange range = [client selectedRange];
    logLine([NSString stringWithFormat:@"activateServer bundle=%@ rect=%@ selRange=(%lu,%lu) attrsEmpty=%d",
             [client bundleIdentifier], NSStringFromRect(rect),
             (unsigned long)range.location, (unsigned long)range.length,
             attrs.count == 0]);
}

- (void)deactivateServer:(id)sender {
    logLine(@"deactivateServer");
    [super deactivateServer:sender];
}

@end
