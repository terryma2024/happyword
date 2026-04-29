import { Question } from '../models/Question';

/**
 * V0.4.1 SpellingArea — point-select full-word spelling for Boss
 * monsters. Owns its own per-tap state (slots, consumed pool, shake
 * timer) so BattlePage / BattleEngine never see partial answers; we
 * only fire `onSpellComplete` once when every slot is correctly
 * filled, at which point BattlePage feeds the full word back to
 * `BattleEngine.submitAnswer` exactly like any Choice / FillLetter
 * answer.
 *
 * Visual layout (mirrors v0.3.10 colour palette):
 *   row 1 — slots (filled = #1D3557 navy on white; empty = #E63946 red on #FCEAEA)
 *   row 2 — letter pool chips (filled cream button, navy text)
 *
 * Interaction rules (spec §6):
 *   - tap a pool chip whose letter matches the next empty slot →
 *     letter slides into slot, chip becomes consumed (greyed).
 *   - tap a chip whose letter doesn't match → chip flashes red
 *     (220 ms), no slot mutation, no HP penalty, no consume.
 *   - tap a consumed chip → no-op (silent).
 *   - completion: the moment the last slot fills correctly, schedule
 *     a 200 ms reveal pause then fire onSpellComplete. The pause
 *     gives the player a beat to see the final letter pop in before
 *     BattlePage rotates to the next question.
 */
const SLOT_FILLED_BG: string = '#FFFFFF';
const SLOT_FILLED_TEXT: string = '#1D3557';
const SLOT_EMPTY_BG: string = '#FCEAEA';
const SLOT_EMPTY_TEXT: string = '#E63946';

const POOL_IDLE_BG: string = '#FFF8E7';
const POOL_TEXT: string = '#1D3557';
const POOL_CONSUMED_BG: string = '#E0E0E0';
const POOL_CONSUMED_TEXT: string = '#A3A3A3';
const POOL_WRONG_BG: string = '#FCEAEA';
const POOL_WRONG_TEXT: string = '#E63946';

const SLOT_W: number = 36;
const SLOT_H: number = 48;
const POOL_W: number = 44;
const POOL_H: number = 52;
const SHAKE_MS: number = 220;
const COMPLETE_FLASH_MS: number = 200;

@Component
export struct SpellingArea {
  @Prop @Watch('onQuestionChanged') question: Question = new Question();
  /** Stable id prefix used by UI tests (e.g. `Boss-Spell-Area`). */
  areaId: string = 'SpellingArea';
  /** Fired exactly once when every slot is correctly filled. */
  onSpellComplete: (answer: string) => void = (): void => {};

  @State private slots: string[] = [];
  @State private consumedPool: boolean[] = [];
  @State private shakingPoolIdx: number = -1;
  @State private completed: boolean = false;
  private shakeTimer: number = -1;
  private completeTimer: number = -1;

  aboutToAppear(): void {
    this.resetForQuestion();
  }

  aboutToDisappear(): void {
    if (this.shakeTimer >= 0) {
      clearTimeout(this.shakeTimer);
      this.shakeTimer = -1;
    }
    if (this.completeTimer >= 0) {
      clearTimeout(this.completeTimer);
      this.completeTimer = -1;
    }
  }

  private onQuestionChanged(): void {
    this.resetForQuestion();
  }

  private resetForQuestion(): void {
    if (this.shakeTimer >= 0) {
      clearTimeout(this.shakeTimer);
      this.shakeTimer = -1;
    }
    if (this.completeTimer >= 0) {
      clearTimeout(this.completeTimer);
      this.completeTimer = -1;
    }
    this.shakingPoolIdx = -1;
    this.completed = false;
    const nextSlots: string[] = [];
    const letters: string[] = this.question.spellLetters;
    const mask: boolean[] = this.question.spellRevealedMask;
    for (let i = 0; i < letters.length; i++) {
      nextSlots.push(mask[i] ? letters[i] : '');
    }
    this.slots = nextSlots;
    const nextConsumed: boolean[] = [];
    for (let i = 0; i < this.question.spellPool.length; i++) {
      nextConsumed.push(false);
    }
    this.consumedPool = nextConsumed;
  }

  private nextEmptySlotIndex(): number {
    for (let i = 0; i < this.slots.length; i++) {
      if (this.slots[i].length === 0) {
        return i;
      }
    }
    return -1;
  }

