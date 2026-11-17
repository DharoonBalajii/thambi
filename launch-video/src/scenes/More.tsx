import React from "react";
import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";
import { Backdrop, Mascot, Split, Tag } from "../components";
import { clamp, Pop, prog, Rise, useSpring, Words } from "../motion";
import { c, devanagari, font, mono, tamil } from "../theme";

/** 6. The buddy on your screen: hold a key, ask out loud, and it points and draws. */
export const BuddyScene: React.FC = () => {
  const frame = useCurrentFrame();
  const move = prog(frame, 62, 30);
  const cursorX = interpolate(move, [0, 1], [120, 440]);
  const cursorY = interpolate(move, [0, 1], [300, 400]);
  const ring = prog(frame, 92, 16);
  const boxes = ["Client", "Server", "Database"];
  return (
    <AbsoluteFill>
      <Backdrop dark tint={c.indigo} second={c.indigoSoft} />
      <Split
        dark
        left={<>
          <Tag label="Voice buddy" color={c.indigoSoft} dark />
          <Words text="Ask out loud. It points and draws." delay={6} size={76} color={c.onInk} highlight={{ points: c.indigoSoft, draws: c.orangeSoft }} />
          <Rise delay={32} style={{ fontSize: 33, lineHeight: 1.4, fontWeight: 500, color: c.onInk2 }}>Hold a key over any slide or PDF. Thambi sees your screen, explains by voice and sketches the diagram.</Rise>
        </>}
        right={
          <div style={{ position: "relative", width: 900, height: 640, fontFamily: font }}>
            <Pop delay={6} style={{ position: "absolute", inset: 0 }}>
              <div style={{ width: "100%", height: "100%", borderRadius: 26, background: c.ink2, border: `1.5px solid ${c.line}`, padding: 40, boxShadow: "0 50px 120px rgba(0,0,0,0.5)" }}>
                <div style={{ fontSize: 20, fontWeight: 700, color: c.onInk3, fontFamily: mono }}>Lecture 9, slide 14</div>
                <div style={{ fontSize: 40, fontWeight: 800, color: c.onInk, margin: "12px 0 30px" }}>Three-tier architecture</div>
                <div style={{ display: "flex", flexDirection: "column", gap: 16, width: 340 }}>
                  {[92, 78, 100, 64, 86].map((w, i) => <div key={i} style={{ width: `${w}%`, height: 14, borderRadius: 8, background: "#33365B" }} />)}
                </div>
                {/* What Thambi draws: three boxes joined by arrows, one after another. */}
                <div style={{ position: "absolute", left: 60, bottom: 60, right: 60, display: "flex", alignItems: "center", justifyContent: "space-between" }}>
                  {boxes.map((label, i) => {
                    const p = prog(frame, 104 + i * 14, 14);
                    return (
                      <React.Fragment key={label}>
                        <div style={{ width: 200, padding: "24px 0", textAlign: "center", borderRadius: 18, fontSize: 25, fontWeight: 800, color: i === 1 ? "#2A1000" : c.onInk,
                          background: i === 1 ? c.orangeSoft : "rgba(165,180,252,0.14)", border: `2.5px solid ${i === 1 ? c.orangeSoft : c.indigoSoft}`, opacity: p, transform: `scale(${0.6 + p * 0.4})` }}>{label}</div>
                        {i < 2 ? <div style={{ flex: 1, height: 4, margin: "0 10px", background: c.indigoSoft, borderRadius: 2, transformOrigin: "left", transform: `scaleX(${prog(frame, 112 + i * 14, 12)})` }} /> : null}
                      </React.Fragment>
                    );
                  })}
                </div>
              </div>
            </Pop>
            {/* Thambi's pointer, with what it is saying. */}
            <div style={{ position: "absolute", left: cursorX, top: cursorY, opacity: prog(frame, 50, 10) }}>
              <div style={{ position: "absolute", left: -34, top: -34, width: 68, height: 68, borderRadius: 34, border: `3px solid ${c.indigoSoft}`, opacity: ring * (1 - prog(frame, 108, 20)), transform: `scale(${0.4 + ring * 1.2})` }} />
              <svg width="38" height="46" viewBox="0 0 38 46"><path d="M3 3 L3 37 L13 28 L20 43 L27 40 L20 25 L34 25 Z" fill="#6366F1" stroke="#fff" strokeWidth="3" strokeLinejoin="round" /></svg>
              <div style={{ position: "absolute", left: 44, top: 30, whiteSpace: "nowrap", padding: "12px 20px", borderRadius: 16, background: c.indigo, color: "#fff", fontSize: 22, fontWeight: 700, opacity: prog(frame, 92, 10) }}>
                The server sits in the middle
              </div>
            </div>
            {/* The student's voice. */}
            <div style={{ position: "absolute", right: -30, top: -34, display: "flex", alignItems: "center", gap: 14, padding: "16px 24px", borderRadius: 999, background: c.orangeSoft, color: "#2A1000", fontSize: 23, fontWeight: 800,
              opacity: prog(frame, 16, 10) * (1 - prog(frame, 70, 10)), transform: `translateY(${(1 - prog(frame, 16, 10)) * 20}px)` }}>
              <div style={{ display: "flex", gap: 4, alignItems: "center", height: 30 }}>
                {[0, 1, 2, 3, 4].map((i) => <div key={i} style={{ width: 5, borderRadius: 3, background: "#2A1000", height: 8 + Math.abs(Math.sin(frame / 3 + i * 1.3)) * 22 }} />)}
              </div>
              "Explain this slide"
            </div>
          </div>
        }
      />
    </AbsoluteFill>
  );
};

