import React from "react";
import { AbsoluteFill, interpolate } from "remotion";
import { font } from "../theme";
import { Bar, Bg, BlurWords, card, clamp, Focus, Giant, inOut, k, Mark, Mono, p, Pointer, Tilt, TypeLine, useT } from "./kit";

type SceneProps = { frames: number };
const center: React.CSSProperties = { alignItems: "center", justifyContent: "center" };

/** Faded bits of a student's pile, drifting at the edges of the problem scene. */
export const Fragment: React.FC<{ x: number; y: number; w: number; delay: number; label: string; tag?: string; rows?: number }> = ({ x, y, w, delay, label, tag, rows = 3 }) => {
  const frame = useT();
  const t = p(frame, delay, 24);
  const drift = Math.sin((frame + delay * 7) / 30) * 8;
  return (
    <div style={{ position: "absolute", left: x, top: y + drift, width: w, opacity: t * 0.9, transform: `scale(${0.9 + t * 0.1})`, fontFamily: font }}>
      <div style={{ background: "#fff", borderRadius: 14, padding: 18, boxShadow: "0 14px 40px rgba(0,0,0,0.08), 0 0 0 1.5px rgba(0,0,0,0.07)", filter: "grayscale(1)" }}>
        <div style={{ fontSize: 17, fontWeight: 600, color: "#3F3F46", marginBottom: 12 }}>{label}</div>
        {Array.from({ length: rows }).map((_, i) => <Bar key={i} w={`${[92, 70, 84, 58][i % 4]}%`} h={9} style={{ marginBottom: 9 }} />)}
      </div>
      {tag ? (
        <div style={{ position: "absolute", right: -46, top: 30, display: "flex", alignItems: "center", opacity: p(frame, delay + 16, 10) }}>
          <svg width="16" height="16" viewBox="0 0 16 16"><path d="M1 1 L15 6 L8 8 L6 15 Z" fill={k.indigo} /></svg>
          <span style={{ background: k.indigo, color: "#fff", fontSize: 15, fontWeight: 600, padding: "5px 12px", borderRadius: 14 }}>{tag}</span>
        </div>
      ) : null}
    </div>
  );
};

/** 1. The problem, typed out in the student's own words. */
export const Problem: React.FC<SceneProps> = ({ frames }) => {
  const frame = useT();
  const second = frame >= 150;
  return (
    <Focus frames={frames}>
      <Bg kind="white" />
      <div style={{ opacity: 1 - p(frame, 140, 10) }}>
        <Fragment x={610} y={70} w={300} delay={62} label="Unit 3 notes.pdf" tag="400 pages" />
        <Fragment x={1420} y={110} w={330} delay={70} label="DBMS slides.pptx" tag="Unread" rows={4} />
        <Fragment x={140} y={700} w={340} delay={78} label="Previous papers" rows={3} />
        <Fragment x={800} y={760} w={300} delay={84} label="Lecture photos" tag="Blurry" rows={2} />
        <Fragment x={1380} y={690} w={360} delay={90} label="Textbook, chapter 7" rows={4} />
      </div>
      <AbsoluteFill style={center}>
        {second ? (
          <BlurWords text="Reading the same chapter… again?" delay={152} size={78} />
        ) : (
          <TypeLine text="Exam in 3 days, 400 pages to go" delay={10} speed={0.62} size={interpolate(frame, [54, 72], [78, 58], { ...clamp, easing: inOut })} selectFrom={15} selectAt={104} />
        )}
      </AbsoluteFill>
    </Focus>
  );
};

/** 2. The turn: one huge soft word that lands as a sentence. */
export const Stop: React.FC<SceneProps> = ({ frames }) => (
  <Focus frames={frames} zoom={0}>
    <Bg kind="white" />
    <AbsoluteFill style={{ ...center, flexDirection: "row", gap: 22 }}>
      <Giant text="Stop" from={8} />
      <BlurWords text="rereading your notes" delay={22} stagger={6} color="#8E8E98" />
    </AbsoluteFill>
  </Focus>
);

