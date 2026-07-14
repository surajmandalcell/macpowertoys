# MacPowerToys for Raycast

This companion extension exposes only MacPowerToys and its built-in tools as Raycast Root Search launchers.

## Local installation

1. Install and open MacPowerToys.
2. Run `npm ci && npm run build` in this directory.
3. Open Raycast's **Import Extension** command and select this directory.
4. Assign aliases or hotkeys to the app launchers you use.

Commands use the local `macpowertoys://` URL scheme. No cloud service is required by the extension.

Before submitting to the Raycast Store, add the owner's Raycast account username as the manifest `author`, then run `npm run lint:store` and `npm run publish`.
