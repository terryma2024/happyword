export const CONFIG_LABEL_WIDTH_VP: number = 120;
export const CONFIG_CONTROL_GAP_VP: number = 12;
export const CONFIG_CONTROL_COLUMN_WIDTH_VP: number = 220;
export const CONFIG_FORM_ROW_WIDTH_VP: number =
  CONFIG_LABEL_WIDTH_VP + CONFIG_CONTROL_GAP_VP + CONFIG_CONTROL_COLUMN_WIDTH_VP;
export const CONFIG_QUESTION_TYPE_OPTIONS_LEFT_ALIGNED: boolean = true;
export const CONFIG_TIMER_OPTIONS_PER_ROW: number = 3;

export function questionTypeColumnRows(typeIds: string[]): string[][] {
  const rows: string[][] = [];
  for (let i = 0; i < typeIds.length; i++) {
    rows.push([typeIds[i]]);
  }
  return rows;
}

export function timerOptionRows(optionSeconds: number[]): number[][] {
  const rows: number[][] = [];
  for (let i = 0; i < optionSeconds.length; i += CONFIG_TIMER_OPTIONS_PER_ROW) {
    const row: number[] = [optionSeconds[i]];
    for (let j = 1; j < CONFIG_TIMER_OPTIONS_PER_ROW && i + j < optionSeconds.length; j++) {
      row.push(optionSeconds[i + j]);
    }
    rows.push(row);
  }
  return rows;
}
