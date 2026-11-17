import React from "react";
import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";
import { Backdrop, Mascot } from "../components";
import { clamp, prog, Rise, useSpring, Words } from "../motion";
import { c, font, mono } from "../theme";

/** The problem, in the student's own clock: the exam is close and the pile is tall. */
export const Hook: React.FC = () => {
  const frame = useCurrentFrame();
  const days = Math.max(3, 12 - Math.floor(prog(frame, 8, 46) * 9));
  const pile = ["Unit 1 notes.pdf", "DBMS slides.pptx", "Lecture 14 photo.jpg", "Textbook, 400 pages", "Previous papers"];
  const out = prog(frame, 100, 14);
  return (
    <AbsoluteFill style={{ fontFamily: font }}>
      <Backdrop dark />
      <AbsoluteFill style={{ padding: "0 140px", justifyContent: "center", opacity: 1 - out, transform: `scale(${1 + out * 0.06})` }}>
        <div style={{ display: "flex", alignItems: "center", gap: 100 }}>
          <div style={{ flex: 1 }}>
            <Rise delay={2} style={{ fontSize: 34, fontWeight: 600, color: c.onInk3, marginBottom: 14 }}>Exam in</Rise>
            <div style={{ display: "flex", alignItems: "baseline", gap: 26 }}>
              <div style={{ fontFamily: mono, fontWeight: 700, fontSize: 300, lineHeight: 0.95, color: days <= 5 ? c.orangeSoft : c.onInk, letterSpacing: -14,
                transform: `scale(${1 + (days <= 5 ? Math.sin(frame / 2.2) * 0.012 : 0)})` }}>{days}</div>
              <Rise delay={6} style={{ fontSize: 90, fontWeight: 800, color: c.onInk, letterSpacing: -3 }}>days</Rise>
            </div>
            <Words text="And this much to read." delay={52} size={64} color={c.onInk2} weight={700} style={{ marginTop: 26 }} />
          </div>
          <div style={{ width: 620, height: 560, position: "relative" }}>
            {pile.map((name, i) => {
              const s = prog(frame, 14 + i * 7, 20);
              const tilt = [-7, 5, -3, 6, -4][i];
              return (
                <div key={name} style={{ position: "absolute", left: 30 + (i % 2) * 40, top: 430 - i * 96, width: 520, padding: "26px 30px", borderRadius: 20,
                  background: c.ink3, border: `1.5px solid ${c.line}`, color: c.onInk, fontSize: 30, fontWeight: 600, display: "flex", alignItems: "center", gap: 18,
                  opacity: s, transform: `translateY(${(1 - s) * -260}px) rotate(${tilt * s}deg)`, boxShadow: "0 24px 50px rgba(0,0,0,0.35)" }}>
                  <span style={{ width: 40, height: 50, borderRadius: 8, background: [c.orangeSoft, c.indigoSoft, c.greenSoft, c.indigo, c.orange][i] }} />
                  {name}
                </div>
              );
            })}
          </div>
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

/** Thambi arrives. */
export const LogoReveal: React.FC = () => {
  const frame = useCurrentFrame();
  const ring = useSpring(0, { damping: 20, stiffness: 60 });
  const settle = prog(frame, 22, 22);
  return (
    <AbsoluteFill style={{ fontFamily: font }}>
      <Backdrop />
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
        {[0, 1, 2].map((i) => (
          <div key={i} style={{ position: "absolute", width: 300 + i * 260, height: 300 + i * 260, borderRadius: 999, border: `2px solid ${c.indigo}`,
            opacity: (0.22 - i * 0.06) * ring, transform: `scale(${0.4 + ring * 0.6 + Math.sin(frame / 20 + i) * 0.015})` }} />
        ))}
        <div style={{ display: "flex", alignItems: "center", gap: interpolate(settle, [0, 1], [0, 44]), transform: `translateY(${-settle * 50}px)` }}>
          <Mascot size={interpolate(settle, [0, 1], [300, 190])} delay={2} look={Math.sin(frame / 16) * 0.6} />
          <div style={{ overflow: "hidden", width: interpolate(settle, [0, 1], [0, 620]) }}>
            <div style={{ fontSize: 190, fontWeight: 800, color: c.text, letterSpacing: -8, lineHeight: 1 }}>Thambi</div>
          </div>
        </div>
        <div style={{ position: "absolute", top: 660, textAlign: "center" }}>
          <Words text="Study faster. Study smarter." delay={42} size={74} color={c.text} highlight={{ faster: c.orangeDeep, smarter: c.indigo }} style={{ justifyContent: "center" }} />
          <Rise delay={62} style={{ fontSize: 34, fontWeight: 500, color: c.text3, marginTop: 22 }}>The AI study buddy for your Mac</Rise>
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

/** The close: name, promise, where to get it. */
export const Closing: React.FC = () => {
  const frame = useCurrentFrame();
  const glow = interpolate(Math.sin(frame / 12), [-1, 1], [0.5, 1], clamp);
  return (
    <AbsoluteFill style={{ fontFamily: font }}>
      <Backdrop dark />
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", gap: 34 }}>
        <Mascot size={210} color={c.indigoSoft} eye={c.ink} delay={4} look={Math.sin(frame / 18) * 0.5} />
        <Words text="Study faster. Study smarter." delay={16} size={104} color={c.onInk} highlight={{ faster: c.orangeSoft, smarter: c.indigoSoft }} style={{ justifyContent: "center" }} />
        <Rise delay={40} style={{ fontSize: 40, fontWeight: 500, color: c.onInk2 }}>Thambi, the AI study buddy for students</Rise>
        <Rise delay={54}>
          <div style={{ marginTop: 18, padding: "26px 56px", borderRadius: 999, background: c.orangeSoft, color: "#2A1000", fontSize: 40, fontWeight: 800,
            boxShadow: `0 0 ${70 * glow}px ${c.orange}99` }}>Free and open source for macOS</div>
        </Rise>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