/** 3. The name, letters rising out of the colour. */
export const Meet: React.FC<SceneProps> = ({ frames }) => {
  const frame = useT();
  const letters = (text: string, delay: number, color: string) => text.split("").map((ch, i) => {
    const t = p(frame, delay + i * 2, 14);
    return (
      <span key={i} style={{ display: "inline-block", transform: `translateY(${(1 - t) * 190}px)`, opacity: t, filter: t < 0.95 ? `blur(${(1 - t) * 12}px)` : undefined, color }}>{ch}</span>
    );
  });
  const mark = p(frame, 52, 16, inOut);
  return (
    <Focus frames={frames}>
      <Bg kind="grad" />
      <AbsoluteFill style={{ ...center, flexDirection: "row", fontFamily: font, fontSize: 150, fontWeight: 600, letterSpacing: -6 }}>
        <span style={{ display: "inline-flex", overflow: "hidden", paddingBottom: 24 }}>{letters("Meet", 6, k.ink)}</span>
        <span style={{ width: interpolate(mark, [0, 1], [44, 200]), display: "inline-flex", justifyContent: "center", transform: `scale(${mark})`, opacity: mark }}>
          <Mark size={132} />
        </span>
        <span style={{ display: "inline-flex", overflow: "hidden", paddingBottom: 24 }}>{letters("Thambi", 20, k.indigo)}</span>
      </AbsoluteFill>
    </Focus>
  );
};

/** 4. What it is, in one line. */
export const Tagline: React.FC<SceneProps & { text?: string; accentWords?: string[] }> = ({ frames, text = "The AI study buddy that learns your notes", accentWords = ["AI", "study", "buddy"] }) => (
  <Focus frames={frames}>
    <Bg kind="grad" />
    <AbsoluteFill style={center}>
      <BlurWords text={text} delay={6} size={70} accentWords={accentWords} />
    </AbsoluteFill>
  </Focus>
);

const Sidebar: React.FC<{ active: string }> = ({ active }) => (
  <div style={{ width: 250, background: "#F7F7F6", borderRight: `1.5px solid ${k.line}`, padding: "24px 16px", display: "flex", flexDirection: "column", gap: 6, flexShrink: 0 }}>
    <div style={{ display: "flex", alignItems: "center", gap: 12, padding: "0 8px 20px" }}>
      <Mark size={34} />
      <span style={{ fontSize: 23, fontWeight: 700, color: k.ink }}>Thambi</span>
    </div>
    {["Ask", "Library", "Notes", "Practice", "Plan", "Friends"].map((name) => (
      <div key={name} style={{ padding: "11px 14px", borderRadius: 12, fontSize: 20, fontWeight: name === active ? 700 : 500, color: name === active ? k.indigo : "#4B4B55", background: name === active ? k.indigoPale : "transparent" }}>{name}</div>
    ))}
  </div>
);

export const Window: React.FC<{ active: string; width?: number; height?: number; children: React.ReactNode }> = ({ active, width = 1240, height = 760, children }) => (
  <div style={{ ...card, width, height, display: "flex", overflow: "hidden", fontFamily: font, border: `1.5px solid ${k.line}` }}>
    <Sidebar active={active} />
    <div style={{ flex: 1, position: "relative", minWidth: 0 }}>{children}</div>
  </div>
);

