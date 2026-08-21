// PROTOTYPE JETABLE — reproduction ObjC de la sonde de research/02, pour isoler si la
// régression du ticket 09 (enabled ne flip plus tout seul) est spécifique au squelette
// Swift ou à la machine/l'OS.
#import <Cocoa/Cocoa.h>
#import <InputMethodKit/InputMethodKit.h>

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSString *connectionName = @"local_bubulle_objcrepro_connection";
        IMKServer *server = [[IMKServer alloc] initWithName:connectionName
                                            bundleIdentifier:[[NSBundle mainBundle] bundleIdentifier]];
        NSLog(@"BubulleProbe (ObjC repro) started pid=%d server=%@", getpid(), server);
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [NSApp run];
    }
    return 0;
}