  private isComplete(): boolean {
    for (let i = 0; i < this.slots.length; i++) {
      if (this.slots[i].length === 0) {
        return false;
      }
    }
    return true;
  }

  private onTapPoolLetter(idx: number): void {
    if (this.completed) {
      return;
    }
    if (idx < 0 || idx >= this.consumedPool.length) {
      return;
    }
    if (this.consumedPool[idx]) {
      return;
    }
    if (this.shakingPoolIdx >= 0) {
      // While a shake is animating, ignore further taps so the kid
      // can clearly see the rejection feedback before retrying.
      return;
    }
    const slotIdx: number = this.nextEmptySlotIndex();
    if (slotIdx < 0) {
      return;
    }
    const expected: string = this.question.spellLetters[slotIdx];
    const tapped: string = this.question.spellPool[idx];
    if (tapped !== expected) {
      this.shakingPoolIdx = idx;
      this.shakeTimer = setTimeout((): void => {
        this.shakeTimer = -1;
        this.shakingPoolIdx = -1;
      }, SHAKE_MS);
      return;
    }
    // Correct tap: copy slots / consumedPool so ArkUI re-observes the
    // change (mutating the same array reference may not trigger a redraw
    // depending on @State observation depth).
    const nextSlots: string[] = this.slots.slice();
    nextSlots[slotIdx] = tapped;
    this.slots = nextSlots;
    const nextConsumed: boolean[] = this.consumedPool.slice();
    nextConsumed[idx] = true;
    this.consumedPool = nextConsumed;

    if (this.isComplete()) {
      this.completed = true;
      this.completeTimer = setTimeout((): void => {
        this.completeTimer = -1;
        this.onSpellComplete(this.question.answer);
      }, COMPLETE_FLASH_MS);
    }
  }

  private slotBg(i: number): string {
    return this.slots[i].length > 0 ? SLOT_FILLED_BG : SLOT_EMPTY_BG;
  }

  private slotText(i: number): string {
    return this.slots[i].length > 0 ? this.slots[i] : '_';
  }

  private slotTextColor(i: number): string {
    return this.slots[i].length > 0 ? SLOT_FILLED_TEXT : SLOT_EMPTY_TEXT;
  }

  private poolBg(i: number): string {
    if (this.consumedPool[i]) {
      return POOL_CONSUMED_BG;
    }
    if (this.shakingPoolIdx === i) {
      return POOL_WRONG_BG;
    }
    return POOL_IDLE_BG;
  }

  private poolTextColor(i: number): string {
    if (this.consumedPool[i]) {
      return POOL_CONSUMED_TEXT;
    }
    if (this.shakingPoolIdx === i) {
      return POOL_WRONG_TEXT;
    }
    return POOL_TEXT;
  }

  @Builder
  private slotsRow() {
    Row({ space: 6 }) {
      ForEach(this.slots, (glyph: string, idx: number) => {
        Stack() {
          Column()
            .width(SLOT_W)
            .height(SLOT_H)
            .backgroundColor(this.slotBg(idx))
            .borderRadius(6)
            .border({ width: 1, color: '#D9D9D9' });
          Text(this.slotText(idx))
            .id(`${this.areaId}_Slot_${idx}`)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.slotTextColor(idx));
        }
        .width(SLOT_W)
        .height(SLOT_H)
        .alignContent(Alignment.Center);
      }, (glyph: string, idx: number): string => `slot-${idx}-${glyph}`);
    }
    .width('100%')
    .justifyContent(FlexAlign.Center);
  }

  @Builder
  private poolRow() {
    Flex({
      wrap: FlexWrap.Wrap,
      justifyContent: FlexAlign.Center,
      alignItems: ItemAlign.Center,
    }) {
      ForEach(this.consumedPool, (_consumed: boolean, idx: number) => {
        Button(this.question.spellPool[idx])
          .id(`${this.areaId}_Pool_${idx}`)
          .type(ButtonType.Circle)
          .width(POOL_W)
          .height(POOL_H)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.poolTextColor(idx))
          .backgroundColor(this.poolBg(idx))
          .margin(4)
          .enabled(!this.consumedPool[idx])
          .onClick((): void => {
            this.onTapPoolLetter(idx);
          });
      }, (_consumed: boolean, idx: number): string => `pool-${idx}-${this.question.spellPool[idx]}`);
    }
    .width('100%')
    .margin({ top: 12 });
  }

  build() {
    Column() {
      this.slotsRow();
      this.poolRow();
    }
    .id(this.areaId)
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 });
  }
}
