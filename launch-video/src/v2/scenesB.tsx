import React from "react";
import { AbsoluteFill, interpolate, random } from "remotion";
import { font } from "../theme";
import { Bg, BlurWords, card, clamp, Focus, Giant, inOut, k, Mark, Mono, p, Pointer, Tilt, TypeLine, useT } from "./kit";
import { Window } from "./scenesA";

type SceneProps = { frames: number };
const center: React.CSSProperties = { alignItems: "center", justifyContent: "center" };

/** A blue progress strip that sits on top of a card, as in the reference's "learning... 29%". */
const ProgressHeader: React.FC<{ label: string; from: number; duration: number; width: number }> = ({ label, from, duration, width }) => {
  const frame = useT();
  const t = p(frame, from, duration, inOut);
  return (
    <div style={{ width, background: k.indigoBright, borderRadius: "14px 14px 0 0", padding: "14px 22px" }}>
      <div style={{ display: "flex", justifyContent: "space-between" }}><Mono size={22} color="#fff">{label}</Mono><Mono size={22} color="#fff">{Math.round(t * 100)}%</Mono></div>
      <div style={{ height: 6, borderRadius: 3, background: "rgba(0,0,0,0.28)", marginTop: 12 }}><div style={{ width: `${t * 100}%`, height: "100%", background: "#fff", borderRadius: 3 }} /></div>
    </div>
  );
};

/** 9. "Then it checks what you { remember }", and the quiz marks a typed answer. */
export const Remember: React.FC<SceneProps> = ({ frames }) => {
  const frame = useT();
  const part = p(frame, 46, 16, inOut);
  const quiz = p(frame, 60, 22, inOut);
  const verdict = p(frame, 136, 12);
  const words = ["Then", "it", "checks", "what", "you"];
  return (
    <Focus frames={frames}>
      <Bg kind="white" />
      <AbsoluteFill style={{ ...center, opacity: 1 - quiz }}>
        <div style={{ display: "flex", gap: 18 + part * 120, fontFamily: font, fontSize: 76, fontWeight: 500, letterSpacing: -2.2, color: k.ink }}>
          {words.map((word, i) => {
            const t = p(frame, 4 + i * 4, 10);
            return <span key={word} style={{ opacity: t * (1 - part), filter: `blur(${(1 - t) * 14 + part * 8}px)` }}>{word}</span>;
          })}
          <span style={{ color: k.indigo, opacity: p(frame, 26, 10), transform: `scale(${1 + part * 0.25})` }}>{"{ remember }"}</span>
        </div>
      </AbsoluteFill>
      <AbsoluteFill style={{ ...center, opacity: quiz, transform: `scale(${0.72 + quiz * 0.28}) translateY(${(1 - quiz) * 60}px)` }}>
        <div style={{ fontFamily: font }}>
          <ProgressHeader label="checking your answer..." from={104} duration={30} width={900} />
          <div style={{ ...card, width: 900, borderRadius: "0 0 18px 18px", padding: "34px 40px", boxSizing: "border-box" }}>
            <Mono size={19} color="#7C7C86">Operating Systems, question 3 of 5</Mono>
            <div style={{ fontSize: 34, fontWeight: 700, color: k.ink, margin: "12px 0 24px", letterSpacing: -0.8 }}>Name the four conditions for a deadlock.</div>
            <div style={{ border: `1.5px solid ${k.line}`, borderRadius: 14, padding: "18px 22px", minHeight: 70, background: "#FAFAFA" }}>
              <TypeLine text="mutual exclusion, hold and wait, no preemption, circular wait" delay={74} speed={1.7} size={24} color={k.ink} caret={frame < 104} />
            </div>
            <div style={{ display: "flex", alignItems: "center", gap: 16, marginTop: 24, opacity: verdict, transform: `translateY(${(1 - verdict) * 14}px)` }}>
              <span style={{ background: "#DCFCE7", color: k.green, fontWeight: 800, fontSize: 22, padding: "9px 18px", borderRadius: 12 }}>Correct</span>
              <span style={{ fontSize: 23, color: "#4B4B55", fontWeight: 500 }}>All four conditions, in the words your notes use.</span>
            </div>
          </div>
        </div>
      </AbsoluteFill>
    </Focus>
  );
};

