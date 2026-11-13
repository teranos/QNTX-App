#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// The app's main is Tauri's, generated, and nothing of this repo sits in it.
// This is loaded with the app's image, before main runs, and begins handing
// the node its tokens once the app has launched: also when Apple launched it
// in the background for a Live Activity that started.
//
// WaitsTokens is Swift's (WaitsTokens.swift), found by its name so that no
// generated header stands between the two.
@interface WaitsBoot : NSObject
@end

@implementation WaitsBoot

+ (void)load {
  [[NSNotificationCenter defaultCenter]
      addObserverForName:UIApplicationDidFinishLaunchingNotification
                  object:nil
                   queue:[NSOperationQueue mainQueue]
              usingBlock:^(NSNotification *note) {
                Class tokens = NSClassFromString(@"WaitsTokens");
                SEL begin = NSSelectorFromString(@"begin");
                if ([tokens respondsToSelector:begin]) {
                  ((void (*)(id, SEL))[tokens methodForSelector:begin])(tokens, begin);
                } else {
                  NSLog(@"[Waits] WaitsTokens is not in this build: the node is handed no token");
                }
              }];
}

@end
