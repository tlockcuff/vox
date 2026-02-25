import { showHUD } from "@raycast/api";
import { togglePlayback } from "./utils";

export default async function Command() {
  togglePlayback();
  await showHUD("⏯️ Toggled");
}