/** 5. The product arrives at an angle, settles, and the files land in it. */
export const Library: React.FC<SceneProps> = ({ frames }) => {
  const frame = useT();
  const files = [["Thermodynamics textbook.pdf", "400 pages"], ["DBMS Unit 3 slides.pptx", "42 slides"], ["Photo of class notes.jpg", "handwriting read"], ["Circuits lab manual.docx", "18 pages"], ["Previous paper 2025.pdf", "6 pages"]];
  const zoom = p(frame, 120, 50, inOut);
  return (
    <Focus frames={frames}>
      <Bg kind="grad" />
      <div style={{ position: "absolute", right: 90, top: 70, textAlign: "right", opacity: 1 - p(frame, 96, 12) }}>
        <BlurWords text="For everything you study" delay={10} size={50} color={k.indigo} style={{ justifyContent: "flex-end", width: 420 }} />
      </div>
      <AbsoluteFill style={{ ...center, transform: `scale(${1 + zoom * 0.42}) translate(${-zoom * 120}px, ${zoom * 40}px)` }}>
        <Tilt delay={4} duration={70}>
          <Window active="Library">
            <div style={{ padding: "38px 44px" }}>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                <div style={{ fontSize: 36, fontWeight: 700, color: k.ink }}>Library</div>
                <div style={{ padding: "12px 22px", borderRadius: 12, background: k.indigo, color: "#fff", fontSize: 20, fontWeight: 600 }}>+ Add materials</div>
              </div>
              <div style={{ marginTop: 26, display: "flex", flexDirection: "column", gap: 12 }}>
                {files.map(([name, meta], i) => {
                  const t = p(frame, 70 + i * 9, 16);
                  return (
                    <div key={name} style={{ display: "flex", alignItems: "center", gap: 16, padding: "17px 20px", borderRadius: 14, border: `1.5px solid ${k.line}`, opacity: t, transform: `translateY(${(1 - t) * 24}px)`, background: "#fff" }}>
                      <span style={{ width: 30, height: 38, borderRadius: 6, background: [k.indigo, k.orange, k.green, k.indigoSoft, "#A1A1AA"][i] }} />
                      <span style={{ fontSize: 22, fontWeight: 600, color: k.ink, flex: 1 }}>{name}</span>
                      <Mono size={17} color="#7C7C86">{meta}</Mono>
                      <span style={{ width: 24, height: 24, borderRadius: 12, background: "#DCFCE7", color: k.green, fontSize: 15, fontWeight: 800, display: "flex", alignItems: "center", justifyContent: "center", transform: `scale(${p(frame, 84 + i * 9, 8)})` }}>✓</span>
                    </div>
                  );
                })}
              </div>
            </div>
          </Window>
        </Tilt>
      </AbsoluteFill>
      <Pointer path={[{ x: 1500, y: 900, at: 40 }, { x: 1290, y: 318, at: 66 }]} clickAt={66} />
    </Focus>
  );
};

