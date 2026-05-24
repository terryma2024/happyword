export class CheckInDayCell {
  dayKey: string = '';
  label: string = '';
  checked: boolean = false;
  inMonth: boolean = false;
}

export class CheckInWeekRow {
  cells: CheckInDayCell[] = [];
}

export function monthAnchorMs(nowMs: number): number {
  const now: Date = new Date(nowMs);
  return new Date(now.getFullYear(), now.getMonth(), 1, 12, 0, 0).getTime();
}

export function shiftMonth(monthMs: number, delta: number): number {
  const current: Date = new Date(monthMs);
  return new Date(current.getFullYear(), current.getMonth() + delta, 1, 12, 0, 0).getTime();
}

export function monthLabel(monthMs: number): string {
  const current: Date = new Date(monthMs);
  return `${current.getFullYear()}年${current.getMonth() + 1}月`;
}

export function monthRowKey(monthMs: number, rowIndex: number): string {
  const current: Date = new Date(monthMs);
  return `${current.getFullYear()}-${current.getMonth() + 1}-row-${rowIndex}`;
}

export function buildCheckInMonthWeeks(monthMs: number, checkedDayKeys: string[]): CheckInWeekRow[] {
  const current: Date = new Date(monthMs);
  const first: Date = new Date(current.getFullYear(), current.getMonth(), 1);
  const daysInMonth: number = new Date(current.getFullYear(), current.getMonth() + 1, 0).getDate();
  const lead: number = first.getDay();
  const rows: CheckInWeekRow[] = [];
  let currentRow: CheckInWeekRow = new CheckInWeekRow();
  for (let blank = 0; blank < lead; blank++) {
    currentRow.cells.push(new CheckInDayCell());
  }
  for (let day = 1; day <= daysInMonth; day++) {
    const dayKey: string = ymd(current.getFullYear(), current.getMonth() + 1, day);
    const cell: CheckInDayCell = new CheckInDayCell();
    cell.dayKey = dayKey;
    cell.label = `${day}`;
    cell.checked = containsDay(checkedDayKeys, dayKey);
    cell.inMonth = true;
    currentRow.cells.push(cell);
    if (currentRow.cells.length === 7) {
      rows.push(currentRow);
      currentRow = new CheckInWeekRow();
    }
  }
  if (currentRow.cells.length > 0) {
    while (currentRow.cells.length < 7) {
      currentRow.cells.push(new CheckInDayCell());
    }
    rows.push(currentRow);
  }
  return rows;
}

function ymd(year: number, month: number, day: number): string {
  const mm: string = month < 10 ? `0${month}` : `${month}`;
  const dd: string = day < 10 ? `0${day}` : `${day}`;
  return `${year}-${mm}-${dd}`;
}

function containsDay(checkedDayKeys: string[], dayKey: string): boolean {
  for (let i = 0; i < checkedDayKeys.length; i++) {
    if (checkedDayKeys[i] === dayKey) {
      return true;
    }
  }
  return false;
}
