# Native camera capture boundary

MissCat's compose and profile camera routes render their complete presentation in
SwiftUI. `MissCatCameraCaptureView` obtains preview frames and photo/movie results
from AVFoundation without a UIKit picker or representable wrapper.

## Permission timing

Opening the camera requests only video-camera access. The photo mode is the initial
mode and must never cause a microphone prompt. Microphone access is evaluated only
after the user selects movie mode, or immediately before recording if movie mode was
already selected. Returning to photo mode or dismissing the camera cancels the
in-app permission-preparation task; a late authorization result cannot start a
recording after cancellation.

The audio state is explicit:

- `available` records the movie with an audio input.
- `silentDenied` keeps movie capture available and tells the user that the movie
  will be silent. Settings and recheck actions remain visible.
- `silentUnavailable` keeps movie capture available and tells the user that no
  microphone can be attached.

Recheck resets the local permission flow and reads the current system decision. It
does not pretend that iOS can display a second prompt after the user has denied it.

## Concurrency ownership

`MissCatCameraEngine` is an actor. It exclusively owns and mutates the capture
session, inputs, outputs, rotation observation, recording cancellation flag, and
temporary movie lifecycle. AVFoundation delegate callbacks are reduced to immutable
`Data`, `URL`, `CGImage`, and failure values before they enter the actor. UI callbacks
are `@MainActor` closures.

This design intentionally avoids both capturing a non-Sendable engine in
`DispatchQueue.async` closures and declaring the engine `@unchecked Sendable`.
`swiftc -strict-concurrency=complete` is the static acceptance check for this file.

## Static acceptance

`MissCatCameraCaptureTests` fixes the following contracts:

- initial camera startup contains no audio permission request;
- denied or unavailable audio is a visible, silent-recording state;
- an outstanding permission flow can be cancelled and retried;
- the capture engine remains actor-owned with no unchecked Sendable escape hatch;
- compose and profile routes continue to use the native SwiftUI camera surface.

Simulator capture, hardware permission prompts, recorded audio, and visual parity
remain runtime acceptance work and are not claimed by the SDK-only checks above.
