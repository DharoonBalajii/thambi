import React from "react";
import { Composition } from "remotion";
import { Launch, totalFrames } from "./Launch";
import { LaunchV2, totalFramesV2 } from "./v2/LaunchV2";
import { FPS, H, W } from "./theme";

export const Root: React.FC = () => (
  <>
    <Composition id="Launch" component={Launch} durationInFrames={totalFrames} fps={FPS} width={W} height={H} defaultProps={{ withMusic: false }} />
    <Composition id="LaunchV2" component={LaunchV2} durationInFrames={totalFramesV2} fps={FPS} width={W} height={H} defaultProps={{ withMusic: false }} />
  </>
);
