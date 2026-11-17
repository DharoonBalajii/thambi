import React from "react";
import { AbsoluteFill, Audio, interpolate, Series, staticFile } from "remotion";
import timeline from "./timeline.json";
import { SpeedContext } from "./kit";
import { Meet, Problem, Stop, Tagline } from "./scenesA";
import { Remember } from "./scenesB";
import { Ask, Contrast, Cta, Friends, Logo, More, Private } from "./scenesC";
import { Keys, OwnNotes, Tutor } from "./scenesD";

// The launch film, built around Thambi's main feature: hold Control + Option anywhere and it reads
// the screen, draws on it and explains in 3D from your own notes. The cuts follow the music: the
// main feature lands on the track's first drop (17.2 s) and the rest of the app on the second (34.4 s).
// timeline.json is shared with tools/make_sfx.py so key clicks, pen strokes and pops land on their frames.
const TaglineOnScreen: React.FC<{ frames: number }> = ({ frames }) => (
  <Tagline frames={frames} text="Your AI tutor, right on your screen" accentWords={["right", "on", "screen"]} />
);

const scenes: Record<string, React.FC<{ frames: number }>> = {
  problem: Problem, stop: Stop, meet: Meet, tagline: TaglineOnScreen, keys: Keys, tutor: Tutor, ownnotes: OwnNotes,
  ask: Ask, remember: Remember, friends: Friends, more: More, private: Private, contrast: Contrast, logo: Logo, cta: Cta,
};

// What sits behind each scene while it blurs in and out, so a cut never flashes the wrong colour.
const backdrop: Record<string, string> = {
  ownnotes: "#09090B", private: "#09090B", cta: "#09090B",
  meet: "#F4F4F2", tagline: "#F4F4F2", tutor: "#F4F4F2", friends: "#F4F4F2",
};

export const totalFramesV2 = timeline.reduce((sum, scene) => sum + scene.frames, 0);

// The music starts 1.2 s into the file, where its first beat is.
const MUSIC_TRIM = 36;

export const LaunchV2: React.FC<{ withMusic: boolean }> = ({ withMusic }) => (
  <AbsoluteFill style={{ background: "#fff" }}>
    {withMusic ? (
      <>
        <Audio src={staticFile("music/wavetoys-upbeat-drums.mp3")} trimBefore={MUSIC_TRIM}
          volume={(f) => interpolate(f, [0, 4, totalFramesV2 - 12, totalFramesV2], [0, 0.9, 0.9, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" })} />
        <Audio src={staticFile("sfx-v4.wav")} volume={1} />
      </>
    ) : null}
    <Series>
      {timeline.map((scene) => {
        const Scene = scenes[scene.id];
        return (
          <Series.Sequence key={scene.id} durationInFrames={scene.frames}>
            <AbsoluteFill style={{ background: backdrop[scene.id] ?? "#FFFFFF" }}>
              <SpeedContext.Provider value={scene.speed}>
                <Scene frames={scene.frames} />
              </SpeedContext.Provider>
            </AbsoluteFill>
          </Series.Sequence>
        );
      })}
    </Series>
  </AbsoluteFill>
);
