// Links the ACTUAL production runtime. Foundation fixtures and a void Substrate
// backend verify installer contracts, NOT real Substrate, UIKit, WeChat or PAC.
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import "WCKRuntime.h"
#import "WCKSettings.h"
#import "WCKPolicy.h"
#include <limits.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#if __has_feature(ptrauth_calls)
#import <ptrauth.h>
#endif

// Observation only: the signature decision is still made by production code.
// Keep the last Method per thread so a failure prints bounded, actionable metadata.
static _Thread_local Method observedMethod;
static void describeObservedMethod(void) {
    if (!observedMethod) return;
    const char *encoding=method_getTypeEncoding(observedMethod);
    unsigned count=method_getNumberOfArguments(observedMethod);
    char *result=method_copyReturnType(observedMethod);
    fprintf(stderr,"LAST METHOD encoding=%s arity=%u return=%s\n",
        encoding ? encoding : "<null>",count,result ? result : "<null>");
    free(result);
    for (unsigned i=0;i<count && i<8;++i) {
        char *type=method_copyArgumentType(observedMethod,i);
        fprintf(stderr,"  argument[%u]=%s\n",i,type ? type : "<null>");
        free(type);
    }
}
static BOOL observeMethodMatches(Class cls, SEL selector, const char *result,
                                 const char *const *arguments, unsigned count) {
    observedMethod=cls && selector ? class_getInstanceMethod(cls,selector) : NULL;
    return WCKMethodMatches(cls,selector,result,arguments,count);
}

static atomic_uint checks;
#define CHECK_ID(tag, expr) do { atomic_fetch_add(&checks,1); if (!(expr)) { \
    fprintf(stderr, "RUNTIME ASSERT[%s] line %d: %s\n", tag, __LINE__, #expr); \
    describeObservedMethod(); \
    exit(86); } } while (0)

static atomic_uint hookCalls, resolveCalls, originalCalls, replacementCalls, otherCalls, foreignCalls, albumCalls;
static IMP originalIMP, otherOriginalIMP, trampolineNext, foreignNext;
static BOOL apiPresent=YES, mutateMethodOnResolve;
typedef NS_ENUM(NSUInteger, BackendMode) {
    BackendNormal, BackendTrampoline, BackendNoop, BackendNoopFilled,
    BackendNoTouch, BackendNull, BackendNullInFlight, BackendRecursive,
    BackendException, BackendReentrant, BackendCrossThread, BackendForeignAfter
};
static BackendMode backendMode=BackendNormal;

static BOOL sameIMP(IMP a, IMP b) {
#if __has_feature(ptrauth_calls)
    return ptrauth_strip(a,ptrauth_key_function_pointer)==ptrauth_strip(b,ptrauth_key_function_pointer);
#else
    return a==b;
#endif
}
static NSInteger invoke(id receiver, SEL selector, NSInteger value) {
    return ((NSInteger (*)(id,SEL,NSInteger))objc_msgSend)(receiver,selector,value);
}
static NSInteger sentinel(id receiver, SEL selector, NSInteger value) { return value-99; }

@interface WCKRuntimeFixture : NSObject
- (NSInteger)value:(NSInteger)value;
- (NSInteger)otherValue:(NSInteger)value;
- (BOOL)booleanValue;
- (void)takeRange:(NSRange)range;
+ (NSInteger)classValue:(NSInteger)value;
@end
@implementation WCKRuntimeFixture
- (NSInteger)value:(NSInteger)value { atomic_fetch_add(&originalCalls,1); return value+100; }
- (NSInteger)otherValue:(NSInteger)value { atomic_fetch_add(&originalCalls,1); return value+200; }
- (BOOL)booleanValue { return YES; }
- (void)takeRange:(NSRange)range { (void)range; }
+ (NSInteger)classValue:(NSInteger)value { atomic_fetch_add(&originalCalls,1); return value+100; }
@end
@interface WCKRuntimeChild : WCKRuntimeFixture @end
@implementation WCKRuntimeChild @end
@interface WCKRuntimeSibling : WCKRuntimeFixture @end
@implementation WCKRuntimeSibling @end

