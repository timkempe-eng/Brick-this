My situation, which I do not think is rare. I am an adult. I have
deliberately given my spouse ownership of the Screen Time passcode on my own
phone, as a guardrail I chose for myself. It works, and I do not want it
changed.

I now want to put my phone into a much more limited state for an hour so I
can concentrate. Assistive Access does exactly this, and does it better than
anything I could build. I cannot use it, because entering it asks for the
Screen Time passcode, which I do not have and deliberately do not want.

What Assistive Access does that nothing else does. It is not a filter
over the same interface — it redraws the interface. Huge targets, one thing
per screen, no gestures to discover, no infinite surfaces. It takes a shiny
black mirror and turns it into a flip phone. That is a change of kind, and
it is the reason it works: the pull of the device is not only which apps are
installed, it is how the thing looks and feels in the hand when you glance at
it.

No third party can build this, at any price. System rendering is not
available to apps, and it should not be. Apple has already built the single
most effective anti-distraction interface on the platform. I am not asking
for it to be built. I am asking to be allowed through the door.

The gate is pointed the wrong way. A credential should be required to
reduce a restriction, not to add one. Everything the Screen Time passcode
protects is on the loosening side: more time, fewer limits, turning it off.
Entering Assistive Access does none of those things. It is strictly
subtractive — fewer apps, less interface, less capability. There is nothing
there for a passcode to protect, and gating it means the one thing I cannot
do to my own phone is make it less powerful.

On the permission model specifically — not on the capability — iOS already
agrees with me everywhere else. With no passcode and no supervision, any
user can:

- Build a Focus that hides whole Home Screen pages and chooses which apps
  appear while it is on.
- Hide or lock individual apps behind Face ID (iOS 18).
- Delete apps, turn on Do Not Disturb, and strip the Home Screen bare.

Every one of those makes the phone less capable, and none of them asks
anybody's permission. I list them only to show that subtractive changes
do not normally need authorization on iOS, and that Assistive Access is the
outlier. Please do not read this as a request for something Focus already
does. I use Focus. It rearranges what is on the glass; it does not change
what the glass is. The phone is still the same object, still inviting the
same reach, and I still open it and find myself somewhere I did not intend to
go. Assistive Access is the only thing on the platform that changes that, and
the only apparent reason I cannot reach it is that it was designed for a
supporter administering somebody else's device. That audience should keep the
passcode exactly as it is. It should not be the only door.

The obvious objection, and my answer. Gating entry presumably stops
somebody with brief physical access from trapping another person in a
simplified phone they cannot leave. That is a real risk and I am not asking
you to accept it. It is solved by the exit credential rather than the entry
one:

- For a self-initiated session, exiting takes the device passcode or
  Face ID — the credential the owner already holds. Nobody can be trapped,
  because whoever can enter can always leave.
- Optionally, the person chooses a duration on the way in and it expires by
  itself.
- The supporter-administered mode is untouched: set up with the Assistive
  Access passcode as it is today, and it still takes that passcode to leave.

Entry needs no authorization because entry cannot harm anyone. Exit is where
the authorization belongs, and which credential it takes should follow from
who started the session.

The precedent for programmatic control already ships.
UIAccessibility.requestGuidedAccessSession(enabled:completionHandler:) has
existed since iOS 7 and puts a device into Single App mode from code. Its
documented requirement is that "entering Single App mode is supported only
for devices that are supervised using Mobile Device Management (MDM), and the
app itself must be enabled for this mode by MDM." So a programmatic lockdown
capability is a decade old and gated to enterprise supervision rather than
absent.

Any one of these would solve it, in order of preference:

1. A self-initiated Assistive Access session: entered without the Assistive
   Access passcode, left with the device passcode or Face ID, optionally
   time-boxed. This needs no new API and no developer involvement at all.
2. A Shortcuts action to enter Assistive Access, so a person can attach it to
   their own automation — an NFC tag, a time of day, arriving somewhere.
3. An API to request entry, gated by explicit user consent at the moment of
   the call — the same shape as
   AuthorizationCenter.requestAuthorization(for: .individual), which already
   puts Family Controls behind Face ID on the user's own device.

What I am actually trying to do, in case it helps: tap an NFC sticker on
my desk and have my phone become a flip phone for an hour, then tap it again
to come back. The apps half I can already build with the Screen Time APIs.
The interface half — the part that changes what the device is rather than
what is on it — only Assistive Access does, and it is the half I am locked
out of.

I am not trying to get around supervision. I am trying to add to it.
