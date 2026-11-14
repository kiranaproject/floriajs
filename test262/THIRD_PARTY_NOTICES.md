# Third-party notices

## TC39 Test262

The diagnostic adapter is designed to consume [TC39 Test262](https://github.com/tc39/test262). The initial pinned revision is `2e58f87d8350ad51224617a041c6e041d52f8444` (`package.json` version `5.0.0`).

No full Test262 checkout or test corpus is vendored into the FloriaJS repository. The files in `config/` contain policy data and upstream paths only.

The Phase 7 authored async fixture root vendors three upstream harness files without modification from the pinned revision:

- `fixtures/async/harness/assert.js`
- `fixtures/async/harness/sta.js`
- `fixtures/async/harness/doneprintHandle.js`

Their upstream copyright headers and BSD licence terms are retained in the files themselves. `fixtures/host/doneprintHandle.js`, `fixtures/negative/harness/doneprintHandle.js`, and `fixtures/metadata/harness/doneprintHandle.js` are the same copied file for fixture-local harness roots.

Test262 is distributed by Ecma International under its BSD licence, with copyright `(C) 2012 Ecma International`. Individual test files also retain their own copyright and licence notices. The authoritative licence is the `LICENSE` file in the pinned upstream checkout:

<https://github.com/tc39/test262/blob/2e58f87d8350ad51224617a041c6e041d52f8444/LICENSE>

If upstream test material, harness files, or portions of them are later copied into this repository, the corresponding copyright notices, licence text, source revision, and any modification notes must be retained alongside that material. Downloading or linking to the suite does not imply endorsement by Ecma International.