static NSInteger replacement(id receiver, SEL selector, NSInteger value) {
    CHECK_ID("original.callable",originalIMP && !sameIMP(originalIMP,(IMP)replacement));
    atomic_fetch_add(&replacementCalls,1);
    return ((NSInteger (*)(id,SEL,NSInteger))originalIMP)(receiver,selector,value)+1000;
}
static NSInteger otherReplacement(id receiver, SEL selector, NSInteger value) {
    CHECK_ID("original.other-callable",otherOriginalIMP && !sameIMP(otherOriginalIMP,(IMP)otherReplacement));
    atomic_fetch_add(&otherCalls,1);
    return ((NSInteger (*)(id,SEL,NSInteger))otherOriginalIMP)(receiver,selector,value)+2000;
}
static NSInteger nextTrampoline(id receiver, SEL selector, NSInteger value) {
    CHECK_ID("original.trampoline-callable",trampolineNext && !sameIMP(trampolineNext,(IMP)nextTrampoline));
    return ((NSInteger (*)(id,SEL,NSInteger))trampolineNext)(receiver,selector,value);
}
static NSInteger foreignReplacement(id receiver, SEL selector, NSInteger value) {
    CHECK_ID("foreign.chain-callable",foreignNext && !sameIMP(foreignNext,(IMP)foreignReplacement));
    atomic_fetch_add(&foreignCalls,1);
    return ((NSInteger (*)(id,SEL,NSInteger))foreignNext)(receiver,selector,value)+7000;
}
static IMP implementation(Class cls, SEL selector) {
    Method m=class_getInstanceMethod(cls,selector);
    CHECK_ID("fixture.method-present",m!=NULL);
    return method_getImplementation(m);
}
static BOOL ownsMethod(Class cls, SEL selector) {
    unsigned n=0; Method *methods=class_copyMethodList(cls,&n); BOOL found=NO;
    for (unsigned i=0;i<n;++i) if (method_getName(methods[i])==selector) found=YES;
    free(methods); return found;
}
// Fake backend must add an inherited target to the requested class, not change
// the superclass Method returned by class_getInstanceMethod.
static void installLocal(Class cls, SEL selector, IMP imp) {
    Method m=class_getInstanceMethod(cls,selector);
    CHECK_ID("backend.target-present",m && imp);
    const char *types=method_getTypeEncoding(m);
    if (!class_addMethod(cls,selector,imp,types)) class_replaceMethod(cls,selector,imp,types);
}
static BOOL installInteger(Class cls, SEL selector, IMP imp, IMP *old) {
    const char *args[]={@encode(NSInteger)};
    return WCKInstallHook(cls,selector,imp,old,@encode(NSInteger),args,1);
}
static NSString *statusKey(Class cls, SEL selector) {
    return [NSString stringWithFormat:@"hook.%s/%s/%s",
        cls && class_isMetaClass(cls) ? "class" : "instance",
        cls ? class_getName(cls) : "<missing>",selector ? sel_getName(selector) : "<missing>"];
}
static void expectStatus(Class cls, SEL selector, NSString *expected) {
    CHECK_ID("status.exact",[WCKRuntimeStatuses()[statusKey(cls,selector)] isEqual:expected]);
}

// Only WCKRuntime.m is compiled with -Ddlsym=WCKRuntimeTestDlsym. Foundation
// and all other production translation units keep their real dlsym binding.
// MSHookMessageEx really returns VOID; never manufacture a BOOL backend API.
static void substrateStub(Class cls, SEL selector, IMP imp, IMP *backendOriginal) {
    atomic_fetch_add(&hookCalls,1);
    CHECK_ID("backend.output-present",backendOriginal!=NULL);
    if (backendMode==BackendReentrant)
        CHECK_ID("reentry.backend-once",atomic_load(&hookCalls)==1);
    IMP before=implementation(cls,selector);
    if (backendMode==BackendNoop) return;
    if (backendMode==BackendNoopFilled) { *backendOriginal=before; return; }
    if (backendMode==BackendTrampoline || backendMode==BackendForeignAfter) {
        trampolineNext=before; *backendOriginal=(IMP)nextTrampoline;
    } else if (backendMode==BackendNull || backendMode==BackendNullInFlight) {
        *backendOriginal=NULL;
    } else if (backendMode==BackendRecursive) {
        *backendOriginal=imp;
    } else if (backendMode!=BackendNoTouch) {
        *backendOriginal=before;
    }
    installLocal(cls,selector,imp);
    if (backendMode==BackendNullInFlight) {
        CHECK_ID("inflight.result",invoke([cls new],selector,7)==1107);
        CHECK_ID("inflight.original-once",atomic_load(&originalCalls)==1);
    }
    if (backendMode==BackendReentrant) {
        IMP secondOwner=(IMP)sentinel;
        CHECK_ID("reentry.same-owner-skipped",!installInteger(cls,selector,imp,&secondOwner));
        CHECK_ID("reentry.output-untouched",sameIMP(secondOwner,(IMP)sentinel));
        CHECK_ID("reentry.live-original",sameIMP(originalIMP,before));
        CHECK_ID("reentry.different-owner-skipped",!installInteger(cls,selector,(IMP)otherReplacement,&secondOwner));
        CHECK_ID("reentry.no-extra-backend",atomic_load(&hookCalls)==1);
    }
    if (backendMode==BackendCrossThread) {
        dispatch_semaphore_t done=dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{ @autoreleasepool {
            IMP otherStorage=(IMP)sentinel;
            CHECK_ID("cross-thread.pending-skipped",!installInteger(cls,selector,imp,&otherStorage));
            CHECK_ID("cross-thread.output-untouched",sameIMP(otherStorage,(IMP)sentinel));
            dispatch_semaphore_signal(done);
        } });
        CHECK_ID("cross-thread.no-deadlock",dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC))==0);
        CHECK_ID("cross-thread.backend-once",atomic_load(&hookCalls)==1);
    }
    if (backendMode==BackendForeignAfter) {
        foreignNext=imp; installLocal(cls,selector,(IMP)foreignReplacement);
    }
    if (backendMode==BackendException)
        @throw [NSException exceptionWithName:@"WCKFixtureBackendException" reason:@"after publication" userInfo:nil];
}
static void wrongFreshMethod(id receiver, SEL selector, NSInteger value) { (void)value; }
void *WCKRuntimeTestDlsym(void *handle, const char *symbol) {
    atomic_fetch_add(&resolveCalls,1);
    CHECK_ID("backend.exact-symbol",handle==RTLD_DEFAULT && symbol && strcmp(symbol,"MSHookMessageEx")==0);
    if (mutateMethodOnResolve) {
        mutateMethodOnResolve=NO;
        NSString *encoding=[@"v@:" stringByAppendingString:[NSString stringWithUTF8String:@encode(NSInteger)]];
        CHECK_ID("fixture.fresh-method-added",class_addMethod(WCKRuntimeChild.class,@selector(value:),(IMP)wrongFreshMethod,encoding.UTF8String));
    }
    return apiPresent ? (void *)substrateStub : NULL;
}

