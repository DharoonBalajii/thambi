import { loadFont as loadJakarta } from "@remotion/google-fonts/PlusJakartaSans";
import { loadFont as loadMono } from "@remotion/google-fonts/JetBrainsMono";
import { loadFont as loadTamil } from "@remotion/google-fonts/NotoSansTamil";
import { loadFont as loadDevanagari } from "@remotion/google-fonts/NotoSansDevanagari";

// Same identity as the app: ink and paper, indigo for Thambi, marigold orange for the student.
// All four typefaces are under the SIL Open Font License.
export const font = loadJakarta("normal", { weights: ["400", "500", "600", "700", "800"], subsets: ["latin"] }).fontFamily;
export const mono = loadMono("normal", { weights: ["500", "700"], subsets: ["latin"] }).fontFamily;
export const tamil = loadTamil("normal", { weights: ["600"], subsets: ["tamil"] }).fontFamily;
export const devanagari = loadDevanagari("normal", { weights: ["600"], subsets: ["devanagari"] }).fontFamily;

export const c = {
  ink: "#0E0F1D",
  ink2: "#16172B",
  ink3: "#1E2039",
  ink4: "#282A49",
  line: "#2A2C48",
  paper: "#FBFBFE",
  paper2: "#F4F5FB",
  paper3: "#ECEEF7",
  paperLine: "#E3E5F0",
  text: "#14152B",
  text2: "#474A63",
  text3: "#6B6E88",
  onInk: "#EEEFFB",
  onInk2: "#BBBDD8",
  onInk3: "#8C8FB0",
  indigo: "#4F46E5",
  indigoDeep: "#4338CA",
  indigoSoft: "#A5B4FC",
  indigoTint: "#EBEDFF",
  orange: "#EA580C",
  orangeDeep: "#C2410C",
  orangeSoft: "#FB923C",
  orangeTint: "#FFEDD9",
  green: "#15803D",
  greenSoft: "#4ADE80",
  greenTint: "#E3F6E9",
  red: "#DC2626",
};

export const FPS = 30;
export const W = 1920;
export const H = 1080;
