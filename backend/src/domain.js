/**
 * Validate organizer course input without depending on a deployed server.
 * Shared pure helpers keep imports and their tests consistent.
 * @module domain
 * @example normalizeAnswer('  North  ') === 'north';
 */

/**
 * Reject invalid organizer input with a stable, actionable error code.
 * @param {boolean} condition Whether the invariant holds.
 * @param {string} code Validation status code.
 * @param {string} message Actionable message without private data.
 * @returns {void}
 * @throws {Error} When the condition is false.
 * @example ensure(points > 0, 'invalid-argument', 'Points must be positive.');
 */
export function ensure(condition, code, message) {
  if (!condition) throw Object.assign(new Error(message), { code });
}

/**
 * Validate bounded input text before using it in documents or identifiers.
 * @param {unknown} value Supplied value.
 * @param {string} label User-facing field name.
 * @param {number} max Maximum trimmed length.
 * @returns {string} Trimmed nonempty text.
 * @throws {Error} For missing, oversized, or control-character input.
 * @example text(' Team A ', 'Team name', 60);
 */
export function text(value, label, max = 100) {
  ensure(typeof value === 'string', 'invalid-argument', `${label} is required.`);
  const result = value.trim();
  ensure(result.length > 0 && result.length <= max && !/[\u0000-\u001f\u007f]/u.test(result),
    'invalid-argument', `${label} is invalid.`);
  return result;
}

/**
 * Validate a single Firestore document identifier, never a path.
 * @param {unknown} value Supplied identifier.
 * @returns {string} Safe identifier.
 * @throws {Error} For path separators or invalid text.
 * @example id('campus-course');
 */
export function id(value) {
  const result = text(value, 'Identifier', 128);
  ensure(/^[A-Za-z0-9_-]+$/u.test(result), 'invalid-argument', 'Identifier is invalid.');
  return result;
}

/**
 * Normalize answers without changing accented letters or punctuation.
 * @param {string} value Answer text.
 * @returns {string} Unicode-normalized, trimmed, case-insensitive answer.
 * @throws {TypeError} If called without a string by internal code.
 * @example normalizeAnswer('  North  ') === 'north';
 */
export function normalizeAnswer(value) {
  return value.normalize('NFKC').trim().replace(/\s+/gu, ' ').toLocaleLowerCase('en-US');
}