/** 6. What happens when you ask: light on the left, a dark panel that reports each step on the right. */
export const Pipeline: React.FC<SceneProps> = ({ frames }) => {
  const frame = useT();
  const split = p(frame, 34, 22, inOut);
  const steps: { at: number; text: string; kind: "check" | "bar" | "source" | "done" }[] = [
    { at: 52, text: "Reading your library on this Mac", kind: "check" },
    { at: 82, text: "Searching 472 pages", kind: "bar" },
    { at: 116, text: "Source found", kind: "source" },
    { at: 150, text: "Answer ready, with page numbers", kind: "done" },
  ];
  return (
    <Focus frames={frames}>
      <Bg kind="grad" />
      <AbsoluteFill style={{ fontFamily: font }}>
        <div style={{ position: "absolute", left: 0, top: 0, bottom: 0, width: `${100 - split * 46}%`, display: "flex", alignItems: "center", justifyContent: "center" }}>
          <div style={{ width: 760, display: "flex", flexDirection: "column", gap: 18 }}>
            <div style={{ ...card, padding: "26px 30px", alignSelf: "flex-end", background: k.indigo, color: "#fff", fontSize: 30, fontWeight: 500, borderRadius: 26, opacity: p(frame, 4, 10) }}>
              <TypeLine text="What is a deadlock?" delay={6} speed={0.9} size={30} color="#fff" caret={false} />
            </div>
            {[0, 1, 2].map((i) => (
              <div key={i} style={{ ...card, padding: 22, opacity: 0.55 + (i === 1 ? 0.45 : 0), boxShadow: i === 1 ? `0 0 0 2.5px ${k.indigo}, 0 30px 80px rgba(0,0,0,0.12)` : card.boxShadow, transform: `translateX(${i === 1 ? 0 : -30}px)` }}>
                <div style={{ fontSize: 18, fontWeight: 700, color: i === 1 ? k.indigo : "#8E8E98", marginBottom: 10 }}>{["Unit 1, page 12", "Operating Systems Unit 2, page 42", "Class notes, page 7"][i]}</div>
                <Bar w="94%" style={{ marginBottom: 9 }} /><Bar w="72%" />
              </div>
            ))}
          </div>
        </div>
        <div style={{ position: "absolute", right: 0, top: 0, bottom: 0, width: `${split * 46}%`, overflow: "hidden", background: `radial-gradient(90% 70% at 100% 50%, #1F1F23 0%, #0B0B0D 60%, #000 100%)` }}>
          <div style={{ position: "absolute", left: 70, top: 250, width: 720, display: "flex", flexDirection: "column", gap: 18 }}>
            {steps.map((step) => {
              const t = p(frame, step.at, 12);
              const done = step.kind === "done";
              return (
                <div key={step.text} style={{ opacity: t, transform: `translateY(${(1 - t) * 18}px)`, border: `1.5px solid ${done ? k.indigoBright : "rgba(255,255,255,0.14)"}`, background: done ? "rgba(99,102,241,0.35)" : "rgba(255,255,255,0.03)", borderRadius: 10, padding: "18px 22px" }}>
                  <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
                    {step.kind === "check" || done ? <span style={{ width: 26, height: 26, borderRadius: 6, background: "#fff", color: k.navy, fontSize: 18, fontWeight: 800, display: "flex", alignItems: "center", justifyContent: "center" }}>✓</span> : null}
                    <Mono size={26}>{step.text.slice(0, Math.max(0, Math.floor((frame - step.at) * 1.6)))}</Mono>
                  </div>
                  {step.kind === "bar" ? <div style={{ height: 5, borderRadius: 3, background: "rgba(255,255,255,0.12)", marginTop: 14 }}><div style={{ width: `${p(frame, step.at + 6, 26, inOut) * 100}%`, height: "100%", borderRadius: 3, background: k.indigoSoft }} /></div> : null}
                  {step.kind === "source" ? <div style={{ marginTop: 12, padding: "10px 14px", border: "1.5px solid rgba(255,255,255,0.14)", borderRadius: 8, opacity: p(frame, step.at + 14, 10) }}><Mono size={20} color="#A1A1AA">OS Unit 2, page 42</Mono></div> : null}
                </div>
              );
            })}
          </div>
        </div>
        <div style={{ position: "absolute", left: `${100 - split * 46}%`, top: 540, width: 22, height: 22, marginLeft: -11, background: k.indigoBright, transform: "rotate(45deg)", opacity: split }} />
      </AbsoluteFill>
    </Focus>
  );
};

