import { showHUD } from "@raycast/api";
import { togglePlayback, getStatus } from "./utils";

export default async function Command() {
  togglePlayback();
  const status = getStatus();
  if (status.state === "paused") {
    await showHUD("▶️ Resumed");
  } else {
    await showHUD("⏸️ Paused");
  }
}
