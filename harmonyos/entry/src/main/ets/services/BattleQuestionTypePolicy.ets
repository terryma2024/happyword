import { MonsterKind, MonsterLevel } from '../data/MonsterCatalog';
import { QuestionKind } from '../models/Question';
import { WordEntry } from '../models/WordEntry';
import { wordSupportsSentenceCloze } from './SentenceClozeGenerator';

export const BATTLE_QUESTION_TYPE_SENTENCE_FILL: string = 'sentence-fill';

export const DEFAULT_ENABLED_QUESTION_TYPES: string[] = [
  QuestionKind.Choice,
  QuestionKind.FillLetter,
  QuestionKind.FillLetterMedium,
  QuestionKind.Spell,
  QuestionKind.SentenceCloze,
];

function alphaLength(raw: string): number {
  const lower: string = raw.toLowerCase();
  let n: number = 0;
  for (let i: number = 0; i < lower.length; i++) {
    const c: string = lower.charAt(i);
    if (c >= 'a' && c <= 'z') {
      n += 1;
    }
  }
  return n;
}

function isImplementedQuestionType(t: string): boolean {
  return t === QuestionKind.Choice
    || t === QuestionKind.FillLetter
    || t === QuestionKind.FillLetterMedium
    || t === QuestionKind.Spell
    || t === QuestionKind.SentenceCloze;
}

export function sanitizeEnabledQuestionTypes(raw: string[]): string[] {
  const out: string[] = [];
  for (let order: number = 0; order < DEFAULT_ENABLED_QUESTION_TYPES.length; order++) {
    const t: string = DEFAULT_ENABLED_QUESTION_TYPES[order];
    for (let i: number = 0; i < raw.length; i++) {
      if (raw[i] === t && out.indexOf(t) < 0) {
        out.push(t);
      }
    }
  }
  if (out.length === 0) {
    return DEFAULT_ENABLED_QUESTION_TYPES.slice();
  }
  return out;
}

export function questionTypeToMonsterKind(typeId: string): MonsterKind {
  if (typeId === QuestionKind.FillLetter) {
    return MonsterKind.Spelling;
  }
  if (typeId === QuestionKind.FillLetterMedium) {
    return MonsterKind.Elite;
  }
  if (typeId === QuestionKind.Spell) {
    return MonsterKind.Boss;
  }
  if (typeId === QuestionKind.SentenceCloze) {
    return MonsterKind.Boss;
  }
  return MonsterKind.Normal;
}

export function questionTypeForMonsterKind(kind: MonsterKind): string {
  if (kind === MonsterKind.Spelling) {
    return QuestionKind.FillLetter;
  }
  if (kind === MonsterKind.Elite) {
    return QuestionKind.FillLetterMedium;
  }
  if (kind === MonsterKind.Boss) {
    return QuestionKind.Spell;
  }
  return QuestionKind.Choice;
}

/** V0.8.3 — primary question type from monster level (not MonsterKind). */
export function questionTypeForMonsterLevel(level: MonsterLevel): string {
  if (level === MonsterLevel.Intermediate) {
    return QuestionKind.FillLetter;
  }
  if (level === MonsterLevel.Advanced) {
    return QuestionKind.FillLetterMedium;
  }
  if (level === MonsterLevel.Super) {
    return QuestionKind.Spell;
  }
  return QuestionKind.Choice;
}

/** Degrade one tier toward Choice when the word cannot host the primary type. */
export function questionTypeFallbackChain(primaryType: string): string[] {
  if (primaryType === QuestionKind.Spell) {
    return [
      QuestionKind.Spell,
      QuestionKind.FillLetterMedium,
      QuestionKind.FillLetter,
      QuestionKind.Choice,
    ];
  }
  if (primaryType === QuestionKind.SentenceCloze) {
    return [
      QuestionKind.SentenceCloze,
      QuestionKind.FillLetterMedium,
      QuestionKind.Spell,
      QuestionKind.FillLetter,
      QuestionKind.Choice,
    ];
  }
  if (primaryType === QuestionKind.FillLetterMedium) {
    return [
      QuestionKind.FillLetterMedium,
      QuestionKind.FillLetter,
      QuestionKind.Choice,
    ];
  }
  if (primaryType === QuestionKind.FillLetter) {
    return [QuestionKind.FillLetter, QuestionKind.Choice];
  }
  return [QuestionKind.Choice];
}

export function resolveQuestionTypeForWord(word: WordEntry, primaryType: string): string {
  const chain: string[] = questionTypeFallbackChain(primaryType);
  for (let i: number = 0; i < chain.length; i++) {
    if (wordSupportsQuestionType(word, chain[i])) {
      return chain[i];
    }
  }
  return QuestionKind.Choice;
}

/** V0.8.4 — degrade only within the active schedule pool (intro or challenge). */
export function resolveQuestionTypeWithinPool(
  word: WordEntry,
  primaryType: string,
  pool: string[],
): string {
  const chain: string[] = questionTypeFallbackChain(primaryType);
  for (let i: number = 0; i < chain.length; i++) {
    const t: string = chain[i];
    if (pool.indexOf(t) >= 0 && wordSupportsQuestionType(word, t)) {
      return t;
    }
  }
  for (let j: number = 0; j < pool.length; j++) {
    if (wordSupportsQuestionType(word, pool[j])) {
      return pool[j];
    }
  }
  return QuestionKind.Choice;
}

export function wordSupportsQuestionType(word: WordEntry, typeId: string): boolean {
  if (!isImplementedQuestionType(typeId)) {
    return false;
  }
  const letters: number = alphaLength(word.word);
  if (typeId === QuestionKind.Choice) {
    return word.word.length > 0;
  }
  if (typeId === QuestionKind.FillLetter) {
    return letters >= 3;
  }
  if (typeId === QuestionKind.FillLetterMedium) {
    return letters >= 4;
  }
  if (typeId === QuestionKind.Spell) {
    return letters >= 4 && letters <= 9;
  }
  if (typeId === QuestionKind.SentenceCloze) {
    return wordSupportsSentenceCloze(word);
  }
  return false;
}

export function anyWordSupportsQuestionTypes(words: WordEntry[], typeIds: string[]): boolean {
  const safeTypes: string[] = sanitizeEnabledQuestionTypes(typeIds);
  for (let i: number = 0; i < words.length; i++) {
    for (let j: number = 0; j < safeTypes.length; j++) {
      if (wordSupportsQuestionType(words[i], safeTypes[j])) {
        return true;
      }
    }
  }
  return false;
}
