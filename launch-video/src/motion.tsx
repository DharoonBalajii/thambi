import React from "react";
import { Easing, interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";

export const ease = Easing.bezier(0.16, 1, 0.3, 1);
export const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

/** 0 to 1 between two frames, eased out. */
export const prog = (frame: number, from: number, duration: number, easing = ease) =>
  interpolate(frame, [from, from + duration], [0, 1], { ...clamp, easing });

export const useSpring = (delay = 0, config: { damping?: number; stiffness?: number; mass?: number } = {}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return spring({ frame: frame - delay, fps, config: { damping: 16, stiffness: 140, mass: 0.8, ...config } });
};

/** Rises and fades in; optionally leaves the same way before `out`. */
export const Rise: React.FC<{ delay?: number; distance?: number; out?: number; style?: React.CSSProperties; children: React.ReactNode }> = ({
  delay = 0, distance = 40, out, style, children,
}) => {
  const frame = useCurrentFrame();
  const enter = prog(frame, delay, 18);
  const leave = out === undefined ? 0 : prog(frame, out, 10, Easing.in(Easing.cubic));
  return (
    <div style={{ opacity: enter * (1 - leave), transform: `translateY(${(1 - enter) * distance - leave * distance * 0.6}px)`, ...style }}>
      {children}
    </div>
  );
};

/** Pops in with a spring. */
export const Pop: React.FC<{ delay?: number; style?: React.CSSProperties; children: React.ReactNode }> = ({ delay = 0, style, children }) => {
  const s = useSpring(delay, { damping: 12, stiffness: 170 });
  return <div style={{ transform: `scale(${s})`, opacity: Math.min(1, s * 1.6), ...style }}>{children}</div>;
};

/** Headline whose words rise one after another from behind a mask. */
export const Words: React.FC<{ text: string; delay?: number; stagger?: number; size: number; color: string; weight?: number; highlight?: Record<string, string>; style?: React.CSSProperties }> = ({
  text, delay = 0, stagger = 3, size, color, weight = 800, highlight = {}, style,
}) => {
  const frame = useCurrentFrame();
  return (
    <div style={{ fontSize: size, fontWeight: weight, color, letterSpacing: -size * 0.035, lineHeight: 1.08, display: "flex", flexWrap: "wrap", gap: `0 ${size * 0.26}px`, ...style }}>
      {text.split(" ").map((word, i) => {
        const p = prog(frame, delay + i * stagger, 16);
        const key = word.replace(/[.,!?]/g, "");
        return (
          <span key={i} style={{ display: "inline-block", overflow: "hidden", paddingBottom: size * 0.14, marginBottom: -size * 0.14 }}>
            <span style={{ display: "inline-block", transform: `translateY(${(1 - p) * 110}%)`, color: highlight[key] ?? color }}>{word}</span>
          </span>
        );
      })}
    </div>
  );
};

/** Text typed one character at a time, with a caret. */
export const Typed: React.FC<{ text: string; delay?: number; speed?: number; caret?: string; style?: React.CSSProperties }> = ({ text, delay = 0, speed = 1.4, caret, style }) => {
  const frame = useCurrentFrame();
  const count = Math.max(0, Math.min(text.length, Math.floor((frame - delay) * speed)));
  const done = count >= text.length;
  return (
    <span style={style}>
      {text.slice(0, count)}
      {caret && (!done || Math.floor(frame / 8) % 2 === 0) && frame >= delay ? (
        <span style={{ display: "inline-block", width: 3, height: "1em", background: caret, marginLeft: 3, transform: "translateY(0.14em)" }} />
      ) : null}
    </span>
  );
};

/** A number that counts up. */
export const useCount = (to: number, delay: number, duration: number) => {
  const frame = useCurrentFrame();
  return Math.round(to * prog(frame, delay, duration));
};
