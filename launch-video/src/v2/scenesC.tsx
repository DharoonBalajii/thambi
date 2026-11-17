import React from "react";
import { AbsoluteFill, interpolate, random } from "remotion";
import { font } from "../theme";
import { Bg, BlurWords, card, clamp, Focus, inOut, k, Mark, Mono, p, Pointer, Tilt, TypeLine, useT } from "./kit";
import { Atom, Avatar, Confetti } from "./scenesB";

// Scenes timed natively for the 60 second cut: one beat is 15 frames at 120 BPM.
type SceneProps = { frames: number };
const center: React.CSSProperties = { alignItems: "center", justifyContent: "center" };

/** A keyboard key that pops up and is pressed. */
const Keycap: React.FC<{ label: string; at: number }> = ({ label, at }) => {
  const frame = useT();
  const show = p(frame, at - 6, 8) * (1 - p(frame, at + 14, 8));
  const press = p(frame, at, 3) - p(frame, at + 3, 6);
  return (
    <div style={{ opacity: show, transform: `translateY(${(1 - show) * 20 + press * 6}px) scale(${0.9 + show * 0.1})`, fontFamily: font, fontSize: 26, fontWeight: 600, color: k.ink,
      padding: "16px 28px", borderRadius: 16, background: "#fff", boxShadow: `0 ${8 - press * 6}px 0 #D4D4D8, 0 0 0 1.5px #D4D4D8, 0 20px 40px rgba(0,0,0,${0.12 - press * 0.06})` }}>
      {label}
    </div>
  );
};

