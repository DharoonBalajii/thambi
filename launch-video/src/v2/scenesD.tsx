import React from "react";
import { AbsoluteFill, interpolate } from "remotion";
import { font, mono } from "../theme";
import { Bg, BlurWords, clamp, Focus, inOut, k, Mark, Mono, out, p, TypeLine, useT } from "./kit";
import { Fragment } from "./scenesA";

// Thambi's main feature: hold Control + Option anywhere, ask out loud, and it reads the screen,
// draws on it (arrows, circles, underlines) and opens a 3D model to explain, using your own notes.
type SceneProps = { frames: number };
const center: React.CSSProperties = { alignItems: "center", justifyContent: "center" };

/** A Mac modifier key: symbol top right, name bottom left. */
const MacKey: React.FC<{ name: string; symbol: string; pressed: number; scale?: number; glow?: number }> = ({ name, symbol, pressed, scale = 1, glow = pressed }) => (
  <div style={{ width: 250 * scale, height: 160 * scale, borderRadius: 26 * scale, background: "#fff", position: "relative", fontFamily: font, color: k.ink,
    transform: `translateY(${pressed * 9 * scale}px)`,
    boxShadow: `0 ${(10 - pressed * 8) * scale}px 0 #D4D4D8, 0 0 0 ${1.5 * scale}px ${glow > 0.5 ? k.indigo : "#D4D4D8"}, 0 0 ${40 * glow * scale}px rgba(79,70,229,${0.45 * glow}), 0 ${24 * scale}px ${50 * scale}px rgba(0,0,0,0.10)` }}>
    <span style={{ position: "absolute", right: 22 * scale, top: 14 * scale, fontSize: 40 * scale, fontWeight: 500, color: glow > 0.5 ? k.indigo : k.ink }}>{symbol}</span>
    <span style={{ position: "absolute", left: 22 * scale, bottom: 16 * scale, fontSize: 28 * scale, fontWeight: 600 }}>{name}</span>
  </div>
);

/** "Call it from anywhere": the two keys pressed on the beat. */
export const Keys: React.FC<SceneProps> = ({ frames }) => {
  const frame = useT();
  const pressAt = 45;
  const pressed = p(frame, pressAt, 4);
  const ripple = p(frame, pressAt, 22);
  return (
    <Focus frames={frames}>
      <Bg kind="white" />
      <Fragment x={110} y={120} w={300} delay={4} label="Lecture slides" tag="PowerPoint" />
      <Fragment x={1480} y={150} w={320} delay={8} label="Course PDF" rows={4} />
      <Fragment x={160} y={760} w={320} delay={12} label="Browser" rows={2} />
      <Fragment x={1440} y={760} w={330} delay={16} label="Lab notes" tag="Handwritten" />
      <div style={{ position: "absolute", left: 0, right: 0, top: 250 }}>
        <BlurWords text="Call it from anywhere" delay={2} stagger={4} size={88} weight={600} accentWords={["anywhere"]} />
      </div>
      <AbsoluteFill style={{ ...center, flexDirection: "row", gap: 40, top: 120 }}>
        {frame >= pressAt ? (
          <div style={{ position: "absolute", width: 700, height: 300, borderRadius: 60, border: `3px solid ${k.indigo}`, opacity: 1 - ripple, transform: `scale(${0.8 + ripple * 0.5})` }} />
        ) : null}
        {[["control", "⌃"], ["option", "⌥"]].map(([name, symbol], i) => {
          const t = p(frame, 16 + i * 5, 14);
          return (
            <React.Fragment key={name}>
              {i === 1 ? <span style={{ fontFamily: font, fontSize: 60, color: "#A0A0A8", opacity: t }}>+</span> : null}
              <div style={{ opacity: t, transform: `translateY(${(1 - t) * 60}px)` }}><MacKey name={name} symbol={symbol} pressed={pressed} /></div>
            </React.Fragment>
          );
        })}
      </AbsoluteFill>
      <div style={{ position: "absolute", left: 0, right: 0, top: 790 }}>
        <BlurWords text="Hold both keys and just ask" delay={50} stagger={3} size={40} color="#6E6E78" />
      </div>
    </Focus>
  );
};

// ---------------------------------------------------------------- the tutor scene