type Feature = { title: string; line: string; color: string; glyph: React.ReactNode };

const glyphStyle: React.CSSProperties = { fontFamily: mono, fontWeight: 700, fontSize: 30, color: "#fff" };

const features: Feature[] = [
  { title: "Teach it back", line: "Explain a topic; Thambi finds the gaps", color: c.indigo, glyph: <span style={glyphStyle}>?!</span> },
  { title: "Concept maps", line: "A whole unit as one picture", color: c.orangeDeep, glyph: <span style={glyphStyle}>◇</span> },
  { title: "Spoken revision", line: "Listen to a unit while you walk", color: c.green, glyph: <span style={glyphStyle}>♪</span> },
  { title: "Lecture to notes", line: "Record class, get clean notes", color: c.indigoDeep, glyph: <span style={glyphStyle}>●</span> },
  { title: "Your language", line: "", color: c.orange, glyph: <span style={{ ...glyphStyle, fontFamily: tamil, fontSize: 28 }}>த</span> },
  { title: "Works offline", line: "Free answers from a model on your Mac", color: c.text, glyph: <span style={glyphStyle}>⌁</span> },
  { title: "Import from iPhone", line: "Snap a page, it lands in your library", color: c.indigo, glyph: <span style={glyphStyle}>▯</span> },
  { title: "Focus timer and streaks", line: "Study sessions that add up", color: c.orangeDeep, glyph: <span style={glyphStyle}>25</span> },
  { title: "Export anywhere", line: "Notes to PDF, cards to Anki", color: c.green, glyph: <span style={glyphStyle}>↗</span> },
  { title: "Study modes", line: "Read, Write or Restricted to your notes", color: c.indigoDeep, glyph: <span style={glyphStyle}>R</span> },
  { title: "Keep a subject in memory", line: "Thambi knows the whole unit", color: c.orange, glyph: <span style={glyphStyle}>∞</span> },
  { title: "Search everything", line: "One shortcut, every page you own", color: c.text, glyph: <span style={glyphStyle}>⌘K</span> },
];

