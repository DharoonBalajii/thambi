import React from "react";
import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";
import { AppWindow, Backdrop, Chip, Mascot, Num, Split, Tag, TextLines } from "../components";
import { clamp, Pop, prog, Rise, Typed, useCount, useSpring, Words } from "../motion";
import { c, font, mono } from "../theme";

const Body: React.FC<{ children: React.ReactNode; delay: number; dark?: boolean }> = ({ children, delay, dark }) => (
  <Rise delay={delay} style={{ fontSize: 33, lineHeight: 1.4, fontWeight: 500, color: dark ? c.onInk2 : c.text2 }}>{children}</Rise>
);

/** 1. Everything you study goes in: files fly into the library and become rows. */
export const LibraryScene: React.FC = () => {
  const frame = useCurrentFrame();
  const files = [
    { name: "Thermodynamics textbook.pdf", meta: "400 pages", color: c.red },
    { name: "DBMS Unit 3 slides.pptx", meta: "42 slides", color: c.orange },
    { name: "Photo of class notes.jpg", meta: "handwriting read", color: c.green },
    { name: "Circuits lab manual.docx", meta: "18 pages", color: c.indigo },
    { name: "My revision notes.md", meta: "note", color: c.text3 },
  ];
  const pages = useCount(472, 50, 70);
  return (
    <AbsoluteFill>
      <Backdrop />
      <Split
        left={<>
          <Tag label="Your library" />
          <Words text="Drop in everything you study." delay={6} size={78} color={c.text} highlight={{ everything: c.orangeDeep }} />
          <Body delay={30}>PDFs, slides, Word files, even photos of handwritten notes. Read on your Mac, nothing uploaded.</Body>
        </>}
        right={
          <AppWindow width={980} height={700} page="Library" delay={4}>
            <div style={{ padding: "40px 44px" }}>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                <div>
                  <div style={{ fontSize: 38, fontWeight: 800, color: c.text }}>Library</div>
                  <div style={{ fontSize: 20, color: c.text3, marginTop: 4 }}><Num size={20} color={c.text2}>{pages}</Num> pages, searchable in seconds</div>
                </div>
                <div style={{ padding: "13px 24px", borderRadius: 14, background: c.orangeDeep, color: "#fff", fontSize: 21, fontWeight: 700 }}>+ Add materials</div>
              </div>
              <div style={{ marginTop: 30, display: "flex", flexDirection: "column", gap: 12 }}>
                {files.map((file, i) => {
                  const s = prog(frame, 26 + i * 12, 22);
                  const fromX = [700, -500, 600, -400, 500][i];
                  const fromY = [-500, -300, 400, 500, -400][i];
                  return (
                    <div key={file.name} style={{ display: "flex", alignItems: "center", gap: 18, padding: "18px 22px", borderRadius: 16, background: "#fff", border: `1.5px solid ${c.paperLine}`,
                      opacity: Math.min(1, s * 2), transform: `translate(${(1 - s) * fromX}px, ${(1 - s) * fromY}px) rotate(${(1 - s) * 18}deg) scale(${1.25 - s * 0.25})`,
                      boxShadow: `0 ${(1 - s) * 40 + 4}px ${(1 - s) * 60 + 10}px rgba(20,21,60,${0.06 + (1 - s) * 0.2})` }}>
                      <span style={{ width: 34, height: 42, borderRadius: 7, background: file.color }} />
                      <span style={{ fontSize: 23, fontWeight: 600, color: c.text, flex: 1 }}>{file.name}</span>
                      <span style={{ fontFamily: mono, fontSize: 18, color: c.text3, fontWeight: 500 }}>{file.meta}</span>
                      <span style={{ width: 26, height: 26, borderRadius: 13, background: c.greenTint, color: c.green, fontSize: 17, fontWeight: 800, display: "flex", alignItems: "center", justifyContent: "center",
                        transform: `scale(${prog(frame, 46 + i * 12, 10)})` }}>✓</span>
                    </div>
                  );
                })}
              </div>
            </div>
          </AppWindow>
        }
      />
    </AbsoluteFill>
  );
};

