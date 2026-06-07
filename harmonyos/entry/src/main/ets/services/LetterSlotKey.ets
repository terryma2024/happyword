export class LetterSlotView {
  idx: number = 0;
  templateIndex: number = 0;
  glyph: string = '';
  isMissing: boolean = false;
  isPending: boolean = false;
}

function slotRole(isMissing: boolean, isPending: boolean): string {
  if (isMissing) {
    return 'missing';
  }
  if (isPending) {
    return 'pending';
  }
  return 'filled';
}

export function letterSlotRenderKey(
  idx: number,
  glyph: string,
  isMissing: boolean,
  isPending: boolean,
): string {
  return `${idx}-${glyph}-${slotRole(isMissing, isPending)}`;
}

export function buildLetterSlots(
  template: string,
  missingIndex: number,
  pendingIndex: number,
): LetterSlotView[] {
  const out: LetterSlotView[] = [];
  let i: number = 0;
  while (i < template.length) {
    const c: string = template.charAt(i);
    if (c !== ' ') {
      const slot: LetterSlotView = new LetterSlotView();
      slot.idx = out.length;
      slot.templateIndex = i;
      slot.glyph = c;
      slot.isMissing = i === missingIndex;
      slot.isPending = i === pendingIndex;
      out.push(slot);
      i++;
      continue;
    }

    let run: number = 0;
    while (i + run < template.length && template.charAt(i + run) === ' ') {
      run++;
    }
    if (run >= 3) {
      const slot: LetterSlotView = new LetterSlotView();
      slot.idx = out.length;
      slot.templateIndex = i;
      slot.glyph = ' ';
      slot.isMissing = i === missingIndex;
      slot.isPending = i === pendingIndex;
      out.push(slot);
    }
    i += run;
  }
  return out;
}