const SLIDE = { x: 288, y: 160, w: 1344, h: 756 };
const BULLETS = ["Double helix", "Sugar-phosphate backbone", "Complementary base pairs", "Hydrogen bonds"];
const BULLET_Y = (i: number) => 236 + i * 72;
const DIAGRAM = { cx: 1010, top: 120, bottom: 700, amp: 150 };
const phase = (y: number) => ((y - DIAGRAM.top) / (DIAGRAM.bottom - DIAGRAM.top)) * Math.PI * 2 * 1.1;
const strandX = (y: number, side: 1 | -1) => DIAGRAM.cx + side * DIAGRAM.amp * Math.sin(phase(y));
const RUNGS = Array.from({ length: 11 }, (_, i) => 150 + i * 52);
const BASES = ["A", "T", "G", "C", "G", "A", "T", "C", "A", "G", "T"];
const PAIR: Record<string, string> = { A: "T", T: "A", G: "C", C: "G" };
const BASE_COLOR: Record<string, string> = { A: k.orange, T: k.green, G: k.indigo, C: "#DB2777" };
// The rung the hydrogen-bond step points at: the widest one in the lower half.
const BOND_RUNG = RUNGS.slice(6, 10).reduce((best, y) => (Math.abs(Math.sin(phase(y))) > Math.abs(Math.sin(phase(best))) ? y : best), RUNGS[6]);

/** The student's own lecture slide, as it would sit on their screen. */
const Slide: React.FC = () => {
  const strand = (side: 1 | -1) => Array.from({ length: 59 }, (_, i) => { const y = DIAGRAM.top + i * 10; return `${i ? "L" : "M"}${strandX(y, side)} ${y}`; }).join(" ");
  return (
    <div style={{ position: "absolute", left: SLIDE.x, top: SLIDE.y - 40, width: SLIDE.w, height: SLIDE.h + 40, borderRadius: 18, overflow: "hidden", background: "#fff",
      boxShadow: "0 40px 100px rgba(0,0,0,0.16), 0 0 0 1.5px rgba(0,0,0,0.08)", fontFamily: font }}>
      <div style={{ height: 40, background: "#F4F4F5", borderBottom: "1.5px solid #E4E4E7", display: "flex", alignItems: "center", justifyContent: "center" }}>
        <span style={{ fontFamily: mono, fontSize: 16, color: "#8E8E98" }}>Biology lecture 4.pptx</span>
      </div>
      <div style={{ position: "relative", width: SLIDE.w, height: SLIDE.h }}>
        <div style={{ position: "absolute", left: 70, top: 56, fontSize: 56, fontWeight: 700, color: k.ink, letterSpacing: -1.5 }}>DNA structure</div>
        <div style={{ position: "absolute", left: 72, top: 134, fontFamily: mono, fontSize: 20, color: "#8E8E98" }}>Biology, lecture 4, slide 9</div>
        {BULLETS.map((text, i) => (
          <div key={text} style={{ position: "absolute", left: 74, top: BULLET_Y(i) - 30, display: "flex", alignItems: "center", gap: 20, fontSize: 31, color: "#3F3F46", fontWeight: 500 }}>
            <span style={{ width: 12, height: 12, borderRadius: 3, background: "#A1A1AA" }} />{text}
          </div>
        ))}
        <svg width={SLIDE.w} height={SLIDE.h} style={{ position: "absolute", left: 0, top: 0 }}>
          {RUNGS.map((y, i) => {
            const a = strandX(y, 1), b = strandX(y, -1), mid = (a + b) / 2;
            const base = BASES[i], pair = PAIR[base];
            return (
              <g key={y}>
                <line x1={a} y1={y} x2={mid} y2={y} stroke={BASE_COLOR[base]} strokeWidth={10} strokeLinecap="round" />
                <line x1={mid} y1={y} x2={b} y2={y} stroke={BASE_COLOR[pair]} strokeWidth={10} strokeLinecap="round" />
                {Math.abs(a - b) > 90 ? (
                  <>
                    <text x={a + (a < b ? 18 : -18)} y={y - 12} fontFamily={font} fontSize={17} fontWeight={700} fill={BASE_COLOR[base]} textAnchor="middle">{base}</text>
                    <text x={b + (a < b ? -18 : 18)} y={y - 12} fontFamily={font} fontSize={17} fontWeight={700} fill={BASE_COLOR[pair]} textAnchor="middle">{pair}</text>
                  </>
                ) : null}
              </g>
            );
          })}
          <path d={strand(1)} fill="none" stroke="#52525B" strokeWidth={9} strokeLinecap="round" />
          <path d={strand(-1)} fill="none" stroke="#A1A1AA" strokeWidth={9} strokeLinecap="round" />
        </svg>
      </div>
    </div>
  );
};