/** 2. Ask: an answer from your own notes, each sentence with its source, opened at the page. */
export const AskScene: React.FC = () => {
  const frame = useCurrentFrame();
  const pageIn = useSpring(118, { damping: 17, stiffness: 120 });
  const highlight = prog(frame, 140, 20);
  const answerLines = [
    ["A ", "deadlock", " happens when processes wait on each other forever."],
    ["It needs four conditions together: mutual exclusion, hold and wait,"],
    ["no preemption and circular wait."],
  ];
  return (
    <AbsoluteFill>
      <Backdrop tint={c.indigo} second={c.indigoSoft} />
      <Split
        flip
        left={<>
          <Tag label="Ask" color={c.orange} />
          <Words text="Answers from your own notes, with the page." delay={6} size={72} color={c.text} highlight={{ page: c.indigo }} />
          <Body delay={34}>Every answer shows where it came from. One click opens the PDF at that page, passage highlighted.</Body>
        </>}
        right={
          <div style={{ position: "relative" }}>
            <AppWindow width={900} height={720} page="Ask" delay={4}>
              <div style={{ padding: "40px 44px", display: "flex", flexDirection: "column", gap: 24 }}>
                <Rise delay={16} style={{ alignSelf: "flex-end", padding: "16px 24px", borderRadius: 20, background: c.paper3, fontSize: 24, fontWeight: 500, color: c.text }}>
                  <Typed text="What is a deadlock and when does it happen?" delay={18} speed={1.6} />
                </Rise>
                <div style={{ display: "flex", gap: 18, opacity: prog(frame, 50, 10) }}>
                  <Mascot size={44} bounce={false} />
                  <div style={{ flex: 1 }}>
                    {answerLines.map((line, i) => (
                      <div key={i} style={{ fontSize: 25, lineHeight: 1.6, color: c.text, fontWeight: 500, opacity: prog(frame, 56 + i * 12, 12), transform: `translateY(${(1 - prog(frame, 56 + i * 12, 12)) * 12}px)` }}>
                        {line.map((part, j) => j === 1 ? <b key={j} style={{ fontWeight: 800 }}>{part}</b> : <span key={j}>{part}</span>)}
                        {i === 0 ? <Chip size={16} style={{ marginLeft: 8 }}>1</Chip> : null}
                        {i === 2 ? <Chip size={16} style={{ marginLeft: 8 }}>2</Chip> : null}
                      </div>
                    ))}
                    <Rise delay={96} style={{ marginTop: 26, display: "flex", flexDirection: "column", gap: 10 }}>
                      <div style={{ fontSize: 18, fontWeight: 600, color: c.text3 }}>Sources</div>
                      {["Operating Systems Unit 2, page 42", "Class notes, page 7"].map((label, i) => (
                        <div key={label} style={{ display: "flex", alignItems: "center", gap: 14, padding: "13px 16px", borderRadius: 14, background: i === 0 && frame > 110 ? c.indigoTint : c.paper2, fontSize: 21, fontWeight: 600, color: c.text }}>
                          <Chip size={15}>{i + 1}</Chip>{label}
                          {i === 0 ? <span style={{ marginLeft: "auto", fontSize: 18, fontWeight: 700, color: c.indigo }}>Show page 42</span> : null}
                        </div>
                      ))}
                    </Rise>
                  </div>
                </div>
              </div>
            </AppWindow>
            {/* The PDF page slides out of the window with its passage lit. */}
            <div style={{ position: "absolute", right: -120, top: 300, width: 360, height: 450, borderRadius: 18, background: "#fff", padding: "30px 30px",
              boxShadow: "0 40px 90px rgba(20,21,60,0.32), 0 0 0 1.5px rgba(20,21,43,0.08)", opacity: Math.min(1, pageIn * 1.5),
              transform: `translateX(${(1 - pageIn) * 240}px) rotate(${3 - pageIn * 0}deg) scale(${0.8 + pageIn * 0.2})` }}>
              <div style={{ fontSize: 17, fontWeight: 700, color: c.text3, fontFamily: mono }}>page 42</div>
              <div style={{ fontSize: 24, fontWeight: 800, color: c.text, margin: "10px 0 20px" }}>2.4 Deadlocks</div>
              <TextLines widths={[100, 92, 96, 70]} delay={122} />
              <div style={{ margin: "18px -12px", padding: "14px 12px", borderRadius: 10, background: `rgba(251,146,60,${0.35 * highlight})`, borderLeft: `5px solid rgba(234,88,12,${highlight})` }}>
                <TextLines widths={[98, 100, 84]} delay={126} color="#C9CCDA" />
              </div>
              <TextLines widths={[94, 100, 88, 97, 60]} delay={130} />
            </div>
          </div>
        }
      />
    </AbsoluteFill>
  );
};

