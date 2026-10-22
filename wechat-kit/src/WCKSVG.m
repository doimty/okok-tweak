// 最小修复 S2：给 ambiguous stamp 增加一次可恢复窗口（仅对同一 request 差异降级为保留旧 stamp + 计数）
static BOOL WCKSVGSameStamp(WCKSVGStamp *a, WCKSVGStamp *b) {
    if (a == b) return a && !a.ambiguous;
    if (!a || !b || a.ambiguous || b.ambiguous || a.tinted != b.tinted || a.rgb != b.rgb ||
        !WCKSVGSameRequest(a.request, b.request) || a.steps.count != b.steps.count) return NO;
    // S2: 同一 request 差异仅降级为保留旧 stamp + 计数（非立即 ambiguous）
    BOOL sameRequest = WCKSVGSameRequest(a.request, b.request);
    if (sameRequest) return NO; // 差异则不匹配，返回 false 触发降级
    for (NSUInteger i = 0; i < a.steps.count; ++i) {
        WCKSVGStep *x = a.steps[i], *y = b.steps[i];
        if (x.operation != y.operation || x.mode != y.mode ||
            !UIEdgeInsetsEqualToEdgeInsets(x.insets, y.insets)) return NO;
    }
    return YES;
}