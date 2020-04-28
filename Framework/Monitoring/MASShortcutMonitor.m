#import "MASShortcutMonitor.h"
#import "MASHotKey.h"

@interface MASShortcutMonitor ()
@property(assign) EventHandlerRef eventHandlerRef;
@property(strong) NSMutableDictionary *hotKeys;
@property(strong) dispatch_block_t allModifierKeysReleasedAction;
@end

static OSStatus MASCarbonEventCallback(EventHandlerCallRef, EventRef, void*);

@implementation MASShortcutMonitor

#pragma mark Initialization

- (instancetype) init
{
    self = [super init];
    [self setHotKeys:[NSMutableDictionary dictionary]];
    
    EventTypeSpec hotKeyPressedSpec[2] = {
        { .eventClass = kEventClassKeyboard, .eventKind = kEventHotKeyPressed },
        { .eventClass = kEventClassKeyboard, .eventKind = kEventRawKeyModifiersChanged }
    };
    
    OSStatus status = InstallEventHandler(GetApplicationEventTarget(),
                                          MASCarbonEventCallback,
                                          2,
                                          hotKeyPressedSpec,
                                          (__bridge void*)self,
                                          &_eventHandlerRef);

    if (status != noErr) {
        return nil;
    }
    
    return self;
}

- (void) dealloc
{
    if (_eventHandlerRef) {
        RemoveEventHandler(_eventHandlerRef);
        _eventHandlerRef = NULL;
    }
}

+ (instancetype) sharedMonitor
{
    static dispatch_once_t once;
    static MASShortcutMonitor *sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

#pragma mark Registration

- (BOOL) registerShortcut: (MASShortcut*) shortcut withAction: (dispatch_block_t) action
{
    MASHotKey *hotKey = [MASHotKey registeredHotKeyWithShortcut:shortcut];
    if (hotKey) {
        [hotKey setAction:action];
        [_hotKeys setObject:hotKey forKey:shortcut];
        return YES;
    } else {
        return NO;
    }
}

- (void) registerActionForAllModifierKeysReleased: (dispatch_block_t) action
{
    _allModifierKeysReleasedAction = action;
}

- (void) unregisterShortcut: (MASShortcut*) shortcut
{
    if (shortcut) {
        [_hotKeys removeObjectForKey:shortcut];
    }
}

- (void) unregisterAllShortcuts
{
    [_hotKeys removeAllObjects];
}

- (BOOL) isShortcutRegistered: (MASShortcut*) shortcut
{
    return !![_hotKeys objectForKey:shortcut];
}

#pragma mark Event Handling

- (void) handleEvent: (EventRef) event
{
    if (GetEventClass(event) != kEventClassKeyboard) {
        return;
    }
    
    if (GetEventKind(event) == kEventRawKeyModifiersChanged && _allModifierKeysReleasedAction) {
        [self handleAllModifierKeysReleased:event];
    } else if (GetEventKind(event) == kEventHotKeyPressed) {
        [self handleHotKeyPressed:event];
    }
}

- (void) handleAllModifierKeysReleased: (EventRef) event
{
    UInt32 modifierKeys;
    OSStatus status = GetEventParameter(event, kEventParamKeyModifiers, typeUInt32, NULL, sizeof(modifierKeys), NULL, &modifierKeys);
    
    if (status != noErr) {
        return;
    }
    
    UInt32 cmdCtrlAltOptionMask = cmdKey | optionKey | controlKey;
    if ((modifierKeys & cmdCtrlAltOptionMask) == 0) {
        NSLog(@"hooooray! found it!");
        _allModifierKeysReleasedAction();
    }
}

- (void) handleHotKeyPressed: (EventRef) event
{
    EventHotKeyID hotKeyID;
    OSStatus status = GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID, NULL, sizeof(hotKeyID), NULL, &hotKeyID);
    if (status != noErr || hotKeyID.signature != MASHotKeySignature) {
        return;
    }
    
    [_hotKeys enumerateKeysAndObjectsUsingBlock:^(MASShortcut *shortcut, MASHotKey *hotKey, BOOL *stop) {
        if (hotKeyID.id == [hotKey carbonID]) {
            if ([hotKey action]) {
                dispatch_async(dispatch_get_main_queue(), [hotKey action]);
            }
            *stop = YES;
        }
    }];
}

@end

static OSStatus MASCarbonEventCallback(EventHandlerCallRef _, EventRef event, void *context)
{
    MASShortcutMonitor *dispatcher = (__bridge id)context;
    [dispatcher handleEvent:event];
    return noErr;
}