static id annotatedObject(id receiver, SEL selector, id value) { return value; }
static void pointerArgument(id receiver, SEL selector, int *value) { (void)value; }
static void blockArgument(id receiver, SEL selector, dispatch_block_t block) { (void)block; }
static dispatch_block_t blockReturn(id receiver, SEL selector) { return ^{}; }
static Class signatureFixture(void) {
    Class cls=objc_allocateClassPair(NSObject.class,"WCKRuntimeSignatureFixture",0);
    CHECK_ID("fixture.signature-class",cls!=Nil);
    // Apple Method metadata uses plain @. Quoted object class names are not
    // consumed by objc4's Method parser; test those separately in the C policy.
    CHECK_ID("fixture.object",class_addMethod(cls,NSSelectorFromString(@"annotated:"),(IMP)annotatedObject,"@@:@"));
    CHECK_ID("fixture.malformed-annotation",class_addMethod(cls,NSSelectorFromString(@"malformedAnnotated:"),(IMP)annotatedObject,"@\"NSString\"@:@\"NSObject\""));
    CHECK_ID("fixture.block",class_addMethod(cls,NSSelectorFromString(@"block:"),(IMP)blockArgument,"v@:@?"));
    CHECK_ID("fixture.block-return",class_addMethod(cls,NSSelectorFromString(@"blockValue"),(IMP)blockReturn,"@?@:"));
    CHECK_ID("fixture.qualified-block",class_addMethod(cls,NSSelectorFromString(@"qualifiedBlock:"),(IMP)blockArgument,"v@:r@?"));
    for (const char *q="rnNoOV";*q;++q) {
        NSString *name=[NSString stringWithFormat:@"pointer_%c:",*q];
        NSString *types=[NSString stringWithFormat:@"v@:%c^i",*q];
        CHECK_ID("fixture.qualified-pointer",class_addMethod(cls,NSSelectorFromString(name),(IMP)pointerArgument,types.UTF8String));
    }
    // R is accepted as a qualifier by the C policy, but not by objc4's Method parser.
    CHECK_ID("fixture.malformed-byref",class_addMethod(cls,NSSelectorFromString(@"pointer_R:"),(IMP)pointerArgument,"v@:R^i"));
    objc_registerClassPair(cls); return cls;
}
static void signatureCases(void) {
    Class cls=WCKRuntimeFixture.class; SEL sel=@selector(value:);
    const char *integer[]={@encode(NSInteger)}, *unsignedInteger[]={@encode(NSUInteger)};
    const char *object[]={"@"}, *two[]={@encode(NSInteger),@encode(NSInteger)};
    CHECK_ID("signature.valid",observeMethodMatches(cls,sel,@encode(NSInteger),integer,1));
    CHECK_ID("signature.return",!observeMethodMatches(cls,sel,@encode(NSUInteger),integer,1));
    CHECK_ID("signature.argument",!observeMethodMatches(cls,sel,@encode(NSInteger),unsignedInteger,1));
    CHECK_ID("signature.object-scalar",!observeMethodMatches(cls,sel,@encode(NSInteger),object,1));
    CHECK_ID("signature.arity",!observeMethodMatches(cls,sel,@encode(NSInteger),NULL,0));
    CHECK_ID("signature.arity-extra",!observeMethodMatches(cls,sel,@encode(NSInteger),two,2));
    CHECK_ID("signature.overflow",!observeMethodMatches(cls,sel,@encode(NSInteger),integer,UINT_MAX));
    CHECK_ID("signature.overflow-minus-one",!observeMethodMatches(cls,sel,@encode(NSInteger),integer,UINT_MAX-1));
    CHECK_ID("signature.zero-arguments",observeMethodMatches(cls,@selector(booleanValue),@encode(BOOL),NULL,0));
    const char *range[]={@encode(NSRange)}, *wrongRange[]={"{WCKWrongRange=QQ}"};
    CHECK_ID("signature.struct",observeMethodMatches(cls,@selector(takeRange:),"v",range,1));
    CHECK_ID("signature.struct-distinct",!observeMethodMatches(cls,@selector(takeRange:),"v",wrongRange,1));
}
static void blockObjectCases(void) {
    Class cls=signatureFixture(); const char *object[]={"@"}, *block[]={"@?"};
    CHECK_ID("signature.object",observeMethodMatches(cls,NSSelectorFromString(@"annotated:"),"@",object,1));
    CHECK_ID("signature.annotated-return-policy",WCKTypeMatches("@\"NSString\"","@"));
    CHECK_ID("signature.annotated-argument-policy",WCKTypeMatches("@\"NSObject\"","@"));
    CHECK_ID("signature.malformed-annotation",!observeMethodMatches(cls,NSSelectorFromString(@"malformedAnnotated:"),"@",object,1));
    CHECK_ID("signature.block-argument",!observeMethodMatches(cls,NSSelectorFromString(@"block:"),"v",object,1));
    CHECK_ID("signature.block-positive",observeMethodMatches(cls,NSSelectorFromString(@"block:"),"v",block,1));
    CHECK_ID("signature.object-not-block",!observeMethodMatches(cls,NSSelectorFromString(@"annotated:"),"@",block,1));
    CHECK_ID("signature.block-return",!observeMethodMatches(cls,NSSelectorFromString(@"blockValue"),"@",NULL,0));
    CHECK_ID("signature.block-return-positive",observeMethodMatches(cls,NSSelectorFromString(@"blockValue"),"@?",NULL,0));
    CHECK_ID("signature.qualified-block",!observeMethodMatches(cls,NSSelectorFromString(@"qualifiedBlock:"),"v",object,1));
}
static void qualifierCases(void) {
    Class cls=signatureFixture(); const char *pointer[]={@encode(int *)}, *wrong[]={@encode(long long *)};
    CHECK_ID("signature.byref-policy",WCKTypeMatches("R^i",@encode(int *)));
    CHECK_ID("signature.malformed-byref",!observeMethodMatches(cls,NSSelectorFromString(@"pointer_R:"),"v",pointer,1));
    for (const char *q="rnNoOV";*q;++q) {
        SEL sel=NSSelectorFromString([NSString stringWithFormat:@"pointer_%c:",*q]);
        CHECK_ID("signature.qualifier",observeMethodMatches(cls,sel,"v",pointer,1));
        CHECK_ID("signature.qualifier-not-wildcard",!observeMethodMatches(cls,sel,"v",wrong,1));
    }
}
static void missingCases(void) {
    Class cls=WCKRuntimeFixture.class; SEL sel=@selector(value:), missing=NSSelectorFromString(@"absentMethod:");
    IMP old=(IMP)sentinel; const char *args[]={@encode(NSInteger)};
    CHECK_ID("missing.class-match",!observeMethodMatches(Nil,sel,@encode(NSInteger),args,1));
    CHECK_ID("missing.selector-match",!observeMethodMatches(cls,NULL,@encode(NSInteger),args,1));
    CHECK_ID("missing.class-install",!installInteger(Nil,sel,(IMP)replacement,&old));
    expectStatus(Nil,sel,@"target_missing");
    CHECK_ID("missing.selector-install",!installInteger(cls,missing,(IMP)replacement,&old));
    expectStatus(cls,missing,@"target_missing");
    CHECK_ID("missing.null-selector-install",!installInteger(cls,NULL,(IMP)replacement,&old));
    expectStatus(cls,NULL,@"target_missing");
    CHECK_ID("missing.output-untouched",sameIMP(old,(IMP)sentinel));
    CHECK_ID("missing.backend-not-resolved",atomic_load(&resolveCalls)==0 && atomic_load(&hookCalls)==0);
}
static void invalidCases(void) {
    Class cls=WCKRuntimeFixture.class; SEL sel=@selector(value:); IMP old=(IMP)sentinel;
    const char *args[]={@encode(NSInteger)}, *nullType[]={NULL}, *emptyType[]={""};
    CHECK_ID("invalid.return-null",!observeMethodMatches(cls,sel,NULL,args,1));
    CHECK_ID("invalid.return-empty",!observeMethodMatches(cls,sel,"",args,1));
    CHECK_ID("invalid.arguments-null",!observeMethodMatches(cls,sel,@encode(NSInteger),NULL,1));
    CHECK_ID("invalid.argument-null",!observeMethodMatches(cls,sel,@encode(NSInteger),nullType,1));
    CHECK_ID("invalid.argument-empty",!observeMethodMatches(cls,sel,@encode(NSInteger),emptyType,1));
    CHECK_ID("invalid.replacement",!installInteger(cls,sel,NULL,&old));
    expectStatus(cls,sel,@"install_failed.invalid_argument");
    CHECK_ID("invalid.original-slot",!installInteger(cls,sel,(IMP)replacement,NULL));
    expectStatus(cls,sel,@"install_failed.invalid_argument");
    CHECK_ID("invalid.output-untouched",sameIMP(old,(IMP)sentinel));
    CHECK_ID("invalid.no-backend",atomic_load(&resolveCalls)==0 && atomic_load(&hookCalls)==0);
}
static void signatureRetry(void) {
    Class cls=WCKRuntimeFixture.class; SEL sel=@selector(value:); const char *args[]={@encode(NSInteger)};
    originalIMP=(IMP)sentinel;
    CHECK_ID("signature.retry-rejected",!WCKInstallHook(cls,sel,(IMP)replacement,&originalIMP,"v",args,1));
    expectStatus(cls,sel,@"install_failed.signature_mismatch");
    CHECK_ID("signature.retry-untouched",sameIMP(originalIMP,(IMP)sentinel) && atomic_load(&hookCalls)==0);
    CHECK_ID("signature.retry-success",installInteger(cls,sel,(IMP)replacement,&originalIMP));
    expectStatus(cls,sel,@"installed");
}
static void apiRetry(void) {
    Class cls=WCKRuntimeFixture.class; SEL sel=@selector(value:); originalIMP=(IMP)sentinel; apiPresent=NO;
    CHECK_ID("api.missing",!installInteger(cls,sel,(IMP)replacement,&originalIMP));
    expectStatus(cls,sel,@"hook_api_missing");
    CHECK_ID("api.no-attempt",atomic_load(&hookCalls)==0 && sameIMP(originalIMP,(IMP)sentinel));
    apiPresent=YES;
    CHECK_ID("api.late-success",installInteger(cls,sel,(IMP)replacement,&originalIMP));
    CHECK_ID("api.attempt-once",atomic_load(&hookCalls)==1);
    expectStatus(cls,sel,@"installed");
}
static void originalCases(BOOL trampoline) {
    Class cls=WCKRuntimeFixture.class; SEL sel=@selector(value:); IMP before=implementation(cls,sel);
    backendMode=trampoline ? BackendTrampoline : BackendNormal;
    CHECK_ID("original.install",installInteger(cls,sel,(IMP)replacement,&originalIMP));
    CHECK_ID("original.retained",originalIMP && !sameIMP(originalIMP,(IMP)replacement));
    if (trampoline) CHECK_ID("original.trampoline-retained",sameIMP(originalIMP,(IMP)nextTrampoline) && !sameIMP(originalIMP,before));
    else CHECK_ID("original.snapshot-retained",sameIMP(originalIMP,before));
    CHECK_ID("original.dispatch",invoke([cls new],sel,9)==1109);
    CHECK_ID("original.invoked-once",atomic_load(&originalCalls)==1 && atomic_load(&replacementCalls)==1);
    CHECK_ID("original.direct-call",((NSInteger (*)(id,SEL,NSInteger))originalIMP)([cls new],sel,3)==103);
    CHECK_ID("original.direct-once",atomic_load(&originalCalls)==2 && atomic_load(&replacementCalls)==1);
    expectStatus(cls,sel,@"installed");
}
static void backendFailure(BackendMode mode, NSString *expected) {
    Class cls=WCKRuntimeFixture.class; SEL sel=@selector(value:); IMP before=implementation(cls,sel); backendMode=mode;
    BOOL result=installInteger(cls,sel,(IMP)replacement,&originalIMP);
    CHECK_ID("postcondition.noop-rejected",!result);
    expectStatus(cls,sel,expected);
    CHECK_ID("failure.safe-original",sameIMP(originalIMP,before));
    BOOL noPatch=mode==BackendNoop || mode==BackendNoopFilled;
    CHECK_ID("quarantine.target-retained",sameIMP(implementation(cls,sel),noPatch ? before : (IMP)replacement));
    unsigned prior=atomic_load(&originalCalls);
    CHECK_ID("failure.dispatch-safe",invoke([cls new],sel,5)==(noPatch ? 105 : 1105));
    CHECK_ID("failure.original-once",atomic_load(&originalCalls)==prior+1);
}
static void recursiveCase(void) {
    Class cls=WCKRuntimeFixture.class; SEL sel=@selector(value:); IMP before=implementation(cls,sel); backendMode=BackendRecursive;
    CHECK_ID("original.recursive-rejected",!installInteger(cls,sel,(IMP)replacement,&originalIMP));
    expectStatus(cls,sel,@"attempted_unverified.original_imp_recursive");
    CHECK_ID("original.recursive-output-safe",sameIMP(originalIMP,before));
    CHECK_ID("original.recursive-dispatch-safe",invoke([cls new],sel,8)==1108);
}
static void duplicateCases(void) {
    Class cls=WCKRuntimeFixture.class; SEL sel=@selector(value:); backendMode=BackendTrampoline;
    CHECK_ID("idempotent.first",installInteger(cls,sel,(IMP)replacement,&originalIMP));
    IMP next=originalIMP; originalIMP=NULL; apiPresent=NO;
    CHECK_ID("idempotent.same-owner",installInteger(cls,sel,(IMP)replacement,&originalIMP));
    CHECK_ID("idempotent.backend-once",atomic_load(&hookCalls)==1 && atomic_load(&resolveCalls)==1);
    CHECK_ID("idempotent.saved-next",sameIMP(originalIMP,next));
    IMP otherStorage=NULL;
    CHECK_ID("idempotent.new-storage",installInteger(cls,sel,(IMP)replacement,&otherStorage));
    CHECK_ID("idempotent.new-storage-next",sameIMP(otherStorage,next));
    CHECK_ID("idempotent.no-rehook",atomic_load(&hookCalls)==1);
    CHECK_ID("idempotent.dispatch",invoke([cls new],sel,6)==1106);
    expectStatus(cls,sel,@"installed");
}
static void conflictCases(void) {
    Class cls=WCKRuntimeFixture.class; SEL sel=@selector(value:);
    CHECK_ID("conflict.first",installInteger(cls,sel,(IMP)replacement,&originalIMP));
    IMP next=originalIMP, differentStorage=(IMP)sentinel;
    CHECK_ID("conflict.different-replacement",!installInteger(cls,sel,(IMP)otherReplacement,&differentStorage));
    CHECK_ID("conflict.other-storage-untouched",sameIMP(differentStorage,(IMP)sentinel));
    CHECK_ID("conflict.same-storage",!installInteger(cls,sel,(IMP)otherReplacement,&originalIMP));
    CHECK_ID("conflict.live-next-untouched",sameIMP(originalIMP,next));
    CHECK_ID("conflict.target-untouched",sameIMP(implementation(cls,sel),(IMP)replacement));
    CHECK_ID("conflict.backend-once",atomic_load(&hookCalls)==1);
    expectStatus(cls,sel,@"conflict_skipped");
    CHECK_ID("conflict.owner-can-repeat",installInteger(cls,sel,(IMP)replacement,&originalIMP));
    expectStatus(cls,sel,@"installed");
}
static void existingReplacementCase(void) {
    Class cls=WCKRuntimeFixture.class; SEL sel=@selector(value:); installLocal(cls,sel,(IMP)replacement);
    originalIMP=(IMP)sentinel;
    CHECK_ID("conflict.preexisting-replacement",!installInteger(cls,sel,(IMP)replacement,&originalIMP));
    CHECK_ID("conflict.no-recursive-original",sameIMP(originalIMP,(IMP)sentinel));
    CHECK_ID("conflict.no-backend",atomic_load(&hookCalls)==0);
    expectStatus(cls,sel,@"conflict_skipped");
}
static void quarantineCases(void) {
    Class cls=WCKRuntimeFixture.class; SEL sel=@selector(value:); backendMode=BackendNull;
    CHECK_ID("quarantine.first-unverified",!installInteger(cls,sel,(IMP)replacement,&originalIMP));
    IMP safe=originalIMP; backendMode=BackendNormal;
    CHECK_ID("quarantine.repeat-unverified",!installInteger(cls,sel,(IMP)replacement,&originalIMP));
    CHECK_ID("quarantine.no-rehook",atomic_load(&hookCalls)==1);
    CHECK_ID("quarantine.saved-safe-next",sameIMP(originalIMP,safe));
    IMP otherStorage=NULL;
    CHECK_ID("quarantine.new-storage-unverified",!installInteger(cls,sel,(IMP)replacement,&otherStorage));
    CHECK_ID("quarantine.new-storage-safe",sameIMP(otherStorage,safe));
    CHECK_ID("quarantine.no-broader-block",installInteger(cls,@selector(otherValue:),(IMP)otherReplacement,&otherOriginalIMP));
    CHECK_ID("quarantine.other-dispatch",invoke([cls new],@selector(otherValue:),2)==2202);
    CHECK_ID("quarantine.target-still-safe",invoke([cls new],sel,2)==1102);
    expectStatus(cls,sel,@"attempted_unverified.original_imp_null");
    expectStatus(cls,@selector(otherValue:),@"installed");
}
static void reentrantCases(void) {
    Class cls=WCKRuntimeFixture.class; SEL sel=@selector(value:); backendMode=BackendReentrant;
    CHECK_ID("reentry.outer-success",installInteger(cls,sel,(IMP)replacement,&originalIMP));
    CHECK_ID("reentry.final-once",atomic_load(&hookCalls)==1);
    CHECK_ID("reentry.original-dispatch",invoke([cls new],sel,4)==1104);
    expectStatus(cls,sel,@"installed");
}
static void crossThreadCases(void) {
    Class cls=WCKRuntimeFixture.class; SEL sel=@selector(value:); backendMode=BackendCrossThread;
    CHECK_ID("cross-thread.outer-success",installInteger(cls,sel,(IMP)replacement,&originalIMP));
    CHECK_ID("cross-thread.final-once",atomic_load(&hookCalls)==1);
    CHECK_ID("cross-thread.original-dispatch",invoke([cls new],sel,4)==1104);
    expectStatus(cls,sel,@"installed");
}
static void freshMethodCases(void) {
    Class cls=WCKRuntimeChild.class; SEL sel=@selector(value:);
    IMP parentBefore=implementation(WCKRuntimeFixture.class,sel); originalIMP=(IMP)sentinel;
    CHECK_ID("signature.fresh-inherited",!ownsMethod(cls,sel)); mutateMethodOnResolve=YES;
    CHECK_ID("signature.fresh-method-check",!installInteger(cls,sel,(IMP)replacement,&originalIMP));
    CHECK_ID("signature.fresh-no-backend",atomic_load(&hookCalls)==0 && atomic_load(&resolveCalls)==1);
    CHECK_ID("signature.fresh-output-untouched",sameIMP(originalIMP,(IMP)sentinel));
    CHECK_ID("signature.fresh-parent-untouched",sameIMP(implementation(WCKRuntimeFixture.class,sel),parentBefore));
    CHECK_ID("signature.fresh-sibling-untouched",sameIMP(implementation(WCKRuntimeSibling.class,sel),parentBefore));
    CHECK_ID("signature.fresh-method-preserved",sameIMP(implementation(cls,sel),(IMP)wrongFreshMethod));
    expectStatus(cls,sel,@"install_failed.signature_mismatch");
}
static void threadedCases(void) {
    Class cls=WCKRuntimeFixture.class; SEL sel=@selector(value:);
    dispatch_apply(32,dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^(size_t n) {
        @autoreleasepool { (void)n; installInteger(cls,sel,(IMP)replacement,&originalIMP); }
    });
    CHECK_ID("thread.backend-once",atomic_load(&hookCalls)==1);
    CHECK_ID("thread.final-idempotent",installInteger(cls,sel,(IMP)replacement,&originalIMP));
    CHECK_ID("thread.safe-dispatch",invoke([cls new],sel,4)==1104);
    expectStatus(cls,sel,@"installed");
}
static void inheritedCases(BOOL classMethod, BOOL failure) {
    Class parent=classMethod ? object_getClass(WCKRuntimeFixture.class) : WCKRuntimeFixture.class;
    Class child=classMethod ? object_getClass(WCKRuntimeChild.class) : WCKRuntimeChild.class;
    Class sibling=classMethod ? object_getClass(WCKRuntimeSibling.class) : WCKRuntimeSibling.class;
    SEL sel=classMethod ? @selector(classValue:) : @selector(value:);
    IMP before=implementation(parent,sel);
    CHECK_ID("inheritance.initially-inherited",!ownsMethod(child,sel));
    backendMode=failure ? BackendNull : BackendNormal;
    CHECK_ID("inheritance.install-result",installInteger(child,sel,(IMP)replacement,&originalIMP)==!failure);
    CHECK_ID("inheritance.class-local",ownsMethod(child,sel));
    CHECK_ID("inheritance.parent-untouched",sameIMP(implementation(parent,sel),before));
    CHECK_ID("inheritance.sibling-untouched",sameIMP(implementation(sibling,sel),before));
    CHECK_ID("inheritance.target-retained",sameIMP(implementation(child,sel),(IMP)replacement));
    id childReceiver=classMethod ? (id)WCKRuntimeChild.class : [WCKRuntimeChild new];
    id parentReceiver=classMethod ? (id)WCKRuntimeFixture.class : [WCKRuntimeFixture new];
    id siblingReceiver=classMethod ? (id)WCKRuntimeSibling.class : [WCKRuntimeSibling new];
    CHECK_ID("inheritance.child-dispatch",invoke(childReceiver,sel,1)==1101);
    CHECK_ID("inheritance.parent-dispatch",invoke(parentReceiver,sel,1)==101);
    CHECK_ID("inheritance.sibling-dispatch",invoke(siblingReceiver,sel,1)==101);
    expectStatus(child,sel,failure ? @"attempted_unverified.original_imp_null" : @"installed");
}
static void parentChainCases(void) {
    SEL sel=@selector(value:);
    CHECK_ID("inheritance.parent-install",installInteger(WCKRuntimeFixture.class,sel,(IMP)otherReplacement,&otherOriginalIMP));
    CHECK_ID("inheritance.child-install",installInteger(WCKRuntimeChild.class,sel,(IMP)replacement,&originalIMP));
    CHECK_ID("inheritance.chain-next",sameIMP(originalIMP,(IMP)otherReplacement));
    CHECK_ID("inheritance.parent-hook-retained",sameIMP(implementation(WCKRuntimeFixture.class,sel),(IMP)otherReplacement));
    CHECK_ID("inheritance.chain-dispatch",invoke([WCKRuntimeChild new],sel,1)==3101);
    CHECK_ID("inheritance.chain-once",atomic_load(&originalCalls)==1 && atomic_load(&replacementCalls)==1 && atomic_load(&otherCalls)==1);
}
static void classDistinctionCases(void) {
    Class cls=WCKRuntimeFixture.class, meta=object_getClass(cls); SEL sel=@selector(classValue:);
    CHECK_ID("class.instance-not-target",!installInteger(cls,sel,(IMP)replacement,&originalIMP));
    expectStatus(cls,sel,@"target_missing");
    CHECK_ID("class.metaclass-install",installInteger(meta,sel,(IMP)replacement,&originalIMP));
    expectStatus(meta,sel,@"installed");
    expectStatus(cls,sel,@"target_missing");
    CHECK_ID("class.dispatch",invoke((id)cls,sel,2)==1102);
}
static void foreignCases(BOOL confirmedFirst) {
    Class cls=WCKRuntimeFixture.class; SEL sel=@selector(value:);
    backendMode=confirmedFirst ? BackendTrampoline : BackendForeignAfter;
    CHECK_ID("foreign.initial-result",installInteger(cls,sel,(IMP)replacement,&originalIMP)==confirmedFirst);
    IMP next=originalIMP;
    if (confirmedFirst) { foreignNext=implementation(cls,sel); installLocal(cls,sel,(IMP)foreignReplacement); }
    CHECK_ID("foreign.outer-retained",sameIMP(implementation(cls,sel),(IMP)foreignReplacement));
    CHECK_ID("foreign.backend-next-retained",sameIMP(originalIMP,(IMP)nextTrampoline));
    originalIMP=NULL;
    CHECK_ID("foreign.repeat-result",installInteger(cls,sel,(IMP)replacement,&originalIMP)==confirmedFirst);
    CHECK_ID("foreign.saved-next",sameIMP(originalIMP,next));
    CHECK_ID("foreign.no-rehook",atomic_load(&hookCalls)==1);
    CHECK_ID("foreign.still-not-rolled-back",sameIMP(implementation(cls,sel),(IMP)foreignReplacement));
    CHECK_ID("foreign.full-chain",invoke([cls new],sel,1)==8101);
    CHECK_ID("foreign.chain-once",atomic_load(&originalCalls)==1 && atomic_load(&replacementCalls)==1 && atomic_load(&foreignCalls)==1);
    expectStatus(cls,sel,confirmedFirst ? @"installed" : @"attempted_unverified.postcondition_failed");
}

