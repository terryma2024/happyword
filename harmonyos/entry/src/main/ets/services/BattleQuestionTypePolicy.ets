import { MonsterKind } from '../data/MonsterCatalog';
import { QuestionKind } from '../models/Question';
import { WordEntry } from '../models/WordEntry';

export const BATTLE_QUESTION_TYPE_SENTENCE_FILL: string = 'sentence-fill';

export const DEFAULT_ENABLED_QUESTION_TYPES: string[] = [
  QuestionKind.Choice,
  QuestionKind.FillLetter,
  QuestionKind.FillLetterMedium,
  QuestionKind.Spell,
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
    || t === QuestionKind.Spell;
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
