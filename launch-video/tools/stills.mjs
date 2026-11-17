import { bundle } from "@remotion/bundler";
import { renderStill, selectComposition } from "@remotion/renderer";
import path from "node:path";
const root = process.cwd();
const frames = process.argv.slice(2).map(Number);
const serveUrl = await bundle({ entryPoint: path.join(root, "src/index.ts") });
const composition = await selectComposition({ serveUrl, id: "LaunchV2", inputProps: {} });
for (const frame of frames) {
  await renderStill({ serveUrl, composition, frame, output: path.join(root, `out/v2stills/f${String(frame).padStart(4, "0")}.png`), scale: 0.5, inputProps: {} });
  console.log("still", frame);
}