/** 7. A sentence whose words part to let the keyword through, then the page itself. */
export const Source: React.FC<SceneProps> = ({ frames }) => {
  const frame = useT();
  const part = p(frame, 50, 16, inOut);
  const page = p(frame, 70, 22, inOut);
  const lit = p(frame, 104, 18);
  return (
    <Focus frames={frames}>
      <Bg kind="white" />
      <AbsoluteFill style={{ ...center, opacity: 1 - page }}>
        <div style={{ display: "flex", gap: 18 + part * 90, fontFamily: font, fontSize: 76, fontWeight: 500, letterSpacing: -2.2, color: k.ink }}>
          {["Every", "answer", "shows", "its"].map((word, i) => <span key={word} style={{ opacity: p(frame, 6 + i * 5, 10) * (1 - part * (i < 3 ? 1 : 0.2)), filter: `blur(${(1 - p(frame, 6 + i * 5, 10)) * 14}px)` }}>{word}</span>)}
          <span style={{ color: k.indigo, opacity: p(frame, 28, 10) }}>{"{ page }"}</span>
        </div>
      </AbsoluteFill>
      <AbsoluteFill style={{ ...center, opacity: page, transform: `scale(${0.7 + page * 0.3})` }}>
        <div style={{ width: 860, fontFamily: font }}>
          <div style={{ background: k.indigoBright, borderRadius: "14px 14px 0 0", padding: "14px 22px" }}>
            <div style={{ display: "flex", justifyContent: "space-between" }}><Mono size={22} color="#fff">opening page 42...</Mono><Mono size={22} color="#fff">{Math.round(p(frame, 74, 30) * 100)}%</Mono></div>
            <div style={{ height: 6, borderRadius: 3, background: "rgba(0,0,0,0.28)", marginTop: 12 }}><div style={{ width: `${p(frame, 74, 30) * 100}%`, height: "100%", background: "#fff", borderRadius: 3 }} /></div>
          </div>
          <div style={{ ...card, borderRadius: "0 0 18px 18px", padding: "34px 40px" }}>
            <div style={{ fontSize: 30, fontWeight: 700, color: k.ink, marginBottom: 20 }}>2.4 Deadlocks</div>
            <Bar w="96%" style={{ marginBottom: 12 }} /><Bar w="88%" style={{ marginBottom: 12 }} />
            <div style={{ margin: "16px -14px", padding: "16px 14px", borderRadius: 10, background: `rgba(249,115,22,${0.2 * lit})`, borderLeft: `6px solid rgba(249,115,22,${lit})` }}>
              <div style={{ fontSize: 23, lineHeight: 1.5, color: k.ink, fontWeight: 500 }}>A deadlock happens when processes wait on each other forever: mutual exclusion, hold and wait, no preemption, circular wait.</div>
            </div>
            <Bar w="92%" style={{ marginBottom: 12 }} /><Bar w="64%" />
          </div>
        </div>
      </AbsoluteFill>
    </Focus>
  );
};

/** 8. The dark statement with the bracketed promise, then the marks to choose from. */
export const Turns: React.FC<SceneProps> = ({ frames }) => {
  const frame = useT();
  const swap = p(frame, 62, 12);
  const close = p(frame, 120, 14, inOut);
  const chips = [2, 5, 10, 16];
  return (
    <Focus frames={frames}>
      <Bg kind="deep" />
      <AbsoluteFill style={{ ...center, opacity: 1 - swap }}>
        <div style={{ display: "flex", gap: 22, alignItems: "baseline" }}>
          <Giant text="it turns" from={5} top="#A1A1AA" bottom="#FFFFFF" />
          <BlurWords text="your notes into" delay={22} color="#A1A1AA" />
        </div>
      </AbsoluteFill>
      <AbsoluteFill style={{ ...center, opacity: swap, flexDirection: "column", gap: 54 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 34 - close * 20, fontFamily: font, fontSize: 86, fontWeight: 600, color: k.indigoSoft, letterSpacing: -2.5 }}>
          <span style={{ fontWeight: 300, fontSize: 130, transform: `translateX(${close * 180}px)` }}>[</span>
          <span style={{ overflow: "hidden", whiteSpace: "nowrap", maxWidth: 1100 * (1 - close), opacity: 1 - close }}>Exam-ready answers</span>
          <span style={{ fontWeight: 300, fontSize: 130, transform: `translateX(${-close * 180}px)` }}>]</span>
        </div>
        <div style={{ display: "flex", gap: 18, opacity: 1 - close }}>
          {chips.map((marks, i) => {
            const t = p(frame, 78 + i * 6, 12);
            const on = Math.floor(interpolate(frame, [84, 118], [0, 3.99], clamp)) === i;
            return (
              <div key={marks} style={{ width: 150, padding: "18px 0", textAlign: "center", borderRadius: 16, border: `1.5px solid ${on ? "#fff" : "rgba(255,255,255,0.2)"}`, background: on ? "#fff" : "rgba(255,255,255,0.04)", color: on ? k.navy : "#A1A1AA", opacity: t, transform: `translateY(${(1 - t) * 20}px) scale(${on ? 1.06 : 1})` }}>
                <Mono size={44} color={on ? k.navy : "#fff"} style={{ fontWeight: 700 }}>{marks}</Mono>
                <div style={{ fontFamily: font, fontSize: 19, fontWeight: 500, marginTop: 4 }}>marks</div>
              </div>
            );
          })}
        </div>
      </AbsoluteFill>
    </Focus>
  );
};
