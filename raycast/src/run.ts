import { open, showHUD } from "@raycast/api";

export function command(action: string, parameters?: Record<string, string>) {
  return async function run() {
    const query = parameters ? `?${new URLSearchParams(parameters)}` : "";
    await open(`powertoys://run/${action}${query}`);
    await showHUD("PowerToys command sent");
  };
}
