# iWords arm-dev-ios

iOS support is looking fragile- the latest iOS-capable Ada compiler is the long term support release of GNAT Pro 19, which is Intel-only (and released in 2019). Without an updated toolchain, the largest barriers appear to be the ones listed below, per Codex. Most glaringly, App Store requirements to use the latest XCode and the impending Rosetta sunset mean we may be unable to build and release a year or so from now, leading to app abandonment or in the worst case, de-listing. The next year looks like it will likely be extra spicy in the security arena and I'm kind of expecting engine-breaking requirements to arrive sooner rather than later.

- Missing ARM64 Simulator support
- Modern linker incompatibilities: old object files or runtime exception metadata may encounter stricter validation or changed linker behavior- there is no promised vendor fix
- Mandatory Xcode/SDK upgrades
