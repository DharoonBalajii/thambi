#!/bin/zsh
# Compiles and runs Thambi's unit tests for the pure rules (no Xcode, no network, no cost).
set -e
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
src=leanring-buddy
swiftc -o $OUT/library Tests/library/main.swift $src/StudyLibrary.swift
swiftc -o $OUT/drawing Tests/drawing/main.swift $src/ThambiDrawing.swift $src/SpeechTimedTags.swift
swiftc -o $OUT/core Tests/core/main.swift $src/ThambiMemory.swift $src/ThambiDictionary.swift $src/ComputerControl.swift \
  $src/NotesMarkdown.swift $src/SpeechAcronymSpeller.swift $src/SpeechSentenceSplitter.swift $src/ThambiSettings.swift \
  $src/ClickyModelRouter.swift $src/OpenDocumentReader.swift $src/StudyLibrary.swift
swiftc -o $OUT/study Tests/study/main.swift $src/StudyAnswerFormat.swift $src/StudyPractice.swift $src/StudyPlanner.swift $src/StudyLanguage.swift $src/StudySocial.swift $src/StudyLibrary.swift
result=0
for suite in library drawing core study; do
  echo "== $suite"; $OUT/$suite || result=1
done
rm -rf $OUT
exit $result
