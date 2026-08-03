import assert from "node:assert/strict";
import test from "node:test";

import { auditPromotionCandidates } from "../tools/promote-material-themes.mjs";

test("promotion audit deduplicates sources and blocks candidates without approved rights", () => {
  const report = auditPromotionCandidates([
    { id: "source-a", outputThemeId: "skin-a", canonicalId: null, risk: { status: "approved" } },
    { id: "source-b", outputThemeId: "skin-b", canonicalId: null, risk: { status: "unreviewed" } },
    { id: "source-c", outputThemeId: "skin-b", canonicalId: "source-b", risk: { status: "unreviewed" } },
  ], new Map([["skin-a", { redistribution: true, commercialUse: true }]]));

  assert.deepEqual(report, {
    sourceRecords: 3,
    uniqueCandidates: 2,
    promotable: ["skin-a"],
    blocked: [{ id: "skin-b", reason: "rights_not_approved" }],
  });
});

test("promotion audit rejects unsafe theme ids", () => {
  assert.throws(() => auditPromotionCandidates([
    { id: "source-a", outputThemeId: "../escape", canonicalId: null, risk: { status: "approved" } },
  ], new Map()), /unsafe/i);
});
