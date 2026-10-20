#import "../XCHomePromotionRegistry.h"
#include <assert.h>
#include <stdio.h>

static unsigned tests;
#define CHECK(value) do { assert(value); ++tests; } while (0)

@interface XCEqualFixture : NSObject
@end
@implementation XCEqualFixture
- (BOOL)isEqual:(id)object { return [object isKindOfClass:XCEqualFixture.class]; }
- (NSUInteger)hash { return 7; }
@end

int main(void) {
    @autoreleasepool {
        XCHomePromotionRegistry *registry = [XCHomePromotionRegistry new];
        NSObject *table = [NSObject new], *otherTable = [NSObject new];
        NSObject *cell = [NSObject new], *normalCell = [NSObject new];
        CHECK([registry stateForTable:nil] == nil);
        CHECK([registry entryForCell:nil] == nil);
        CHECK([registry markCell:nil table:table hidden:NO interactive:YES] == nil);
        CHECK([registry queueTable:nil] == 0);
        CHECK([registry invalidateTable:nil].count == 0);
        CHECK(![registry isMarkedCell:cell table:table]);
        XCHomePromotionTableState *state = [registry stateForTable:table];
        CHECK(state.generation == 1);
        CHECK([registry queueTable:table] == 0);
        XCHomePromotionEntry *entry = [registry markCell:cell table:table hidden:NO interactive:YES];
        CHECK(entry.cell == cell && entry.table == table);
        CHECK(!entry.hidden && entry.interactive && !entry.applied);
        CHECK([registry isMarkedCell:cell table:table]);
        CHECK(![registry isMarkedCell:normalCell table:table]);
        CHECK(![registry isMarkedCell:cell table:otherTable]);
        CHECK([registry markCell:cell table:table hidden:YES interactive:NO] == entry);
        CHECK(!entry.hidden && entry.interactive);
        NSUInteger generation = [registry queueTable:table];
        CHECK(generation == 1);
        CHECK([registry queueTable:table] == 0);
        CHECK([registry beginReflowForTable:table generation:generation available:YES]);
        CHECK(state.reflowing && !state.dirty && !state.queued);
        CHECK([registry queueTable:table] == 0);
        state.reflowing = NO;
        CHECK([registry queueTable:table] == 0);

        XCHomePromotionEntry *forgotten = [registry forgetCell:cell];
        CHECK(forgotten == entry && [registry entryForCell:cell] == nil);
        CHECK(![registry isMarkedCell:cell table:table] && state.dirty);
        CHECK([registry forgetCell:cell] == nil);
        [registry markCell:cell table:table hidden:NO interactive:YES];
        generation = [registry queueTable:table];
        CHECK(generation == 1);
        NSArray *removed = [registry invalidateTable:table];
        CHECK(removed.count == 1 && state.generation == 2);
        CHECK(!state.dirty && !state.queued);
        CHECK(![registry isMarkedCell:cell table:table]);
        [registry markCell:cell table:table hidden:NO interactive:YES];
        NSUInteger fresh = [registry queueTable:table];
        CHECK(fresh == 2);
        CHECK(![registry beginReflowForTable:table generation:generation available:YES]);
        CHECK(state.queued); // Old async callback must not consume the fresh request.
        CHECK([registry beginReflowForTable:table generation:fresh available:YES]);
        state.reflowing = NO;

        [registry forgetCell:cell];
        fresh = [registry queueTable:table];
        CHECK(![registry beginReflowForTable:table generation:fresh available:NO]);
        CHECK(state.dirty && !state.queued && !state.reflowing);
        state.depth = 1;
        CHECK([registry queueTable:table] == 0);
        state.depth = 0;
        fresh = [registry queueTable:table];
        CHECK(fresh != 0);
        CHECK([registry beginReflowForTable:table generation:fresh available:YES]);
        state.reflowing = NO;

        entry = [registry markCell:cell table:nil hidden:NO interactive:YES];
        CHECK(entry.table == nil && ![registry isMarkedCell:cell table:table]);
        CHECK([registry markCell:cell table:table hidden:NO interactive:YES] == entry);
        CHECK([registry isMarkedCell:cell table:table]);
        CHECK([registry markCell:cell table:otherTable hidden:YES interactive:NO] == entry);
        CHECK(![registry isMarkedCell:cell table:table]);
        CHECK([registry isMarkedCell:cell table:otherTable]);
        CHECK(state.dirty && [registry stateForTable:otherTable].dirty);
        CHECK([registry invalidateTable:table].count == 0);
        CHECK([registry isMarkedCell:cell table:otherTable]);
        CHECK([registry invalidateTable:otherTable].count == 1);
        CHECK([registry entryForCell:cell] == nil);
        [registry markCell:normalCell table:table hidden:NO interactive:YES];
        CHECK(![registry isMarkedCell:cell table:table]); // A reused row position does not mark another cell.
        CHECK([registry isMarkedCell:normalCell table:table]);
        [registry forgetCell:normalCell];

        XCEqualFixture *equalCellA = [XCEqualFixture new], *equalCellB = [XCEqualFixture new];
        XCEqualFixture *equalTableA = [XCEqualFixture new], *equalTableB = [XCEqualFixture new];
        CHECK([equalCellA isEqual:equalCellB] && [equalTableA isEqual:equalTableB]);
        [registry markCell:equalCellA table:equalTableA hidden:NO interactive:YES];
        CHECK(![registry isMarkedCell:equalCellB table:equalTableA]);
        CHECK(![registry isMarkedCell:equalCellA table:equalTableB]);
        CHECK([registry stateForTable:equalTableA] != [registry stateForTable:equalTableB]);
        [registry forgetCell:equalCellA];

        __weak NSObject *weakCell;
        XCHomePromotionEntry *weakEntry;
        @autoreleasepool {
            __attribute__((objc_precise_lifetime)) NSObject *temporary = [NSObject new];
            weakCell = temporary;
            weakEntry = [registry markCell:temporary table:table hidden:NO interactive:YES];
            CHECK(weakEntry.cell == temporary);
        }
        CHECK(weakCell == nil && weakEntry.cell == nil);
        __weak NSObject *weakTable;
        @autoreleasepool {
            __attribute__((objc_precise_lifetime)) NSObject *temporary = [NSObject new];
            weakTable = temporary;
            entry = [registry markCell:cell table:temporary hidden:NO interactive:YES];
            CHECK(entry.table == temporary);
        }
        CHECK(weakTable == nil && entry.table == nil);
        CHECK(![registry isMarkedCell:cell table:nil]);
        CHECK([registry invalidateTable:table].count == 1); // Drop unattached stale mark.
        CHECK([registry entryForCell:cell] == nil);
        printf("PASS: %u production home-promotion registry cases\n", tests);
    }
    return 0;
}
