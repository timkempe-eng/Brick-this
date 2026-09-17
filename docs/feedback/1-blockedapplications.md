I am building an iOS app that helps a person remove distracting apps from
their own phone for a set period, with their explicit consent, on their own
device. I need to know whether blockedApplications is a sanctioned way to
do that, because Apple currently says three different things.

1. The documentation says it hides apps.

ManagedSettings.ApplicationSettings.blockedApplications is documented as:
"The system hides blocked applications and prevents the user from launching
them."

2. An Apple Frameworks Engineer recommends it for exactly this use. In
Developer Forums thread 716519 ("How to hide specific apps from home screen
proactively?"), an Apple Frameworks Engineer answers that this is possible,
posts sample code setting store.application.blockedApplications, and
confirms it works under .individual authorization — not only under a
parent-child Family Sharing arrangement.

3. App Review rejects it. In Developer Forums thread 776058, a developer
whose Family Controls & Personal Device Usage entitlement had already been
approved was rejected under guideline 2.5.1: "your app uses ScreenTime API to
hide apps." The developer appealed, quoting the documentation above
verbatim, and received the same rejection text again. No Apple engineer
responded in the thread, and it is still unresolved.

What I need is a decision rather than a workaround. Either:

- blockedApplications is a supported way for an authorized app to hide apps
  on a consenting user's own device — in which case App Review needs to know
  that, because developers are currently being rejected for following both
  the documentation and an Apple engineer's advice; or
- it is not, and the documentation and the forum answer are both wrong — in
  which case please say so in the documentation, so that the API's one
  documented behaviour is not a trap.

Why it matters: shielding an app covers it when you open it, but the icon,
the badge and the folder stay on the Home Screen. Hiding is the behaviour my
users are asking for, and it is the one that is ambiguous. I would rather build
the sanctioned version than find out at review, after an entitlement request
that already takes weeks.