// A tiny Foundation-only production module proves consumers do not claim ready
// merely because the original slot was seeded or installation was attempted.
@interface ExptService : NSObject
- (BOOL)getExpt:(id)key withBoolDef:(BOOL)value;
@end
@implementation ExptService
- (BOOL)getExpt:(id)key withBoolDef:(BOOL)value { atomic_fetch_add(&albumCalls,1); return value; }
@end
static WCKSettings *fixtureStore;
@interface WCKSettings (RuntimePrivateStore)
- (instancetype)initWithFileURL:(NSURL *)url;
@end
@interface WCKSettings (RuntimeFixtureStore)
+ (instancetype)runtimeFixtureShared;
@end
@implementation WCKSettings (RuntimeFixtureStore)
+ (instancetype)runtimeFixtureShared { return fixtureStore; }
@end
static void prepareSettings(void) {
    NSString *home=NSProcessInfo.processInfo.environment[@"HOME"];
    CHECK_ID("settings.isolated-home",[home.lastPathComponent hasPrefix:@"runtime-"]);
    fixtureStore=[[WCKSettings alloc] initWithFileURL:[NSURL fileURLWithPath:[home stringByAppendingPathComponent:@"Preferences/runtime.plist"]]];
    Method shared=class_getClassMethod(WCKSettings.class,@selector(shared));
    Method fixture=class_getClassMethod(WCKSettings.class,@selector(runtimeFixtureShared));
    method_exchangeImplementations(shared,fixture);
    NSError *error=nil;
    CHECK_ID("settings.enabled",[fixtureStore setObject:@YES forKey:@"enabled" error:&error] && !error);
    CHECK_ID("settings.feature",[fixtureStore setObject:@YES forKey:@"albumSheet" error:&error] && !error);
}
static void moduleCases(BOOL confirmed) {
    prepareSettings(); backendMode=confirmed ? BackendNormal : BackendNull;
    WCKSetModuleStatus(@"neighbor",@"ready");
    WCKInstallAlbumSheet();
    CHECK_ID("module.honest-readiness",[WCKRuntimeStatuses()[@"albumSheet"] isEqual:@"ready"]==confirmed);
    expectStatus(ExptService.class,NSSelectorFromString(@"getExpt:withBoolDef:"),confirmed ? @"installed" : @"attempted_unverified.original_imp_null");
    WCKInstallAlbumSheet();
    CHECK_ID("module.repeat-readiness",[WCKRuntimeStatuses()[@"albumSheet"] isEqual:@"ready"]==confirmed);
    CHECK_ID("module.backend-once",atomic_load(&hookCalls)==1);
    CHECK_ID("module.no-neighbor-reset",[WCKRuntimeStatuses()[@"neighbor"] isEqual:@"ready"]);
    ExptService *service=[ExptService new];
    CHECK_ID("module.callable-original",[service getExpt:@"unrelated-experiment" withBoolDef:YES]);
    CHECK_ID("module.original-once",atomic_load(&albumCalls)==1);
    CHECK_ID("module.feature-not-regated",WCKEnabled(@"albumSheet"));
    CHECK_ID("module.exact-experiment",[service getExpt:@"clicfg_chat_album_pagesheet_mode" withBoolDef:NO]);
    CHECK_ID("module.experiment-no-original",atomic_load(&albumCalls)==1);
}
static void snapshotCases(void) {
    WCKSetModuleStatus(@"neighbor",@"ready");
    NSDictionary *snapshot=WCKRuntimeStatuses();
    WCKSetModuleStatus(@"neighbor",@"changed");
    CHECK_ID("status.snapshot-immutable",[snapshot[@"neighbor"] isEqual:@"ready"]);
    CHECK_ID("status.snapshot-new",[WCKRuntimeStatuses()[@"neighbor"] isEqual:@"changed"]);
    backendMode=BackendNoopFilled;
    CHECK_ID("status.unverified-result",!installInteger(WCKRuntimeFixture.class,@selector(value:),(IMP)replacement,&originalIMP));
    CHECK_ID("status.failure-no-global-reset",[WCKRuntimeStatuses()[@"neighbor"] isEqual:@"changed"]);
    backendMode=BackendNormal;
    CHECK_ID("status.independent-target",installInteger(WCKRuntimeFixture.class,@selector(otherValue:),(IMP)otherReplacement,&otherOriginalIMP));
    expectStatus(WCKRuntimeFixture.class,@selector(value:),@"attempted_unverified.postcondition_failed");
    expectStatus(WCKRuntimeFixture.class,@selector(otherValue:),@"installed");
}

