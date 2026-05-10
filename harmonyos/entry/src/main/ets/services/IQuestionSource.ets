import { Question } from '../models/Question';

/**
 * Question-source contract used by BattleEngine. The engine no
 * longer depends on QuestionGenerator concretely so that today's
 * adventure can swap in PlanQuestionSource without changing the
 * engine's call site.
 */
export interface IQuestionSource {
  nextQuestion(lastWordId?: string): Question;
}
