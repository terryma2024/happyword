/**
 * CategoryCatalog — V0.5 schema_v4 overlay for AdventureCatalog.
 *
 * The server publishes a top-level `categories[]` block in pack JSON
 * starting at schema_version 4: `[{ id, labelEn, labelZh, storyZh? }]`.
 * HomePage uses this catalog to overlay the server-provided Chinese
 * label / story onto the bundled `AdventureCatalog` regions whenever
 * the operator has synced a v4+ pack. v1 packs (which is what currently
 * ships) carry no categories[] block, so `parsePackCategories` returns
 * an empty array and the bundled labels stay in place — no regression.
 *
 * The class is intentionally pure (no IO, no AppStorage, no async).
 * HomePage owns the lifecycle: it calls `parsePackCategories` after
 * the WordPackCache has produced a record, then invokes `setRows`.
 */

export class CategoryRow {
  id: string = '';
  labelEn: string = '';
  labelZh: string = '';
  storyZh?: string;
}

interface RawCategoryJson {
  id?: string;
  labelEn?: string;
  labelZh?: string;
  storyZh?: string;
}

interface RawPackJson {
  categories?: RawCategoryJson[];
}

export class CategoryCatalog {
  private rows: CategoryRow[] = [];
  private byIdMap: Map<string, CategoryRow> = new Map<string, CategoryRow>();

  setRows(rows: CategoryRow[]): void {
    this.rows = rows.slice();
    const next: Map<string, CategoryRow> = new Map<string, CategoryRow>();
    for (let i = 0; i < this.rows.length; i++) {
      next.set(this.rows[i].id, this.rows[i]);
    }
    this.byIdMap = next;
  }

  getById(id: string): CategoryRow | undefined {
    return this.byIdMap.get(id);
  }

  size(): number {
    return this.rows.length;
  }

  static parsePackCategories(packJson: string): CategoryRow[] {
    if (packJson.length === 0) {
      return [];
    }
    let parsed: RawPackJson | null = null;
    try {
      parsed = JSON.parse(packJson) as RawPackJson;
    } catch (_err) {
      return [];
    }
    if (parsed === null || parsed === undefined) {
      return [];
    }
    const arr: RawCategoryJson[] | undefined = parsed.categories;
    if (arr === undefined || !Array.isArray(arr)) {
      return [];
    }
    const out: CategoryRow[] = [];
    for (let i = 0; i < arr.length; i++) {
      const r: RawCategoryJson = arr[i];
      if (typeof r.id !== 'string' || r.id.length === 0) {
        continue;
      }
      const row: CategoryRow = new CategoryRow();
      row.id = r.id;
      row.labelEn = typeof r.labelEn === 'string' ? r.labelEn : '';
      row.labelZh = typeof r.labelZh === 'string' ? r.labelZh : '';
      if (typeof r.storyZh === 'string' && r.storyZh.length > 0) {
        row.storyZh = r.storyZh;
      }
      out.push(row);
    }
    return out;
  }
}