/** 3. Marks: the same answer in the length the exam pays for. */
export const MarksScene: React.FC = () => {
  const frame = useCurrentFrame();
  const options = [2, 5, 10, 16];
  const active = frame < 40 ? 0 : frame < 72 ? 1 : frame < 104 ? 2 : 3;
  const lineCounts = [2, 5, 9, 13];
  const grow = (i: number) => prog(frame, 8 + i * 32, 18);
  const lines = Math.round(interpolate(grow(active), [0, 1], [active === 0 ? 0 : lineCounts[active - 1], lineCounts[active]], clamp));
  const widths = [96, 88, 100, 92, 70, 97, 85, 100, 60, 94, 99, 82, 45];
  return (
    <AbsoluteFill>
      <Backdrop dark />
      <Split
        dark
        left={<>
          <Tag label="Exam format" color={c.orangeSoft} dark />
          <Words text="Written the way your exam marks it." delay={6} size={74} color={c.onInk} highlight={{ marks: c.orangeSoft }} />
          <Body delay={32} dark>Pick 2, 5, 10 or 16 marks. Definition, points, diagram, conclusion: the shape examiners look for.</Body>
        </>}
        right={
          <div style={{ width: 860, fontFamily: font }}>
            <div style={{ display: "flex", gap: 14, marginBottom: 26 }}>
              {options.map((marks, i) => {
                const on = i === active;
                return (
                  <div key={marks} style={{ flex: 1, padding: "22px 0", borderRadius: 20, textAlign: "center", background: on ? c.orangeSoft : c.ink3, border: `1.5px solid ${on ? c.orangeSoft : c.line}`,
                    color: on ? "#2A1000" : c.onInk2, transform: `scale(${on ? 1.06 : 1})`, boxShadow: on ? `0 16px 50px ${c.orange}66` : "none" }}>
                    <div style={{ fontFamily: mono, fontSize: 52, fontWeight: 700, lineHeight: 1 }}>{marks}</div>
                    <div style={{ fontSize: 20, fontWeight: 600, marginTop: 6 }}>marks</div>
                  </div>
                );
              })}
            </div>
            <div style={{ borderRadius: 24, background: c.ink2, border: `1.5px solid ${c.line}`, padding: "34px 36px", height: 520, overflow: "hidden" }}>
              <div style={{ fontSize: 26, fontWeight: 800, color: c.onInk, marginBottom: 20 }}>Explain paging in operating systems</div>
              <div style={{ display: "flex", flexDirection: "column", gap: 15 }}>
                {widths.slice(0, lines).map((w, i) => {
                  const heading = active >= 2 && (i === 2 || i === 6 || i === 10);
                  const diagram = active >= 2 && i === 8;
                  return diagram ? (
                    <div key={i} style={{ display: "flex", gap: 12, alignItems: "center" }}>
                      {[0, 1, 2].map((b) => <div key={b} style={{ width: 96, height: 40, borderRadius: 9, border: `2px solid ${c.indigoSoft}`, background: "rgba(165,180,252,0.12)" }} />)}
                      <span style={{ fontSize: 17, fontWeight: 600, color: c.indigoSoft }}>diagram</span>
                    </div>
                  ) : (
                    <div key={i} style={{ width: `${heading ? 34 : w}%`, height: heading ? 16 : 12, borderRadius: 10, background: heading ? c.indigoSoft : "#3A3D63" }} />
                  );
                })}
              </div>
            </div>
          </div>
        }
      />
    </AbsoluteFill>
  );
};

