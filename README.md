<img src="assets/icon.svg" width="64" height="64" alt="">

# helium-fork

Created in [T3 Code](https://t3.codes).

## Helium Dev

Helium Dev is a small app that you set as the default browser. It opens Helium with `--custom-devtools-frontend`, pointed at the DevTools frontend inside `Helium Dev.app`. It declares the same URL schemes and file types as Helium.

If Helium already runs without the flag, Helium Dev asks to restart Helium.

- `just devtools` builds the release frontend into `devtools/devtools-frontend/out/Release`.
- `just helium-dev-build` builds `build/Helium Dev.app`.
- `just homebrew` publishes a GitHub release and updates the `helium-dev` cask in `gstark/tap`.

Install it with `brew install gstark/tap/helium-dev`, then open Helium Dev once. On its first launch, it asks to become the default browser, and macOS asks you to confirm. The Homebrew sandbox does not let the cask open the app during the install. To ask again, run `open -a "Helium Dev" --args --make-default`.

The frontend must match the Chromium milestone of Helium. When Helium moves to a new milestone, rebase the `status-filters` branch.
