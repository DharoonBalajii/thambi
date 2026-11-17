import React from "react";
import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";
import { c, font, mono } from "./theme";
import { clamp, prog, useSpring } from "./motion";

/** Thambi: a rounded square with two eyes. It blinks, and can look around. */
export const Mascot: React.FC<{ size: number; color?: string; eye?: string; look?: number; delay?: number; bounce?: boolean }> = ({
  size, color = c.indigo, eye = "#FFFFFF", look = 0, delay = 0, bounce = true,
}) => {
  const frame = useCurrentFrame();
  const s = useSpring(delay, { damping: 10, stiffness: 150 });
  const blinkAt = (frame + 20) % 75;
  const blink = blinkAt < 5 ? 1 - Math.abs(blinkAt - 2.5) / 2.5 : 0;
  const bob = bounce ? Math.sin(frame / 14) * size * 0.025 : 0;
  const eyeW = size * 0.11;
  const eyeH = size * 0.26 * (1 - blink * 0.85);
  return (
    <div style={{ width: size, height: size, transform: `translateY(${bob}px) scale(${s})`, borderRadius: size * 0.3, background: color, position: "relative",
      boxShadow: `0 ${size * 0.12}px ${size * 0.35}px ${color}55` }}>
      {[-1, 1].map((side) => (
        <div key={side} style={{ position: "absolute", width: eyeW, height: eyeH, borderRadius: eyeW, background: eye,
          left: size / 2 + side * size * 0.13 - eyeW / 2 + look * size * 0.07, top: size * 0.47 - eyeH / 2 }} />
      ))}
    </div>
  );
};

/** Slow drifting colour fields and a faint grid: movement behind every scene without a single photo. */
export const Backdrop: React.FC<{ dark?: boolean; tint?: string; second?: string }> = ({ dark = false, tint = c.indigo, second = c.orange }) => {
  const frame = useCurrentFrame();
  const base = dark ? c.ink : c.paper;
  const blob = (x: number, y: number, r: number, color: string, speed: number, phase: number) => (
    <div style={{ position: "absolute", width: r, height: r, borderRadius: r, background: color, opacity: dark ? 0.26 : 0.2, filter: `blur(${r * 0.32}px)`,
      left: x + Math.sin(frame / speed + phase) * 90, top: y + Math.cos(frame / (speed * 1.3) + phase) * 70 }} />
  );
  const lineColor = dark ? "rgba(255,255,255,0.045)" : "rgba(20,21,43,0.05)";
  return (
    <AbsoluteFill style={{ background: base, overflow: "hidden" }}>
      {blob(-200, -260, 900, tint, 50, 0)}
      {blob(1250, 520, 820, second, 62, 2)}
      {blob(700, -380, 600, dark ? c.indigoSoft : c.indigoSoft, 44, 4)}
      <AbsoluteFill style={{ backgroundImage: `linear-gradient(${lineColor} 1px, transparent 1px), linear-gradient(90deg, ${lineColor} 1px, transparent 1px)`,
        backgroundSize: "80px 80px", backgroundPosition: `${-frame * 0.4}px ${-frame * 0.25}px` }} />
    </AbsoluteFill>
  );
};

/** The small label above a headline, as a pill with a coloured dot of the scene's number. */
export const Tag: React.FC<{ label: string; delay?: number; color?: string; dark?: boolean }> = ({ label, delay = 0, color = c.indigo, dark = false }) => {
  const frame = useCurrentFrame();
  const p = prog(frame, delay, 16);
  return (
    <div style={{ display: "inline-flex", alignItems: "center", gap: 12, padding: "10px 20px 10px 14px", borderRadius: 999, fontFamily: font, fontSize: 24, fontWeight: 600,
      color: dark ? c.onInk : c.text, background: dark ? "rgba(255,255,255,0.08)" : "#FFFFFF", border: `1.5px solid ${dark ? "rgba(255,255,255,0.14)" : c.paperLine}`,
      opacity: p, transform: `translateX(${(1 - p) * -30}px)`, alignSelf: "flex-start" }}>
      <span style={{ width: 26, height: 26, borderRadius: 9, background: color, display: "inline-block" }} />
      {label}
    </div>
  );
};