/** 4. Practice: a quiz from your notes, checked, and the miss becomes a card that comes back. */
export const PracticeScene: React.FC = () => {
  const frame = useCurrentFrame();
  const checked = frame > 78;
  const flip = prog(frame, 120, 22);
  const cardIn = useSpring(104, { damping: 15 });
  const ratings = [["Again", "10 min"], ["Hard", "1 day"], ["Good", "4 days"], ["Easy", "14 days"]];
  return (
    <AbsoluteFill>
      <Backdrop tint={c.green} second={c.indigo} />
      <Split
        left={<>
          <Tag label="Practice" color={c.green} />
          <Words text="Quiz yourself. Remember for good." delay={6} size={76} color={c.text} highlight={{ good: c.green }} />
          <Body delay={32}>Questions made from your own notes. What you miss turns into flashcards that return right before you forget.</Body>
        </>}
        right={
          <div style={{ position: "relative", width: 900, height: 720, fontFamily: font }}>
            <Pop delay={8} style={{ position: "absolute", left: 0, top: 10, width: 640 }}>
              <div style={{ borderRadius: 26, background: "#fff", padding: "34px 36px", boxShadow: "0 40px 90px rgba(20,21,60,0.2), 0 0 0 1.5px rgba(20,21,43,0.07)" }}>
                <div style={{ display: "flex", justifyContent: "space-between", fontSize: 19, fontWeight: 700, color: c.text3 }}>
                  <span>Question <Num size={19} color={c.text2}>3</Num> of <Num size={19} color={c.text2}>5</Num></span><span>DBMS Unit 3</span>
                </div>
                <div style={{ fontSize: 31, fontWeight: 800, color: c.text, margin: "16px 0 20px", lineHeight: 1.25 }}>Why does a database keep a write-ahead log?</div>
                <div style={{ borderRadius: 16, border: `2px solid ${checked ? c.green : c.indigo}`, padding: "18px 20px", minHeight: 96, fontSize: 23, lineHeight: 1.45, color: c.text, fontWeight: 500 }}>
                  <Typed text="So it can redo or undo changes after a crash." delay={30} speed={1.3} caret={checked ? undefined : c.indigo} />
                </div>
                <div style={{ marginTop: 18, display: "flex", alignItems: "center", gap: 14, opacity: prog(frame, 80, 10), transform: `translateY(${(1 - prog(frame, 80, 10)) * 14}px)` }}>
                  <span style={{ width: 44, height: 44, borderRadius: 22, background: c.green, color: "#fff", fontSize: 26, fontWeight: 800, display: "flex", alignItems: "center", justifyContent: "center", transform: `scale(${useSpring(82, { damping: 9 })})` }}>✓</span>
                  <span style={{ fontSize: 24, fontWeight: 800, color: c.green }}>Correct</span>
                  <span style={{ fontSize: 20, color: c.text2, fontWeight: 500 }}>You explained recovery well.</span>
                </div>
              </div>
            </Pop>
            {/* The flashcard flips to its answer; the schedule buttons follow. */}
            <div style={{ position: "absolute", right: 0, top: 380, width: 520, opacity: Math.min(1, cardIn * 1.5), transform: `translateY(${(1 - cardIn) * 140}px) rotate(${-3 + cardIn * 3}deg)`, perspective: 1400 }}>
              <div style={{ borderRadius: 26, height: 250, background: flip < 0.5 ? c.indigo : "#fff", color: flip < 0.5 ? "#fff" : c.text, padding: 34, display: "flex", flexDirection: "column", justifyContent: "center",
                transform: `rotateX(${flip < 0.5 ? flip * 180 : (flip - 1) * 180}deg)`, boxShadow: "0 40px 90px rgba(20,21,60,0.3), 0 0 0 1.5px rgba(20,21,43,0.07)" }}>
                <div style={{ fontSize: 17, fontWeight: 700, opacity: 0.7, marginBottom: 10 }}>{flip < 0.5 ? "Flashcard" : "Answer"}</div>
                <div style={{ fontSize: 30, fontWeight: 800, lineHeight: 1.25 }}>{flip < 0.5 ? "What is third normal form?" : "No non-key column depends on another non-key column."}</div>
              </div>
              <div style={{ display: "flex", gap: 10, marginTop: 16 }}>
                {ratings.map(([name, when], i) => {
                  const p = prog(frame, 146 + i * 4, 12);
                  const picked = i === 2 && frame > 176;
                  return (
                    <div key={name} style={{ flex: 1, padding: "14px 0", borderRadius: 16, textAlign: "center", background: picked ? c.green : "#fff", color: picked ? "#fff" : c.text,
                      border: `1.5px solid ${picked ? c.green : c.paperLine}`, opacity: p, transform: `translateY(${(1 - p) * 20}px) scale(${picked ? 1.07 : 1})` }}>
                      <div style={{ fontSize: 20, fontWeight: 800 }}>{name}</div>
                      <div style={{ fontFamily: mono, fontSize: 16, fontWeight: 500, opacity: 0.75, marginTop: 3 }}>{when}</div>
                    </div>
                  );
                })}
              </div>
            </div>
          </div>
        }
      />
    </AbsoluteFill>
  );
};