/** A pen stroke that draws itself. */
const Ink: React.FC<{ d: string; at: number; dur?: number; width?: number; color?: string; dash?: boolean }> = ({ d, at, dur = 14, width = 6, color = k.indigo, dash }) => {
  const frame = useT();
  const t = p(frame, at, dur, inOut);
  if (t <= 0) return null;
  return <path d={d} pathLength={1} fill="none" stroke={color} strokeWidth={width} strokeLinecap="round" strokeLinejoin="round"
    strokeDasharray={dash ? undefined : "1 1"} strokeDashoffset={dash ? undefined : 1 - t} opacity={dash ? t : 1} style={{ filter: "drop-shadow(0 2px 6px rgba(79,70,229,0.35))" }} />;
};

/** A hand-drawn loop around a point. */
const loop = (cx: number, cy: number, rx: number, ry: number, seed: number) => {
  const pts = Array.from({ length: 50 }, (_, i) => {
    const a = -Math.PI * 0.6 + (i / 49) * Math.PI * 2.15;
    const wob = 1 + 0.04 * Math.sin(i * 0.9 + seed) + 0.03 * Math.sin(i * 0.37 + seed * 2);
    return `${i ? "L" : "M"}${(cx + Math.cos(a) * rx * wob).toFixed(1)} ${(cy + Math.sin(a) * ry * wob * (1 + i / 400)).toFixed(1)}`;
  });
  return pts.join(" ");
};

/** A curved arrow from one point to another, with its head as a second stroke. */
const Arrow: React.FC<{ from: [number, number]; to: [number, number]; bend?: number; at: number; dur?: number }> = ({ from, to, bend = -0.25, at, dur = 16 }) => {
  const [x1, y1] = from, [x2, y2] = to;
  const mx = (x1 + x2) / 2 - (y2 - y1) * bend, my = (y1 + y2) / 2 + (x2 - x1) * bend;
  const ang = Math.atan2(y2 - my, x2 - mx);
  const head = (da: number) => `${x2 - Math.cos(ang + da) * 26} ${y2 - Math.sin(ang + da) * 26}`;
  return (
    <>
      <Ink d={`M${x1} ${y1} Q${mx} ${my} ${x2} ${y2}`} at={at} dur={dur} />
      <Ink d={`M${head(0.5)} L${x2} ${y2} L${head(-0.5)}`} at={at + dur - 2} dur={6} />
    </>
  );
};

