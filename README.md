# CashApp: M-Pesa Tracker

An offline, privacy-first M-Pesa expense tracker.

## Permanent Product Constraint
This app must remain fully **ad-free**, **offline**, and **free of any third-party SDK** for monetization, analytics, or tracking. This is a deliberate differentiator versus mainstream expense trackers. Do not add any ad network, analytics SDK, or telemetry package to `pubspec.yaml` at any point without this being explicitly discussed first.

## Known Limitations & Behaviors
- **Background Sync**: M-Pesa transactions sync automatically within 15 minutes, or instantly when you open the app. Due to Android 15 background battery restrictions, instant background interception cannot be guaranteed when the app is swiped away. This latency is normal and tested.