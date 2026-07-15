## 1.0.0

Release date: 2026-07-15

* Stable release
* **Breaking**: Refactored `PDLogger` from static class to instance class for independent logging per client
* **Breaking**: `PDLongLinkConfig` now uses `logger` field for custom logger injection (removed `enableLogging`, `logLevel`, `logCallback` fields)
* Instance-level logging system with `PDLogger` injection via `PDLongLinkConfig.logger`
* Message queue with configurable overflow strategy (`dropOldest` / `dropNewest`)
* Standardized error codes (10 types) with `PDLongLinkErrorCode`
* Configurable heartbeat `pongMessage` for heartbeat response matching
* SSE `lastEventId` support for reconnection resumption
* SSE `parseSseFormat` toggle for raw vs parsed event data
* Flutter lifecycle awareness (auto-reconnect on resume, optional background disconnect)
* Cross-platform support: iOS, Android, Web, macOS, Windows, Linux
* Comprehensive dartdoc API documentation
* 68 unit tests covering all public APIs

## 0.1.0

Release date: 2026-07-14

* Initial test release
* WebSocket connection support (dart:io / dart:html)
* System WebSocket support (Android/iOS native WebSocket)
* Server-Sent Events (SSE) support
* Auto-reconnect with exponential backoff and jitter
* Heartbeat mechanism with configurable ping/pong messages
* Message queue for offline buffering
* Instance-level logging system
* Standardized error codes (10 types)
* Flutter lifecycle awareness
* Cross-platform support: iOS, Android, Web, macOS, Windows, Linux

## 0.0.1

Release date: 2026-07-14

* Initial development version
