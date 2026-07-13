import { open, showHUD } from "@raycast/api";

export function command(action: string, parameters?: Record<string, string>) {
  return async function run() {
    const query = parameters ? `?${new URLSearchParams(parameters)}` : "";
    await open(`macpowertoys://run/${action}${query}`);
    await showHUD("MacPowerToys command sent");
  };
}
