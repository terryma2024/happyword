import { describe, it, expect } from '@ohos/hypium';
import {
  buildCheckInMonthWeeks,
  CheckInDayCell,
  CheckInWeekRow,
  monthAnchorMs,
  monthLabel,
  monthRowKey,
  shiftMonth,
} from '../main/ets/services/CheckInCalendarView';

function ts(year: number, monthIndex: number, day: number): number {
  return new Date(year, monthIndex, day, 12, 0, 0).getTime();
}

function findCell(weeks: CheckInWeekRow[], dayKey: string): CheckInDayCell {
  for (let r = 0; r < weeks.length; r++) {
    for (let c = 0; c < weeks[r].cells.length; c++) {
      if (weeks[r].cells[c].dayKey === dayKey) {
        return weeks[r].cells[c];
      }
    }
  }
  return new CheckInDayCell();
}

export default function checkInCalendarViewTest() {
  describe('CheckInCalendarView', () => {
    it('buildsMonthGridAndMarksCheckedDays', 0, () => {
      const anchor: number = monthAnchorMs(ts(2026, 4, 24));
      const weeks: CheckInWeekRow[] = buildCheckInMonthWeeks(anchor, ['2026-05-24']);
      const first: CheckInDayCell = weeks[0].cells[5];
      const checked: CheckInDayCell = findCell(weeks, '2026-05-24');
      expect(monthLabel(anchor)).assertEqual('2026年5月');
      expect(first.dayKey).assertEqual('2026-05-01');
      expect(first.inMonth).assertTrue();
      expect(checked.checked).assertTrue();
      expect(weeks[0].cells.length).assertEqual(7);
    });

    it('shiftsMonthsAcrossYearBoundary', 0, () => {
      const dec: number = monthAnchorMs(ts(2026, 11, 8));
      expect(monthLabel(shiftMonth(dec, 1))).assertEqual('2027年1月');
      expect(monthLabel(shiftMonth(dec, -1))).assertEqual('2026年11月');
    });

    it('usesDifferentRowKeysForDifferentMonths', 0, () => {
      const may: number = monthAnchorMs(ts(2026, 4, 24));
      const june: number = shiftMonth(may, 1);
      expect(monthRowKey(may, 0) === monthRowKey(june, 0)).assertFalse();
    });
  });
}
