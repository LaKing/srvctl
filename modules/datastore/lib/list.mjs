// modules/datastore/lib/list.mjs — the rows of the `list` verb.
//
// `list DAT [FIELD...]` prints one line per record: the record id, then the
// requested fields, separated by tabs. It exists because a bash loop that calls
// `get` per record starts one node process per record (about 0.26 s each); a
// loop over `list` starts one. main.mjs supplies valueOf, so a field resolves
// exactly as `get DAT ID FIELD` resolves it, derived fields included.
//
// The line format is fixed by how bash reads it (`IFS=$'\t' read -r C host ip`):
// - An unset value is "-", never an empty cell. Tab is IFS whitespace, so read
//   would merge two adjacent tabs and shift every later field one to the left.
// - A value that holds a tab or a line break cannot be a cell; it is reported
//   and printed as unset. Generated files (nspawn, hosts) are read with get.
// - A field that cannot be derived for one record (a container whose user is
//   gone, say) is reported and printed as unset for that record only, so one
//   broken record does not hide all the others from the caller's loop.

export const UNSET = "-";

function cell(id, field, valueOf, warn) {
    let value;
    try {
        value = valueOf(id, field);
    } catch (err) {
        warn(id + " " + field + ": " + err.message);
        return UNSET;
    }
    if (value === undefined || value === null || value === "") return UNSET;
    const text = typeof value === "object" ? JSON.stringify(value) : String(value);
    if (/[\t\n\r]/.test(text)) {
        warn(id + " " + field + ": the value spans lines or holds a tab, read it with get");
        return UNSET;
    }
    if (text === UNSET) warn(id + " " + field + ': the stored value "' + UNSET + '" reads as unset');
    return text;
}

// ids: record ids in output order. valueOf(id, field): the value `get` would
// return. warn(text): called once per cell that could not be printed.
export function listRows(ids, fields, valueOf, warn) {
    return ids.map((id) => [id, ...fields.map((field) => cell(id, field, valueOf, warn))].join("\t"));
}