/** The typing segment: a big ask bar, a question typed into it, Enter, and the answer unfolding with its sources. */
export const Ask: React.FC<SceneProps> = ({ frames }) => {
  const frame = useT();
  const question = "Explain deadlocks for 10 marks";
  const typingStarts = 12;
  const rise = p(frame, 70, 20, inOut);
  const answer = p(frame, 84, 14);
  const send = p(frame, 62, 3) - p(frame, 65, 8);
  const points = [
    ["Definition", "processes wait on each other forever, so none can finish"],
    ["Four conditions", "mutual exclusion, hold and wait, no preemption, circular wait"],
    ["Example", "two trains on one track, each waiting for the other to back up"],
    ["Handling", "prevention, avoidance with the Banker's algorithm, detection"],
  ];
  return (
    <Focus frames={frames}>
      <Bg kind="white" />
      <div style={{ position: "absolute", left: 0, right: 0, top: 300, opacity: 1 - p(frame, 60, 10) }}>
        <BlurWords text="Ask in your own words" delay={2} stagger={3} size={58} accentWords={["own", "words"]} />
      </div>
      <AbsoluteFill style={{ alignItems: "center", fontFamily: font }}>
        <div style={{ position: "absolute", top: 476 - rise * 330, transform: `scale(${1 - rise * 0.14})`, display: "flex", flexDirection: "column", alignItems: "center", gap: 26 }}>
          <div style={{ ...card, width: 1180, height: 128, borderRadius: 64, display: "flex", alignItems: "center", padding: "0 28px 0 34px", boxSizing: "border-box", gap: 26, opacity: p(frame, 0, 8),
            boxShadow: `0 30px 80px rgba(0,0,0,0.10), 0 0 0 ${frame >= typingStarts && frame < 70 ? 2.5 : 1.5}px ${frame >= typingStarts && frame < 70 ? k.indigo : "rgba(0,0,0,0.08)"}` }}>
            <Mark size={60} />
            <div style={{ flex: 1, position: "relative", height: 60, display: "flex", alignItems: "center" }}>
              {frame < typingStarts ? <span style={{ fontSize: 44, fontWeight: 500, color: "#B4B4BC", letterSpacing: -1.2 }}>Ask anything from your notes</span> : null}
              <TypeLine text={question} delay={typingStarts} speed={0.75} size={44} caret={frame < 70} />
            </div>
            <div style={{ width: 76, height: 76, borderRadius: 38, background: frame >= 44 ? k.indigo : "#E4E4E7", display: "flex", alignItems: "center", justifyContent: "center", transform: `scale(${1 - send * 0.15})` }}>
              <svg width="34" height="34" viewBox="0 0 24 24"><path d="M12 19V5M5 12l7-7 7 7" fill="none" stroke="#fff" strokeWidth={2.8} strokeLinecap="round" strokeLinejoin="round" /></svg>
            </div>
          </div>
          <div style={{ display: "flex", gap: 18, alignItems: "center", height: 70, opacity: 1 - rise }}>
            <div style={{ opacity: p(frame, 48, 8), transform: `scale(${0.8 + p(frame, 48, 10) * 0.2})`, padding: "12px 22px", borderRadius: 30, border: `2px solid ${k.indigo}`, color: k.indigo, fontSize: 24, fontWeight: 700 }}>10 mark answer</div>
            <Keycap label="return" at={62} />
          </div>
        </div>
        <div style={{ position: "absolute", top: 330, width: 1100, opacity: answer, transform: `translateY(${(1 - answer) * 50}px)` }}>
          <div style={{ ...card, padding: "36px 44px", boxSizing: "border-box" }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", marginBottom: 22 }}>
              <span style={{ fontSize: 38, fontWeight: 700, color: k.ink, letterSpacing: -1 }}>Deadlock</span>
              <Mono size={19} color="#7C7C86">10 marks, about 250 words</Mono>
            </div>
            {points.map(([title, body], i) => {
              const t = p(frame, 92 + i * 8, 12);
              return (
                <div key={title} style={{ display: "flex", gap: 18, padding: "11px 0", opacity: t, filter: t < 0.97 ? `blur(${(1 - t) * 8}px)` : undefined, transform: `translateX(${(1 - t) * 20}px)` }}>
                  <Mono size={22} color={k.indigo} style={{ fontWeight: 700, width: 28 }}>{i + 1}</Mono>
                  <span style={{ fontSize: 24, color: k.ink, lineHeight: 1.4 }}><b>{title}:</b> {body}</span>
                </div>
              );
            })}
            <div style={{ display: "flex", gap: 12, marginTop: 20 }}>
              {["OS Unit 2, page 42", "Class notes, page 7"].map((src, i) => {
                const t = p(frame, 126 + i * 5, 10);
                return <div key={src} style={{ opacity: t, transform: `scale(${0.85 + t * 0.15})`, padding: "9px 16px", borderRadius: 10, background: k.indigoPale, color: k.indigo, fontSize: 19, fontWeight: 700 }}>{src}</div>;
              })}
            </div>
          </div>
        </div>
      </AbsoluteFill>
    </Focus>
  );
};

/** Past papers in, the topics that keep coming back out, then a plan for the days left. */
export const Plan: React.FC<SceneProps> = ({ frames }) => {
  const frame = useT();
  const swap = p(frame, 50, 10, inOut);
  const topics: [string, number][] = [["Deadlocks", 6], ["Paging", 5], ["CPU scheduling", 4], ["Semaphores", 3], ["File systems", 2]];
  const days = [
    ["Day 1", "Deadlocks and paging", "the two most asked"],
    ["Day 2", "Scheduling, then a quiz", "with 10 mark answers"],
    ["Day 3", "Last year's paper", "timed, like the exam"],
  ];
  return (
    <Focus frames={frames}>
      <Bg kind="white" />
      <AbsoluteFill style={{ ...center, flexDirection: "column", gap: 50, opacity: 1 - swap, transform: `translateY(${-swap * 60}px)` }}>
        <BlurWords text="Past papers show what gets asked again and again" delay={2} stagger={3} size={58} accentWords={["again"]} style={{ width: 1600 }} />
        <div style={{ ...card, width: 1000, padding: "34px 44px", boxSizing: "border-box", fontFamily: font, opacity: p(frame, 8, 10), transform: `translateY(${(1 - p(frame, 8, 14)) * 30}px)` }}>
          <Mono size={19} color="#7C7C86">Asked in 6 previous papers</Mono>
          <div style={{ display: "flex", flexDirection: "column", gap: 16, marginTop: 20 }}>
            {topics.map(([name, count], i) => {
              const t = p(frame, 12 + i * 4, 20, inOut);
              return (
                <div key={name} style={{ display: "flex", alignItems: "center", gap: 20 }}>
                  <span style={{ width: 220, fontSize: 23, fontWeight: 600, color: k.ink }}>{name}</span>
                  <div style={{ flex: 1, height: 22, borderRadius: 11, background: "#F2F2F3" }}>
                    <div style={{ width: `${(count / 6) * 100 * t}%`, height: "100%", borderRadius: 11, background: i < 2 ? k.indigo : k.indigoSoft }} />
                  </div>
                  <Mono size={20} color={i < 2 ? k.indigo : "#7C7C86"} style={{ width: 40, textAlign: "right" }}>{Math.round(count * t)}</Mono>
                </div>
              );
            })}
          </div>
        </div>
      </AbsoluteFill>
      <AbsoluteFill style={{ ...center, flexDirection: "column", gap: 56, opacity: swap }}>
        <BlurWords text="Three days left? Here is your plan" delay={52} stagger={3} size={58} accentWords={["plan"]} />
        <div style={{ display: "flex", alignItems: "center", fontFamily: font }}>
          {days.map(([day, what, why], i) => {
            const t = p(frame, 60 + i * 7, 14);
            return (
              <React.Fragment key={day}>
                {i > 0 ? <div style={{ width: 70, height: 3, background: k.indigoSoft, transform: `scaleX(${p(frame, 58 + i * 7, 10)})`, transformOrigin: "left" }} /> : null}
                <div style={{ ...card, width: 400, padding: "28px 30px", boxSizing: "border-box", opacity: t, transform: `translateY(${(1 - t) * 30}px)`, border: i === 0 ? `2.5px solid ${k.indigo}` : "2.5px solid transparent" }}>
                  <Mono size={20} color={k.indigo} style={{ fontWeight: 700 }}>{day}</Mono>
                  <div style={{ fontSize: 29, fontWeight: 700, color: k.ink, margin: "10px 0 6px", letterSpacing: -0.6 }}>{what}</div>
                  <div style={{ fontSize: 21, color: "#6E6E78", fontWeight: 500 }}>{why}</div>
                </div>
              </React.Fragment>
            );
          })}
        </div>
      </AbsoluteFill>
    </Focus>
  );
};

/** Friends studying right now, a chat with a 3D model in it, and a study session started together. */
export const Friends: React.FC<SceneProps> = ({ frames }) => {
  const frame = useT();
  const friends: [string, string, string, boolean][] = [
    ["Priya", "#E11D48", "Focusing on DBMS, 12 min left", true],
    ["Arjun", k.green, "Practising Physics for 8 min", true],
    ["Meera", k.orange, "On a break", false],
  ];
  const chat = p(frame, 34, 16, inOut);
  const toast = p(frame, 100, 10);
  return (
    <Focus frames={frames}>
      <Bg kind="grad" />
      <div style={{ position: "absolute", left: 0, right: 0, top: 80 }}>
        <BlurWords text="Study with friends, live" delay={2} stagger={3} size={66} accentWords={["live"]} />
      </div>
      <AbsoluteFill style={{ transform: "scale(1.1)", transformOrigin: "50% 24%" }}>
        <div style={{ position: "absolute", left: 190, top: 270, fontFamily: font }}>
          <Tilt delay={4} duration={30} from={{ rx: 20, ry: -24, rz: 3, scale: 0.92, y: 120 }}>
            <div style={{ ...card, width: 620, padding: "30px 30px 18px", boxSizing: "border-box" }}>
              <div style={{ fontSize: 27, fontWeight: 700, color: k.ink, marginBottom: 18 }}>Friends</div>
              {friends.map(([name, color, status, live], i) => {
                const t = p(frame, 12 + i * 5, 12);
                return (
                  <div key={name} style={{ display: "flex", alignItems: "center", gap: 18, padding: "16px 8px", borderTop: i ? `1.5px solid ${k.line}` : undefined, opacity: t, transform: `translateX(${(1 - t) * -24}px)` }}>
                    <div style={{ position: "relative" }}>
                      <Avatar name={name} color={color} />
                      {live ? <div style={{ position: "absolute", right: -2, bottom: -2, width: 18, height: 18, borderRadius: 9, background: "#22C55E", border: "3px solid #fff", transform: `scale(${1 + 0.15 * Math.sin(frame / 6)})` }} /> : null}
                    </div>
                    <div>
                      <div style={{ fontSize: 23, fontWeight: 700, color: k.ink }}>{name}</div>
                      <div style={{ fontSize: 19, fontWeight: 500, color: live ? k.indigo : "#8E8E98", marginTop: 2 }}>{status}</div>
                    </div>
                  </div>
                );
              })}
            </div>
          </Tilt>
        </div>
        <div style={{ position: "absolute", left: 870, top: 250, width: 860, opacity: chat, transform: `translateX(${(1 - chat) * 120}px)`, fontFamily: font }}>
          <div style={{ ...card, padding: "26px 30px", boxSizing: "border-box" }}>
            <div style={{ display: "flex", alignItems: "center", gap: 14, paddingBottom: 18, borderBottom: `1.5px solid ${k.line}` }}>
              <Avatar name="Priya" color="#E11D48" size={44} />
              <div style={{ fontSize: 23, fontWeight: 700, color: k.ink, flex: 1 }}>Priya</div>
              <div style={{ padding: "11px 20px", borderRadius: 12, background: frame >= 94 ? k.ink : k.indigo, color: "#fff", fontSize: 19, fontWeight: 600 }}>Study together</div>
            </div>
            <div style={{ display: "flex", flexDirection: "column", gap: 14, paddingTop: 20 }}>
              <div style={{ alignSelf: "flex-start", background: "#F2F2F3", borderRadius: "18px 18px 18px 6px", padding: "14px 20px", fontSize: 22, color: k.ink, opacity: p(frame, 44, 8), transform: `translateY(${(1 - p(frame, 44, 8)) * 14}px)` }}>
                How do electrons sit around the nucleus?
              </div>
              <div style={{ alignSelf: "flex-end", width: 430, background: k.indigo, borderRadius: "18px 18px 6px 18px", padding: 16, opacity: p(frame, 58, 10), transform: `translateY(${(1 - p(frame, 58, 10)) * 18}px)` }}>
                <div style={{ background: "#fff", borderRadius: 12, height: 200, display: "flex", alignItems: "center", justifyContent: "center" }}><Atom size={190} /></div>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", marginTop: 12, color: "#fff" }}>
                  <span style={{ fontSize: 21, fontWeight: 700 }}>Atom</span>
                  <Mono size={16} color="#E0E7FF">3D model, drag to turn</Mono>
                </div>
              </div>
            </div>
          </div>
        </div>
        <Pointer path={[{ x: 1500, y: 980, at: 74 }, { x: 1610, y: 312, at: 92 }]} clickAt={94} />
        <Confetti x={1610} y={300} at={95} />
      </AbsoluteFill>
      <div style={{ position: "absolute", left: "50%", bottom: 70, transform: `translate(-50%, ${(1 - toast) * 24}px)`, opacity: toast, background: k.ink, color: "#fff", fontFamily: font, fontSize: 24, fontWeight: 600, padding: "16px 28px", borderRadius: 16, display: "flex", gap: 14, alignItems: "center" }}>
        <Mark size={30} /> Studying together with Priya for 25 min
      </div>
    </Focus>
  );
};

/** Voice: ask out loud about what is on screen, and Thambi flies over, circles it and explains. */
export const Voice: React.FC<SceneProps> = ({ frames }) => {
  const frame = useT();
  const draw = p(frame, 46, 14, inOut);
  const caption = p(frame, 54, 10);
  const curve = (x: number) => 520 - 4 * 300 * (x / 880) * (1 - x / 880);
  const path = Array.from({ length: 45 }, (_, i) => { const x = i * 20; return `${i ? "L" : "M"}${60 + x} ${curve(x)}`; }).join(" ");
  const cx = 60 + 440, cy = curve(440);
  const fly = p(frame, 22, 24, inOut);
  const buddyX = interpolate(fly, [0, 1], [1560, 520 + cx - 30]);
  const buddyY = interpolate(fly, [0, 1], [900, 190 + cy - 150]) - Math.sin(fly * Math.PI) * 120;
  return (
    <Focus frames={frames}>
      <Bg kind="deep" />
      <div style={{ position: "absolute", left: 0, right: 0, top: 64 }}>
        <BlurWords text="Ask out loud about anything on your screen" delay={2} stagger={3} size={54} color="#fff" accent={k.indigoSoft} accentWords={["out", "loud"]} />
      </div>
      <div style={{ position: "absolute", left: 520, top: 190 }}>
        <Tilt delay={2} duration={22} from={{ rx: 24, ry: 0, rz: 0, scale: 0.9, y: 120 }}>
          <div style={{ ...card, width: 1000, height: 640, position: "relative", fontFamily: font }}>
            <div style={{ position: "absolute", left: 44, top: 32, fontSize: 30, fontWeight: 700, color: k.ink }}>Projectile motion</div>
            <Mono size={17} color="#8E8E98" style={{ position: "absolute", right: 40, top: 42 }}>Physics lecture 6, slide 14</Mono>
            <svg width="1000" height="640" style={{ position: "absolute", left: 0, top: 0 }}>
              <line x1={60} y1={520} x2={960} y2={520} stroke="#D4D4D8" strokeWidth={3} />
              <line x1={60} y1={140} x2={60} y2={520} stroke="#D4D4D8" strokeWidth={3} />
              <path d={path} fill="none" stroke={k.ink} strokeWidth={4} strokeDasharray={1400} strokeDashoffset={1400 * (1 - p(frame, 6, 22))} />
              <circle cx={cx} cy={cy} r={62} fill="none" stroke={k.indigo} strokeWidth={6} strokeLinecap="round" strokeDasharray={390} strokeDashoffset={390 * (1 - draw)} transform={`rotate(-90 ${cx} ${cy})`} />
            </svg>
            <div style={{ position: "absolute", left: cx + 80, top: cy - 10, opacity: caption, transform: `translateY(${(1 - caption) * 12}px)`, background: k.indigo, color: "#fff", fontSize: 22, fontWeight: 600, padding: "12px 18px", borderRadius: 14, width: 330 }}>
              At the top, the vertical speed is zero
            </div>
          </div>
        </Tilt>
      </div>
      <div style={{ position: "absolute", left: buddyX, top: buddyY, opacity: p(frame, 20, 6), transform: `rotate(${Math.sin(fly * Math.PI) * -12}deg)` }}>
        <Mark size={58} />
      </div>
      <div style={{ position: "absolute", left: 120, top: 520, fontFamily: font, opacity: p(frame, 8, 10) }}>
        <div style={{ display: "flex", gap: 6, alignItems: "center", height: 90 }}>
          {Array.from({ length: 22 }).map((_, i) => {
            const speaking = frame >= 10 && frame < 40;
            const h = speaking ? 14 + Math.abs(Math.sin(frame / 3 + i * 0.9)) * 70 * (0.4 + random(`b${i}`) * 0.6) : 10;
            return <div key={i} style={{ width: 8, height: h, borderRadius: 4, background: k.indigoSoft }} />;
          })}
        </div>
        <div style={{ display: "inline-block", marginTop: 18, background: "rgba(255,255,255,0.08)", border: "1.5px solid rgba(255,255,255,0.18)", borderRadius: "18px 18px 18px 6px", padding: "14px 20px", opacity: p(frame, 8, 8) }}>
          <TypeLine text="Why is it flat here?" delay={10} speed={1} size={32} color="#fff" caret={false} />
        </div>
      </div>
    </Focus>
  );
};

/** Everything else, rolling past on the beat. */
export const More: React.FC<SceneProps> = ({ frames }) => {
  const frame = useT();
  const items = ["answers in Tamil, Hindi and English", "photos of handwritten notes", "2, 5, 10 or 16 mark answers", "a focus timer and streaks", "flashcards you can take to Anki", "practice from last year's papers"];
  const pos = interpolate(frame, items.map((_, i) => 6 + i * 15), items.map((_, i) => i), { ...clamp, easing: inOut });
  return (
    <Focus frames={frames}>
      <Bg kind="white" />
      <AbsoluteFill style={{ flexDirection: "row", alignItems: "center", fontFamily: font, fontSize: 64, fontWeight: 500, letterSpacing: -1.8 }}>
        <div style={{ width: 640, textAlign: "right", paddingRight: 30, color: k.ink, opacity: p(frame, 0, 8) }}>Thambi also does</div>
        <div style={{ position: "relative", flex: 1, height: 1080 }}>
          {items.map((item, i) => {
            const d = i - pos;
            const near = Math.max(0, 1 - Math.abs(d) * 0.55);
            return (
              <div key={item} style={{ position: "absolute", left: 0, top: 540 - 42 + d * 104, color: Math.abs(d) < 0.5 ? k.indigo : "#BDBDC4", opacity: near, filter: Math.abs(d) > 0.4 ? `blur(${Math.min(6, Math.abs(d) * 3)}px)` : undefined, whiteSpace: "nowrap", transform: `scale(${1 - Math.min(1, Math.abs(d)) * 0.12})`, transformOrigin: "left center" }}>
                {item}
              </div>
            );
          })}
        </div>
      </AbsoluteFill>
    </Focus>
  );
};

/** The privacy promise, on graphite. */
export const Private: React.FC<SceneProps> = ({ frames }) => {
  const frame = useT();
  const lock = p(frame, 2, 14, inOut);
  const lines = ["no account to sign up for", "friends connect directly, encrypted", "nothing is shared until you turn it on"];
  return (
    <Focus frames={frames}>
      <Bg kind="black" />
      <AbsoluteFill style={{ ...center, flexDirection: "column", gap: 40 }}>
        <svg width="96" height="110" viewBox="0 0 48 56" style={{ opacity: lock, transform: `scale(${0.6 + lock * 0.4})` }}>
          <path d={`M12 26 V${18 - (1 - lock) * 6} a12 12 0 0 1 24 0 V26`} fill="none" stroke="#D4D4D8" strokeWidth={5} strokeLinecap="round" />
          <rect x={6} y={24} width={36} height={28} rx={7} fill={k.indigoBright} />
          <circle cx={24} cy={37} r={4} fill="#fff" />
        </svg>
        <BlurWords text="Your library stays on your Mac" delay={8} stagger={3} size={80} color="#fff" accent={k.indigoSoft} accentWords={["Mac"]} />
        <div style={{ display: "flex", gap: 22, marginTop: 10 }}>
          {lines.map((line, i) => {
            const t = p(frame, 28 + i * 5, 10);
            return (
              <div key={line} style={{ opacity: t, transform: `translateY(${(1 - t) * 16}px)`, border: "1.5px solid rgba(255,255,255,0.18)", borderRadius: 10, padding: "14px 20px", display: "flex", alignItems: "center", gap: 12 }}>
                <span style={{ width: 22, height: 22, borderRadius: 5, background: "#fff", color: "#000", fontSize: 15, fontWeight: 800, display: "flex", alignItems: "center", justifyContent: "center", fontFamily: font }}>✓</span>
                <Mono size={22}>{line}</Mono>
              </div>
            );
          })}
        </div>
      </AbsoluteFill>
    </Focus>
  );
};

/** The two-beat contrast line. */
export const Contrast: React.FC<SceneProps> = ({ frames }) => {
  const frame = useT();
  const dim = p(frame, 34, 12);
  return (
    <Focus frames={frames}>
      <Bg kind="white" />
      <AbsoluteFill style={{ ...center, flexDirection: "column", gap: 26 }}>
        <div style={{ opacity: 1 - dim * 0.6 }}>
          <BlurWords text="Other apps answer your questions" delay={2} stagger={3} size={74} color={dim > 0.5 ? "#A0A0A8" : k.ink} />
        </div>
        <BlurWords text="Thambi makes sure you remember them" delay={36} stagger={4} size={74} weight={600} accentWords={["remember", "them"]} />
      </AbsoluteFill>
    </Focus>
  );
};

/** The end card. */
export const Logo: React.FC<SceneProps> = ({ frames }) => {
  const frame = useT();
  const mark = p(frame, 2, 16, inOut);
  return (
    <Focus frames={frames}>
      <Bg kind="white" />
      <AbsoluteFill style={{ ...center, flexDirection: "column", gap: 36 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 34 }}>
          <div style={{ transform: `scale(${mark}) rotate(${(1 - mark) * -40}deg)`, opacity: mark }}><Mark size={150} phase={6} /></div>
          <div style={{ fontFamily: font, fontSize: 150, fontWeight: 700, letterSpacing: -6, color: k.ink, display: "flex", overflow: "hidden", paddingBottom: 20 }}>
            {"Thambi".split("").map((ch, i) => {
              const t = p(frame, 6 + i * 2, 12);
              return <span key={i} style={{ display: "inline-block", transform: `translateY(${(1 - t) * 170}px)`, opacity: t }}>{ch}</span>;
            })}
          </div>
        </div>
        <BlurWords text="Study faster. Remember longer." delay={20} stagger={3} size={46} color="#5E5E68" accentWords={["Remember", "longer"]} />
      </AbsoluteFill>
    </Focus>
  );
};

/** The call to action on black. */
export const Cta: React.FC<SceneProps> = ({ frames }) => {
  const frame = useT();
  const button = p(frame, 18, 12);
  return (
    <Focus frames={frames}>
      <Bg kind="black" />
      <AbsoluteFill style={{ ...center, flexDirection: "column", gap: 56 }}>
        <BlurWords text="Start studying smarter today" delay={2} stagger={3} size={92} weight={600} color="#fff" accent={k.indigoSoft} accentWords={["smarter"]} />
        <div style={{ opacity: button, transform: `translateY(${(1 - button) * 20}px)`, display: "flex", alignItems: "center", gap: 16, background: "#fff", color: k.ink, fontFamily: font, fontSize: 32, fontWeight: 600, padding: "22px 40px", borderRadius: 18 }}>
          <Mark size={40} phase={30} /> Download Thambi for Mac
        </div>
      </AbsoluteFill>
    </Focus>
  );
};