/** 10. A flashcard flips, the student rates it, and it is scheduled for the day before they would forget. */
export const Flashcards: React.FC<SceneProps> = ({ frames }) => {
  const frame = useT();
  const flip = p(frame, 58, 18, inOut);
  const toast = p(frame, 112, 12);
  const ratings = [["Again", "1 min"], ["Hard", "2 days"], ["Good", "4 days"], ["Easy", "9 days"]];
  return (
    <Focus frames={frames}>
      <Bg kind="grad" />
      <div style={{ position: "absolute", left: 110, top: 84, width: 560 }}>
        <BlurWords text="Flashcards that come back right before you forget" delay={8} size={50} style={{ justifyContent: "flex-start" }} accentWords={["forget"]} />
      </div>
      <AbsoluteFill style={{ ...center, paddingLeft: 560 }}>
        <Tilt delay={2} duration={56} from={{ rx: 26, ry: 22, rz: -4, scale: 0.9, y: 220 }}>
          <Window active="Practice" width={1120} height={720}>
            <div style={{ padding: "40px 46px", display: "flex", flexDirection: "column", alignItems: "center" }}>
              <div style={{ alignSelf: "stretch", display: "flex", justifyContent: "space-between" }}>
                <div style={{ fontSize: 32, fontWeight: 700, color: k.ink }}>Review</div>
                <Mono size={19} color="#7C7C86">12 cards due today</Mono>
              </div>
              <div style={{ perspective: 1600, marginTop: 34 }}>
                <div style={{ width: 640, height: 300, borderRadius: 20, border: `2px solid ${flip > 0.5 ? k.indigo : k.line}`, background: "#fff", boxShadow: "0 24px 60px rgba(0,0,0,0.10)",
                  transform: `rotateY(${flip * 180}deg)`, display: "flex", alignItems: "center", justifyContent: "center", padding: 40, boxSizing: "border-box" }}>
                  <div style={{ transform: flip > 0.5 ? "rotateY(180deg)" : undefined, textAlign: "center" }}>
                    {flip <= 0.5 ? (
                      <div style={{ fontSize: 38, fontWeight: 700, color: k.ink, letterSpacing: -1 }}>What is normalisation?</div>
                    ) : (
                      <>
                        <div style={{ fontSize: 27, fontWeight: 500, color: k.ink, lineHeight: 1.45 }}>Organising tables so each fact is stored once, which removes redundancy and update errors.</div>
                        <Mono size={17} color={k.indigo} style={{ display: "block", marginTop: 18 }}>DBMS Unit 3, page 88</Mono>
                      </>
                    )}
                  </div>
                </div>
              </div>
              <div style={{ display: "flex", gap: 14, marginTop: 34, opacity: p(frame, 76, 12) }}>
                {ratings.map(([name, wait]) => {
                  const chosen = name === "Good" && frame >= 104;
                  return (
                    <div key={name} style={{ width: 150, padding: "14px 0", borderRadius: 14, textAlign: "center", border: `1.5px solid ${chosen ? k.indigo : k.line}`, background: chosen ? k.indigo : "#fff", color: chosen ? "#fff" : k.ink }}>
                      <div style={{ fontSize: 22, fontWeight: 700 }}>{name}</div>
                      <Mono size={16} color={chosen ? "#E0E7FF" : "#7C7C86"}>{wait}</Mono>
                    </div>
                  );
                })}
              </div>
            </div>
            <div style={{ position: "absolute", left: "50%", bottom: 34, transform: `translate(-50%, ${(1 - toast) * 20}px)`, opacity: toast, background: k.ink, color: "#fff", fontSize: 21, fontWeight: 600, padding: "13px 24px", borderRadius: 14, whiteSpace: "nowrap" }}>
              Next review in 4 days
            </div>
          </Window>
        </Tilt>
      </AbsoluteFill>
      <Pointer path={[{ x: 1700, y: 960, at: 80 }, { x: 1340, y: 790, at: 102 }]} clickAt={104} />
    </Focus>
  );
};

/** A friend's initials in a coloured circle. */
export const Avatar: React.FC<{ name: string; color: string; size?: number }> = ({ name, color, size = 52 }) => (
  <div style={{ width: size, height: size, borderRadius: size / 2, background: color, color: "#fff", fontWeight: 700, fontSize: size * 0.4, display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>{name[0]}</div>
);

/** The ready-made atom model, turning: what a friend sends to teach with. */
export const Atom: React.FC<{ size: number }> = ({ size }) => {
  const frame = useT();
  const spin = frame * 2.4;
  return (
    <svg width={size} height={size} viewBox="-100 -100 200 200">
      {[0, 60, 120].map((angle, i) => {
        const a = ((spin * (i % 2 ? -1 : 1) + angle * 3) * Math.PI) / 180;
        const ex = Math.cos(a) * 82, ey = Math.sin(a) * 28;
        const r = (angle * Math.PI) / 180;
        return (
          <g key={angle} transform={`rotate(${angle})`}>
            <ellipse rx={82} ry={28} fill="none" stroke={k.indigoSoft} strokeWidth={3} />
            <circle cx={ex} cy={ey} r={8} fill={k.indigo} opacity={0.6 + 0.4 * Math.cos(a + r)} />
          </g>
        );
      })}
      <circle r={20} fill={k.orange} />
      <circle r={20} fill="url(#shine)" />
      <defs><radialGradient id="shine" cx="35%" cy="35%"><stop offset="0%" stopColor="#fff" stopOpacity={0.7} /><stop offset="100%" stopColor="#fff" stopOpacity={0} /></radialGradient></defs>
    </svg>
  );
};

/** Paper confetti from one point, the "user invited" beat. */
export const Confetti: React.FC<{ x: number; y: number; at: number }> = ({ x, y, at }) => {
  const frame = useT();
  if (frame < at) return null;
  const t = (frame - at) / 30;
  const colors = [k.indigo, k.orange, k.indigoSoft, k.green, "#FACC15"];
  return (
    <>
      {Array.from({ length: 46 }).map((_, i) => {
        const angle = random(`a${i}`) * Math.PI * 2;
        const speed = 260 + random(`s${i}`) * 420;
        const px = x + Math.cos(angle) * speed * t;
        const py = y + Math.sin(angle) * speed * t * 0.8 + 420 * t * t;
        return (
          <div key={i} style={{ position: "absolute", left: px, top: py, width: 10 + random(`w${i}`) * 8, height: 6 + random(`h${i}`) * 6, borderRadius: 2, background: colors[i % colors.length],
            transform: `rotate(${frame * (6 + random(`r${i}`) * 10)}deg)`, opacity: interpolate(t, [0, 0.1, 1.1, 1.5], [0, 1, 1, 0], clamp), zIndex: 30 }} />
        );
      })}
    </>
  );
};

/** 14. The beat before the list. */
export const And: React.FC<SceneProps> = ({ frames }) => (
  <Focus frames={frames} zoom={0}>
    <Bg kind="deep" />
    <AbsoluteFill style={center}>
      <Giant text="And" from={9} size={170} top="#A1A1AA" bottom="#FFFFFF" />
    </AbsoluteFill>
  </Focus>
);

