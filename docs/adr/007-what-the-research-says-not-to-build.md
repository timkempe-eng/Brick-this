# ADR 007: what the research says not to build

**Status:** accepted, 2026-09-03. Moved here out of `PARKING_LOT.md` when that
file was cut back to open work only.

## Context

A research sprint against Brick's App Store reviews and the child-development
literature produced eighteen ranked feature gaps, all of which are now built or
declined in an ADR. It also produced six things the market ships and this
product will not. Those are not gaps and they were never on the backlog — but
the reasoning is worth keeping somewhere, because every one of them is a
plausible-sounding feature request that will arrive again.

A backlog is a list of work. This is a list of decisions, which is what an ADR
is for.

## Decision

**Screen time as chore currency** — declined. ScreenCoach, Chore Champ,
Carrots&Cake, EarnIt and Zenvy all do it, and it is the single biggest thing in
this market. The research says it backfires: paying for a behaviour in the
thing you are trying to reduce teaches that the thing is worth having. The
autonomy ladder and the rewards ledger are the same intent built the way the
evidence supports — consistency buys *control*, and rewards are priced in days
and cannot be priced in minutes, structurally.

**Message and content monitoring** — declined. Bark and Qustodio ship it. Hard
rule 3 forbids it, and the research says it damages the trust it is meant to
protect. This is the privacy model working rather than a gap in it.

**Location tracking** — declined, same reasoning. Every family app ships it; it
is surveillance, reviewers report it as unreliable anyway, and it needs an
always-on entitlement that fails hard rule 7. A physical tag in another room
solves the same problems with no entitlement at all.

**Alternative unlock frictions** — shake, pattern, walk-a-distance, as Unpluq
does. Declined because the tag is a better friction: it is somewhere else in
the house, and a second weaker gate only teaches you to route around the first.

**AI usage analysis** — declined. Opal does it. It requires learning what the
user does, which is exactly what rule 3 exists to prevent.

**Refreshing the emergency allowance on request** — not needed. Brick makes you
email support once you are out. Dad's five per rolling thirty days already
restore themselves, which is better than the thing being copied.

## Consequences

Each of these will be suggested again, by somebody who has seen a competitor do
it. The answer is not "we didn't get to it" — it is here, with the reasoning and
the sources.

The two findings that shaped the whole ranked backlog are the same shape and
belong beside them:

1. **Never pay in screen time.** Reward autonomy, not minutes.
2. **Never observe.** The app cannot learn what you did, by construction.

## Sources

[Brick FAQ](https://getbrick.com/pages/faq) ·
App Store reviews for *Brick — Ditch Distractions* ·
[Unpluq vs Brick](https://whatifididnt.com/blog/unpluq-vs-brick/) ·
[A year with Brick](https://whatifididnt.com/blog/brick-phone-app/) ·
[Brick alternatives](https://www.getfocusphone.com/articles/brick-alternatives/) ·
[NBC News two-week test](https://www.nbcnews.com/select/shopping/brick-phone-app-blocker-review-rcna259740) ·
[Apple: AuthorizationCenter](https://developer.apple.com/documentation/familycontrols/authorizationcenter) ·
[Apple: requestAuthorization(for:)](https://developer.apple.com/documentation/familycontrols/authorizationcenter/requestauthorization(for:)) ·
[WWDC22: What's new in Screen Time API](https://developer.apple.com/videos/play/wwdc2022/110336/) ·
[Apple: respond to a Screen Time request](https://support.apple.com/guide/iphone/respond-to-a-screen-time-request-iph74e434e84/ios) ·
[UCF: parental-control apps may be counterproductive](https://www.ucf.edu/news/apps-keep-children-safe-online-may-counterproductive/) ·
[Beyond parental control (arXiv 2503.22995)](https://arxiv.org/html/2503.22995) ·
[MIT Tech Review: child-monitoring apps need a reboot](https://www.technologyreview.com/2026/08/19/1141623/child-monitoring-apps-need-reboot/) ·
[AAP: monitoring vs independence by age](https://www.aap.org/en/patient-care/media-and-children/center-of-excellence-on-social-media-and-youth-mental-health/qa-portal/qa-portal-library/qa-portal-library-questions/balancing-online-safety-and-independence-parental-monitoring-by-age/) ·
[Psychology Today: when we use screens to reward kids](https://www.psychologytoday.com/us/blog/the-art-of-talking-with-children/202407/when-we-use-screens-to-reward-kids-they-use-screens) ·
[Why screen time as a reward can backfire](https://kesq.com/stacker-parenting-family/2026/08/04/does-screen-time-affect-behavior-why-using-it-as-a-reward-can-backfire/) ·
[Adolescent involvement in screen decisions (PMC11016903)](https://pmc.ncbi.nlm.nih.gov/articles/PMC11016903/) ·
[Children and Screens: all in the family](https://www.childrenandscreens.org/learn-explore/research/all-in-the-family/) ·
[OurPact review](https://timily.app/guides/ourpact-review/) ·
[Earn-screen-time app roundup](https://timily.app/guides/earn-screen-time-app/)
