# 1.0.8 native launch-skip experiment

## Goal and assumptions

Reduce the approximately six-second cold-start hold by selecting the App's own `LaunchUtil.ignoreSplashAd` branch, before the high-level ad window exists. This is an experiment, not a proven instant-launch fix.

Static evidence for Xiaocan 3.21.6: LaunchUtil has instance size 24, byte `ignoreSplashAd` at offset 8 and lazy launchView at offset 16. Its native launch setup schedules a main-queue check after about two seconds; a true ignore flag leads to launchView cleanup and a Published state update.

## Minimal change

- Remove the unsuccessful HomeSplashPopupGate hook and all injected handleAdClosed calls.
- After the real LaunchUtil Objective-C init returns, validate the class, App version and runtime ivar layout; set only the ignoreSplashAd byte to 1.
- Do not create a LaunchUtil instance, call a raw Swift address, force-remove launchView, shorten dispatch timers, or suppress business initialization.
- Keep existing window-alpha suppression and previously tested BU/GDT fallbacks unchanged.
- Fail closed for a different version, missing ivars, a different layout, a nil/replaced initializer result or an invalid boolean value.

## Independent failure signals

- No init diagnostic: real creation may bypass Objective-C init or predate tweak loading. Then this experiment has not exercised its target.
- Diagnostic reports flag applied but startup remains around six seconds: selecting the branch alone is insufficient, or its timer starts late.
- Blank/unresponsive homepage, repeated navigation, crash, or a late ad covering home: reject the candidate even if the launch image disappears sooner.
- A layout/version mismatch must not write any object memory.

## Validation and boundaries

The pure-C production memory guard is tested with sentinel buffers, all layout guards, repeated calls, canonical boolean values and unaffected surrounding bytes. Run the tests locally and in the cloud build. Static diff checks do not validate Objective-C initialization or UIKit behavior.

Cloud build must compile arm64 and arm64e, then package verification must confirm version, bundle filter, expected features, absence of HomeSplashPopupGate and installation/dependency layout. Do not install on the device automatically; the user will cold-launch three times and check visible/interactive home, not merely root-controller creation.
