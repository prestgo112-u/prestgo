// Construction de fichiers CSV.
//
// Deux choix volontaires pour que le fichier s'ouvre correctement dans Excel
// en configuration française :
//   - le séparateur est le point-virgule (Excel FR attend `;`, pas `,`) ;
//   - le fichier commence par un BOM UTF-8, sinon les accents s'affichent mal.

const SEPARATOR = ";";
const BOM = "﻿";

// Échappe une valeur : les guillemets sont doublés, et on entoure la valeur de
// guillemets dès qu'elle contient un séparateur, un guillemet ou un saut de ligne.
function escapeCell(value: unknown): string {
  if (value === null || value === undefined) {
    return "";
  }
  const text = value instanceof Date ? value.toISOString() : String(value);
  if (text.includes(SEPARATOR) || text.includes('"') || text.includes("\n") || text.includes("\r")) {
    return `"${text.replace(/"/g, '""')}"`;
  }
  return text;
}

export function buildCsv(headers: string[], rows: unknown[][]): string {
  const lines = [headers.join(SEPARATOR), ...rows.map((row) => row.map(escapeCell).join(SEPARATOR))];
  return BOM + lines.join("\r\n") + "\r\n";
}
