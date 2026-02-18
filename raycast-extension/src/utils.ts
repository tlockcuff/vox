import { execSync } from "child_process";
import { homedir } from "os";
import { existsSync, readFileSync, writeFileSync } from "fs";
import path from "path";

const SPEAKSEL_DIR = path.join(homedir(), ".speaksel");
const SCRIPT = path.join(SPEAKSEL_DIR, "speaksel.sh");

export function isInstalled(): boolean {
  return existsSync(SCRIPT);
}

export function runCommand(cmd: string): string {
  const env = {
    ...process.env,
    DYLD_LIBRARY_PATH: `${SPEAKSEL_DIR}/bin:${process.env.DYLD_LIBRARY_PATH || ""}`,
  };
  try {
    return execSync(`"${SCRIPT}" ${cmd}`, { env, timeout: 30000 }).toString().trim();
  } catch {
    return "";
  }
}

export function speak(text: string): void {
  const env = {
    ...process.env,
    DYLD_LIBRARY_PATH: `${SPEAKSEL_DIR}/bin:${process.env.DYLD_LIBRARY_PATH || ""}`,
  };
  const { execFile } = require("child_process");
  execFile(SCRIPT, ["speak", text], { env, timeout: 60000 }, () => {});
}

export function stopSpeaking(): void {
  runCommand("stop");
}

export function togglePlayback(): void {
  runCommand("toggle");
}

export function getStatus(): { state: string; voice: string; speed: string } {
  try {
    const result = runCommand("status");
    return JSON.parse(result);
  } catch {
    return { state: "stopped", voice: "5", speed: "1.0" };
  }
}

export function setVoice(id: string): void {
  writeFileSync(path.join(SPEAKSEL_DIR, "voice"), id);
}

export function setSpeed(speed: string): void {
  writeFileSync(path.join(SPEAKSEL_DIR, "speed"), speed);
}

export function getVoice(): string {
  const f = path.join(SPEAKSEL_DIR, "voice");
  return existsSync(f) ? readFileSync(f, "utf-8").trim() : "5";
}

export function getSpeed(): string {
  const f = path.join(SPEAKSEL_DIR, "speed");
  return existsSync(f) ? readFileSync(f, "utf-8").trim() : "1.0";
}

export const VOICE_NAMES: Record<string, string> = {
  "0": "American Female",
  "1": "AF - Bella",
  "2": "AF - Nicole",
  "3": "AF - Sarah",
  "4": "AF - Sky",
  "5": "AM - Adam",
  "6": "AM - Michael",
  "7": "BF - Emma",
  "8": "BF - Isabella",
  "9": "BM - George",
  "10": "BM - Lewis",
};
