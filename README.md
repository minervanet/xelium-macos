# xelium
<p align="center">
  <img src="resources/assets/legacy.png" width="128" alt="Xelium app icon">
</p>
macOS packaging & development tooling for the
[Xelium Browser](https://github.com/minervanet/xelium-macos).

Xelium is a custom macOS build/fork focused on tailored features and workflow
enhancements, evolving the Helium base with its own defaults, patches, and
release flow.

## Building and development
macOS is our primary development platform, so it's the recommended environment
for developing new Xelium features.

[> See docs/building.md](docs/building.md)

## Contributing
Before contributing to this repo, please read the guidelines in the main repo's
[CONTRIBUTING.md](https://github.com/minervanet/xelium-macos/blob/main/CONTRIBUTING.md).

Found a bug or have a feature request? Please open an issue on the
[issue tracker](https://github.com/minervanet/xelium-macos/issues).

## Credits

### Depot
Big thank you to [Depot](https://depot.dev/) for sponsoring our runners,
which handle the macOS builds of Xelium. Their high-performance infrastructure
lets us compile, package, and release new builds of Xelium within hours,
not days.

### ungoogled-chromium-macos
This repo is based on
[ungoogled-chromium-macos](https://github.com/ungoogled-software/ungoogled-chromium-macos),
but heavily modified for Xelium (via the Helium base it forks). Special thanks
to everyone behind ungoogled-chromium, they made working with Chromium
infinitely easier.

## License
All code, patches, modified portions of imported code or patches, and
any other content that is unique to Xelium and not imported from other
repositories is licensed under GPL-3.0. See [LICENSE](LICENSE).

Any content imported from other projects retains its original license (for
example, any original unmodified code imported from ungoogled-chromium remains
licensed under their [BSD 3-Clause license](LICENSE.ungoogled_chromium)).