/** The Thambi window: title bar, sidebar with the page list, and whatever the scene shows. */
export const AppWindow: React.FC<{ width: number; height: number; page: string; delay?: number; children: React.ReactNode; style?: React.CSSProperties }> = ({
  width, height, page, delay = 0, children, style,
}) => {
  const s = useSpring(delay, { damping: 18, stiffness: 110 });
  const pages = ["Ask", "Library", "Notes", "Practice", "Plan"];
  return (
    <div style={{ width, height, borderRadius: 26, background: c.paper, overflow: "hidden", display: "flex", fontFamily: font,
      boxShadow: "0 50px 120px rgba(20,21,60,0.28), 0 0 0 1.5px rgba(20,21,43,0.08)", opacity: Math.min(1, s * 1.4),
      transform: `translateY(${(1 - s) * 120}px) scale(${0.94 + s * 0.06})`, ...style }}>
      <div style={{ width: 250, background: c.paper2, borderRight: `1.5px solid ${c.paperLine}`, padding: "22px 16px", display: "flex", flexDirection: "column", gap: 6, flexShrink: 0 }}>
        <div style={{ display: "flex", gap: 9, marginBottom: 22, paddingLeft: 4 }}>
          {["#FF5F57", "#FEBC2E", "#28C840"].map((dot) => <div key={dot} style={{ width: 14, height: 14, borderRadius: 7, background: dot }} />)}
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 12, padding: "0 8px 18px" }}>
          <Mascot size={34} bounce={false} />
          <div style={{ fontSize: 23, fontWeight: 700, color: c.text }}>Thambi</div>
        </div>
        {pages.map((name) => (
          <div key={name} style={{ padding: "11px 14px", borderRadius: 12, fontSize: 20, fontWeight: name === page ? 700 : 500, color: name === page ? c.text : c.text2,
            background: name === page ? c.orangeTint : "transparent", display: "flex", alignItems: "center", gap: 12 }}>
            <span style={{ width: 10, height: 10, borderRadius: 4, background: name === page ? c.orangeDeep : c.paperLine }} />
            {name}
          </div>
        ))}
      </div>
      <div style={{ flex: 1, position: "relative", minWidth: 0 }}>{children}</div>
    </div>
  );
};

export const Chip: React.FC<{ children: React.ReactNode; bg?: string; color?: string; size?: number; style?: React.CSSProperties }> = ({ children, bg = c.indigoTint, color = c.indigo, size = 20, style }) => (
  <span style={{ display: "inline-flex", alignItems: "center", gap: 8, padding: `${size * 0.3}px ${size * 0.7}px`, borderRadius: size * 0.5, background: bg, color, fontFamily: font, fontSize: size, fontWeight: 700, ...style }}>
    {children}
  </span>
);

export const Num: React.FC<{ children: React.ReactNode; size?: number; color?: string }> = ({ children, size = 20, color = c.indigo }) => (
  <span style={{ fontFamily: mono, fontWeight: 700, fontSize: size, color }}>{children}</span>
);

/** Grey lines standing in for a paragraph; they draw in one after another. */
export const TextLines: React.FC<{ widths: number[]; delay?: number; gap?: number; color?: string; height?: number; highlight?: number; highlightColor?: string }> = ({
  widths, delay = 0, gap = 14, color = c.paperLine, height = 12, highlight, highlightColor = c.orangeSoft,
}) => {
  const frame = useCurrentFrame();
  return (
    <div style={{ display: "flex", flexDirection: "column", gap }}>
      {widths.map((w, i) => {
        const p = prog(frame, delay + i * 2, 12);
        const lit = highlight !== undefined && i >= highlight && i < highlight + 3;
        return <div key={i} style={{ width: `${w * p}%`, height, borderRadius: height, background: lit ? highlightColor : color, opacity: lit ? 0.75 : 1 }} />;
      })}
    </div>
  );
};

/** Layout shared by the feature scenes: words on the left, the product on the right. */
export const Split: React.FC<{ left: React.ReactNode; right: React.ReactNode; dark?: boolean; flip?: boolean }> = ({ left, right, dark, flip }) => {
  const frame = useCurrentFrame();
  const drift = interpolate(frame, [0, 240], [0, -18], clamp);
  return (
    <AbsoluteFill style={{ fontFamily: font, flexDirection: flip ? "row-reverse" : "row", alignItems: "center", padding: "0 110px", gap: 80 }}>
      <div style={{ width: 620, display: "flex", flexDirection: "column", gap: 30, flexShrink: 0, color: dark ? c.onInk : c.text }}>{left}</div>
      <div style={{ flex: 1, display: "flex", justifyContent: "center", alignItems: "center", transform: `translateY(${drift}px)` }}>{right}</div>
    </AbsoluteFill>
  );
};
