<p align="center">
  <img src="../docs/appicon.svg" width="96" height="96" alt="MacPowerToys icon">
</p>

# MacPowerToys for Raycast

Launch MacPowerToys or its built-in tools from Raycast Root Search.
Each command opens the matching utility or menu-bar panel through the local
`macpowertoys://` URL scheme. The extension runs no background service.

<p align="center">
  <img src="../docs/screenshots/macpowertoys-launcher.png" width="900" alt="MacPowerToys launcher">
</p>

## Commands

| Group             | Commands                                                |
| ----------------- | ------------------------------------------------------- |
| App               | MacPowerToys                                            |
| Screen            | Ruler, Color Picker, Text Extractor                     |
| System            | Awake, Input Devices, System Care, System Monitor, Logs |
| Files and network | Cloud Sync, Diskman, NetToys, Portman                   |

## Local installation

1. [Install MacPowerToys](https://github.com/surajmandalcell/macpowertoys/releases/latest) and open it once.
2. Build the extension from this directory:

   ```bash
   npm ci
   npm run build
   ```

3. Open Raycast's **Import Extension** command and select this directory.
4. Assign aliases or hotkeys to the app launchers you use.

## Development

```bash
npm run dev
npm run lint
```

`npm run dev` rebuilds the one imported extension in place; it does not add a
second development registration to Raycast.

Before submitting to the Raycast Store, run `npm run lint:store`, then
`npm run publish` from the owner's Raycast account.
