import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import {
  extractContract,
  TARGET_NODES,
} from './extract_antigravity_contract.mjs';

function workflow(nodes = TARGET_NODES) {
  return {
    id: '8k30Q8FFwvr3lbtu',
    name: 'AntiGravity',
    versionId: 'draft-version',
    nodes: nodes.map((name, index) => ({
      id: `node-${index}`,
      name,
      type: 'n8n-nodes-base.code',
      typeVersion: 2,
      credentials: {
        httpHeaderAuth: { id: 'credential-id', name: 'production' },
      },
      parameters: {
        jsCode: `
          const secret = "must-not-survive";
          const paths = [
            "/api/v1/technical_incident_checks/precheck",
            "/api/v1/technical_incident_checks/${'${id}'}/match",
            "/api/v1/technical_incident_checks/${'${id}'}/commit",
            "/api/v1/technical_incident_evaluations/${'${id}'}/feedback"
          ];
          return { method: "POST", contract_version: "1.0",
            api_access_token: config.token, "Content-Type": "application/json",
            id, check_id, evaluation_id, commit_token,
            conversation_display_id, source_message_id, mode, request_id,
            classification, is_support_issue, problem_type, service_key,
            symptoms, semantic_confidence, topic_change, needs_clarification,
            reason_code, contracts, sanitized_contracts, selected_contract_id,
            selected_contract, contract_id, status, pop_id, pop_name,
            service_group, connection_type, state, city, neighborhood,
            postal_code, street, number, location, feedback, note,
            no_candidate, general_match, localized_candidate, needs_document,
            needs_contract_selection, matched, ambiguous, expired, fallback,
            duplicate, accepted, stale, timeout, retry };
        `,
      },
    })),
  };
}

test('extracts only the five nodes and redacts credential material', async () => {
  const directory = await fs.mkdtemp(
    path.join(os.tmpdir(), 'antigravity-contract-')
  );
  const input = path.join(directory, 'workflow.json');
  const output = path.join(directory, 'output');
  await fs.writeFile(input, JSON.stringify(workflow()));

  const result = await extractContract(input, output);
  const extracted = await fs.readFile(result.jsonPath, 'utf8');
  const report = await fs.readFile(result.reportPath, 'utf8');

  assert.equal(JSON.parse(extracted).nodes.length, 5);
  assert.doesNotMatch(extracted, /must-not-survive|credential-id|production/);
  assert.match(extracted, /\[REDACTED\]/);
  assert.match(report, /no_candidate/);
  assert.match(report, /SHA-256/);
});

test('fails closed when any required Code node is absent', async () => {
  const directory = await fs.mkdtemp(
    path.join(os.tmpdir(), 'antigravity-contract-')
  );
  const input = path.join(directory, 'workflow.json');
  await fs.writeFile(
    input,
    JSON.stringify(workflow(TARGET_NODES.slice(0, -1)))
  );

  await assert.rejects(
    extractContract(input, path.join(directory, 'output')),
    /TI_Feedback_Adapter_V1/
  );
});
