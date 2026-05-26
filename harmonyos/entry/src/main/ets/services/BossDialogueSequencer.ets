export enum BossDialogueIntroDecisionKind {
  Show = 'show',
  Defer = 'defer',
  Skip = 'skip',
}

export class BossDialogueIntroDecision {
  kind: BossDialogueIntroDecisionKind = BossDialogueIntroDecisionKind.Skip;
  monsterIndex: number = -1;
  catalogIndex: number = -1;
}

function decision(
  kind: BossDialogueIntroDecisionKind,
  monsterIndex: number = -1,
  catalogIndex: number = -1,
): BossDialogueIntroDecision {
  const out: BossDialogueIntroDecision = new BossDialogueIntroDecision();
  out.kind = kind;
  out.monsterIndex = monsterIndex;
  out.catalogIndex = catalogIndex;
  return out;
}

export class BossDialogueSequencer {
  beginDefeatTransition(): void {
    // Defeat bubbles are currently disabled, so intro lines should stay immediate.
  }

  requestIntro(
    monsterIndex: number,
    catalogIndex: number,
    lastIntroMonsterIndex: number,
    shownCatalogIndices: number[],
  ): BossDialogueIntroDecision {
    if (monsterIndex === lastIntroMonsterIndex || shownCatalogIndices.indexOf(catalogIndex) >= 0) {
      return decision(BossDialogueIntroDecisionKind.Skip);
    }
    return decision(BossDialogueIntroDecisionKind.Show, monsterIndex, catalogIndex);
  }

  releaseAfterDefeat(): BossDialogueIntroDecision {
    return decision(BossDialogueIntroDecisionKind.Skip);
  }
}
