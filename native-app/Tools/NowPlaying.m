#import <Foundation/Foundation.h>
#import <dlfcn.h>

void sorayura_now_playing(void) {
    @autoreleasepool {
        void *framework = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
        if (!framework) exit(1);

        const char *action = getenv("SORAYURA_MEDIA_ACTION");
        if (!action) exit(1);
        if (strcmp(action, "read") != 0 && strcmp(action, "artwork") != 0) {
            NSDictionary *commands = @{@"play": @0, @"pause": @1, @"next track": @4, @"previous track": @5};
            NSNumber *command = commands[@(action)];
            bool (*send)(unsigned int, NSDictionary *) = dlsym(framework, "MRMediaRemoteSendCommand");
            exit(command && send && send(command.unsignedIntValue, nil) ? 0 : 1);
        }

        void (*getInfo)(dispatch_queue_t, void (^)(NSDictionary *)) = dlsym(framework, "MRMediaRemoteGetNowPlayingInfo");
        void (*getPlaying)(dispatch_queue_t, void (^)(bool)) = dlsym(framework, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
        if (!getInfo || !getPlaying) exit(1);

        dispatch_queue_t queue = dispatch_queue_create("dev.sorayura.now-playing", DISPATCH_QUEUE_SERIAL);
        dispatch_group_t group = dispatch_group_create();
        __block NSDictionary *info;
        __block BOOL playing = NO;
        dispatch_group_enter(group);
        getInfo(queue, ^(NSDictionary *value) { info = value; dispatch_group_leave(group); });
        dispatch_group_enter(group);
        getPlaying(queue, ^(bool value) { playing = value; dispatch_group_leave(group); });
        if (dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) != 0) exit(1);

        NSMutableDictionary *result = [@{@"playing": @(playing)} mutableCopy];
        NSDictionary *fields = @{
            @"title": @"Title", @"artist": @"Artist", @"album": @"Album",
            @"identifier": @"ContentItemIdentifier"
        };
        for (NSString *field in fields) {
            id value = info[ [@"kMRMediaRemoteNowPlayingInfo" stringByAppendingString:fields[field]] ];
            if ([value isKindOfClass:NSString.class] && [value length] <= 2048) result[field] = value;
        }
        NSData *art = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
        if (strcmp(action, "artwork") == 0 && [art isKindOfClass:NSData.class] && art.length <= 5000000) {
            result[@"artwork"] = [art base64EncodedStringWithOptions:0];
        }
        NSData *json = [NSJSONSerialization dataWithJSONObject:result options:0 error:NULL];
        if (!json) exit(1);
        fwrite(json.bytes, 1, json.length, stdout);
    }
}
