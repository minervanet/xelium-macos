<p align="center">
  <img src="resources/assets/legacy.png" width="128" alt="Xelium app icon">
</p>

# Xelium

Xelium is an unofficial, personal build of [Helium](https://github.com/imputnet/helium). It is not affiliated with or endorsed by the Helium team.

## What this is

A proof of concept showing that Chromium/Helium can be made to look and feel like Arc, using the native Chromium frame instead of CEF.

The browser is still 100% Helium under the hood. The visible changes to the app's identity are the name (Xelium), the app icon, and the bundle ID (`net.minerva.xelium`), so Xelium and Helium can be installed side by side without conflicting.

## What I changed

Mostly nothing of my own. Xelium is Helium plus a handful of open, unmerged pull requests from the Helium repo, collected into one personal build. Many of those PRs would take a long time to land, or may never be merged, because the Helium project is strict about what goes in, which is a good thing for the main project. This build is a place to try them together.

I also added a few small patches of my own to make these pieces work together (see below).

## Credits

Everything here belongs to the original authors.

- Helium: https://github.com/imputnet/helium
- Unmerged PRs included:
  - [#2747](https://github.com/imputnet/helium/pull/2747): "comfortable" interface size (by dumbmoron)
  - [#2367](https://github.com/imputnet/helium/pull/2367): show address bar in sidebar (by heloess)

My own patches: comfortable sizing for vertical tabs, configurable rounded-frame thickness, narrower sidebar with the address bar.

## Updates

I'll keep Xelium updated as long as I'm still using Helium and Helium is still around. Updates won't be quick, since every big change means a Chromium rebuild that takes hours. Thanks for your patience.

## Notes

- This is for personal use and testing. It has no support and no guarantees.
- Behavior may break on Chromium updates, since the patches need refreshing each time.
- Licensing follows the upstream projects. Check Helium's license in the repo.
