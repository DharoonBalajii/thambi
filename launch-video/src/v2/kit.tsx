import React, { createContext, useContext } from "react";
import { AbsoluteFill, Easing, interpolate, useCurrentFrame } from "remotion";
import { font, mono } from "../theme";

// The second cut's palette: white space, one indigo, deep navy for contrast scenes.
export const k = {
  ink: "#0B1020",
  grey: "#8E8E98",
  line: "#E7E7E4",
  paper: "#F4F4F2",
  graphite: "#111113",
  indigo: "#4F46E5",
  indigoBright: "#6366F1",
  indigoSoft: "#A5B4FC",
  indigoPale: "#E0E7FF",
  navy: "#070B1F",
  orange: "#F97316",
  green: "#16A34A",
  white: "#FFFFFF",
};

/** How fast a scene's own timeline plays, so a scene can be tightened without rewriting its timings. */
export const SpeedContext = createContext(1);
export const useT = () => useCurrentFrame() * useContext(SpeedContext);

export const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
export const out = Easing.bezier(0.16, 1, 0.3, 1);
export const inOut = Easing.bezier(0.65, 0, 0.35, 1);
export const p = (frame: number, from: number, duration: number, easing = out) =>
  interpolate(frame, [from, from + duration], [0, 1], { ...clamp, easing });

type BgKind = "white" | "glow" | "grad" | "deep" | "black";

/** Backgrounds: clean white, warm light grey with a fine dot grid, and graphite. No coloured glow:
 *  colour lives only in the type and the product. They drift slowly so nothing is ever static. */
export const Bg: React.FC<{ kind: BgKind }> = ({ kind }) => {
  const frame = useCurrentFrame();
  const drift = (frame * 0.25) % 32;
  const light = kind === "white" || kind === "glow";
  const paper = kind === "grad";
  const dark = kind === "deep" || kind === "black";
  const base: React.CSSProperties = light
    ? { background: "#FFFFFF" }
    : paper
      ? { background: k.paper }
      : { background: kind === "black" ? "radial-gradient(80% 80% at 50% 45%, #18181B 0%, #09090B 60%, #000000 100%)" : "radial-gradient(75% 75% at 50% 45%, #1C1C1F 0%, #111113 55%, #070708 100%)" };
  return (
    <AbsoluteFill style={base}>
      {light ? (
        <svg width="1920" height="1080" style={{ position: "absolute" }}>
          <circle cx={-200} cy={540} r={700 + frame * 0.6} fill="none" stroke="#EDEDEA" strokeWidth={2} />
          <circle cx={2150} cy={900} r={620 + frame * 0.5} fill="none" stroke="#EDEDEA" strokeWidth={2} />
        </svg>
      ) : null}
      {paper ? (
        <AbsoluteFill style={{ backgroundImage: "radial-gradient(#D9D9D4 1.6px, transparent 1.7px)", backgroundSize: "32px 32px", backgroundPosition: `${drift}px ${drift * 0.5}px`, opacity: 0.8,
          WebkitMaskImage: "radial-gradient(80% 75% at 50% 50%, transparent 30%, #000 100%)", maskImage: "radial-gradient(80% 75% at 50% 50%, transparent 30%, #000 100%)" }} />
      ) : null}
      {dark ? (
        <AbsoluteFill style={{ backgroundImage: "linear-gradient(rgba(255,255,255,0.045) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.045) 1px, transparent 1px)", backgroundSize: "64px 64px",
          backgroundPosition: `0 ${drift * 2}px`, WebkitMaskImage: "radial-gradient(70% 70% at 50% 50%, #000 20%, transparent 100%)", maskImage: "radial-gradient(70% 70% at 50% 50%, #000 20%, transparent 100%)" }} />
      ) : null}
    </AbsoluteFill>
  );
};

/** Every scene pulls into focus at its start and out of focus at its end, so cuts feel like one move. */
export const Focus: React.FC<{ frames: number; children: React.ReactNode; zoom?: number }> = ({ frames, children, zoom = 0.04 }) => {
  const frame = useCurrentFrame();
  const enter = p(frame, 0, 9);
  const leave = p(frame, frames - 8, 8, Easing.in(Easing.cubic));
  const blur = (1 - enter) * 18 + leave * 22;
  return (
    <AbsoluteFill style={{ filter: blur > 0.3 ? `blur(${blur}px)` : undefined, opacity: Math.min(enter * 1.6, 1) * (1 - leave * 0.85),
      transform: `scale(${1 + (1 - enter) * zoom + leave * zoom * 1.6 + (frame / frames) * 0.03})` }}>
      {children}
    </AbsoluteFill>
  );
};

