import React from "react";
import { AbsoluteFill, Audio, staticFile } from "remotion";
import { linearTiming, springTiming, TransitionSeries } from "@remotion/transitions";
import { fade } from "@remotion/transitions/fade";
import { slide } from "@remotion/transitions/slide";
import { wipe } from "@remotion/transitions/wipe";
import { Closing, Hook, LogoReveal } from "./scenes/Opening";
import { AskScene, LibraryScene, MarksScene, PlanScene, PracticeScene } from "./scenes/Product";
import { BuddyScene, GridScene, TrustScene } from "./scenes/More";

export const TRANSITION = 15;

// Each scene and how long it holds, in frames at 30 fps.
export const scenes: { id: string; frames: number; view: React.FC }[] = [
  { id: "hook", frames: 120, view: Hook },
  { id: "logo", frames: 110, view: LogoReveal },
  { id: "library", frames: 165, view: LibraryScene },
  { id: "ask", frames: 215, view: AskScene },
  { id: "marks", frames: 160, view: MarksScene },
  { id: "practice", frames: 225, view: PracticeScene },
  { id: "plan", frames: 200, view: PlanScene },
  { id: "buddy", frames: 185, view: BuddyScene },
  { id: "grid", frames: 215, view: GridScene },
  { id: "trust", frames: 150, view: TrustScene },
  { id: "closing", frames: 165, view: Closing },
];

export const totalFrames = scenes.reduce((sum, scene) => sum + scene.frames, 0) - TRANSITION * (scenes.length - 1);

const transitions = [
  fade(), slide({ direction: "from-right" }), wipe({ direction: "from-left" }), slide({ direction: "from-bottom" }), fade(),
  slide({ direction: "from-right" }), wipe({ direction: "from-top-left" }), slide({ direction: "from-bottom" }), fade(), fade(),
];

export const Launch: React.FC<{ withMusic: boolean }> = ({ withMusic }) => (
  <AbsoluteFill style={{ background: "#0E0F1D" }}>
    {withMusic ? <Audio src={staticFile("soundtrack.wav")} volume={0.9} /> : null}
    <TransitionSeries>
      {scenes.map((scene, i) => (
        <React.Fragment key={scene.id}>
          <TransitionSeries.Sequence durationInFrames={scene.frames}>
            <scene.view />
          </TransitionSeries.Sequence>
          {i < scenes.length - 1 ? (
            <TransitionSeries.Transition presentation={transitions[i] as never}
              timing={i % 2 === 0 ? linearTiming({ durationInFrames: TRANSITION }) : springTiming({ durationInFrames: TRANSITION, config: { damping: 200 } })} />
          ) : null}
        </React.Fragment>
      ))}
    </TransitionSeries>
  </AbsoluteFill>
);