/** The helix, actually 3D: points on two strands rotated in space, projected and depth sorted. */
const Helix: React.FC<{ width: number; height: number; grow: number; spin: number; labels: number }> = ({ width, height, grow, spin, labels }) => {
  const pairs = 16, rise = 35, radius = 150, f = 900, tilt = 0.32;
  const cx = width / 2, cy = height / 2 + 10;
  const project = (x: number, y: number, z: number) => {
    const y2 = y * Math.cos(tilt) - z * Math.sin(tilt);
    const z2 = y * Math.sin(tilt) + z * Math.cos(tilt);
    const s = f / (f + z2);
    return { x: cx + x * s, y: cy + y2 * s, z: z2, s };
  };
  type Item = { z: number; el: React.ReactNode };
  const items: Item[] = [];
  const strandPts: { x: number; y: number; z: number; s: number }[][] = [[], []];
  for (let i = 0; i < pairs; i++) {
    const show = interpolate(grow * pairs, [i, i + 1.2], [0, 1], clamp);
    const y = (i - (pairs - 1) / 2) * rise;
    const a = i * 0.62 + spin;
    const base = BASES[i % BASES.length];
    const pts = [0, Math.PI * 0.82].map((off) => project(Math.cos(a + off) * radius * show, -y, Math.sin(a + off) * radius * show));
    strandPts[0].push(pts[0]); strandPts[1].push(pts[1]);
    if (show <= 0) continue;
    const mid = { x: (pts[0].x + pts[1].x) / 2, y: (pts[0].y + pts[1].y) / 2 };
    items.push({ z: (pts[0].z * 3 + pts[1].z) / 4, el: <line key={`r${i}a`} x1={pts[0].x} y1={pts[0].y} x2={mid.x} y2={mid.y} stroke={BASE_COLOR[base]} strokeWidth={11 * pts[0].s} strokeLinecap="round" opacity={show} /> });
    items.push({ z: (pts[1].z * 3 + pts[0].z) / 4, el: <line key={`r${i}b`} x1={mid.x} y1={mid.y} x2={pts[1].x} y2={pts[1].y} stroke={BASE_COLOR[PAIR[base]]} strokeWidth={11 * pts[1].s} strokeLinecap="round" opacity={show} /> });
    pts.forEach((pt, side) => items.push({ z: pt.z - 1, el: <circle key={`s${i}${side}`} cx={pt.x} cy={pt.y} r={17 * pt.s * show} fill={side ? "url(#ballB)" : "url(#ballA)"} /> }));
  }
  strandPts.forEach((pts, side) => {
    for (let i = 0; i + 1 < pts.length; i++) {
      const showNext = interpolate(grow * pairs, [i + 1, i + 2.2], [0, 1], clamp);
      if (showNext <= 0) continue;
      const a = pts[i], b = pts[i + 1];
      items.push({ z: (a.z + b.z) / 2 + 2, el: <line key={`b${side}${i}`} x1={a.x} y1={a.y} x2={b.x} y2={b.y} stroke={side ? "#A5B4FC" : "#E4E4E7"} strokeWidth={8 * (a.s + b.s) / 2} strokeLinecap="round" opacity={showNext} /> });
    }
  });
  items.sort((a, b) => b.z - a.z);
  // Labels follow points as the model turns.
  const front = strandPts[0][5], rung = strandPts[0][11], rungB = strandPts[1][11];
  const rungMid = rung && rungB ? { x: (rung.x + rungB.x) / 2, y: (rung.y + rungB.y) / 2 } : null;
  return (
    <svg width={width} height={height}>
      <defs>
        <radialGradient id="ballA" cx="35%" cy="30%"><stop offset="0%" stopColor="#FFFFFF" /><stop offset="45%" stopColor="#D4D4D8" /><stop offset="100%" stopColor="#52525B" /></radialGradient>
        <radialGradient id="ballB" cx="35%" cy="30%"><stop offset="0%" stopColor="#EEF2FF" /><stop offset="45%" stopColor="#818CF8" /><stop offset="100%" stopColor="#3730A3" /></radialGradient>
      </defs>
      {items.map((item) => item.el)}
      {front && labels > 0 ? (
        <g opacity={labels}>
          <line x1={front.x - 18} y1={front.y} x2={cx - 250} y2={front.y} stroke="#fff" strokeWidth={2} opacity={0.55} />
          <circle cx={front.x} cy={front.y} r={6} fill="none" stroke="#fff" strokeWidth={2} />
          <text x={cx - 262} y={front.y + 8} fill="#fff" fontFamily={font} fontSize={24} fontWeight={600} textAnchor="end">Backbone</text>
        </g>
      ) : null}
      {rungMid && labels > 0 ? (
        <g opacity={labels}>
          <line x1={rungMid.x + 10} y1={rungMid.y} x2={cx + 250} y2={rungMid.y} stroke="#fff" strokeWidth={2} opacity={0.55} />
          <circle cx={rungMid.x} cy={rungMid.y} r={6} fill="none" stroke="#fff" strokeWidth={2} />
          <text x={cx + 262} y={rungMid.y + 8} fill="#fff" fontFamily={font} fontSize={24} fontWeight={600}>Base pair</text>
        </g>
      ) : null}
    </svg>
  );
};

/** One caption line Thambi speaks, as a subtitle with a small voice wave. */
const Caption: React.FC<{ windows: [number, number, string, string?][] }> = ({ windows }) => {
  const frame = useT();
  const current = windows.find(([a, b]) => frame >= a && frame < b);
  if (!current) return null;
  const [a, b, text, source] = current;
  const t = p(frame, a, 8) * (1 - p(frame, b - 6, 6));
  return (
    <div style={{ position: "absolute", left: "50%", top: 948, transform: `translate(-50%, ${(1 - t) * 16}px)`, opacity: t, display: "flex", alignItems: "center", gap: 16,
      background: k.ink, color: "#fff", fontFamily: font, fontSize: 28, fontWeight: 600, padding: "16px 26px", borderRadius: 18, whiteSpace: "nowrap", boxShadow: "0 20px 50px rgba(0,0,0,0.25)" }}>
      <span style={{ display: "flex", gap: 3, alignItems: "center", height: 24 }}>
        {[0, 1, 2, 3].map((i) => <span key={i} style={{ width: 4, borderRadius: 2, background: k.indigoSoft, height: 8 + Math.abs(Math.sin(frame / 3 + i * 1.3)) * 16 }} />)}
      </span>
      {text}
      {source ? <span style={{ fontFamily: mono, fontSize: 18, color: "#A5B4FC", fontWeight: 500, marginLeft: 6 }}>{source}</span> : null}
    </div>
  );
};

