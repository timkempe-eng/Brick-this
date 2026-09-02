# From a GitHub repo to a Dadded phone, with no Mac

You have an iPhone, an iPad and a GitHub account. No Mac, no Xcode. That is
enough — but the route is different from the usual one, and one part of it
costs money.

Everything below happens in Safari on the iPad.

## The short version

GitHub's macOS runners have Xcode on them, and they're free for public
repositories. So the Mac in this project is a rented one that exists for four
minutes per push:

- **Every push** builds the app and all three extensions (`.github/workflows/test.yml`).
  If it compiles, it compiles.
- **When you want it on your phone**, run the Release workflow from the Actions
  tab. It signs the build and sends it to TestFlight.
- **You install from TestFlight** on the iPhone, like any beta.

## What this costs

**The Apple Developer Program, $99/year.** This is not optional and there is no
way around it:

- Free provisioning — the 7-day-certificate route — requires Xcode on a Mac.
- Sideloading tools (AltStore and friends) can't grant the Family Controls
  entitlement, which is the whole app.
- Swift Playgrounds on iPad can build and submit apps, but **not app
  extensions**, and Dad needs three of them. It cannot build this project.

So: TestFlight is the only Mac-free way onto the phone, and TestFlight requires
the paid program. If that's a dealbreaker, stop here rather than after buying
the tags.

## Order of operations

The waiting item is first, because it's the long pole.

### 1. Join the Apple Developer Program

developer.apple.com, from Safari. Enrolment can take a day or two.

### 2. Request Family Controls (Distribution) — do this immediately

Then, once approved, **enable the capability on each App ID** in Certificates,
IDs & Profiles. Approval and enablement are two different steps, and `match`
does not do the second one for you.

App blocking needs an entitlement Apple grants by hand, per bundle id. TestFlight
will reject the build without it. Reported turnaround is four business days to
several weeks, so file it the day you enrol.

You need it for all four ids:

- `app.dad.Dad`
- `app.dad.Dad.ShieldConfiguration`
- `app.dad.Dad.ShieldAction`
- `app.dad.Dad.ActivityMonitor`

Say plainly that it's a personal digital-wellbeing app that hides your own apps
at your own request, that the tap mechanic is NFC, and that the app never
receives app identities — only opaque tokens. See [entitlements.md](entitlements.md).

While you wait, the build still runs on every push. You just can't install it.

### 3. Create an App Store Connect API key

App Store Connect → Users and Access → Integrations → App Store Connect API.
Role: **App Manager**. The `.p8` file downloads **once** — save it somewhere you
can copy from on the iPad.

This key is what lets fastlane `match` create and store the signing certificate
and profiles. Nothing is exported from anyone's Keychain, which is the usual
reason this needs a Mac. **Not** Xcode automatic signing — that fails in CI for
reasons worth reading once: [signing.md](signing.md).

### 4. Add four repository secrets

GitHub → Settings → Secrets and variables → Actions → New repository secret:

| Secret | Where it comes from |
|---|---|
| `APPLE_TEAM_ID` | Membership page, 10 characters |
| `ASC_KEY_ID` | shown next to the key you just made |
| `ASC_ISSUER_ID` | shown above the key list |
| `ASC_KEY_P8` | **base64** of the `.p8` — `base64 -i AuthKey_XXXX.p8`. There's no local `base64` on an iPad, so run it in an agent session |
| `MATCH_PASSWORD` | any passphrase; it encrypts the stored certificate |

One repository **variable** is needed: `MATCH_GIT_URL`, pointing at an empty
**private** repo for `match` to store the encrypted certificate in — this repo
is public, so it cannot hold one, and the lane refuses if you try. Plus the
secret `MATCH_GIT_TOKEN`, a fine-grained PAT with Contents read **and write**
on that repo. Dad keeps its own certificate rather than sharing another
project's, which means **check the certificate count before your first Release
run** — Apple's ceiling is two or three per account, depending who you ask.

Actions → **Apple account maintenance** → Run workflow, with the revoke field
blank. It lists them in seconds, on Ubuntu. The release workflow also refuses to
run if the account is already at the ceiling with no stored certificate to
reuse. [Why this matters](signing.md#the-certificate-ceiling)

### 5. Create the app record

App Store Connect → Apps → **+** → New App, bundle id `app.dad.Dad`. TestFlight
needs somewhere to put the build.

### 6. Run the Release workflow

Actions tab → **Release to TestFlight** → Run workflow. Ten minutes or so.

### 7. Install from TestFlight

Install Apple's TestFlight app on the iPhone, accept the invite for your own
build, install Dad.

## When the tags arrive

1. **Open Dad, grant Screen Time access.** One system prompt.
2. **Build a Mode.** Start with one — "Deep Work" — and three or four apps you
   actually lose time to. Blocking thirty on day one is how people quit this
   after a week.
3. **Pair a tag.** Settings → Pair a Dad tag. Until you pair one, any tag works.
4. **Test it in-app.** Press "Dad my phone", then try to open a blocked app. You
   should get the "Dadded." shield.
5. **Optionally give a Mode a schedule.** Sleep, every night, 22:00–07:00, and
   the phone Dads itself. A schedule never overrides a session you started by
   hand, and you can always tap out early.
6. **Set up the Shortcuts automation** so a tap works with Dad closed —
   [three lines of setup](nfc-and-tags.md#2-shortcuts-automation--the-one-to-use).
   This is all on the iPhone, no computer involved.
7. **Stick the tag somewhere inconvenient.** This is the actual product. A
   sticker on your desk gives you nothing; one in a drawer in another room is
   the whole mechanism.

## If something doesn't work

**The build fails on macOS.** Read the log in the Actions tab — it names the file
and line. That is the normal way to work here.

**TestFlight rejects the upload.** Almost always the Family Controls entitlement
isn't approved yet, or isn't approved for all four bundle ids. `match` does not
manage capabilities, so the App ID must carry Family Controls *before* the
profile is minted — and after enabling it, run Release once with
`force_profiles: true`, because `match` reuses a profile that predates the
capability.

**`ASC_KEY_P8` errors.** It must be base64, not the raw file. The Fastfile
rejects a raw paste up front.

**Signing fails with "no registered devices" or "No Accounts".** That is
automatic signing, not `match`. See [signing.md](signing.md).

**The tap does nothing.** Check the Shortcuts automation has Ask Before Running
off. NFC personal automations need iPhone XS or later.

**"Tag not found."** Is it on metal? Even a laptop lid detunes the antenna.

**Apps aren't blocked but the app says Dadded.** The Mode has nothing selected,
or Screen Time authorization was declined.

**A scheduled Mode never fires.** It needs at least one day and a window of 15
minutes or more — anything shorter is below what DeviceActivity will monitor.
The editor says so when the schedule can't run.

## A note on the escape hatches

Five emergency overrides per rolling 30 days, and they come back on their own.
Brick makes you email support; that's friction for its own sake. The limit
exists to make you notice you're reaching for the hatch, not to lock you out of
your own phone.

If you're burning all five, the Mode is wrong. Block less.
