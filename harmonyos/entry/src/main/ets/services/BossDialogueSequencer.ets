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
  private deferIntroUntilDefeatClears: boolean = false;
  private pendingMonsterIndex: number = -1;
  private pendingCatalogIndex: number = -1;

  beginDefeatTransition(): void {
    this.deferIntroUntilDefeatClears = true;
    this.pendingMonsterIndex = -1;
    this.pendingCatalogIndex = -1;
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
    if (this.deferIntroUntilDefeatClears) {
      this.pendingMonsterIndex = monsterIndex;
      this.pendingCatalogIndex = catalogIndex;
      return decision(BossDialogueIntroDecisionKind.Defer, monsterIndex, catalogIndex);
    }
    return decision(BossDialogueIntroDecisionKind.Show, monsterIndex, catalogIndex);
  }

  releaseAfterDefeat(): BossDialogueIntroDecision {
    this.deferIntroUntilDefeatClears = false;
    if (this.pendingMonsterIndex < 0 || this.pendingCatalogIndex < 0) {
      return decision(BossDialogueIntroDecisionKind.Skip);
    }
    const out: BossDialogueIntroDecision = decision(
      BossDialogueIntroDecisionKind.Show,
      this.pendingMonsterIndex,
      this.pendingCatalogIndex,
    );
    this.pendingMonsterIndex = -1;
    this.pendingCatalogIndex = -1;
    return out;
  }
}