/** 7. Everything else, as a wall of cards that deals itself out. */
export const GridScene: React.FC = () => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill style={{ fontFamily: font }}>
      <Backdrop />
      <AbsoluteFill style={{ padding: "70px 110px", gap: 40 }}>
        <div style={{ display: "flex", alignItems: "flex-end", justifyContent: "space-between" }}>
          <Words text="And everything else a student needs." delay={4} size={70} color={c.text} highlight={{ everything: c.indigo }} />
        </div>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 22, flex: 1 }}>
          {features.map((feature, i) => {
            const delay = 22 + i * 6;
            const p = prog(frame, delay, 20);
            const col = i % 4;
            const lift = Math.sin(frame / 22 + i) * 4;
            return (
              <div key={feature.title} style={{ borderRadius: 24, background: "#fff", padding: "26px 28px", display: "flex", flexDirection: "column", gap: 14,
                boxShadow: "0 18px 50px rgba(20,21,60,0.10), 0 0 0 1.5px rgba(20,21,43,0.06)", opacity: p,
                transform: `translateY(${(1 - p) * 90 + lift}px) rotate(${(1 - p) * (col - 1.5) * 4}deg) scale(${0.85 + p * 0.15})` }}>
                <div style={{ width: 68, height: 68, borderRadius: 20, background: feature.color, display: "flex", alignItems: "center", justifyContent: "center",
                  transform: `scale(${interpolate(prog(frame, delay + 8, 14), [0, 0.6, 1], [0, 1.15, 1], clamp)})` }}>{feature.glyph}</div>
                <div style={{ fontSize: 28, fontWeight: 800, color: c.text, letterSpacing: -0.6 }}>{feature.title}</div>
                {feature.title === "Your language" ? (
                  <div style={{ fontSize: 22, color: c.text2, fontWeight: 600, lineHeight: 1.5 }}>
                    <span style={{ fontFamily: tamil }}>தமிழ்</span>, <span style={{ fontFamily: devanagari }}>हिन्दी</span>, English or a mix of them
                  </div>
                ) : (
                  <div style={{ fontSize: 21, color: c.text2, fontWeight: 500, lineHeight: 1.35 }}>{feature.line}</div>
                )}
              </div>
            );
          })}
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

/** 8. Why you can trust it with your notes. */
export const TrustScene: React.FC = () => {
  const frame = useCurrentFrame();
  const points = [
    { big: "On your Mac", small: "Your notes are read and searched locally. Only the few passages a question needs are sent.", color: c.indigoSoft },
    { big: "Free reviews", small: "Flashcards, search, plans and timers never call the AI.", color: c.greenSoft },
    { big: "Open source", small: "Read the code. Change it. Share it with your class.", color: c.orangeSoft },
  ];
  const shield = useSpring(6, { damping: 11 });
  return (
    <AbsoluteFill style={{ fontFamily: font }}>
      <Backdrop dark tint={c.green} second={c.indigo} />
      <AbsoluteFill style={{ padding: "0 130px", justifyContent: "center", gap: 60 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 40 }}>
          <div style={{ transform: `scale(${shield})` }}>
            <svg width="120" height="136" viewBox="0 0 120 136">
              <path d="M60 6 L110 24 V66 C110 98 88 120 60 130 C32 120 10 98 10 66 V24 Z" fill="rgba(165,180,252,0.16)" stroke={c.indigoSoft} strokeWidth="6" strokeLinejoin="round" />
              <path d="M38 68 L54 84 L84 52" fill="none" stroke={c.greenSoft} strokeWidth="9" strokeLinecap="round" strokeLinejoin="round"
                strokeDasharray="80" strokeDashoffset={80 * (1 - prog(frame, 20, 16))} />
            </svg>
          </div>
          <Words text="Your notes stay yours." delay={8} size={104} color={c.onInk} highlight={{ yours: c.orangeSoft }} />
        </div>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 28 }}>
          {points.map((point, i) => {
            const p = prog(frame, 36 + i * 10, 20);
            return (
              <div key={point.big} style={{ borderRadius: 26, padding: "34px 36px", background: "rgba(255,255,255,0.06)", border: "1.5px solid rgba(255,255,255,0.12)", opacity: p, transform: `translateY(${(1 - p) * 60}px)` }}>
                <div style={{ width: 54, height: 8, borderRadius: 4, background: point.color, marginBottom: 22, transformOrigin: "left", transform: `scaleX(${prog(frame, 46 + i * 10, 16)})` }} />
                <div style={{ fontSize: 44, fontWeight: 800, color: c.onInk, letterSpacing: -1.2 }}>{point.big}</div>
                <div style={{ fontSize: 26, lineHeight: 1.4, fontWeight: 500, color: c.onInk2, marginTop: 12 }}>{point.small}</div>
              </div>
            );
          })}
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