/** A sentence that arrives one word at a time, each word sliding in out of a blur. */
export const BlurWords: React.FC<{ text: string; delay?: number; stagger?: number; size?: number; color?: string; accent?: string; accentWords?: string[]; weight?: number; style?: React.CSSProperties }> = ({
  text, delay = 0, stagger = 5, size = 76, color = k.ink, accent = k.indigo, accentWords = [], weight = 500, style,
}) => {
  const frame = useT();
  return (
    <div style={{ fontFamily: font, fontSize: size, fontWeight: weight, letterSpacing: -size * 0.03, color, display: "flex", flexWrap: "wrap", justifyContent: "center", gap: `0 ${size * 0.28}px`, lineHeight: 1.15, ...style }}>
      {text.split(" ").map((word, i) => {
        const t = p(frame, delay + i * stagger, 11);
        const isAccent = accentWords.includes(word.replace(/[.,?!]/g, ""));
        return (
          <span key={i} style={{ display: "inline-block", opacity: t, filter: t < 0.98 ? `blur(${(1 - t) * 16}px)` : undefined, transform: `translateX(${(1 - t) * 26}px)`, color: isAccent ? accent : undefined }}>
            {word}
          </span>
        );
      })}
    </div>
  );
};

/** One word that starts enormous and soft and lands small and sharp. */
export const Giant: React.FC<{ text: string; delay?: number; from?: number; size?: number; color?: string; top?: string; bottom?: string }> = ({ text, delay = 0, from = 7, size = 76, top = k.indigoBright, bottom = k.ink }) => {
  const frame = useT();
  const t = p(frame, delay, 16, inOut);
  return (
    <span style={{ display: "inline-block", fontFamily: font, fontWeight: 500, fontSize: size, letterSpacing: -size * 0.03, transform: `scale(${interpolate(t, [0, 1], [from, 1])})`,
      filter: t < 0.97 ? `blur(${(1 - t) * 10}px)` : undefined, opacity: Math.min(1, p(frame, delay, 4) * 2),
      backgroundImage: `linear-gradient(180deg, ${top} ${10 - t * 60}%, ${bottom} ${70 - t * 40}%)`, WebkitBackgroundClip: "text", backgroundClip: "text", color: "transparent" }}>
      {text}
    </span>
  );
};

/** Text typed with a caret. `select` paints a selection over the last characters, like a drag. */
export const TypeLine: React.FC<{ text: string; delay?: number; speed?: number; size?: number; color?: string; selectFrom?: number; selectAt?: number; caret?: boolean }> = ({
  text, delay = 0, speed = 0.9, size = 72, color = k.ink, selectFrom, selectAt, caret = true,
}) => {
  const frame = useT();
  const count = Math.max(0, Math.min(text.length, Math.floor((frame - delay) * speed)));
  const selected = selectFrom !== undefined && selectAt !== undefined && frame >= selectAt;
  const sel = selected ? p(frame, selectAt!, 8) : 0;
  const head = selected ? text.slice(0, selectFrom) : text.slice(0, count);
  const tail = selected ? text.slice(selectFrom) : "";
  return (
    <div style={{ fontFamily: font, fontSize: size, fontWeight: 500, letterSpacing: -size * 0.03, color, whiteSpace: "pre" }}>
      {head}
      {selected ? (
        <span style={{ backgroundImage: `linear-gradient(${k.indigo}, ${k.indigo})`, backgroundSize: `${sel * 100}% 100%`, backgroundRepeat: "no-repeat", color: sel > 0.5 ? "#fff" : color, padding: "0 6px" }}>{tail}</span>
      ) : null}
      {caret && !selected && frame >= delay - 12 && (count < text.length || Math.floor(frame / 9) % 2 === 0) ? (
        <span style={{ display: "inline-block", width: size * 0.045, height: size * 0.95, background: color, marginLeft: 4, transform: `translateY(${size * 0.14}px)` }} />
      ) : null}
    </div>
  );
};

/** A surface seen at an angle that settles flat: the product arriving. */
export const Tilt: React.FC<{ delay?: number; duration?: number; from?: { rx: number; ry: number; rz: number; scale: number; y: number }; to?: { rx: number; ry: number; rz: number; scale: number; y: number }; children: React.ReactNode; origin?: string }> = ({
  delay = 0, duration = 50, children, origin = "50% 50%",
  from = { rx: 34, ry: -18, rz: 6, scale: 0.92, y: 260 }, to = { rx: 0, ry: 0, rz: 0, scale: 1, y: 0 },
}) => {
  const frame = useT();
  const t = p(frame, delay, duration, inOut);
  const mix = (a: number, b: number) => a + (b - a) * t;
  return (
    <div style={{ perspective: 2200 }}>
      <div style={{ transformOrigin: origin, transform: `translateY(${mix(from.y, to.y)}px) rotateX(${mix(from.rx, to.rx)}deg) rotateY(${mix(from.ry, to.ry)}deg) rotateZ(${mix(from.rz, to.rz)}deg) scale(${mix(from.scale, to.scale)})`,
        opacity: Math.min(1, p(frame, delay, 10) * 1.5) }}>
        {children}
      </div>
    </div>
  );
};

