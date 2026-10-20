#pragma once
#import <Foundation/Foundation.h>

// Main-thread confined. Neither cells nor tables are retained; paths are never cached.
@interface XCHomePromotionEntry : NSObject
@property(nonatomic, weak) id cell, table;
@property(nonatomic) BOOL hidden, interactive, applied;
@property(nonatomic) NSUInteger generation;
@end
@implementation XCHomePromotionEntry
@end

@interface XCHomePromotionTableState : NSObject
@property(nonatomic) NSUInteger generation, depth;
@property(nonatomic) BOOL dirty, queued, reflowing;
@end
@implementation XCHomePromotionTableState
@end

@interface XCHomePromotionRegistry : NSObject {
    NSMapTable<id, XCHomePromotionEntry *> *_entries;
    NSMapTable<id, XCHomePromotionTableState *> *_tables;
}
- (XCHomePromotionTableState *)stateForTable:(id)table;
- (XCHomePromotionEntry *)entryForCell:(id)cell;
- (XCHomePromotionEntry *)markCell:(id)cell table:(id)table hidden:(BOOL)hidden interactive:(BOOL)interactive;
- (XCHomePromotionEntry *)forgetCell:(id)cell;
- (NSArray<XCHomePromotionEntry *> *)invalidateTable:(id)table;
- (BOOL)isMarkedCell:(id)cell table:(id)table;
- (NSUInteger)queueTable:(id)table;
- (BOOL)beginReflowForTable:(id)table generation:(NSUInteger)generation available:(BOOL)available;
@end

@implementation XCHomePromotionRegistry
- (instancetype)init {
    if ((self = [super init])) {
        NSPointerFunctionsOptions keys = NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality;
        _entries = [NSMapTable mapTableWithKeyOptions:keys valueOptions:NSPointerFunctionsStrongMemory];
        _tables = [NSMapTable mapTableWithKeyOptions:keys valueOptions:NSPointerFunctionsStrongMemory];
    }
    return self;
}
- (XCHomePromotionTableState *)stateForTable:(id)table {
    if (!table) return nil;
    XCHomePromotionTableState *state = [_tables objectForKey:table];
    if (!state) {
        state = [XCHomePromotionTableState new]; state.generation = 1;
        [_tables setObject:state forKey:table];
    }
    return state;
}
- (XCHomePromotionEntry *)entryForCell:(id)cell {
    return cell ? [_entries objectForKey:cell] : nil;
}
- (XCHomePromotionEntry *)markCell:(id)cell table:(id)table hidden:(BOOL)hidden interactive:(BOOL)interactive {
    if (!cell) return nil;
    XCHomePromotionEntry *entry = [self entryForCell:cell];
    XCHomePromotionTableState *state = [self stateForTable:table];
    if (!entry) {
        entry = [XCHomePromotionEntry new]; entry.cell = cell;
        entry.hidden = hidden; entry.interactive = interactive;
        [_entries setObject:entry forKey:cell];
        state.dirty = YES;
    }
    if (entry.table != table || entry.generation != state.generation) {
        [self stateForTable:entry.table].dirty = YES;
        entry.table = table; entry.generation = state.generation; state.dirty = YES;
    }
    return entry;
}
- (XCHomePromotionEntry *)forgetCell:(id)cell {
    XCHomePromotionEntry *entry = [self entryForCell:cell];
    if (entry) { [_entries removeObjectForKey:cell]; [self stateForTable:entry.table].dirty = YES; }
    return entry;
}
- (NSArray<XCHomePromotionEntry *> *)invalidateTable:(id)table {
    if (!table) return @[];
    XCHomePromotionTableState *state = [self stateForTable:table];
    ++state.generation; state.queued = NO; state.dirty = NO;
    NSMutableArray *removed = [NSMutableArray array];
    for (id cell in _entries.keyEnumerator.allObjects) {
        XCHomePromotionEntry *entry = [self entryForCell:cell];
        // Unattached marks cannot be proven to belong to the new data generation.
        if (!entry.table || entry.table == table) { [removed addObject:entry]; [_entries removeObjectForKey:cell]; }
    }
    return removed;
}
- (BOOL)isMarkedCell:(id)cell table:(id)table {
    XCHomePromotionEntry *entry = [self entryForCell:cell];
    return cell && table && entry.cell == cell && entry.table == table &&
        entry.generation == [self stateForTable:table].generation;
}
- (NSUInteger)queueTable:(id)table {
    XCHomePromotionTableState *state = [self stateForTable:table];
    if (!state.dirty || state.queued || state.depth || state.reflowing) return 0;
    state.queued = YES; return state.generation;
}
- (BOOL)beginReflowForTable:(id)table generation:(NSUInteger)generation available:(BOOL)available {
    XCHomePromotionTableState *state = [self stateForTable:table];
    if (!generation || state.generation != generation || !state.queued) return NO;
    state.queued = NO;
    if (!available || state.depth || state.reflowing || !state.dirty) return NO;
    state.dirty = NO; state.reflowing = YES; return YES;
}
@end
