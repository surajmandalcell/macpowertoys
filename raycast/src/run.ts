import { open } from "@raycast/api";

export function openTool(toolID: string) {
  return async function run() {
    await open(`macpowertoys://open/${toolID}`);
  };
}