int main(int argc, const char *argv[]) { @autoreleasepool {
    CHECK_ID("fixture.argument",argc==2);
    NSString *test=[NSString stringWithUTF8String:argv[1]];
    if ([test isEqual:@"missing-targets"]) missingCases();
    else if ([test isEqual:@"invalid-arguments"]) invalidCases();
    else if ([test isEqual:@"signatures"]) signatureCases();
    else if ([test isEqual:@"block-object"]) blockObjectCases();
    else if ([test isEqual:@"qualifiers"]) qualifierCases();
    else if ([test isEqual:@"signature-retry"]) signatureRetry();
    else if ([test isEqual:@"api-missing-retry"]) apiRetry();
    else if ([test isEqual:@"install-original"]) originalCases(NO);
    else if ([test isEqual:@"install-trampoline"]) originalCases(YES);
    else if ([test isEqual:@"backend-noop"]) backendFailure(BackendNoopFilled,@"attempted_unverified.postcondition_failed");
    else if ([test isEqual:@"backend-noop-empty"]) backendFailure(BackendNoop,@"attempted_unverified.original_imp_null");
    else if ([test isEqual:@"backend-no-touch"]) backendFailure(BackendNoTouch,@"attempted_unverified.original_imp_null");
    else if ([test isEqual:@"backend-null-original"]) backendFailure(BackendNull,@"attempted_unverified.original_imp_null");
    else if ([test isEqual:@"backend-null-inflight"]) backendFailure(BackendNullInFlight,@"attempted_unverified.original_imp_null");
    else if ([test isEqual:@"backend-recursive-original"]) recursiveCase();
    else if ([test isEqual:@"backend-exception"]) backendFailure(BackendException,@"attempted_unverified.hook_exception");
    else if ([test isEqual:@"idempotent-owner"]) duplicateCases();
    else if ([test isEqual:@"owner-conflict"]) conflictCases();
    else if ([test isEqual:@"preexisting-replacement"]) existingReplacementCase();
    else if ([test isEqual:@"quarantine-repeat"]) quarantineCases();
    else if ([test isEqual:@"reentrant-owner"]) reentrantCases();
    else if ([test isEqual:@"threaded-owner"]) threadedCases();
    else if ([test isEqual:@"cross-thread-owner"]) crossThreadCases();
    else if ([test isEqual:@"fresh-method-signature"]) freshMethodCases();
    else if ([test isEqual:@"inherited-instance"]) inheritedCases(NO,NO);
    else if ([test isEqual:@"inherited-class"]) inheritedCases(YES,NO);
    else if ([test isEqual:@"inherited-quarantine"]) inheritedCases(NO,YES);
    else if ([test isEqual:@"inherited-parent-chain"]) parentChainCases();
    else if ([test isEqual:@"class-target-distinction"]) classDistinctionCases();
    else if ([test isEqual:@"foreign-postcondition"]) foreignCases(NO);
    else if ([test isEqual:@"confirmed-outer-chain"]) foreignCases(YES);
    else if ([test isEqual:@"status-snapshot"]) snapshotCases();
    else if ([test isEqual:@"module-ready"]) moduleCases(YES);
    else if ([test isEqual:@"module-unverified"]) moduleCases(NO);
    else CHECK_ID("fixture.known-case",NO);
    printf("RUNTIME CASE %s PASS (%u checks; actual production runtime, stub Substrate)\n",argv[1],atomic_load(&checks));
} return 0; }
