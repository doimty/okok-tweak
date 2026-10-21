# Test-only UIKit model

`fake-uikit/` is a deterministic Foundation-backed model for exercising the actual
production `WCKSVG.m` factory/provenance/view-refresh code. It does not draw pixels
and is not UIKit, an iOS simulator, or a WeChat device test. The native runner must
report it as a model test, not visual verification.
