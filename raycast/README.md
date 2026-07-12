# PowerToys for Raycast

This extension exposes PowerToys utilities as separate Raycast Root Search commands.

## Local installation

1. Open Raycast's **Import Extension** command.
2. Select this `raycast` directory.
3. Run `npm install && npm run dev` while developing.

PowerToys must be installed with the `powertoys` URL scheme. Commands launch the app
when needed and send a stable action identifier to its shared command router.
