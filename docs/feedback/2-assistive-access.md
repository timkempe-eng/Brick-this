I am an adult. I have deliberately given my spouse the Screen Time passcode on
my own phone, as a guardrail I chose for myself. I want to be able to put that
phone into Assistive Access for an hour so I can concentrate, then leave it
again. I cannot, because entering Assistive Access requires the Screen Time
passcode, which I do not hold on purpose.

Steps to reproduce:

1. Set a Screen Time passcode on your iPhone and have someone else hold it.
2. Set up Assistive Access. It uses the existing Screen Time passcode.
3. Add Assistive Access to the Accessibility Shortcut.
4. Triple-click the side button.

Result: a passcode prompt. I cannot put my own phone into Assistive Access.

Expected: I can move my own device into a more restricted state without a
credential held by somebody else.

Why I think this is a design inconsistency rather than an inconvenience:

Entering Assistive Access is subtractive. It removes apps, interface and
capability; it grants nothing. The Screen Time passcode exists to stop
restrictions being loosened. Entering Assistive Access loosens nothing, so
there is nothing for the passcode to protect at that moment.

Everywhere else on iOS, a subtractive change needs no authorization. With no
passcode and no supervision, any user can hide whole Home Screen pages with a
Focus, hide or lock individual apps behind Face ID, or delete apps outright.
Assistive Access is the exception, and the apparent reason is that it was
designed for a supporter administering somebody else's device.

I mention Focus only as evidence about permissions. It is not a substitute for
what I am asking for, and I already use it.

Why Assistive Access specifically:

It is the only thing on iOS that redraws the interface rather than filtering
it — large targets, one thing per screen, no gestures to discover. Focus
changes what is on the screen. Assistive Access changes how the device draws
itself, and that is the reason it works: what pulls at me is not only which
apps are installed, it is how the phone looks and feels when I glance at it.

No third-party app can build this. System rendering is not available to apps,
and should not be. Apple has already built it. I am asking for a way in.

The risk of ungating entry, and a suggested fix:

I assume entry is gated so that nobody with brief physical access can trap
another person in a phone they cannot leave. That is a real risk. It can be
addressed on the exit credential rather than the entry one: a session the
device's owner starts should end with the device passcode or Face ID, which
they already hold. Nobody can be trapped, because whoever can enter can also
leave. A supporter-configured session keeps the Assistive Access passcode
exactly as it works today.

Any one of these would solve my case, in order of preference:

1. A self-initiated Assistive Access session — entered with no Assistive
   Access passcode, left with the device passcode or Face ID, optionally with
   a duration set on the way in. This needs no new API.
2. A Shortcuts action to enter Assistive Access, so a person can trigger it
   from their own automation.
3. An API to request entry that requires explicit user consent at the moment
   of the call, in the same shape as
   AuthorizationCenter.requestAuthorization(for: .individual), which already
   puts Family Controls behind Face ID on the user's own device.

Related precedent: UIAccessibility.requestGuidedAccessSession(enabled:
completionHandler:) has put a device into Single App mode from code since
iOS 7, restricted to devices supervised by MDM. The capability exists and is
long-standing; what is missing is a path for a person acting on their own
device.

For context on what I am building: I want to tap an NFC sticker on my desk and
have my phone become essentials-only for an hour, then tap it again to come
back. The app side I can already build with the Screen Time APIs. The interface
side is the half only Assistive Access can do.
