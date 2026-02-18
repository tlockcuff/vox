import { List, Action, ActionPanel, Icon, Color } from "@raycast/api";
import { useState, useEffect } from "react";
import {
  getStatus,
  stopSpeaking,
  togglePlayback,
  setVoice,
  setSpeed,
  getVoice,
  getSpeed,
  VOICE_NAMES,
} from "./utils";

export default function Command() {
  const [state, setState] = useState("stopped");
  const [voice, setVoiceState] = useState(getVoice());
  const [speed, setSpeedState] = useState(getSpeed());

  const refresh = () => {
    const s = getStatus();
    setState(s.state);
    setVoiceState(getVoice());
    setSpeedState(getSpeed());
  };

  useEffect(() => {
    refresh();
    const interval = setInterval(refresh, 1000);
    return () => clearInterval(interval);
  }, []);

  const stateIcon =
    state === "playing"
      ? { source: Icon.Play, tintColor: Color.Green }
      : state === "paused"
        ? { source: Icon.Pause, tintColor: Color.Yellow }
        : { source: Icon.Stop, tintColor: Color.SecondaryText };

  const stateText =
    state === "playing" ? "Playing" : state === "paused" ? "Paused" : "Stopped";

  return (
    <List>
      <List.Section title="Playback">
        <List.Item
          icon={stateIcon}
          title={stateText}
          subtitle={`Voice: ${VOICE_NAMES[voice] || voice} • Speed: ${speed}x`}
          actions={
            <ActionPanel>
              {state === "playing" && (
                <Action
                  title="Pause"
                  icon={Icon.Pause}
                  onAction={() => {
                    togglePlayback();
                    refresh();
                  }}
                />
              )}
              {state === "paused" && (
                <Action
                  title="Resume"
                  icon={Icon.Play}
                  onAction={() => {
                    togglePlayback();
                    refresh();
                  }}
                />
              )}
              {(state === "playing" || state === "paused") && (
                <Action
                  title="Stop"
                  icon={Icon.Stop}
                  onAction={() => {
                    stopSpeaking();
                    refresh();
                  }}
                />
              )}
            </ActionPanel>
          }
        />
      </List.Section>

      <List.Section title="Speed">
        {["0.5", "0.75", "1.0", "1.25", "1.5", "1.75", "2.0"].map((s) => (
          <List.Item
            key={s}
            icon={s === speed ? Icon.Checkmark : Icon.Circle}
            title={`${s}x`}
            subtitle={
              s === "0.5"
                ? "Slow"
                : s === "1.0"
                  ? "Normal"
                  : s === "2.0"
                    ? "Fast"
                    : ""
            }
            actions={
              <ActionPanel>
                <Action
                  title={`Set Speed to ${s}x`}
                  onAction={() => {
                    setSpeed(s);
                    setSpeedState(s);
                  }}
                />
              </ActionPanel>
            }
          />
        ))}
      </List.Section>

      <List.Section title="Voice">
        {Object.entries(VOICE_NAMES).map(([id, name]) => (
          <List.Item
            key={id}
            icon={id === voice ? Icon.Checkmark : Icon.Person}
            title={name}
            subtitle={`ID: ${id}`}
            actions={
              <ActionPanel>
                <Action
                  title={`Set Voice to ${name}`}
                  onAction={() => {
                    setVoice(id);
                    setVoiceState(id);
                  }}
                />
              </ActionPanel>
            }
          />
        ))}
      </List.Section>
    </List>
  );
}