/** 5. Plan: what past papers repeat, then a day-by-day plan to the exam. */
export const PlanScene: React.FC = () => {
  const frame = useCurrentFrame();
  const topics = [
    { name: "Normalisation", asked: 5, marks: 16 },
    { name: "Transactions and ACID", asked: 4, marks: 16 },
    { name: "Deadlock handling", asked: 4, marks: 10 },
    { name: "Indexing, B+ trees", asked: 3, marks: 10 },
    { name: "ER modelling", asked: 2, marks: 5 },
  ];
  const kinds = ["L", "L", "R", "L", "R", "L", "R", "L", "R", "R", "P", "P"];
  const colors: Record<string, string> = { L: c.indigo, R: c.orange, P: c.green };
  return (
    <AbsoluteFill>
      <Backdrop tint={c.orange} second={c.indigo} />
      <Split
        flip
        left={<>
          <Tag label="Exam planner" color={c.orange} />
          <Words text="Know what repeats. Plan every day." delay={6} size={76} color={c.text} highlight={{ repeats: c.orangeDeep }} />
          <Body delay={32}>Add previous-year papers. Thambi finds the questions that keep coming back and builds your plan to exam day.</Body>
        </>}
        right={
          <div style={{ width: 900, display: "flex", flexDirection: "column", gap: 22, fontFamily: font }}>
            <Pop delay={6}>
              <div style={{ borderRadius: 26, background: "#fff", padding: "30px 34px", boxShadow: "0 30px 80px rgba(20,21,60,0.16), 0 0 0 1.5px rgba(20,21,43,0.07)" }}>
                <div style={{ fontSize: 22, fontWeight: 800, color: c.text, marginBottom: 18 }}>Asked again and again <span style={{ color: c.text3, fontWeight: 600 }}>in 5 past papers</span></div>
                {topics.map((topic, i) => {
                  const p = prog(frame, 22 + i * 7, 26);
                  return (
                    <div key={topic.name} style={{ display: "flex", alignItems: "center", gap: 16, marginBottom: 12 }}>
                      <div style={{ width: 250, fontSize: 21, fontWeight: 600, color: c.text }}>{topic.name}</div>
                      <div style={{ flex: 1, height: 26, borderRadius: 13, background: c.paper3, overflow: "hidden" }}>
                        <div style={{ width: `${(topic.asked / 5) * 100 * p}%`, height: "100%", borderRadius: 13, background: i < 2 ? c.orangeDeep : i < 4 ? c.orangeSoft : "#F8C9A0" }} />
                      </div>
                      <div style={{ width: 170, textAlign: "right", fontFamily: mono, fontSize: 18, fontWeight: 700, color: c.text2 }}>{Math.round(topic.asked * p)}× {topic.marks} marks</div>
                    </div>
                  );
                })}
              </div>
            </Pop>
            <Pop delay={70}>
              <div style={{ borderRadius: 26, background: "#fff", padding: "28px 34px", boxShadow: "0 30px 80px rgba(20,21,60,0.16), 0 0 0 1.5px rgba(20,21,43,0.07)" }}>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 18 }}>
                  <div style={{ fontSize: 22, fontWeight: 800, color: c.text }}>Your plan <span style={{ color: c.text3, fontWeight: 600 }}>12 days to the exam</span></div>
                  <div style={{ display: "flex", gap: 16, fontSize: 17, fontWeight: 700 }}>
                    {[["Learn", c.indigo], ["Revise", c.orange], ["Past papers", c.green]].map(([label, color]) => (
                      <span key={label} style={{ display: "flex", alignItems: "center", gap: 7, color: c.text2 }}><span style={{ width: 13, height: 13, borderRadius: 4, background: color }} />{label}</span>
                    ))}
                  </div>
                </div>
                <div style={{ display: "grid", gridTemplateColumns: "repeat(12, 1fr)", gap: 9 }}>
                  {kinds.map((kind, i) => {
                    const p = prog(frame, 84 + i * 4, 14);
                    const done = frame > 140 + i * 5 && i < 4;
                    return (
                      <div key={i} style={{ height: 96, borderRadius: 14, background: colors[kind], opacity: p, transform: `translateY(${(1 - p) * 30}px) scale(${0.7 + p * 0.3})`, color: "#fff",
                        display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 4 }}>
                        <div style={{ fontFamily: mono, fontSize: 22, fontWeight: 700 }}>{i + 1}</div>
                        <div style={{ fontSize: 18, fontWeight: 800, height: 22 }}>{done ? "✓" : ""}</div>
                      </div>
                    );
                  })}
                </div>
              </div>
            </Pop>
          </div>
        }
      />
    </AbsoluteFill>
  );
};