/** The keys, held: a small reminder of how the student called Thambi, with what they said. */
const HeldKeys: React.FC<{ holds: [number, number, string][] }> = ({ holds }) => {
  const frame = useT();
  const active = holds.find(([a, b]) => frame >= a - 4 && frame < b + 18);
  const held = holds.some(([a, b]) => frame >= a && frame < b);
  const pressed = held ? 1 : 0;
  const said = active ? active[2] : "";
  return (
    <div style={{ position: "absolute", left: 60, top: 936, display: "flex", alignItems: "center", gap: 14 }}>
      <MacKey name="control" symbol="⌃" pressed={pressed} scale={0.42} />
      <MacKey name="option" symbol="⌥" pressed={pressed} scale={0.42} />
      {active ? (
        <div style={{ marginLeft: 12, display: "flex", alignItems: "center", gap: 12, background: "#fff", borderRadius: 16, padding: "12px 18px", boxShadow: "0 10px 30px rgba(0,0,0,0.10), 0 0 0 1.5px rgba(0,0,0,0.06)",
          opacity: p(frame, active[0] - 4, 6) * (1 - p(frame, active[1] + 10, 8)) }}>
          <svg width="18" height="24" viewBox="0 0 18 24"><rect x="5" y="1" width="8" height="14" rx="4" fill={held ? k.indigo : "#A1A1AA"} /><path d="M2 11a7 7 0 0 0 14 0M9 18v5" stroke={held ? k.indigo : "#A1A1AA"} strokeWidth="2" fill="none" strokeLinecap="round" /></svg>
          <TypeLine text={said} delay={active[0] + 6} speed={0.75} size={24} caret={false} />
        </div>
      ) : null}
    </div>
  );
};

