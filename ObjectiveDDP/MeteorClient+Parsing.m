#import "MeteorClient.h"

@implementation MeteorClient (Parsing)

- (void)_handleMethodResultMessageWithMessageId:(NSString *)messageId message:(NSDictionary *)message msg:(NSString *)msg {
    if ([self.methodIds containsObject:messageId]) {
        if([msg isEqualToString:@"result"]) {
            asyncCallback callback = [self.deferreds objectForKey:messageId];
            id response;
            if(message[@"error"]) {
                NSDictionary *errorDesc = message[@"error"];
                NSDictionary *userInfo = @{NSLocalizedDescriptionKey: errorDesc};
                NSError *responseError = [NSError errorWithDomain:errorDesc[@"errorType"] code:[errorDesc[@"error"]integerValue] userInfo:userInfo];
                if (callback)
                    callback(nil, responseError);
                response = responseError;
            } else {
                response = message[@"result"];
                if (callback)
                    callback(response, nil);
            }
            NSString *notificationName = [NSString stringWithFormat:@"response_%@", messageId];
            [[NSNotificationCenter defaultCenter] postNotificationName:notificationName object:self userInfo:response];
            [self.deferreds removeObjectForKey:messageId];
            [self.methodIds removeObject:messageId];
        }
    }
}

- (void)_handleLoginChallengeResponse:(NSDictionary *)message msg:(NSString *)msg {
    if ([msg isEqualToString:@"result"]
        && message[@"result"]
        && [message[@"result"] isKindOfClass:[NSDictionary class]]
        && message[@"result"][@"B"]
        && message[@"result"][@"identity"]
        && message[@"result"][@"salt"]) {
        [self didReceiveLoginChallengeWithResponse:message[@"result"]];
    }
}

static int LOGON_RETRY_MAX = 5;

- (void)_handleLoginError:(NSDictionary *)message msg:(NSString *)msg {
    if([msg isEqualToString:@"result"]
       && message[@"error"]
       && [message[@"error"][@"error"]integerValue] == 403) {
        self.userIsLoggingIn = NO;
        if (++self.retryAttempts < LOGON_RETRY_MAX && self.connected) {
            [self logonWithUsername:self.userName password:self.password];
        } else {
            self.retryAttempts = 0;
            [self.authDelegate authenticationFailed:message[@"error"][@"reason"]];
        }
    }
}

- (void)_handleHAMKVerification:(NSDictionary *)message msg:(NSString *)msg {
    if (msg && [msg isEqualToString:@"result"]
        && message[@"result"]
        && [message[@"result"] isKindOfClass:[NSDictionary class]]
        && message[@"result"][@"id"]
        && message[@"result"][@"HAMK"]
        && message[@"result"][@"token"]) {
        NSDictionary *response = message[@"result"];
        [self didReceiveHAMKVerificationWithResponse:response];
    }
}

- (void)_handleAddedMessage:(NSDictionary *)message msg:(NSString *)msg {
    if (msg && [msg isEqualToString:@"added"]
        && message[@"collection"]) {
        NSDictionary *object = [self _parseObjectAndAddToCollection:message];
        NSString *notificationName = [NSString stringWithFormat:@"%@_added", message[@"collection"]];
        [[NSNotificationCenter defaultCenter] postNotificationName:notificationName object:self userInfo:object];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"added" object:self userInfo:object];
    }
}

- (NSDictionary *)_parseObjectAndAddToCollection:(NSDictionary *)message {
    NSMutableDictionary *object = [NSMutableDictionary dictionaryWithDictionary:@{@"_id": message[@"id"]}];
    
    for (id key in message[@"fields"]) {
        object[key] = message[@"fields"][key];
    }
    
    if (!self.collections[message[@"collection"]]) {
        self.collections[message[@"collection"]] = [NSMutableArray array];
    }
    
    NSMutableArray *collection = self.collections[message[@"collection"]];
    
    [collection addObject:object];
    
    return object;
}

- (void)_handleRemovedMessage:(NSDictionary *)message msg:(NSString *)msg {
    if (msg && [msg isEqualToString:@"removed"]
        && message[@"collection"]) {
        [self _parseRemoved:message];
        NSString *notificationName = [NSString stringWithFormat:@"%@_removed", message[@"collection"]];
        [[NSNotificationCenter defaultCenter] postNotificationName:notificationName object:self];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"removed" object:self];
    }
}

- (void)_parseRemoved:(NSDictionary *)message {
    NSString *removedId = [message objectForKey:@"id"];
    int indexOfRemovedObject = 0;
    
    NSMutableArray *collection = self.collections[message[@"collection"]];
    
    for (NSDictionary *object in collection) {
        if ([object[@"_id"] isEqualToString:removedId]) {
            break;
        }
        indexOfRemovedObject++;
    }
    
    [collection removeObjectAtIndex:indexOfRemovedObject];
}

- (void)_handleChangedMessage:(NSDictionary *)message msg:(NSString *)msg {
    if (msg && [msg isEqualToString:@"changed"]
        && message[@"collection"]) {
        NSDictionary *object = [self _parseObjectAndUpdateCollection:message];
        NSString *notificationName = [NSString stringWithFormat:@"%@_changed", message[@"collection"]];
        [[NSNotificationCenter defaultCenter] postNotificationName:notificationName object:self userInfo:object];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"changed" object:self userInfo:object];
    }
}

- (NSDictionary *)_parseObjectAndUpdateCollection:(NSDictionary *)message {
    NSPredicate *pred = [NSPredicate predicateWithFormat:@"(_id like %@)", message[@"id"]];
    NSMutableArray *collection = self.collections[message[@"collection"]];
    NSArray *filteredArray = [collection filteredArrayUsingPredicate:pred];
    NSMutableDictionary *object = filteredArray[0];
    for (id key in message[@"fields"]) {
        object[key] = message[@"fields"][key];
    }
    return object;
}

@end