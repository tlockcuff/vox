import { showHUD } from "@raycast/api";
import { stopSpeaking } from "./utils";

export default async function Command() {
  stopSpeaking();
  await showHUD("🔇 Stopped");
}