/** The mouse pointer, moving through points and pressing at the last one. */
export const Pointer: React.FC<{ path: { x: number; y: number; at: number }[]; clickAt?: number; dark?: boolean }> = ({ path, clickAt, dark = true }) => {
  const frame = useT();
  const x = interpolate(frame, path.map((s) => s.at), path.map((s) => s.x), { ...clamp, easing: inOut });
  const y = interpolate(frame, path.map((s) => s.at), path.map((s) => s.y), { ...clamp, easing: inOut });
  const press = clickAt === undefined ? 0 : p(frame, clickAt, 5) - p(frame, clickAt + 5, 8);
  const ring = clickAt === undefined ? 0 : p(frame, clickAt, 16);
  return (
    <div style={{ position: "absolute", left: x, top: y, opacity: p(frame, path[0].at - 6, 6), zIndex: 20 }}>
      {clickAt !== undefined && frame >= clickAt ? (
        <div style={{ position: "absolute", left: -30, top: -30, width: 60, height: 60, borderRadius: 30, border: `3px solid ${k.indigo}`, opacity: 1 - ring, transform: `scale(${0.3 + ring * 1.3})` }} />
      ) : null}
      <svg width="34" height="40" viewBox="0 0 34 40" style={{ transform: `scale(${1 - press * 0.18})`, filter: "drop-shadow(0 4px 8px rgba(0,0,0,0.25))" }}>
        <path d="M3 3 L3 31 L11 24 L16 36 L22 33.5 L17 22 L28 22 Z" fill={dark ? "#111827" : "#fff"} stroke={dark ? "#fff" : "#111827"} strokeWidth="2.4" strokeLinejoin="round" />
      </svg>
    </div>
  );
};

/** System text in the monospaced face. */
export const Mono: React.FC<{ children: React.ReactNode; size?: number; color?: string; style?: React.CSSProperties }> = ({ children, size = 24, color = "#E4E4E7", style }) => (
  <span style={{ fontFamily: mono, fontWeight: 500, fontSize: size, color, ...style }}>{children}</span>
);

/** Thambi's mascot, drawn exactly like the app's ThambiMascotArt: a head with three round corners and
 *  one sharp one (top left), two pill eyes. It blinks on the real clock, sometimes twice, and glances. */
export const Mark: React.FC<{ size: number; color?: string; eye?: string; phase?: number }> = ({ size, color = k.indigo, eye = "#fff", phase = 0 }) => {
  const frame = useCurrentFrame() + phase;
  const cycle = 57;
  const at = (frame + 20) % cycle;
  const round = Math.floor((frame + 20) / cycle);
  const shut = (start: number) => (at >= start && at < start + 6 ? 1 - Math.abs(at - start - 3) / 3 : 0);
  const blink = Math.max(shut(0), round % 3 === 1 ? shut(9) : 0);
  const glance = Math.sin(frame / 23) > 0.6 ? 1 : Math.sin(frame / 23) < -0.75 ? -1 : 0;
  const r = size * 0.3;
  const w = size * 0.115, h = size * 0.25 * (1 - blink * 0.88);
  const head = `M0 0 H${size - r} A${r} ${r} 0 0 1 ${size} ${r} V${size - r} A${r} ${r} 0 0 1 ${size - r} ${size} H${r} A${r} ${r} 0 0 1 0 ${size - r} Z`;
  const id = `mg${Math.round(size)}`;
  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} style={{ flexShrink: 0, overflow: "visible", filter: `drop-shadow(0 ${size * 0.08}px ${size * 0.14}px rgba(0,0,0,0.18))` }}>
      <defs><linearGradient id={id} x1="0" y1="0" x2="0.6" y2="1"><stop offset="0%" stopColor={k.indigoBright} /><stop offset="100%" stopColor={color} /></linearGradient></defs>
      <path d={head} fill={`url(#${id})`} />
      {[0.37, 0.65].map((cx) => (
        <rect key={cx} x={size * cx - w / 2 + glance * size * 0.03} y={size * 0.5 - h / 2} width={w} height={Math.max(h, size * 0.02)} rx={Math.min(w, h) / 2} fill={eye} />
      ))}
    </svg>
  );
};

/** Grey stand-in for a line of text inside a mock screen. */
export const Bar: React.FC<{ w: number | string; h?: number; color?: string; style?: React.CSSProperties }> = ({ w, h = 12, color = "#E8E8EA", style }) => (
  <div style={{ width: w, height: h, borderRadius: h, background: color, ...style }} />
);

export const card: React.CSSProperties = { background: "#fff", borderRadius: 22, boxShadow: "0 40px 100px rgba(0,0,0,0.10), 0 0 0 1.5px rgba(0,0,0,0.06)" };
