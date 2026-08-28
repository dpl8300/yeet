import { assertEquals } from "jsr:@std/assert@1";
import fixture from "../../../packages/airtime-core/tests/fixtures/golden-traces.json" with { type: "json" };
import { validateAndDetectTrace } from "../../../packages/airtime-core/src/index.ts";

Deno.test("the Edge Function detector accepts the shared golden trace", () => {
  const result = validateAndDetectTrace(fixture.valid);
  assertEquals(Math.round(result.airtime * 1000), fixture.expectedAirtimeMs);
});

Deno.test("the Edge Function detector rejects incomplete traces", () => {
  let message = "";
  try { validateAndDetectTrace(fixture.valid.slice(0, 8)); }
  catch (error) { message = error instanceof Error ? error.message : ""; }
  assertEquals(message, "invalid-terminal-state");
});
