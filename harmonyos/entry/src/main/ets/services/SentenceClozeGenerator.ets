import { Question, QuestionKind } from '../models/Question';
import { WordEntry } from '../models/WordEntry';
import { WordRepository } from './WordRepository';
import { RandomFn, shuffle } from '../utils/shuffle';

export class SentenceClozeTargetSpan {
  start: number = 0;
  endExclusive: number = 0;
}

function isAsciiLetter(c: string): boolean {
  if (c.length === 0) {
    return false;
  }
  const code: number = c.toLowerCase().charCodeAt(0);
  return code >= 97 && code <= 122;
}

function isWhitespace(c: string): boolean {
  return c === ' ' || c === '\t' || c === '\n' || c === '\r';
}

function hasLetterBoundary(raw: string, start: number, endExclusive: number): boolean {
  const before: string = start > 0 ? raw.charAt(start - 1) : '';
  const after: string = endExclusive < raw.length ? raw.charAt(endExclusive) : '';
  return !isAsciiLetter(before) && !isAsciiLetter(after);
}

function matchTargetAt(raw: string, target: string, start: number): number {
  const lowerRaw: string = raw.toLowerCase();
  const lowerTarget: string = target.toLowerCase().trim();
  let rawIdx: number = start;
  let targetIdx: number = 0;
  while (targetIdx < lowerTarget.length) {
    const targetChar: string = lowerTarget.charAt(targetIdx);
    if (isWhitespace(targetChar)) {
      let targetSpaceEnd: number = targetIdx;
      while (targetSpaceEnd < lowerTarget.length && isWhitespace(lowerTarget.charAt(targetSpaceEnd))) {
        targetSpaceEnd++;
      }
      if (rawIdx >= lowerRaw.length || !isWhitespace(lowerRaw.charAt(rawIdx))) {
        return -1;
      }
      while (rawIdx < lowerRaw.length && isWhitespace(lowerRaw.charAt(rawIdx))) {
        rawIdx++;
      }
      targetIdx = targetSpaceEnd;
      continue;
    }
    if (rawIdx >= lowerRaw.length || lowerRaw.charAt(rawIdx) !== targetChar) {
      return -1;
    }
    rawIdx++;
    targetIdx++;
  }
  return rawIdx;
}

export function findSentenceClozeTargetSpan(exampleEn: string, targetWord: string): SentenceClozeTargetSpan | undefined {
  const target: string = targetWord.trim();
  if (exampleEn.length === 0 || target.length === 0) {
    return undefined;
  }
  for (let i = 0; i < exampleEn.length; i++) {
    const end: number = matchTargetAt(exampleEn, target, i);
    if (end < 0) {
      continue;
    }
    if (!hasLetterBoundary(exampleEn, i, end)) {
      continue;
    }
    const span: SentenceClozeTargetSpan = new SentenceClozeTargetSpan();
    span.start = i;
    span.endExclusive = end;
    return span;
  }
  return undefined;
}

export function wordSupportsSentenceCloze(word: WordEntry): boolean {
  if (word.example === undefined) {
    return false;
  }
  if (word.example.en.trim().length === 0 || word.example.zh.trim().length === 0) {
    return false;
  }
  return findSentenceClozeTargetSpan(word.example.en, word.word) !== undefined;
}

export class SentenceClozeGenerator {
  private readonly rng: RandomFn;

  constructor(rng?: RandomFn) {
    this.rng = rng ?? Math.random;
  }

  generate(word: WordEntry, repo: WordRepository, lastWordId?: string): Question | undefined {
    if (word.example === undefined) {
      return undefined;
    }
    const span: SentenceClozeTargetSpan | undefined =
      findSentenceClozeTargetSpan(word.example.en, word.word);
    if (span === undefined || word.example.zh.trim().length === 0) {
      return undefined;
    }
    const options: string[] = this.buildOptions(word, repo, lastWordId);
    if (options.length < 3) {
      return undefined;
    }
    const q: Question = new Question();
    q.kind = QuestionKind.SentenceCloze;
    q.wordId = word.id;
    q.promptZh = word.meaningZh;
    q.answer = word.word;
    q.options = shuffle<string>(options.slice(0, 3), this.rng);
    q.sentenceTemplate = `${word.example.en.slice(0, span.start)}____${word.example.en.slice(span.endExclusive)}`;
    q.sentenceZh = word.example.zh;
    return q.isValid() ? q : undefined;
  }

  private buildOptions(word: WordEntry, repo: WordRepository, lastWordId?: string): string[] {
    const out: string[] = [];
    this.pushUnique(out, word.word);
    if (word.distractors !== undefined) {
      for (let i = 0; i < word.distractors.length; i++) {
        this.pushUnique(out, word.distractors[i]);
      }
    }
    const entries: WordEntry[] = repo.all();
    for (let i = 0; i < entries.length; i++) {
      const e: WordEntry = entries[i];
      if (e.id === word.id || (lastWordId !== undefined && e.id === lastWordId)) {
        continue;
      }
      this.pushUnique(out, e.word);
      if (out.length >= 3) {
        break;
      }
    }
    return out;
  }

  private pushUnique(out: string[], value: string): void {
    const trimmed: string = value.trim();
    if (trimmed.length === 0) {
      return;
    }
    const normalized: string = trimmed.toLowerCase();
    for (let i = 0; i < out.length; i++) {
      if (out[i].toLowerCase() === normalized) {
        return;
      }
    }
    out.push(trimmed);
  }
}