/** Hold, ask, and Thambi reads the slide, draws on it and opens it in 3D. One continuous take. */
export const Tutor: React.FC<SceneProps> = ({ frames }) => {
  const frame = useT();
  const DROP = 84, S2 = 160, S3 = 236, ASK3D = 312, PANEL = 350;
  // Camera: push in on each thing Thambi explains, then pull back for the model.
  const cam = [
    [0, 960, 540, 1], [DROP, 960, 540, 1], [DROP + 14, 760, 450, 1.16], [S2 - 4, 760, 450, 1.16], [S2 + 12, 1120, 560, 1.15], [S3 - 4, 1120, 560, 1.15],
    [S3 + 12, 1000, 640, 1.14], [ASK3D - 6, 1000, 640, 1.14], [ASK3D + 12, 960, 540, 1],
  ];
  const at = (idx: number) => interpolate(frame, cam.map((c) => c[0]), cam.map((c) => c[idx]), { ...clamp, easing: inOut });
  const [fx, fy, s] = [at(1), at(2), at(3)];
  const panel = p(frame, PANEL - 8, 20, out);
  const scan = interpolate(frame, [62, 84], [0, 1], clamp);
  // Where Thambi flies, in screen space.
  const stops = [
    [0, 1290, 520], [10, 1290, 520], [60, 1290, 520], [72, 1560, 230], [DROP, 1560, 230], [DROP + 12, 880, 372], [S2, 880, 372], [S2 + 12, 960, 470],
    [S3, 960, 470], [S3 + 12, 1130, 780], [ASK3D, 1130, 780], [ASK3D + 14, 1300, 470], [PANEL - 6, 1300, 470], [PANEL + 14, 330, 330],
  ];
  // Thambi lives in screen space but follows the camera while it explains, so it stays beside its drawing.
  const sx = interpolate(frame, stops.map((q) => q[0]), stops.map((q) => q[1]), { ...clamp, easing: inOut });
  const sy = interpolate(frame, stops.map((q) => q[0]), stops.map((q) => q[2]), { ...clamp, easing: inOut });
  const follow = 1 - panel;
  const bx = sx + ((960 + (sx - fx) * s) - sx) * follow;
  const by = sy + ((540 + (sy - fy) * s) - sy) * follow;
  const appear = p(frame, 6, 10);
  const listening = (frame >= 6 && frame < 60) || (frame >= ASK3D && frame < ASK3D + 30);
  const b2y = BULLET_Y(1), b3y = BULLET_Y(2), b4y = BULLET_Y(3);
  const backboneY = 300;
  const rungMid = (RUNGS[4] + RUNGS[5]) / 2;
  return (
    <Focus frames={frames} zoom={0.02}>
      <Bg kind="grad" />
      <AbsoluteFill style={{ transformOrigin: "0 0", transform: `translate(${960 - fx * s}px, ${540 - fy * s}px) scale(${s})`,
        filter: panel > 0.02 ? `blur(${panel * 5}px)` : undefined, opacity: 1 - panel * 0.55 }}>
        <Slide />
        {/* Reading the screen: a beam sweeps the slide and what it found lights up. */}
        {frame >= 60 && frame < 96 ? (
          <div style={{ position: "absolute", left: SLIDE.x, top: SLIDE.y, width: SLIDE.w, height: SLIDE.h, overflow: "hidden", opacity: 1 - p(frame, 86, 10) }}>
            <div style={{ position: "absolute", left: 0, right: 0, top: scan * SLIDE.h - 70, height: 70, background: "linear-gradient(180deg, rgba(79,70,229,0) 0%, rgba(79,70,229,0.18) 85%, rgba(79,70,229,0.9) 100%)" }} />
            {[[54, 40, 470, 125], [60, 196, 560, 270], [790, 110, 450, 610]].map(([x, y, w, h], i) => {
              const lit = scan * SLIDE.h > y + h * 0.4 ? 1 : 0;
              return <div key={i} style={{ position: "absolute", left: x, top: y, width: w, height: h, border: `2.5px dashed ${k.indigo}`, borderRadius: 12, opacity: lit * 0.9, background: "rgba(79,70,229,0.05)" }} />;
            })}
          </div>
        ) : null}
        {/* What Thambi draws, in the slide's own coordinates. */}
        <svg width={SLIDE.w} height={SLIDE.h} style={{ position: "absolute", left: SLIDE.x, top: SLIDE.y, overflow: "visible" }}>
          <Ink d={`M108 ${b2y + 14} Q300 ${b2y + 22} 500 ${b2y + 12}`} at={DROP + 8} dur={12} />
          <Arrow from={[520, b2y - 4]} to={[strandX(backboneY, 1) - 24, backboneY]} bend={-0.18} at={DROP + 20} />
          <Ink d={loop(strandX(backboneY, 1), backboneY, 34, 60, 1)} at={DROP + 34} dur={14} />
          <Ink d={`M108 ${b3y + 14} Q300 ${b3y + 22} 506 ${b3y + 12}`} at={S2 + 6} dur={12} />
          <Ink d={loop(DIAGRAM.cx, rungMid, 205, 62, 2)} at={S2 + 16} dur={16} />
          <Arrow from={[524, b3y - 2]} to={[DIAGRAM.cx - 215, rungMid]} bend={0.12} at={S2 + 30} />
          <Ink d={`M108 ${b4y + 14} Q220 ${b4y + 20} 330 ${b4y + 12}`} at={S3 + 6} dur={10} />
          <Arrow from={[350, b4y - 6]} to={[DIAGRAM.cx - 12, BOND_RUNG + 18]} bend={-0.2} at={S3 + 16} dur={18} />
          {[-16, 0, 16].map((dx, i) => <Ink key={dx} d={`M${DIAGRAM.cx + dx} ${BOND_RUNG - 22} L${DIAGRAM.cx + dx} ${BOND_RUNG + 22}`} at={S3 + 36 + i * 3} dur={5} width={4} color={k.orange} />)}
        </svg>
        {/* The student's own pointer, where they were working. */}
        <svg width="34" height="40" viewBox="0 0 34 40" style={{ position: "absolute", left: 1230, top: 530, opacity: 1 - p(frame, 70, 10), filter: "drop-shadow(0 4px 8px rgba(0,0,0,0.25))" }}>
          <path d="M3 3 L3 31 L11 24 L16 36 L22 33.5 L17 22 L28 22 Z" fill="#111827" stroke="#fff" strokeWidth="2.4" strokeLinejoin="round" />
        </svg>
      </AbsoluteFill>
      {/* The 3D model, in Thambi's own panel. */}
      {panel > 0 ? (
        <div style={{ position: "absolute", left: 490, top: 120, width: 940, height: 760, borderRadius: 24, overflow: "hidden", opacity: panel, transform: `scale(${0.9 + panel * 0.1}) translateY(${(1 - panel) * 40}px)`,
          background: "radial-gradient(80% 80% at 50% 40%, #232327 0%, #121214 70%)", boxShadow: "0 50px 120px rgba(0,0,0,0.35), 0 0 0 1.5px rgba(255,255,255,0.08)", fontFamily: font }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", padding: "22px 28px 0" }}>
            <span style={{ fontSize: 26, fontWeight: 700, color: "#fff" }}>DNA double helix</span>
            <Mono size={17} color="#A1A1AA">3D model, drag to turn</Mono>
          </div>
          <Helix width={940} height={690} grow={p(frame, PANEL, 40, inOut)} spin={frame * 0.045} labels={p(frame, PANEL + 70, 12)} />
        </div>
      ) : null}
      {/* Thambi itself, beside what it is explaining. */}
      <div style={{ position: "absolute", left: bx, top: by, opacity: appear, transform: `scale(${0.4 + appear * 0.6})`, zIndex: 10 }}>
        <Mark size={64} />
        {listening ? (
          <div style={{ position: "absolute", left: 74, top: 20, display: "flex", gap: 3, alignItems: "center", height: 26 }}>
            {[0, 1, 2, 3, 4].map((i) => <span key={i} style={{ width: 4, borderRadius: 2, background: k.indigo, height: 6 + Math.abs(Math.sin(frame / 2.5 + i * 1.1)) * 20 }} />)}
          </div>
        ) : null}
      </div>
      <HeldKeys holds={[[0, 58, "Explain this slide using my notes"], [ASK3D, ASK3D + 28, "Show me in 3D"]]} />
      <Caption windows={[
        [62, DROP, "Reading your slide…"],
        [DROP + 4, S2 - 2, "These sides are the sugar-phosphate backbone", "Your notes, page 12"],
        [S2 + 2, S3 - 2, "Across the middle, A pairs with T and G with C"],
        [S3 + 2, ASK3D - 2, "Hydrogen bonds hold each pair together"],
        [PANEL + 4, PANEL + 74, "Here it is in 3D"],
        [PANEL + 76, frames + 10, "Each rung is one base pair"],
      ]} />
    </Focus>
  );
};

/** The quiet beat in the music: where the answers come from. */
export const OwnNotes: React.FC<SceneProps> = ({ frames }) => {
  const frame = useT();
  const part = p(frame, 40, 14, inOut);
  const words = ["It", "teaches", "from", "your"];
  return (
    <Focus frames={frames}>
      <Bg kind="black" />
      <AbsoluteFill style={{ ...center, flexDirection: "column", gap: 56 }}>
        <div style={{ display: "flex", gap: 22 + part * 70, fontFamily: font, fontSize: 84, fontWeight: 500, letterSpacing: -2.4, color: "#fff" }}>
          {words.map((word, i) => {
            const t = p(frame, 4 + i * 4, 10);
            return <span key={word} style={{ opacity: t * (1 - part * 0.55), filter: `blur(${(1 - t) * 14}px)` }}>{word}</span>;
          })}
          <span style={{ color: k.indigoSoft, opacity: p(frame, 22, 10), transform: `scale(${1 + part * 0.12})` }}>{"{ own notes }"}</span>
        </div>
        <div style={{ display: "flex", gap: 16 }}>
          {["PowerPoint slides", "PDFs", "photos of notes", "textbooks"].map((chip, i) => {
            const t = p(frame, 48 + i * 5, 10);
            return <div key={chip} style={{ opacity: t, transform: `translateY(${(1 - t) * 16}px)`, border: "1.5px solid rgba(255,255,255,0.2)", borderRadius: 12, padding: "12px 20px" }}><Mono size={22}>{chip}</Mono></div>;
          })}
        </div>
      </AbsoluteFill>
    </Focus>
  );
};

