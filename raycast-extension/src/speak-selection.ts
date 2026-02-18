import { getSelectedText, showHUD, showToast, Toast } from "@raycast/api";
import { speak, isInstalled } from "./utils";

export default async function Command() {
  if (!isInstalled()) {
    await showToast({
      style: Toast.Style.Failure,
      title: "Vox not installed",
      message: "Run the install.sh script first",
    });
    return;
  }

  try {
    const text = await getSelectedText();
    if (!text || text.trim().length === 0) {
      await showHUD("⚠️ No text selected");
      return;
    }

    await showHUD("🗣️ Speaking...");
    speak(text);
  } catch {
    await showHUD("⚠️ Could not get selected text — make sure text is highlighted");
  }
}
